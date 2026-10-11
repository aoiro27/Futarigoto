import Foundation
import SwiftData

// PRODUCTION_DTO

enum AppError: Error { case notReady }
final class StepSession {
    let context: ModelContext
    var currentUserID: UUID? = UUID()
    var currentHouseholdID: UUID? = UUID()
    var publishCount = 0
    init(_ context: ModelContext) { self.context = context }
    func requireContext() throws -> ModelContext { context }
    func agreement(id: UUID) -> Agreement? {
        try? context.fetch(FetchDescriptor<Agreement>()).first { $0.id == id }
    }
    func schedulePublishToCloud() { publishCount += 1 }
    // PRODUCTION_METHOD
}

let schema = Schema([Agreement.self, AgreementStep.self])
let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
let context = ModelContext(container)
let session = StepSession(context)
let parent = Agreement(householdId: session.currentHouseholdID!, title: "片づける", scopeType: .both)
let other = Agreement(householdId: session.currentHouseholdID!, title: "連絡する", scopeType: .both)
context.insert(parent)
context.insert(other)
try context.save()
let day = AppWeek.startOfDay(.now)
try session.addStep(agreementID: parent.id, text: "  夕食後に5分だけ片づける  ", reviewDate: day)
try session.addStep(agreementID: other.id, text: "帰る前にメッセージする", reviewDate: nil)
let freshContext = ModelContext(container)
let steps = try freshContext.fetch(FetchDescriptor<AgreementStep>())
let agreementCount = try freshContext.fetchCount(FetchDescriptor<Agreement>())
assert(agreementCount == 2, "Steps must not become new agreements")
assert(steps.count == 2)
let saved = steps.first { $0.agreementId == parent.id }!
assert(saved.text == "夕食後に5分だけ片づける")
assert(saved.reviewDate == day && saved.authorId == session.currentUserID)
assert(steps.filter { $0.agreementId == other.id }.count == 1)
let dto = AgreementStepDTO(id: saved.id, agreementId: saved.agreementId, authorId: saved.authorId, text: saved.text, reviewDate: saved.reviewDate, createdAt: saved.createdAt)
let data = try JSONEncoder().encode(dto)
let decoded = try JSONDecoder().decode(AgreementStepDTO.self, from: data)
assert(decoded.agreementId == parent.id && decoded.reviewDate == day && decoded.text == saved.text)
let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
assert(json["agreement_id"] != nil && json["author_id"] != nil && json["review_date"] != nil)
func rejected(_ action: () throws -> Void) {
    do { try action(); assertionFailure("Expected rejection") } catch {}
}
rejected { try session.addStep(agreementID: UUID(), text: "不明な約束", reviewDate: nil) }
rejected { try session.addStep(agreementID: parent.id, text: " \n ", reviewDate: nil) }
rejected { try session.addStep(agreementID: parent.id, text: String(repeating: "あ", count: 501), reviewDate: nil) }
parent.deletedAt = .now
rejected { try session.addStep(agreementID: parent.id, text: "削除済み", reviewDate: nil) }
parent.deletedAt = nil
session.currentHouseholdID = UUID()
rejected { try session.addStep(agreementID: parent.id, text: "別の家庭", reviewDate: nil) }
assert(session.publishCount == 2)
let stepCount = try context.fetchCount(FetchDescriptor<AgreementStep>())
assert(stepCount == 2)
print("PASS: parent association, independent records, persistence, cloud encoding, validation, household isolation")
