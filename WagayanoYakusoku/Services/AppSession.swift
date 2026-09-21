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

    @ObservationIgnored
    private var modelContext: ModelContext?

    private let userDefaultsKey = "currentUserID"
    private let partnerRevealPrefix = "partnerRevealSeen."

    func attach(modelContext: ModelContext) {
        self.modelContext = modelContext
        if let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
           let id = UUID(uuidString: raw),
           user(id: id) != nil {
            currentUserID = id
        }
        didAttach = true
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme == "wagayano-yakusoku" else { return }
        let code: String?
        if url.host == "join" {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            code = path.isEmpty ? URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value : path
        } else if url.path.contains("join") {
            code = url.path.split(separator: "/").last.map(String.init)
        } else {
            code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value
        }
        if let code, !code.isEmpty {
            pendingInviteCode = code.uppercased()
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
        guard let householdId = currentHouseholdID, let userId = currentUserID else { return nil }
        let other = members(in: householdId).first(where: { $0.userId != userId })
        guard let other else { return nil }
        return user(id: other.userId)
    }

    var householdMembers: [User] {
        guard let householdId = currentHouseholdID else { return [] }
        return members(in: householdId).compactMap { user(id: $0.userId) }
    }

    var isOnboarded: Bool {
        currentUser != nil && currentHousehold != nil
    }

    var canInvitePartner: Bool {
        guard let householdId = currentHouseholdID else { return false }
        return members(in: householdId).count < 2
    }

    var inviteURL: URL? {
        guard let code = currentHousehold?.inviteCode else { return nil }
        return URL(string: "wagayano-yakusoku://join?code=\(code)")
    }

    var inviteShareText: String {
        guard let code = currentHousehold?.inviteCode else { return "" }
        return "「わが家の約束」で一緒にはじめませんか？\n招待コード: \(code)\n\(inviteURL?.absoluteString ?? "")"
    }

    // MARK: - Onboarding

    func createUserAndHousehold(displayName: String) throws {
        let context = try requireContext()
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let user = User(displayName: trimmed)
        let household = Household(inviteCode: Self.makeInviteCode())
        let member = HouseholdMember(householdId: household.id, userId: user.id)
        context.insert(user)
        context.insert(household)
        context.insert(member)
        try context.save()
        setCurrentUser(user.id)
        showsPostCreateInvite = true
        NotificationService.shared.requestAuthorization()
    }

    func dismissPostCreateInvite() {
        showsPostCreateInvite = false
    }

    func createUserAndJoin(displayName: String, code: String) throws {
        let context = try requireContext()
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty, !normalized.isEmpty else {
            throw AppError.invalidInvite
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
        pendingInviteCode = nil
        NotificationService.shared.requestAuthorization()
    }

    func addPartnerOnThisDevice(displayName: String) throws {
        let context = try requireContext()
        guard let householdId = currentHouseholdID else { return }
        if members(in: householdId).count >= 2 {
            throw AppError.householdFull
        }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let user = User(displayName: trimmed)
        let member = HouseholdMember(householdId: householdId, userId: user.id)
        context.insert(user)
        context.insert(member)
        try context.save()
        setCurrentUser(user.id)
    }

    func switchToUser(_ user: User) {
        setCurrentUser(user.id)
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
        guard let householdId = currentHouseholdID, let userId = currentUserID else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let resolved = resolve(scope: scope, currentUserId: userId)
        let agreement = Agreement(
            householdId: householdId,
            title: String(trimmed.prefix(100)),
            scopeType: resolved.type,
            specificUserId: resolved.specificUserId,
            memo: normalizedMemo(memo)
        )
        context.insert(agreement)
        try context.save()
    }

    func updateAgreement(_ agreement: Agreement, title: String, scope: ScopeFormSelection, memo: String?) throws {
        let context = try requireContext()
        guard let userId = currentUserID else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let resolved = resolve(scope: scope, currentUserId: userId)
        agreement.title = String(trimmed.prefix(100))
        agreement.scopeType = resolved.type
        agreement.specificUserId = resolved.specificUserId
        agreement.memo = normalizedMemo(memo)
        agreement.updatedAt = .now
        try context.save()
    }

    func deleteAgreement(_ agreement: Agreement) throws {
        let context = try requireContext()
        agreement.deletedAt = .now
        agreement.updatedAt = .now
        try context.save()
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
        case .both: return .both
        case .conditional: return .conditional
        case .specificUser:
            if agreement.specificUserId == currentUserID {
                return .myself
            }
            return .partner
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
    }

    func updateObservation(_ observation: DailyObservation, type: ObservationType, note: String?) throws {
        guard !observation.isPublished else { return }
        let context = try requireContext()
        observation.type = type
        observation.note = normalizedNote(note)
        observation.updatedAt = .now
        try context.save()
    }

    func deleteObservation(_ observation: DailyObservation) throws {
        guard !observation.isPublished else { return }
        let context = try requireContext()
        observation.deletedAt = .now
        observation.updatedAt = .now
        try context.save()
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

    // MARK: - Weekly review

    func reviewWeekStart(on date: Date = .now) -> Date? {
        guard currentUserID != nil else { return nil }
        let thisWeek = AppWeek.start(of: date)
        let candidates = AppWeek.isSunday(date) ? [thisWeek] : [AppWeek.previousWeekStart(from: date)]
        for week in candidates {
            if !hasCompletedOwnReview(weekStart: week) {
                return week
            }
            if partner != nil,
               bothCompletedReview(weekStart: week),
               !hasSeenPartnerReveal(weekStart: week) {
                return week
            }
        }
        return nil
    }

    var isReviewAvailable: Bool {
        reviewWeekStart() != nil
    }

    func hasCompletedOwnReview(weekStart: Date) -> Bool {
        guard let userId = currentUserID else { return false }
        let targets = applicableAgreements(for: userId)
        guard !targets.isEmpty else { return true }
        let existing = reflections(userId: userId, weekStart: weekStart)
        let ids = Set(existing.map(\.agreementId))
        return targets.allSatisfy { ids.contains($0.id) }
    }

    func bothCompletedReview(weekStart: Date) -> Bool {
        let people = householdMembers
        guard people.count == 2 else { return false }
        return people.allSatisfy { member in
            let targets = applicableAgreements(for: member.id)
            if targets.isEmpty { return true }
            let existing = reflections(userId: member.id, weekStart: weekStart)
            let ids = Set(existing.map(\.agreementId))
            return targets.allSatisfy { ids.contains($0.id) }
        }
    }

    func saveReflections(_ drafts: [ReflectionDraft], weekStart: Date) throws {
        let context = try requireContext()
        guard let userId = currentUserID else { return }
        for draft in drafts {
            if let existing = reflections(userId: userId, weekStart: weekStart)
                .first(where: { $0.agreementId == draft.agreementId }) {
                existing.applicable = draft.applicable
                existing.selfReflection = draft.selfReflection
                existing.completedAt = .now
            } else {
                let item = WeeklyReflection(
                    agreementId: draft.agreementId,
                    userId: userId,
                    weekStartDate: weekStart,
                    applicable: draft.applicable,
                    selfReflection: draft.selfReflection
                )
                context.insert(item)
            }
        }
        try context.save()

        let alreadyPublished = allObservations().contains {
            AppWeek.contains($0.createdAt, weekStart: weekStart) && $0.isPublished
        }
        if bothCompletedReview(weekStart: weekStart) {
            publishObservations(in: weekStart)
            if householdMembers.count == 2, !alreadyPublished {
                NotificationService.shared.notifyBothReflectionsReady()
            }
        }
    }

    func partnerObservations(weekStart: Date) -> [DailyObservation] {
        guard let partnerId = partner?.id else { return [] }
        return allObservations()
            .filter {
                $0.authorId == partnerId &&
                !$0.isDeleted &&
                AppWeek.contains($0.createdAt, weekStart: weekStart) &&
                $0.isPublished
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func markPartnerRevealSeen(weekStart: Date) {
        guard let userId = currentUserID else { return }
        UserDefaults.standard.set(true, forKey: revealKey(userId: userId, weekStart: weekStart))
    }

    func hasSeenPartnerReveal(weekStart: Date) -> Bool {
        guard let userId = currentUserID else { return false }
        return UserDefaults.standard.bool(forKey: revealKey(userId: userId, weekStart: weekStart))
    }

    // MARK: - Private

    private func publishObservations(in weekStart: Date) {
        guard let context = modelContext, let householdId = currentHouseholdID else { return }
        let agreementIDs = Set(allAgreements().filter { $0.householdId == householdId }.map(\.id))
        let targets = allObservations().filter {
            agreementIDs.contains($0.agreementId) &&
            !$0.isDeleted &&
            !$0.isPublished &&
            AppWeek.contains($0.createdAt, weekStart: weekStart)
        }
        for item in targets {
            item.publishedAt = .now
        }
        try? context.save()
    }

    private func setCurrentUser(_ id: UUID) {
        currentUserID = id
        UserDefaults.standard.set(id.uuidString, forKey: userDefaultsKey)
    }

    private func revealKey(userId: UUID, weekStart: Date) -> String {
        "\(partnerRevealPrefix)\(userId.uuidString).\(weekStart.timeIntervalSince1970)"
    }

    private func resolve(scope: ScopeFormSelection, currentUserId: UUID) -> (type: ScopeType, specificUserId: UUID?) {
        switch scope {
        case .both:
            return (.both, nil)
        case .conditional:
            return (.conditional, nil)
        case .myself:
            return (.specificUser, currentUserId)
        case .partner:
            return (.specificUser, partner?.id)
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
        var descriptor = FetchDescriptor<Household>(predicate: #Predicate { $0.inviteCode == code })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
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

    private func reflections(userId: UUID, weekStart: Date) -> [WeeklyReflection] {
        guard let modelContext else { return [] }
        let all = (try? modelContext.fetch(FetchDescriptor<WeeklyReflection>())) ?? []
        return all.filter {
            $0.userId == userId && AppWeek.calendar.isDate($0.weekStartDate, inSameDayAs: weekStart)
        }
    }

    static func makeInviteCode() -> String {
        let chars = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
        return String((0..<6).compactMap { _ in chars.randomElement() })
    }
}

enum ScopeFormSelection: String, CaseIterable, Identifiable {
    case both
    case conditional
    case myself
    case partner

    var id: String { rawValue }

    var label: String {
        switch self {
        case .both: AppCopy.both
        case .conditional: AppCopy.conditional
        case .myself: AppCopy.myself
        case .partner: AppCopy.partner
        }
    }
}

struct ReflectionDraft: Identifiable {
    var agreementId: UUID
    var applicable: Bool
    var selfReflection: SelfReflection?

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

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "準備ができていません。"
        case .invalidInvite:
            return "招待コードが見つかりませんでした。"
        case .householdFull:
            return "この家庭はすでにふたりで始まっています。"
        }
    }
}
