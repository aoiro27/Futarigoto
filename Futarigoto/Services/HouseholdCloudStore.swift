import Foundation
import CloudKit

enum HouseholdCloudStore {
    static let containerIdentifier = "iCloud.jp.yukiusui.futarigoto"
    private static let recordType = "HouseholdChunk"
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static var database: CKDatabase {
        CKContainer(identifier: containerIdentifier).publicCloudDatabase
    }

    static func save(slot: Int, snapshot: HouseholdSnapshot) async throws {
        let recordID = CKRecord.ID(recordName: recordName(code: snapshot.household.inviteCode, slot: slot))
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: recordType, recordID: recordID)
        }
        record["inviteCode"] = snapshot.household.inviteCode
        record["slot"] = slot as CKRecordValue
        record["payload"] = try encoder.encode(snapshot) as CKRecordValue
        try await database.save(record)
    }

    static func fetch(slot: Int, code: String) async throws -> HouseholdSnapshot? {
        let recordID = CKRecord.ID(recordName: recordName(code: code, slot: slot))
        do {
            let record = try await database.record(for: recordID)
            guard let data = record["payload"] as? Data else { return nil }
            return try decoder.decode(HouseholdSnapshot.self, from: data)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    static func fetchMerged(code: String) async throws -> HouseholdSnapshot? {
        let slot0 = try await fetch(slot: 0, code: code)
        let slot1 = try await fetch(slot: 1, code: code)
        switch (slot0, slot1) {
        case (nil, nil):
            return nil
        case (let first?, nil):
            return first
        case (nil, let second?):
            return second
        case (let first?, let second?):
            return HouseholdSnapshot.merge(first, second)
        }
    }

    static func mapCloudError(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        guard let ckError = error as? CKError else { return .cloudUnavailable }
        switch ckError.code {
        case .notAuthenticated, .permissionFailure:
            return .cloudAccountNeeded
        case .unknownItem:
            return .invalidInvite
        default:
            return .cloudUnavailable
        }
    }

    private static func recordName(code: String, slot: Int) -> String {
        "\(code)-\(slot)"
    }
}

struct HouseholdSnapshot: Codable {
    var household: HouseholdDTO
    var users: [UserDTO]
    var members: [MemberDTO]
    var agreements: [AgreementDTO]
    var observations: [ObservationDTO]
    var reflections: [ReflectionDTO]

    static func merge(_ lhs: HouseholdSnapshot, _ rhs: HouseholdSnapshot) -> HouseholdSnapshot {
        HouseholdSnapshot(
            household: lhs.household.createdAt <= rhs.household.createdAt ? lhs.household : rhs.household,
            users: merge(lhs.users, rhs.users, id: \.id, newer: { $0.createdAt >= $1.createdAt }),
            members: merge(lhs.members, rhs.members, id: { "\($0.householdId.uuidString)-\($0.userId.uuidString)" }, newer: { $0.joinedAt >= $1.joinedAt }),
            agreements: merge(lhs.agreements, rhs.agreements, id: \.id, newer: { $0.updatedAt >= $1.updatedAt }),
            observations: merge(lhs.observations, rhs.observations, id: \.id, newer: { $0.updatedAt >= $1.updatedAt }),
            reflections: merge(lhs.reflections, rhs.reflections, id: \.id, newer: { $0.completedAt >= $1.completedAt })
        )
    }

    private static func merge<Item, ID: Hashable>(
        _ lhs: [Item],
        _ rhs: [Item],
        id: (Item) -> ID,
        newer: (Item, Item) -> Bool
    ) -> [Item] {
        var map: [ID: Item] = [:]
        for item in lhs + rhs {
            let key = id(item)
            if let existing = map[key] {
                if newer(item, existing) {
                    map[key] = item
                }
            } else {
                map[key] = item
            }
        }
        return Array(map.values)
    }
}

struct HouseholdDTO: Codable {
    var id: UUID
    var createdAt: Date
    var inviteCode: String
}

struct UserDTO: Codable {
    var id: UUID
    var displayName: String
    var createdAt: Date
}

struct MemberDTO: Codable {
    var householdId: UUID
    var userId: UUID
    var joinedAt: Date
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
