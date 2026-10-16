#!/usr/bin/env bash
# Static test gate for the td-orchestrator plugin.
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
base = {
	"{{main_branch}}": "main",
	"{{test_gate}}": "\n  - ./x.sh\n  - 'say \"a: b\" # it''s'",
	"{{specs_dir}}": "docs/specs",
	"{{plans_dir}}": "docs/plans",
	"{{builders}}": "2",
	"{{reviewers}}": "1",
	"{{legacy_main_mode}}": "false",
	"{{budgets}}": "{ implementer: 90, reviewer: 45, planner: 60 }",
}
def fill(fm, values, unset=()):
	# the wizard comments out the whole line of an unset key
	fm = "\n".join(f"# {l.split(':', 1)[0]}:" if l.split(":", 1)[0] in unset else l
	               for l in fm.split("\n"))
	for k, v in values.items():
		if k.strip("{}") in unset:
			continue
		assert k in fm, f"placeholder {k} missing"
		fm = fm.replace(k, v)
	assert "{{" not in fm, "unfilled placeholder"
	return yaml.safe_load(fm)
# full config, including a single-quoted gate command as the wizard writes it
data = fill(m.group(1), base)
for key in ["config_version", "main_branch", "test_gate", "specs_dir", "plans_dir",
            "builders", "reviewers", "budgets", "legacy_main_mode"]:
	assert key in data, f"key {key} missing"
assert data["config_version"] == 1
assert data["test_gate"] == ["./x.sh", "say \"a: b\" # it's"], data["test_gate"]
assert data["budgets"] == {"implementer": 90, "reviewer": 45, "planner": 60}
# a command ending in ':' must be quoted; unquoted it parses as a one-key map
gate = lambda g: fill(m.group(1), {**base, "{{test_gate}}": g})["test_gate"]
assert gate("\n  - 'make check:'") == ["make check:"]
assert gate("\n  - make check:") == [{"make check": None}]
# empty gate
assert fill(m.group(1), {**base, "{{test_gate}}": "[]"})["test_gate"] == []
# no planner, plans kept
data = fill(m.group(1), base, unset=("specs_dir",))
assert "specs_dir" not in data and data["plans_dir"] == "docs/plans"
# neither specs nor plans
data = fill(m.group(1), base, unset=("specs_dir", "plans_dir"))
assert "specs_dir" not in data and "plans_dir" not in data
for section in ["## Implementer", "## Reviewer", "## Planner", "## Orchestrator"]:
	assert re.search(rf"^{section}$", text, re.M), f"section {section} missing"
PY
fi

# skills: present, frontmatter name matches directory
for s in orchestrate implementer reviewer planner; do
	f="skills/$s/SKILL.md"
	if [ ! -f "$f" ]; then err "missing $f"; continue; fi
	head -5 "$f" | grep -qx "name: $s" || err "$f: frontmatter name must be $s"
done
[ -d skills ] && {
	out=$(claude plugin validate skills 2>&1) || err "skills invalid"
	echo "$out" | grep -qi 'warning' && { echo "$out"; err "skills have warnings"; }
}

# no project-specific terms in shipped skill/template files
banned='godot|gdscript|\bGUT\b|\.uid\b|run_tests|smoke\.sh|superpowers/(specs|plans)|horde|\bgame\b'
hits=$(grep -rniE "$banned" skills templates 2>/dev/null)
[ -z "$hits" ] || { echo "$hits"; err "project-specific terms in skills/templates"; }

# the main branch is never hard-coded in git commands
hits=$(grep -rnE 'git [^`]*\b(main|master)\b' skills 2>/dev/null)
[ -z "$hits" ] || { echo "$hits"; err "hard-coded main/master in git commands (use <MAIN_BRANCH>)"; }

# orchestrator: key rules present
o=skills/orchestrate/SKILL.md
if [ -f "$o" ]; then
	for needle in 'Use skill td-orchestrator:' 'setup.md' '--setup' '--dry-run' \
		'legacy_main_mode' 'specs_dir' 'td-orchestrator@td-orchestrator' \
		'unknown key' '<MAIN_BRANCH>' 'orchestrator: prompted' 'agent-blocked' \
		'--plugin-dir <PLUGIN_ROOT>' '<PLUGIN_ROOT>' 'command -v jq' 'superpowers' \
		'integers ≥ 1' 'assume there are no live agents' 'do precondition 1, then read' \
		'orchestrator.local.md' 'merged per role' 'check-ignore -q .claude/orchestrator.local.md' \
		'## Orchestrator instructions' "<<'EOF'" 'orchestrator instruction failed'; do
		grep -qF -- "$needle" "$o" || err "$o lacks: $needle"
	done
fi

# wizard: present and covers every step
w=skills/orchestrate/setup.md
if [ ! -f "$w" ]; then
	err "missing $w"
else
	for needle in 'AskUserQuestion' '(Detected)' 'test_gate' 'command -v' 'check-ignore' \
		'.worktrees/' 'claude plugin install td-orchestrator@td-orchestrator --scope project' \
		'templates/orchestrator.md' 'chore: td-orchestrator config' 'unknown key' '[]' 'at least two options' \
		'For every key without a valid existing value' 'Keep current' '{{budgets}}' \
		'commit -m "chore: td-orchestrator config" --' 'rev-parse --abbrev-ref HEAD' \
		'single quotes' 'ends with `:`' 'plans_dir` keeps' \
		'check-ignore -q .claude/orchestrator.local.md'; do
		grep -qF -- "$needle" "$w" || err "$w lacks: $needle"
	done
fi
# roles: read the local config next to the shared one
for s in implementer reviewer planner; do
	grep -qF '<MAIN_REPO>/.claude/orchestrator.local.md' "skills/$s/SKILL.md" \
		|| err "skills/$s/SKILL.md lacks the local config"
done
[ -x scripts/make-fixture.sh ] || err "missing executable scripts/make-fixture.sh"
[ -f LICENSE ] || err "missing LICENSE"

# orchestrator: Herdr is checked before the config, so the wizard never runs for a run that cannot start
if [ -f "$o" ]; then
	herdr_line=$(grep -n 'HERDR_ENV' "$o" | head -1 | cut -d: -f1)
	config_line=$(grep -n '^[0-9]*\. Config:' "$o" | head -1 | cut -d: -f1)
	[ -n "$herdr_line" ] && [ -n "$config_line" ] && [ "$herdr_line" -lt "$config_line" ] \
		|| err "$o: Herdr precondition must come before the config precondition"
fi

[ "$fail" = 0 ] && echo "check.sh: all green"
exit "$fail"
