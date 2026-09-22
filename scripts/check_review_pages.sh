#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
review_check=$(mktemp /tmp/futarigoto-review-check.XXXXXX)
trap 'rm -f "$review_check" "$review_check.swift"' EXIT
python3 - "$review_check.swift" <<'PY'
from pathlib import Path
import sys
source = Path('Futarigoto/Views/WeeklyReview/WeeklyReviewFlowView.swift').read_text()
models = source[source.index('enum ReviewFocus:'):source.index('private enum ReflectionGap')]
domain = Path('Futarigoto/Models/Domain.swift').read_text()
reflection = domain[domain.index('enum SelfReflection:'):domain.index('enum AppCopy')]
tests = Path('scripts/check_review_pages.swift').read_text()
Path(sys.argv[1]).write_text('import Foundation\n' + reflection + models + tests)
PY
swift "$review_check.swift"
