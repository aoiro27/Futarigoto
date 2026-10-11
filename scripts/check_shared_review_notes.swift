import Foundation

// Exercise the production sharing methods with an in-memory server that hides
// unpublished partner notes, like fetch_household_state and observations RLS.
final class Note {
    let id = UUID()
    let agreementId: UUID
    let author: String
    var publishedAt: Date?
    var updatedAt = Date()
    var isDeleted = false
    var isPublished: Bool { publishedAt != nil }

    init(_ agreementId: UUID, author: String) {
        self.agreementId = agreementId
        self.author = author
    }

    func copy() -> Note {
        let note = Note(agreementId, author: author)
        note.publishedAt = publishedAt
        note.isDeleted = isDeleted
        return note
    }
}

struct Agreement {
    let id: UUID
    let householdId: UUID
}

struct Context {
    func save() throws {}
}

enum HouseholdCloudStore {
    static var notes: [Note] = []
    static var events: [String] = []
    static var fails = false

    static func publishPendingObservations() async throws {
        events.append("share")
        if fails { throw NSError(domain: "Offline", code: 1) }
        for note in notes where !note.isDeleted && !note.isPublished {
            note.publishedAt = .now
        }
    }
}

final class Session {
    let household = UUID()
    var currentHouseholdID: UUID? { household }
    var modelContext: Context? = Context()
    var partner: String? = "partner"
    var completed = true
    var cloudPublishFailed = false
    var agreements: [Agreement] = []
    var notes: [Note] = []
    var dirty = false

    func bothCompletedReview(reviewDate: Date) -> Bool { completed }
    func allAgreements() -> [Agreement] { agreements }
    func allObservations() -> [Note] { notes }
    func markCloudDirty() { dirty = true }

    func publishToCloud(markFailure: Bool) async {
        guard dirty else { return }
        HouseholdCloudStore.events.append("upload")
        HouseholdCloudStore.notes.removeAll { $0.author == "self" }
        HouseholdCloudStore.notes += notes.filter { $0.author == "self" }.map { $0.copy() }
        dirty = false
    }

    func pullHousehold() async throws {
        HouseholdCloudStore.events.append("pull")
        notes = HouseholdCloudStore.notes
            .filter { $0.author == "self" || $0.isPublished }
            .map { $0.copy() }
    }

    // PRODUCTION_METHODS
}

func fixture(ownNote: Bool = true) -> Session {
    HouseholdCloudStore.events = []
    HouseholdCloudStore.fails = false
    let session = Session()
    let agreement = Agreement(id: UUID(), householdId: session.household)
    session.agreements = [agreement]
    session.notes = ownNote ? [Note(agreement.id, author: "self")] : []
    HouseholdCloudStore.notes = session.notes.map { $0.copy() }
        + [Note(agreement.id, author: "partner")]
    return session
}

func verify() async {
    let session = fixture()
    await session.syncSharedReviewNotes(reviewDate: .now)
    precondition(Set(session.notes.map(\.author)) == ["self", "partner"])
    precondition(session.notes.allSatisfy(\.isPublished))
    precondition(HouseholdCloudStore.events == ["upload", "share", "pull"],
                 "Persist local publication, share both authors, then fetch")
    let dates = session.notes.map(\.publishedAt)
    await session.syncSharedReviewNotes(reviewDate: .now)
    precondition(session.notes.map(\.publishedAt) == dates, "Repeated sync preserves publication dates")

    let onlyPartner = fixture(ownNote: false)
    await onlyPartner.syncSharedReviewNotes(reviewDate: .now)
    precondition(onlyPartner.notes.count == 1 && onlyPartner.notes[0].author == "partner",
                 "Partner notes must appear even with no local unpublished notes")

    let waiting = fixture()
    waiting.completed = false
    await waiting.syncSharedReviewNotes(reviewDate: .now)
    precondition(HouseholdCloudStore.events.isEmpty, "Do not share before both finish")
    precondition(!waiting.notes[0].isPublished)

    let failed = fixture()
    HouseholdCloudStore.fails = true
    await failed.syncSharedReviewNotes(reviewDate: .now)
    precondition(failed.cloudPublishFailed)
    precondition(!HouseholdCloudStore.events.contains("pull"))
    HouseholdCloudStore.fails = false
    await failed.syncSharedReviewNotes(reviewDate: .now)
    precondition(failed.notes.count == 2, "Retry must recover partner notes")
    print("PASS: both authors, upload/share/fetch order, repeat, partner-only, waiting, failure and retry")
}

await verify()
