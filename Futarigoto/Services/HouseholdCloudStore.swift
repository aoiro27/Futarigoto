import Foundation
import Supabase

enum HouseholdCloudStore {
    private static let photoBucket = "observation-photos"

    static func ensureUser() async throws -> UUID {
        let client = try SupabaseConfig.client()
        if let session = client.auth.currentSession, !session.isExpired {
            return session.user.id
        }
        if let session = try? await client.auth.session {
            return session.user.id
        }
        let session = try await client.auth.signInAnonymously()
        return session.user.id
    }

    static func createHousehold(id: UUID, inviteCode: String, displayName: String) async throws {
        let client = try SupabaseConfig.client()
        try await client
            .rpc(
                "create_household",
                params: CreateHouseholdParams(
                    householdId: id,
                    inviteCode: inviteCode,
                    displayName: displayName
                )
            )
            .execute()
    }

    static func joinHousehold(inviteCode: String, displayName: String) async throws -> UUID {
        let client = try SupabaseConfig.client()
        let response = try await client
            .rpc(
                "join_household",
                params: JoinHouseholdParams(
                    inviteCode: inviteCode,
                    displayName: displayName
                )
            )
            .execute()
        if let id = try? SupabaseConfig.makeDecoder().decode(UUID.self, from: response.data) {
            return id
        }
        if let raw = String(data: response.data, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" \n")),
           let id = UUID(uuidString: raw) {
            return id
        }
        throw AppError.invalidInvite
    }

    static func fetchHousehold() async throws -> HouseholdSnapshot? {
        do {
            return try await fetchHouseholdViaRPC()
        } catch is SnapshotDecodeError {
            return try await fetchHouseholdFromTables()
        } catch {
            let text = String(describing: error).lowercased()
            if text.contains("does not exist") || text.contains("pgrst202") || text.contains("404") {
                return try await fetchHouseholdFromTables()
            }
            throw error
        }
    }

    static func save(snapshot: HouseholdSnapshot) async throws {
        let client = try SupabaseConfig.client()
        let userId = try await ensureUser()

        let profiles = snapshot.users.filter { $0.id == userId }
        let reflections = snapshot.reflections.filter { $0.userId == userId }
        let ownObservations = snapshot.observations.filter { $0.authorId == userId }
        let agreements = snapshot.agreements

        try await withThrowingTaskGroup(of: Void.self) { group in
            if !profiles.isEmpty {
                group.addTask {
                    try await client.from("profiles").upsert(profiles).execute()
                }
            }
            if !agreements.isEmpty {
                group.addTask {
                    try await client.from("agreements").upsert(agreements).execute()
                }
            }
            if !reflections.isEmpty {
                group.addTask {
                    try await client.from("reflections").upsert(
                        reflections,
                        onConflict: "agreement_id,user_id,week_start_date"
                    ).execute()
                }
            }
            if !ownObservations.isEmpty {
                group.addTask {
                    try await client.from("observations").upsert(ownObservations.map(ObservationRow.init)).execute()
                }
            }
            try await group.waitForAll()
        }

        do {
            var snapshot = snapshot
            let uploaded = try await syncImages(onto: &snapshot, householdId: snapshot.household.id, userId: userId)
            if uploaded {
                let withPhotos = snapshot.observations.filter { $0.authorId == userId }.map(ObservationRow.init)
                if !withPhotos.isEmpty {
                    try await client.from("observations").upsert(withPhotos).execute()
                }
            }
        } catch {
            // 写真の失敗で、すでに送ったひとことまで巻き戻さない。
        }
    }

    static func downloadMissingImages(
        from snapshot: HouseholdSnapshot,
        alreadyHave: Set<UUID>
    ) async -> [UUID: Data] {
        var copy = snapshot
        await attachImages(to: &copy, skipping: alreadyHave)
        var images: [UUID: Data] = [:]
        for item in copy.observations {
            if let data = item.imageData, !data.isEmpty {
                images[item.id] = data
            }
        }
        return images
    }

    static func publishPendingObservations() async throws {
        let client = try SupabaseConfig.client()
        try await client.rpc("publish_household_observations").execute()
    }

    static func mapCloudError(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        let text = String(describing: error).lowercased()
            + " "
            + (error.localizedDescription.lowercased())
        if text.contains("invalid invite") {
            return .invalidInvite
        }
        if text.contains("household full") {
            return .householdFull
        }
        if text.contains("not configured") {
            return .notConfigured
        }
        return .cloudUnavailable
    }

    @discardableResult
    private static func syncImages(onto snapshot: inout HouseholdSnapshot, householdId: UUID, userId: UUID) async throws -> Bool {
        let client = try SupabaseConfig.client()
        let now = Date()
        var removePaths: [String] = []
        var uploads: [(id: UUID, data: Data, path: String)] = []

        for index in snapshot.observations.indices {
            guard snapshot.observations[index].authorId == userId else { continue }
            let item = snapshot.observations[index]
            let expired = item.imageExpiresAt.map { $0 <= now } ?? false
            if expired || item.imageData == nil || item.imageData?.isEmpty == true {
                if let path = item.imagePath, !path.isEmpty {
                    removePaths.append(path)
                }
                snapshot.observations[index].imagePath = nil
                snapshot.observations[index].imageExpiresAt = nil
                snapshot.observations[index].imageData = nil
                continue
            }
            if let existingPath = item.imagePath, !existingPath.isEmpty {
                continue
            }
            guard let data = item.imageData else { continue }
            let path = "\(householdId.uuidString.lowercased())/\(item.id.uuidString.lowercased()).jpg"
            uploads.append((item.id, data, path))
        }

        var uploadedIDs: Set<UUID> = []
        await withTaskGroup(of: UUID?.self) { group in
            if !removePaths.isEmpty {
                group.addTask {
                    _ = try? await client.storage.from(photoBucket).remove(paths: removePaths)
                    return nil
                }
            }
            for item in uploads {
                group.addTask {
                    do {
                        try await client.storage.from(photoBucket).upload(
                            item.path,
                            data: item.data,
                            options: FileOptions(contentType: "image/jpeg", upsert: true)
                        )
                        return item.id
                    } catch {
                        return nil
                    }
                }
            }
            for await id in group {
                if let id {
                    uploadedIDs.insert(id)
                }
            }
        }

        var uploaded = false
        for item in uploads where uploadedIDs.contains(item.id) {
            guard let index = snapshot.observations.firstIndex(where: { $0.id == item.id }) else { continue }
            snapshot.observations[index].imagePath = item.path
            if snapshot.observations[index].imageExpiresAt == nil {
                snapshot.observations[index].imageExpiresAt = ObservationPhotoPolicy.expiryDate(from: now)
            }
            uploaded = true
        }
        return uploaded
    }

    private static func fetchHouseholdFromTables() async throws -> HouseholdSnapshot? {
        let client = try SupabaseConfig.client()
        let members: [MemberDTO] = try await client
            .from("household_members")
            .select()
            .execute()
            .value
        guard let householdId = members.first?.householdId else { return nil }

        async let householdsTask: [HouseholdDTO] = client
            .from("households")
            .select()
            .eq("id", value: householdId)
            .limit(1)
            .execute()
            .value
        async let usersTask: [UserDTO] = client
            .from("profiles")
            .select()
            .in("id", values: members.map(\.userId.uuidString))
            .execute()
            .value
        async let agreementsTask: [AgreementDTO] = client
            .from("agreements")
            .select()
            .eq("household_id", value: householdId)
            .execute()
            .value
        async let observationsTask: [ObservationDTO] = client
            .from("observations")
            .select()
            .execute()
            .value
        async let reflectionsTask: [ReflectionDTO] = client
            .from("reflections")
            .select()
            .execute()
            .value

        let households = try await householdsTask
        guard let household = households.first else { return nil }
        let users = try await usersTask
        let agreements = try await agreementsTask
        let agreementIds = Set(agreements.map(\.id))
        let observations = try await observationsTask.filter { agreementIds.contains($0.agreementId) }
        let reflections = try await reflectionsTask.filter { agreementIds.contains($0.agreementId) }

        return HouseholdSnapshot(
            household: household,
            users: users,
            members: members,
            agreements: agreements,
            observations: observations,
            reflections: reflections
        )
    }

    private static func fetchHouseholdViaRPC() async throws -> HouseholdSnapshot? {
        let client = try SupabaseConfig.client()
        let response = try await client.rpc("fetch_household_state").execute()
        return try decodeSnapshot(from: response.data)
    }

    private static func decodeSnapshot(from data: Data) throws -> HouseholdSnapshot? {
        if data.isEmpty || data == Data("null".utf8) {
            return nil
        }
        let decoder = SupabaseConfig.makeDecoder()
        if let snapshot = try? decoder.decode(HouseholdSnapshot.self, from: data) {
            return snapshot
        }
        if let wrapped = try? decoder.decode([HouseholdSnapshot].self, from: data) {
            return wrapped.first
        }
        if let raw = try? decoder.decode(String.self, from: data),
           let nested = raw.data(using: .utf8),
           let snapshot = try? decoder.decode(HouseholdSnapshot.self, from: nested) {
            return snapshot
        }
        throw SnapshotDecodeError.failed
    }

    private static func attachImages(to snapshot: inout HouseholdSnapshot, skipping: Set<UUID> = []) async {
        guard let client = try? SupabaseConfig.client() else { return }
        let now = Date()
        await withTaskGroup(of: (UUID, Data?).self) { group in
            for observation in snapshot.observations {
                guard !skipping.contains(observation.id) else { continue }
                guard let path = observation.imagePath, !path.isEmpty else { continue }
                if let expires = observation.imageExpiresAt, expires <= now { continue }
                group.addTask {
                    let data = try? await client.storage.from(photoBucket).download(path: path)
                    return (observation.id, data)
                }
            }
            var images: [UUID: Data] = [:]
            for await (id, data) in group {
                if let data, !data.isEmpty {
                    images[id] = data
                }
            }
            for index in snapshot.observations.indices {
                let item = snapshot.observations[index]
                if let expires = item.imageExpiresAt, expires <= now {
                    snapshot.observations[index].imagePath = nil
                    snapshot.observations[index].imageExpiresAt = nil
                    snapshot.observations[index].imageData = nil
                    continue
                }
                if let data = images[item.id] {
                    snapshot.observations[index].imageData = data
                }
            }
        }
    }
}

private struct CreateHouseholdParams: Encodable {
    var householdId: UUID
    var inviteCode: String
    var displayName: String

    enum CodingKeys: String, CodingKey {
        case householdId = "p_household_id"
        case inviteCode = "p_invite_code"
        case displayName = "p_display_name"
    }
}

private struct JoinHouseholdParams: Encodable {
    var inviteCode: String
    var displayName: String

    enum CodingKeys: String, CodingKey {
        case inviteCode = "p_invite_code"
        case displayName = "p_display_name"
    }
}

private struct ObservationRow: Encodable {
    var id: UUID
    var agreementId: UUID
    var authorId: UUID
    var typeRaw: String
    var note: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var publishedAt: Date?
    var imagePath: String?
    var imageExpiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case agreementId = "agreement_id"
        case authorId = "author_id"
        case typeRaw = "type_raw"
        case note
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case publishedAt = "published_at"
        case imagePath = "image_path"
        case imageExpiresAt = "image_expires_at"
    }

    init(_ dto: ObservationDTO) {
        id = dto.id
        agreementId = dto.agreementId
        authorId = dto.authorId
        typeRaw = dto.typeRaw
        note = dto.note
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
        deletedAt = dto.deletedAt
        publishedAt = dto.publishedAt
        imagePath = dto.imagePath
        imageExpiresAt = dto.imageExpiresAt
    }
}

struct HouseholdSnapshot: Codable {
    var household: HouseholdDTO
    var users: [UserDTO]
    var members: [MemberDTO]
    var agreements: [AgreementDTO]
    var observations: [ObservationDTO]
    var reflections: [ReflectionDTO]
}

struct HouseholdDTO: Codable {
    var id: UUID
    var createdAt: Date
    var inviteCode: String

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case inviteCode = "invite_code"
    }
}

struct UserDTO: Codable {
    var id: UUID
    var displayName: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case createdAt = "created_at"
    }
}

struct MemberDTO: Codable {
    var householdId: UUID
    var userId: UUID
    var joinedAt: Date

    enum CodingKeys: String, CodingKey {
        case householdId = "household_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
    }
}

struct AgreementDTO: Codable {
    var id: UUID
    var householdId: UUID
    var title: String
    var scopeTypeRaw: String
    var specificUserId: UUID?
    var memo: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case title
        case scopeTypeRaw = "scope_type_raw"
        case specificUserId = "specific_user_id"
        case memo
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct ObservationDTO: Codable {
    var id: UUID
    var agreementId: UUID
    var authorId: UUID
    var typeRaw: String
    var note: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var publishedAt: Date?
    var imagePath: String?
    var imageExpiresAt: Date?
    var imageData: Data? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case agreementId = "agreement_id"
        case authorId = "author_id"
        case typeRaw = "type_raw"
        case note
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case publishedAt = "published_at"
        case imagePath = "image_path"
        case imageExpiresAt = "image_expires_at"
    }
}

struct ReflectionDTO: Codable {
    var id: UUID
    var agreementId: UUID
    var userId: UUID
    var weekStartDate: Date
    var applicable: Bool
    var selfReflectionRaw: String?
    var otherApplicable: Bool?
    var otherReflectionRaw: String?
    var completedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case agreementId = "agreement_id"
        case userId = "user_id"
        case weekStartDate = "week_start_date"
        case applicable
        case selfReflectionRaw = "self_reflection_raw"
        case otherApplicable = "other_applicable"
        case otherReflectionRaw = "other_reflection_raw"
        case completedAt = "completed_at"
    }
}

private enum SnapshotDecodeError: Error {
    case failed
}

enum InviteCode {
    static let alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"

    static func make() -> String {
        String((0..<6).compactMap { _ in alphabet.randomElement() })
    }

    static func normalize(_ raw: String) -> String {
        let mapped = (raw.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? raw)
            .uppercased()

        if let fromURL = extractURL(from: mapped), let code = code(from: fromURL) {
            return code
        }

        if let regex = try? NSRegularExpression(pattern: #"招待コード[:：]\s*([A-Z0-9]+)"#),
           let match = regex.firstMatch(in: mapped, range: NSRange(mapped.startIndex..., in: mapped)),
           let range = Range(match.range(at: 1), in: mapped) {
            return String(mapped[range]).filter { alphabet.contains($0) }
        }

        return mapped.filter { alphabet.contains($0) }
    }

    static func code(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "futarigoto" else { return nil }
        if url.host?.lowercased() == "join" {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !path.isEmpty {
                return path.filter { alphabet.contains($0) }
            }
            if let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name.lowercased() == "code" })?.value {
                return value.uppercased().filter { alphabet.contains($0) }
            }
        }
        if url.path.lowercased().contains("join"),
           let last = url.path.split(separator: "/").last {
            return String(last).uppercased().filter { alphabet.contains($0) }
        }
        if let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name.lowercased() == "code" })?.value {
            return value.uppercased().filter { alphabet.contains($0) }
        }
        return nil
    }

    private static func extractURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme?.lowercased() == "futarigoto" {
            return url
        }
        guard let regex = try? NSRegularExpression(pattern: #"futarigoto://[^\s]+"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else {
            return nil
        }
        var urlString = String(text[range])
        if let separator = urlString.range(of: "://") {
            urlString = urlString[..<separator.lowerBound].lowercased() + urlString[separator.lowerBound...]
        }
        return URL(string: urlString)
    }
}
