#!/usr/bin/env bash
# Static test gate for the claude-orchestrator plugin.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
err() { echo "FAIL: $*"; fail=1; }

# --- manifests -------------------------------------------------------------
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json; do
	[ -f "$f" ] || err "missing $f"
done
if [ -f .claude-plugin/plugin.json ]; then
	out=$(claude plugin validate .claude-plugin/plugin.json 2>&1) || err "plugin.json invalid"
	echo "$out" | grep -qi 'warning' && { echo "$out"; err "plugin.json has warnings"; }
fi
if [ -f .claude-plugin/marketplace.json ]; then
	out=$(claude plugin validate . 2>&1) || err "marketplace invalid"
	echo "$out" | grep -qi 'warning' && { echo "$out"; err "marketplace has warnings"; }
	[ "$(jq -r '.name' .claude-plugin/marketplace.json)" = td-orchestrator ] || err "marketplace name"
	[ "$(jq -r '.plugins[0].name' .claude-plugin/marketplace.json)" = td-orchestrator ] || err "marketplace plugin name"
fi

# --- checks (extended by later tasks) --------------------------------------

# template: exists, frontmatter parses once placeholders are filled, has all keys
if [ ! -f templates/orchestrator.md ]; then
	err "missing templates/orchestrator.md"
else
	python3 - templates/orchestrator.md <<'PY' || err "template schema"
import sys, re, yaml
text = open(sys.argv[1]).read()
m = re.match(r'^---\n(.*?)\n---\n', text, re.S)
assert m, "no frontmatter"
fm = m.group(1)
fill = {
	"{{main_branch}}": "main",
	"{{test_gate}}": "\n  - ./x.sh",
	"{{specs_dir}}": "docs/specs",
	"{{plans_dir}}": "docs/plans",
	"{{builders}}": "2",
	"{{reviewers}}": "1",
	"{{legacy_main_mode}}": "false",
}
for k, v in fill.items():
	assert k in fm, f"placeholder {k} missing"
	fm = fm.replace(k, v)
data = yaml.safe_load(fm)
for key in ["config_version", "main_branch", "test_gate", "specs_dir", "plans_dir",
            "builders", "reviewers", "budgets", "legacy_main_mode"]:
	assert key in data, f"key {key} missing"
assert data["config_version"] == 1
assert data["budgets"] == {"implementer": 90, "reviewer": 45, "planner": 60}
for section in ["## Implementer", "## Reviewer", "## Planner"]:
	assert section in text, f"section {section} missing"
PY
fi

[ "$fail" = 0 ] && echo "check.sh: all green"
exit "$fail"
