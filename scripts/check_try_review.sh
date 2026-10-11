#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
check_file=$(mktemp /tmp/futarigoto-try-check.XXXXXX)
trap 'rm -f "$check_file" "$check_file.swift"' EXIT
python3 - "$check_file.swift" <<'PYTHON'
from pathlib import Path
import sys
source = Path('Futarigoto/Models/Domain.swift').read_text()
policy = source[source.index('enum ReviewGoalEligibility {'):]
week = Path('Futarigoto/Services/AppWeek.swift').read_text()
tests = """
let day = AppWeek.startOfDay(Date())
let firstAnswer = day.addingTimeInterval(3600)
let newTry = firstAnswer.addingTimeInterval(60)
assert(ReviewGoalEligibility.includes(createdAt: day, reviewDate: day, firstAnswerAt: firstAnswer))
assert(!ReviewGoalEligibility.includes(createdAt: newTry, reviewDate: day, firstAnswerAt: firstAnswer))
assert(ReviewGoalEligibility.includes(createdAt: newTry, reviewDate: day.addingTimeInterval(86400), firstAnswerAt: nil))
assert(!ReviewGoalEligibility.includes(createdAt: newTry, reviewDate: day.addingTimeInterval(-86400), firstAnswerAt: nil))
assert(ReviewGoalEligibility.includes(createdAt: day, reviewDate: day, firstAnswerAt: nil))
print("TRY review eligibility: 5 checks passed")
"""
Path(sys.argv[1]).write_text(week + '\n' + policy + tests)
PYTHON
swift "$check_file.swift"
