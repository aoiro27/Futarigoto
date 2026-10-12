#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d /tmp/futarigoto-comment-check.XXXXXX)
trap 'rm -rf "$check_dir"' EXIT
python3 - "$check_dir/main.swift" <<'PY'
from pathlib import Path
import sys
session = Path('Futarigoto/Services/AppSession.swift').read_text()
method = session[session.index('    private func storeReviewComment('):session.index('    func syncSharedReviewNotes(')].replace('private func storeReviewComment', 'func storeReviewComment')
cloud = Path('Futarigoto/Services/HouseholdCloudStore.swift').read_text()
dto = cloud[cloud.index('struct ReviewCommentDTO:'):cloud.index('struct AgreementStepDTO:')]
harness = Path('scripts/check_review_comments.swift').read_text()
Path(sys.argv[1]).write_text(harness.replace('// PRODUCTION_METHOD', method).replace('// PRODUCTION_DTO', dto))
PY
swiftc Futarigoto/Models/Entities.swift Futarigoto/Models/Domain.swift Futarigoto/Services/AppWeek.swift "$check_dir/main.swift" -o "$check_dir/check"
"$check_dir/check"
