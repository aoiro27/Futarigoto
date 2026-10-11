#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
review_check=$(mktemp /tmp/futarigoto-shared-review.XXXXXX)
trap 'rm -f "$review_check" "$review_check.swift"' EXIT
python3 - "$review_check.swift" <<'PY'
from pathlib import Path
import sys
source = Path('Futarigoto/Services/AppSession.swift').read_text()
sync = source[source.index('    func syncSharedReviewNotes('):source.index('    func markPartnerRevealSeen(')]
publish = source[source.index('    private func publishUnpublishedObservations('):source.index('    private func setCurrentUser(')]
tests = Path('scripts/check_shared_review_notes.swift').read_text()
Path(sys.argv[1]).write_text(tests.replace('// PRODUCTION_METHODS', sync + publish))
PY
swift "$review_check.swift"
