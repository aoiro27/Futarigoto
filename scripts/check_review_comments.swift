import Foundation
import SwiftData

// PRODUCTION_DTO

enum AppError: Error { case notReady }
final class CommentSession {
    var currentHouseholdID: UUID? = UUID()
    var currentUserID: UUID? = UUID()
    let context: ModelContext
    init(_ context: ModelContext) { self.context = context }
    func allReviewComments() -> [ReviewComment] {
        (try? context.fetch(FetchDescriptor<ReviewComment>())) ?? []
    }
    // PRODUCTION_METHOD
}

let schema = Schema([ReviewComment.self])
let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
let context = ModelContext(container)
let session = CommentSession(context)
let day = AppWeek.startOfDay(.now)
try session.storeReviewComment(" \n ", reviewDate: day, context: context)
assert(session.allReviewComments().isEmpty, "An optional blank comment must not create a record")
try session.storeReviewComment("  話せてよかった  ", reviewDate: day.addingTimeInterval(3600), context: context)
try context.save()
let initialID = session.allReviewComments()[0].id
try session.storeReviewComment("ありがとう", reviewDate: day.addingTimeInterval(7200), context: context)
try context.save()
assert(session.allReviewComments().count == 1, "Retry must update the same day's comment")
assert(session.allReviewComments()[0].id == initialID)
assert(session.allReviewComments()[0].reviewDate == day)
let firstUser = session.currentUserID
session.currentUserID = UUID()
try session.storeReviewComment("相手のひとこと", reviewDate: day, context: context)
try session.storeReviewComment("翌日のひとこと", reviewDate: day.addingTimeInterval(86400), context: context)
let originalHousehold = session.currentHouseholdID
session.currentHouseholdID = UUID()
try session.storeReviewComment("別の家庭", reviewDate: day, context: context)
try context.save()
assert(session.allReviewComments().count == 4)
let freshContext = ModelContext(container)
let saved = try freshContext.fetch(FetchDescriptor<ReviewComment>())
let own = saved.first { $0.userId == firstUser }!
assert(own.text == "ありがとう" && own.householdId == originalHousehold)
let dto = ReviewCommentDTO(id: own.id, householdId: own.householdId, userId: own.userId, reviewDate: own.reviewDate, text: own.text, updatedAt: own.updatedAt)
let data = try JSONEncoder().encode(dto)
let decoded = try JSONDecoder().decode(ReviewCommentDTO.self, from: data)
assert(decoded.text == own.text && decoded.userId == own.userId && decoded.reviewDate == day)
let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
assert(json["agreement_id"] == nil, "A whole-review comment must not belong to an agreement")
assert(json["household_id"] != nil && json["review_date"] != nil)
do {
    try session.storeReviewComment(String(repeating: "あ", count: 501), reviewDate: day, context: context)
    assertionFailure("Must reject over 500 characters")
} catch {}
session.currentHouseholdID = originalHousehold
session.currentUserID = firstUser
try session.storeReviewComment("", reviewDate: day, context: context)
try context.save()
assert(session.allReviewComments().first { $0.id == initialID }?.text == "")
assert(session.allReviewComments().count == 4)
print("PASS: whole-review association, optional input, normalization, retry, persistence, user/day/household isolation, cloud encoding, length and clearing")
