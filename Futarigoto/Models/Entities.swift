import Foundation
import SwiftData

@Model
final class User {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var createdAt: Date

    init(id: UUID = UUID(), displayName: String, createdAt: Date = .now) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
    }
}

@Model
final class Household {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var inviteCode: String

    init(id: UUID = UUID(), createdAt: Date = .now, inviteCode: String) {
        self.id = id
        self.createdAt = createdAt
        self.inviteCode = inviteCode
    }
}

@Model
final class HouseholdMember {
    var householdId: UUID
    var userId: UUID
    var joinedAt: Date

    init(householdId: UUID, userId: UUID, joinedAt: Date = .now) {
        self.householdId = householdId
        self.userId = userId
        self.joinedAt = joinedAt
    }
}

@Model
final class Agreement {
    @Attribute(.unique) var id: UUID
    var householdId: UUID
    var title: String
    var scopeTypeRaw: String
    var specificUserId: UUID?
    var memo: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    var scopeType: ScopeType {
        get { ScopeType(rawValue: scopeTypeRaw) ?? .both }
        set { scopeTypeRaw = newValue.rawValue }
    }

    var isActive: Bool { deletedAt == nil }

    init(
        id: UUID = UUID(),
        householdId: UUID,
        title: String,
        scopeType: ScopeType,
        specificUserId: UUID? = nil,
        memo: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.householdId = householdId
        self.title = title
        self.scopeTypeRaw = scopeType.rawValue
        self.specificUserId = specificUserId
        self.memo = memo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    func applies(to userId: UUID) -> Bool {
        switch scopeType {
        case .both, .conditional:
            return true
        case .specificUser:
            return specificUserId == userId
        }
    }
}

@Model
final class DailyObservation {
    @Attribute(.unique) var id: UUID
    var agreementId: UUID
    var authorId: UUID
    var typeRaw: String
    var note: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var publishedAt: Date?

    var type: ObservationType {
        get { ObservationType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    var isDeleted: Bool { deletedAt != nil }
    var isPublished: Bool { publishedAt != nil }

    init(
        id: UUID = UUID(),
        agreementId: UUID,
        authorId: UUID,
        type: ObservationType,
        note: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        publishedAt: Date? = nil
    ) {
        self.id = id
        self.agreementId = agreementId
        self.authorId = authorId
        self.typeRaw = type.rawValue
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.publishedAt = publishedAt
    }
}

@Model
final class WeeklyReflection {
    @Attribute(.unique) var id: UUID
    var agreementId: UUID
    var userId: UUID
    var weekStartDate: Date
    var applicable: Bool
    var selfReflectionRaw: String?
    var otherApplicable: Bool?
    var otherReflectionRaw: String?
    var completedAt: Date

    var selfReflection: SelfReflection? {
        get {
            guard let selfReflectionRaw else { return nil }
            return SelfReflection(rawValue: selfReflectionRaw)
        }
        set { selfReflectionRaw = newValue?.rawValue }
    }

    var otherReflection: SelfReflection? {
        get {
            guard let otherReflectionRaw else { return nil }
            return SelfReflection(rawValue: otherReflectionRaw)
        }
        set { otherReflectionRaw = newValue?.rawValue }
    }

    var hasSelfAnswer: Bool {
        applicable == false || selfReflection != nil
    }

    var hasOtherAnswer: Bool {
        guard let otherApplicable else { return false }
        return otherApplicable == false || otherReflection != nil
    }

    init(
        id: UUID = UUID(),
        agreementId: UUID,
        userId: UUID,
        weekStartDate: Date,
        applicable: Bool,
        selfReflection: SelfReflection? = nil,
        otherApplicable: Bool? = nil,
        otherReflection: SelfReflection? = nil,
        completedAt: Date = .now
    ) {
        self.id = id
        self.agreementId = agreementId
        self.userId = userId
        self.weekStartDate = weekStartDate
        self.applicable = applicable
        self.selfReflectionRaw = selfReflection?.rawValue
        self.otherApplicable = otherApplicable
        self.otherReflectionRaw = otherReflection?.rawValue
        self.completedAt = completedAt
    }
}
