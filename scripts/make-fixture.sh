#!/usr/bin/env bash
# Creates a throwaway git + td repository for testing the setup wizard.
# Usage: make-fixture.sh <dir> [branch]
set -euo pipefail
dir=${1:?usage: make-fixture.sh <dir> [branch]}
branch=${2:-main}
[ -e "$dir" ] && { echo "$dir exists" >&2; exit 1; }
mkdir -p "$dir/docs/specs" "$dir/docs/plans"
cd "$dir"
git init -q -b "$branch"
git config user.name fixture
git config user.email fixture@example.invalid
cat > run_tests.sh <<'SH'
#!/usr/bin/env bash
echo "tests ok"
SH
chmod +x run_tests.sh
cat > CLAUDE.md <<'MD'
# Fixture
Run the tests with `./run_tests.sh`.
MD
echo "# Spec" > docs/specs/example.md
echo "# Plan" > docs/plans/example.md
td init </dev/null >/dev/null 2>&1
git add -A
git commit -q -m "fixture"
echo "fixture ready: $dir (branch $branch)"
