#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
check_file=$(mktemp /tmp/futarigoto-period.XXXXXX)
trap 'rm -f "$check_file" "$check_file.swift"' EXIT
python3 - "$check_file.swift" <<'PY'
from pathlib import Path
import sys
source = Path('Futarigoto/Models/Domain.swift').read_text()
policy = source[source.index('struct ReviewRecordPeriod {'):]
session = Path('Futarigoto/Services/AppSession.swift').read_text()
method = session[session.index('    func reviewRecordPeriod('):session.index('    private func hasCompletedReview(')]
tests = r'''
struct Agreement { let id: UUID; let householdId: UUID }
struct Person { let id: UUID }
struct Answer { let agreementId: UUID; let userId: UUID; let weekStartDate: Date; let completedAt: Date }
final class Session {
    let currentHouseholdID = UUID()
    let householdMembers = [Person(id: UUID()), Person(id: UUID())]
    var agreements: [Agreement] = []
    var answers: [Answer] = []
    var completedDays: Set<Date> = []
    func allAgreements() -> [Agreement] { agreements }
    func allReflections() -> [Answer] { answers }
    func hasCompletedReview(userId: UUID, reviewDate: Date) -> Bool { completedDays.contains(reviewDate) }
    // METHOD
}
let day = AppWeek.startOfDay(Date())
let previous = day.addingTimeInterval(-7 * 86400)
let end = day.addingTimeInterval(3600)
let previousEnd = previous.addingTimeInterval(7200)
let session = Session()
let agreement = Agreement(id: UUID(), householdId: session.currentHouseholdID)
session.agreements = [agreement]
session.answers = [Answer(agreementId: agreement.id, userId: session.householdMembers[0].id, weekStartDate: day, completedAt: end)]
var period = session.reviewRecordPeriod(reviewDate: day)
assert(period.contains(previous.addingTimeInterval(-86400)), "First review includes all earlier entries")
assert(!period.contains(end.addingTimeInterval(1)), "Entries after this review belong to next review")
session.answers.append(Answer(agreementId: agreement.id, userId: session.householdMembers[1].id, weekStartDate: previous, completedAt: previousEnd))
session.completedDays.insert(previous)
period = session.reviewRecordPeriod(reviewDate: day)
assert(period.after == previousEnd)
assert(!period.contains(previousEnd), "Previous boundary is not duplicated")
assert(period.contains(previousEnd.addingTimeInterval(1)), "Same-day entry just after previous review is included")
assert(period.contains(day.addingTimeInterval(-86400)), "Earlier-day records must not disappear")
assert(period.contains(end))
let partial = day.addingTimeInterval(-86400)
session.answers.append(Answer(agreementId: agreement.id, userId: session.householdMembers[0].id, weekStartDate: partial, completedAt: partial))
assert(session.reviewRecordPeriod(reviewDate: day).after == previousEnd, "Partial review does not cut off records")
let otherAgreement = Agreement(id: UUID(), householdId: UUID())
session.agreements.append(otherAgreement)
session.answers.append(Answer(agreementId: otherAgreement.id, userId: session.householdMembers[0].id, weekStartDate: day, completedAt: end.addingTimeInterval(999)))
assert(session.reviewRecordPeriod(reviewDate: day).through == end, "Other household does not change boundary")
print("PASS: first review, exact boundaries, multi-day interval, partial review, household isolation")
'''
Path(sys.argv[1]).write_text(Path('Futarigoto/Services/AppWeek.swift').read_text() + '\n' + policy + tests.replace('// METHOD', method))
PY
swift "$check_file.swift"
