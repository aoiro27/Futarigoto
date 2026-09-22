import Foundation

// Run with scripts/check_review_pages.sh. Models are read from production source.
func verifyReviewPages() {
    let ids = (0..<5).map { _ in UUID() }
    let questions = ids.flatMap { id in
        [ReviewFocus.selfEval, .partnerEval].map {
            ReviewQuestion(agreementId: id, title: "約束", focus: $0, eyebrow: "", ask: "")
        }
    }
    let pages = ReviewPage.group(questions)
    precondition(pages.count == 5, "Five agreements must produce five pages")
    precondition(pages.map(\.agreementId) == ids, "Keep agreement order")
    precondition(pages.allSatisfy { $0.questions.count == 2 })
    var answers = questions.map { ReviewAnswer(agreementId: $0.agreementId, focus: $0.focus) }
    precondition(!pages[0].isComplete(in: answers))
    answers[0].applicable = true
    answers[0].reflection = .veryGood
    precondition(!pages[0].isComplete(in: answers), "One person cannot complete a shared page")
    answers[1].applicable = false
    precondition(pages[0].isComplete(in: answers), "Not applicable is a valid answer")
    answers[1].applicable = true
    precondition(!pages[0].isComplete(in: answers), "Applicable requires a reflection")
    answers[1].reflection = .oftenMissed
    precondition(pages[0].isComplete(in: answers))
    precondition(pages.firstIndex(where: { !$0.isComplete(in: answers) }) == 1, "Resume at first unfinished agreement")
    let soloPages = ReviewPage.group(questions.filter { $0.focus == .selfEval })
    precondition(soloPages.count == 5 && soloPages.allSatisfy { $0.questions.count == 1 })
    precondition(soloPages[0].isComplete(in: answers))
    let partnerOnly = ReviewPage.group([questions[1]])
    precondition(partnerOnly[0].isComplete(in: answers))
    precondition(ReviewPage.group([]).isEmpty)
    print("PASS: page grouping, ordering, both-person completion, skip, reselection, resume, solo and partner-only")
}
verifyReviewPages()
