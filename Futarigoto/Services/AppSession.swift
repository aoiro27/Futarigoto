import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class AppSession {
    private(set) var currentUserID: UUID?
    var pendingInviteCode: String?
    var showsPostCreateInvite = false
    var didAttach = false
    var cloudPublishFailed = false
    var syncRevision = 0

    @ObservationIgnored
    private var modelContext: ModelContext?

    private let userDefaultsKey = "currentUserID"
    private let partnerRevealPrefix = "partnerRevealSeen."
    private let cloudSlotPrefix = "cloudSlot."

    func attach(modelContext: ModelContext) {
        self.modelContext = modelContext
        if let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
           let id = UUID(uuidString: raw),
           user(id: id) != nil {
            currentUserID = id
        }
        didAttach = true
        Task { await refreshFromCloud() }
    }

    func handleIncomingURL(_ url: URL) {
        if let code = InviteCode.code(from: url), !code.isEmpty {
            pendingInviteCode = code
        }
    }

    var currentUser: User? {
        guard let currentUserID else { return nil }
        return user(id: currentUserID)
    }

    var currentHousehold: Household? {
        guard let userId = currentUserID,
              let member = members().first(where: { $0.userId == userId }) else { return nil }
        return household(id: member.householdId)
    }

    var currentHouseholdID: UUID? { currentHousehold?.id }

    var partner: User? {
        let _ = syncRevision
        guard let householdId = currentHouseholdID, let userId = currentUserID else { return nil }
        let other = members(in: householdId).first(where: { $0.userId != userId })
        guard let other else { return nil }
        return user(id: other.userId)
    }

    var householdMembers: [User] {
        let _ = syncRevision
        guard let householdId = currentHouseholdID else { return [] }
        return members(in: householdId).compactMap { user(id: $0.userId) }
    }

    var isOnboarded: Bool {
        currentUser != nil && currentHousehold != nil
    }

    var canInvitePartner: Bool {
        let _ = syncRevision
        guard let householdId = currentHouseholdID else { return false }
        return members(in: householdId).count < 2
    }

    var inviteURL: URL? {
        guard let code = currentHousehold?.inviteCode else { return nil }
        return URL(string: "futarigoto://join?code=\(code)")
    }

    var inviteShareText: String {
        guard let code = currentHousehold?.inviteCode else { return "" }
        return "「ふたりごと」で一緒にはじめませんか？\n招待コード: \(code)\n\(inviteURL?.absoluteString ?? "")"
    }

    // MARK: - Onboarding

    func createUserAndHousehold(displayName: String) async throws {
        let context = try requireContext()
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let user = User(displayName: trimmed)
        let household = Household(inviteCode: InviteCode.make())
        let member = HouseholdMember(householdId: household.id, userId: user.id)
        context.insert(user)
        context.insert(household)
        context.insert(member)
        try context.save()
        setCurrentUser(user.id)
        rememberCloudSlot(0, householdId: household.id)
        showsPostCreateInvite = true
        NotificationService.shared.requestAuthorization()
        await publishToCloud(markFailure: true)
    }

    func dismissPostCreateInvite() {
        showsPostCreateInvite = false
    }

    func createUserAndJoin(displayName: String, code: String) async throws {
        let context = try requireContext()
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = InviteCode.normalize(code)
        guard !trimmed.isEmpty, !normalized.isEmpty else {
            throw AppError.invalidInvite
        }

        var joinedViaCloud = false
        if household(byCode: normalized) == nil {
            do {
                guard let remote = try await HouseholdCloudStore.fetchMerged(code: normalized) else {
                    throw AppError.invalidInvite
                }
                if remote.members.count >= 2 {
                    throw AppError.householdFull
                }
                try installSnapshot(remote)
                joinedViaCloud = true
            } catch let error as AppError {
                throw error
            } catch {
                throw HouseholdCloudStore.mapCloudError(error)
            }
        }

        guard let household = household(byCode: normalized) else {
            throw AppError.invalidInvite
        }
        if members(in: household.id).count >= 2 {
            throw AppError.householdFull
        }
        let user = User(displayName: trimmed)
        let member = HouseholdMember(householdId: household.id, userId: user.id)
        context.insert(user)
        context.insert(member)
        try context.save()
        setCurrentUser(user.id)
        rememberCloudSlot(joinedViaCloud ? 1 : 0, householdId: household.id)
        pendingInviteCode = nil
        NotificationService.shared.requestAuthorization()
        await publishToCloud(markFailure: true)
    }

    // MARK: - Agreements

    func activeAgreements() -> [Agreement] {
        guard let householdId = currentHouseholdID else { return [] }
        return allAgreements()
            .filter { $0.householdId == householdId && $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func agreement(id: UUID) -> Agreement? {
        allAgreements().first(where: { $0.id == id })
    }

    func addAgreement(title: String, scope: ScopeFormSelection, memo: String?) throws {
        let context = try requireContext()
        guard let householdId = currentHouseholdID, currentUserID != nil else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let resolved = resolve(scope: scope)
        let agreement = Agreement(
            householdId: householdId,
            title: String(trimmed.prefix(100)),
            scopeType: resolved.type,
            specificUserId: resolved.specificUserId,
            memo: normalizedMemo(memo)
        )
        context.insert(agreement)
        try context.save()
        schedulePublishToCloud()
    }

    func updateAgreement(_ agreement: Agreement, title: String, scope: ScopeFormSelection, memo: String?) throws {
        let context = try requireContext()
        guard currentUserID != nil else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let resolved = resolve(scope: scope)
        agreement.title = String(trimmed.prefix(100))
        agreement.scopeType = resolved.type
        agreement.specificUserId = resolved.specificUserId
        agreement.memo = normalizedMemo(memo)
        agreement.updatedAt = .now
        try context.save()
        schedulePublishToCloud()
    }

    func deleteAgreement(_ agreement: Agreement) throws {
        let context = try requireContext()
        agreement.deletedAt = .now
        agreement.updatedAt = .now
        try context.save()
        schedulePublishToCloud()
    }

    func scopeDisplay(for agreement: Agreement) -> String {
        switch agreement.scopeType {
        case .both:
            return AppCopy.both
        case .conditional:
            return AppCopy.conditional
        case .specificUser:
            if let id = agreement.specificUserId, let user = user(id: id) {
                return user.displayName
            }
            return AppCopy.partner
        }
    }

    func formSelection(for agreement: Agreement) -> ScopeFormSelection {
        switch agreement.scopeType {
        case .both, .conditional:
            return .both
        case .specificUser:
            if let id = agreement.specificUserId {
                return .member(id)
            }
            return .both
        }
    }

    func scopeOptions() -> [ScopeFormSelection] {
        [.both] + orderedScopeMembers().map { .member($0.id) }
    }

    func scopeLabel(for option: ScopeFormSelection) -> String {
        switch option {
        case .both:
            return AppCopy.both
        case .member(let id):
            return user(id: id)?.displayName ?? AppCopy.partner
        }
    }

    func applicableAgreements(for userId: UUID) -> [Agreement] {
        activeAgreements().filter { $0.applies(to: userId) }
    }

    // MARK: - Observations

    func observationsThisWeek(for userId: UUID) -> [DailyObservation] {
        let start = AppWeek.start(of: .now)
        return allObservations()
            .filter {
                $0.authorId == userId &&
                !$0.isDeleted &&
                AppWeek.contains($0.createdAt, weekStart: start)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func addObservation(agreementId: UUID, type: ObservationType, note: String?) throws {
        let context = try requireContext()
        guard let userId = currentUserID else { return }
        let observation = DailyObservation(
            agreementId: agreementId,
            authorId: userId,
            type: type,
            note: normalizedNote(note)
        )
        context.insert(observation)
        try context.save()
        schedulePublishToCloud()
    }

    func updateObservation(_ observation: DailyObservation, type: ObservationType, note: String?) throws {
        guard !observation.isPublished else { return }
        let context = try requireContext()
        observation.type = type
        observation.note = normalizedNote(note)
        observation.updatedAt = .now
        try context.save()
        schedulePublishToCloud()
    }

    func deleteObservation(_ observation: DailyObservation) throws {
        guard !observation.isPublished else { return }
        let context = try requireContext()
        observation.deletedAt = .now
        observation.updatedAt = .now
        try context.save()
        schedulePublishToCloud()
    }

    func visibleHistory(for agreement: Agreement) -> [DailyObservation] {
        guard let userId = currentUserID else { return [] }
        return allObservations()
            .filter { observation in
                observation.agreementId == agreement.id &&
                !observation.isDeleted &&
                (observation.authorId == userId || observation.isPublished)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func weeklySummaries(for agreement: Agreement) -> [WeekSummary] {
        let items = visibleHistory(for: agreement)
        let grouped = Dictionary(grouping: items) { AppWeek.start(of: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { start in
            let list = grouped[start] ?? []
            return WeekSummary(
                weekStart: start,
                label: AppWeek.weekLabel(for: start),
                positiveCount: list.filter { $0.type == .positive }.count,
                concernCount: list.filter { $0.type == .concern }.count,
                otherCount: list.filter { $0.type == .other }.count
            )
        }
    }

    func monthlyConcerns(for agreement: Agreement) -> [MonthSummary] {
        let items = visibleHistory(for: agreement).filter { $0.type == .concern }
        let grouped = Dictionary(grouping: items) { AppWeek.monthStart(of: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { start in
            MonthSummary(
                monthStart: start,
                label: AppWeek.monthLabel(for: start),
                concernCount: grouped[start]?.count ?? 0
            )
        }
    }

    // MARK: - Review

    func todayReviewDate() -> Date {
        AppWeek.startOfDay(.now)
    }

    func hasCompletedOwnReview(reviewDate: Date) -> Bool {
        guard let userId = currentUserID else { return false }
        return hasCompletedReview(userId: userId, reviewDate: reviewDate)
    }

    func bothCompletedReview(reviewDate: Date) -> Bool {
        let people = householdMembers
        guard people.count == 2 else { return false }
        return people.allSatisfy { hasCompletedReview(userId: $0.id, reviewDate: reviewDate) }
    }

    private func hasCompletedReview(userId: UUID, reviewDate: Date) -> Bool {
        let existing = reflections(userId: userId, reviewDate: reviewDate)
        let byAgreement = Dictionary(uniqueKeysWithValues: existing.map { ($0.agreementId, $0) })
        let myAgreements = applicableAgreements(for: userId)
        let otherId = householdMembers.first(where: { $0.id != userId })?.id
        let otherAgreements = otherId.map { applicableAgreements(for: $0) } ?? []
        guard !myAgreements.isEmpty || !otherAgreements.isEmpty else { return false }

        for agreement in myAgreements {
            guard let item = byAgreement[agreement.id], item.hasSelfAnswer else { return false }
        }
        for agreement in otherAgreements {
            guard let item = byAgreement[agreement.id], item.hasOtherAnswer else { return false }
        }
        return true
    }

    func saveReflections(_ drafts: [ReflectionDraft], reviewDate: Date) throws {
        let context = try requireContext()
        guard let userId = currentUserID else { return }
        let day = AppWeek.startOfDay(reviewDate)
        for draft in drafts {
            if let existing = reflections(userId: userId, reviewDate: day)
                .first(where: { $0.agreementId == draft.agreementId }) {
                if let applicable = draft.applicable {
                    existing.applicable = applicable
                    existing.selfReflection = draft.selfReflection
                }
                if draft.otherApplicable != nil {
                    existing.otherApplicable = draft.otherApplicable
                    existing.otherReflection = draft.otherReflection
                }
                existing.completedAt = .now
            } else {
                let item = WeeklyReflection(
                    agreementId: draft.agreementId,
                    userId: userId,
                    weekStartDate: day,
                    applicable: draft.applicable ?? false,
                    selfReflection: draft.selfReflection,
                    otherApplicable: draft.otherApplicable,
                    otherReflection: draft.otherReflection
                )
                context.insert(item)
            }
        }
        try context.save()
        schedulePublishToCloud()

        let hadUnpublished = allObservations().contains { !$0.isDeleted && !$0.isPublished }
        if bothCompletedReview(reviewDate: day) || partner == nil {
            publishUnpublishedObservations()
            if householdMembers.count == 2, hadUnpublished {
                NotificationService.shared.notifyBothReflectionsReady()
            }
        }
    }

    func revealReviewNotesIfNeeded(reviewDate: Date) {
        guard bothCompletedReview(reviewDate: reviewDate) || partner == nil else { return }
        publishUnpublishedObservations()
    }

    func markPartnerRevealSeen(reviewDate: Date) {
        guard let userId = currentUserID else { return }
        UserDefaults.standard.set(true, forKey: revealKey(userId: userId, reviewDate: reviewDate))
    }

    func hasSeenPartnerReveal(reviewDate: Date) -> Bool {
        guard let userId = currentUserID else { return false }
        return UserDefaults.standard.bool(forKey: revealKey(userId: userId, reviewDate: reviewDate))
    }

    func pastReviewDates() -> [Date] {
        let people = Set(householdMembers.map(\.id))
        let days = Set(
            allReflections()
                .filter { people.contains($0.userId) }
                .map { AppWeek.startOfDay($0.weekStartDate) }
        )
        return days.sorted(by: >)
    }

    // MARK: - Private

    private func publishUnpublishedObservations() {
        guard let context = modelContext, let householdId = currentHouseholdID else { return }
        let agreementIDs = Set(allAgreements().filter { $0.householdId == householdId }.map(\.id))
        let targets = allObservations().filter {
            agreementIDs.contains($0.agreementId) &&
            !$0.isDeleted &&
            !$0.isPublished
        }
        for item in targets {
            item.publishedAt = .now
            item.updatedAt = .now
        }
        try? context.save()
        schedulePublishToCloud()
    }

    private func setCurrentUser(_ id: UUID) {
        currentUserID = id
        UserDefaults.standard.set(id.uuidString, forKey: userDefaultsKey)
    }

    private func revealKey(userId: UUID, reviewDate: Date) -> String {
        "\(partnerRevealPrefix)\(userId.uuidString).\(AppWeek.startOfDay(reviewDate).timeIntervalSince1970)"
    }

    private func resolve(scope: ScopeFormSelection) -> (type: ScopeType, specificUserId: UUID?) {
        switch scope {
        case .both:
            return (.both, nil)
        case .member(let id):
            return (.specificUser, id)
        }
    }

    private func orderedScopeMembers() -> [User] {
        householdMembers.sorted { lhs, rhs in
            if lhs.id == currentUserID { return true }
            if rhs.id == currentUserID { return false }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func normalizedMemo(_ memo: String?) -> String? {
        let value = memo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : String(value.prefix(300))
    }

    private func normalizedNote(_ note: String?) -> String? {
        let value = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : String(value.prefix(300))
    }

    private func requireContext() throws -> ModelContext {
        guard let modelContext else { throw AppError.notReady }
        return modelContext
    }

    private func user(id: UUID) -> User? {
        guard let modelContext else { return nil }
        var descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func household(id: UUID) -> Household? {
        guard let modelContext else { return nil }
        var descriptor = FetchDescriptor<Household>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func household(byCode code: String) -> Household? {
        guard let modelContext else { return nil }
        let all = (try? modelContext.fetch(FetchDescriptor<Household>())) ?? []
        return all.first { InviteCode.normalize($0.inviteCode) == code }
    }

    private func members(in householdId: UUID? = nil) -> [HouseholdMember] {
        guard let modelContext else { return [] }
        let all = (try? modelContext.fetch(FetchDescriptor<HouseholdMember>())) ?? []
        if let householdId {
            return all.filter { $0.householdId == householdId }
        }
        return all
    }

    private func allAgreements() -> [Agreement] {
        guard let modelContext else { return [] }
        return (try? modelContext.fetch(FetchDescriptor<Agreement>())) ?? []
    }

    private func allObservations() -> [DailyObservation] {
        guard let modelContext else { return [] }
        return (try? modelContext.fetch(FetchDescriptor<DailyObservation>())) ?? []
    }

    private func reflections(userId: UUID, reviewDate: Date) -> [WeeklyReflection] {
        allReflections().filter {
            $0.userId == userId && AppWeek.isSameDay($0.weekStartDate, reviewDate)
        }
    }

    private func allReflections() -> [WeeklyReflection] {
        guard let modelContext else { return [] }
        return (try? modelContext.fetch(FetchDescriptor<WeeklyReflection>())) ?? []
    }

    private func allUsers() -> [User] {
        guard let modelContext else { return [] }
        return (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
    }

    private func allHouseholds() -> [Household] {
        guard let modelContext else { return [] }
        return (try? modelContext.fetch(FetchDescriptor<Household>())) ?? []
    }

    private func rememberCloudSlot(_ slot: Int, householdId: UUID) {
        UserDefaults.standard.set(slot, forKey: cloudSlotPrefix + householdId.uuidString)
    }

    private func currentCloudSlot() -> Int? {
        guard let householdId = currentHouseholdID else { return nil }
        let key = cloudSlotPrefix + householdId.uuidString
        if UserDefaults.standard.object(forKey: key) == nil {
            return 0
        }
        return UserDefaults.standard.integer(forKey: key)
    }

    func retryCloudPublish() async {
        await publishToCloud(markFailure: true)
    }

    func refreshFromCloud() async {
        guard let code = currentHousehold?.inviteCode else { return }
        do {
            guard let remote = try await HouseholdCloudStore.fetchMerged(code: InviteCode.normalize(code)) else { return }
            try installSnapshot(remote)
            cloudPublishFailed = false
        } catch {
            // Keep local data if the cloud copy cannot be read yet.
        }
    }

    private func schedulePublishToCloud() {
        Task { await publishToCloud(markFailure: false) }
    }

    private func publishToCloud(markFailure: Bool) async {
        guard let snapshot = makeSnapshot(), let slot = currentCloudSlot() else { return }
        do {
            try await HouseholdCloudStore.save(slot: slot, snapshot: snapshot)
            cloudPublishFailed = false
        } catch {
            if markFailure {
                cloudPublishFailed = true
            }
        }
    }

    private func makeSnapshot() -> HouseholdSnapshot? {
        guard let household = currentHousehold else { return nil }
        let memberList = members(in: household.id)
        let userIDs = Set(memberList.map(\.userId))
        let agreementList = allAgreements().filter { $0.householdId == household.id }
        let agreementIDs = Set(agreementList.map(\.id))
        return HouseholdSnapshot(
            household: HouseholdDTO(id: household.id, createdAt: household.createdAt, inviteCode: household.inviteCode),
            users: allUsers().filter { userIDs.contains($0.id) }.map {
                UserDTO(id: $0.id, displayName: $0.displayName, createdAt: $0.createdAt)
            },
            members: memberList.map {
                MemberDTO(householdId: $0.householdId, userId: $0.userId, joinedAt: $0.joinedAt)
            },
            agreements: agreementList.map {
                AgreementDTO(
                    id: $0.id,
                    householdId: $0.householdId,
                    title: $0.title,
                    scopeTypeRaw: $0.scopeTypeRaw,
                    specificUserId: $0.specificUserId,
                    memo: $0.memo,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    deletedAt: $0.deletedAt
                )
            },
            observations: allObservations().filter { agreementIDs.contains($0.agreementId) }.map {
                ObservationDTO(
                    id: $0.id,
                    agreementId: $0.agreementId,
                    authorId: $0.authorId,
                    typeRaw: $0.typeRaw,
                    note: $0.note,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    deletedAt: $0.deletedAt,
                    publishedAt: $0.publishedAt
                )
            },
            reflections: allReflections().filter { agreementIDs.contains($0.agreementId) }.map {
                ReflectionDTO(
                    id: $0.id,
                    agreementId: $0.agreementId,
                    userId: $0.userId,
                    weekStartDate: $0.weekStartDate,
                    applicable: $0.applicable,
                    selfReflectionRaw: $0.selfReflectionRaw,
                    otherApplicable: $0.otherApplicable,
                    otherReflectionRaw: $0.otherReflectionRaw,
                    completedAt: $0.completedAt
                )
            }
        )
    }

    @discardableResult
    private func installSnapshot(_ snapshot: HouseholdSnapshot) throws -> Household {
        let context = try requireContext()

        let household: Household
        if let existing = allHouseholds().first(where: { $0.id == snapshot.household.id }) {
            existing.inviteCode = snapshot.household.inviteCode
            household = existing
        } else {
            household = Household(
                id: snapshot.household.id,
                createdAt: snapshot.household.createdAt,
                inviteCode: snapshot.household.inviteCode
            )
            context.insert(household)
        }

        for dto in snapshot.users {
            if let existing = allUsers().first(where: { $0.id == dto.id }) {
                existing.displayName = dto.displayName
            } else {
                context.insert(User(id: dto.id, displayName: dto.displayName, createdAt: dto.createdAt))
            }
        }

        let existingMembers = members()
        for dto in snapshot.members {
            if !existingMembers.contains(where: { $0.householdId == dto.householdId && $0.userId == dto.userId }) {
                context.insert(HouseholdMember(householdId: dto.householdId, userId: dto.userId, joinedAt: dto.joinedAt))
            }
        }

        let existingAgreements = allAgreements()
        for dto in snapshot.agreements {
            if let existing = existingAgreements.first(where: { $0.id == dto.id }) {
                if dto.updatedAt >= existing.updatedAt {
                    existing.title = dto.title
                    existing.scopeTypeRaw = dto.scopeTypeRaw
                    existing.specificUserId = dto.specificUserId
                    existing.memo = dto.memo
                    existing.updatedAt = dto.updatedAt
                    existing.deletedAt = dto.deletedAt
                }
            } else {
                context.insert(
                    Agreement(
                        id: dto.id,
                        householdId: dto.householdId,
                        title: dto.title,
                        scopeType: ScopeType(rawValue: dto.scopeTypeRaw) ?? .both,
                        specificUserId: dto.specificUserId,
                        memo: dto.memo,
                        createdAt: dto.createdAt,
                        updatedAt: dto.updatedAt,
                        deletedAt: dto.deletedAt
                    )
                )
            }
        }

        let existingObservations = allObservations()
        for dto in snapshot.observations {
            if let existing = existingObservations.first(where: { $0.id == dto.id }) {
                if dto.updatedAt >= existing.updatedAt {
                    existing.typeRaw = dto.typeRaw
                    existing.note = dto.note
                    existing.updatedAt = dto.updatedAt
                    existing.deletedAt = dto.deletedAt
                    existing.publishedAt = dto.publishedAt
                }
            } else {
                context.insert(
                    DailyObservation(
                        id: dto.id,
                        agreementId: dto.agreementId,
                        authorId: dto.authorId,
                        type: ObservationType(rawValue: dto.typeRaw) ?? .other,
                        note: dto.note,
                        createdAt: dto.createdAt,
                        updatedAt: dto.updatedAt,
                        deletedAt: dto.deletedAt,
                        publishedAt: dto.publishedAt
                    )
                )
            }
        }

        let existingReflections = allReflections()
        for dto in snapshot.reflections {
            if let existing = existingReflections.first(where: { $0.id == dto.id }) {
                if dto.completedAt >= existing.completedAt {
                    existing.applicable = dto.applicable
                    existing.selfReflectionRaw = dto.selfReflectionRaw
                    existing.otherApplicable = dto.otherApplicable
                    existing.otherReflectionRaw = dto.otherReflectionRaw
                    existing.completedAt = dto.completedAt
                    existing.weekStartDate = dto.weekStartDate
                }
            } else {
                let item = WeeklyReflection(
                    id: dto.id,
                    agreementId: dto.agreementId,
                    userId: dto.userId,
                    weekStartDate: dto.weekStartDate,
                    applicable: dto.applicable,
                    otherApplicable: dto.otherApplicable,
                    completedAt: dto.completedAt
                )
                item.selfReflectionRaw = dto.selfReflectionRaw
                item.otherReflectionRaw = dto.otherReflectionRaw
                context.insert(item)
            }
        }

        try context.save()
        syncRevision += 1
        return household
    }
}

enum ScopeFormSelection: Hashable, Identifiable {
    case both
    case member(UUID)

    var id: String {
        switch self {
        case .both:
            return "both"
        case .member(let id):
            return id.uuidString
        }
    }
}

struct ReflectionDraft: Identifiable {
    var agreementId: UUID
    var applicable: Bool?
    var selfReflection: SelfReflection?
    var otherApplicable: Bool?
    var otherReflection: SelfReflection?

    var id: UUID { agreementId }
}

struct WeekSummary: Identifiable {
    var weekStart: Date
    var label: String
    var positiveCount: Int
    var concernCount: Int
    var otherCount: Int
    var id: Date { weekStart }
}

struct MonthSummary: Identifiable {
    var monthStart: Date
    var label: String
    var concernCount: Int
    var id: Date { monthStart }
}

enum AppError: LocalizedError {
    case notReady
    case invalidInvite
    case householdFull
    case cloudAccountNeeded
    case cloudUnavailable

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "準備ができていません。"
        case .invalidInvite:
            return "招待コードが見つかりませんでした。"
        case .householdFull:
            return "この家庭はすでにふたりで始まっています。"
        case .cloudAccountNeeded:
            return "招待コードでつながるには、iCloudにサインインしてください。"
        case .cloudUnavailable:
            return "通信できませんでした。時間をおいてもう一度試してください。"
        }
    }
}
