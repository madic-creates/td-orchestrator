# claude-orchestrator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the `game` repo's v1 agent orchestrator into a standalone, project-agnostic Claude Code plugin with a per-repo config file and a setup wizard, then migrate `game` onto it.

**Architecture:** The plugin consists of four Markdown skills (`orchestrate`, `implementer`, `reviewer`, `planner`), a wizard procedure (`skills/orchestrate/setup.md`) and a config template. Everything repo-specific lives in `.claude/orchestrator.md` inside each target repo. A static check script (`scripts/check.sh`) is the plugin's test gate: manifest validation, skill presence, template schema, and a ban on project-specific terms.

**Tech Stack:** Claude Code plugins (skills, marketplace), Markdown + YAML frontmatter, Bash, Python 3 + PyYAML (only in `scripts/check.sh`), Herdr, td, git.

**Spec:** `docs/design.md` (same repo).

## Global Constraints

- Plugin name and marketplace name: `claude-orchestrator`; plugin id `claude-orchestrator@claude-orchestrator`.
- Role skills are invoked as `claude-orchestrator:implementer`, `claude-orchestrator:reviewer`, `claude-orchestrator:planner`.
- Config file in target repos: `.claude/orchestrator.md`, `config_version: 1`.
- Required config keys: `config_version`, `main_branch`, `test_gate`. Optional: `specs_dir`, `plans_dir` (required when `specs_dir` is set), `builders` (2), `reviewers` (1), `budgets` (`implementer: 90, reviewer: 45, planner: 60`), `legacy_main_mode` (`false`).
- Fixed conventions: worktree `<MAIN_REPO>/.worktrees/<id>`, branch `td/<id>`, commit messages end with `(<ISSUE_ID>)`, agent names `impl-`/`rev-`/`plan-` + id without `td-`, labels `needs-human`, `stuck`, `agent-blocked`, `plan`.
- No file under `skills/` or `templates/` names a project, language, test framework or fixed doc path (enforced by `scripts/check.sh`).
- Everything in the repo is English. Commit messages end with `(td-739c0f)`.
- Work happens on branch `td/td-739c0f` of the plugin repo; it is fast-forward merged into `main` after the final review. Nothing is pushed unless the user asks.
- `--setup` runs only the wizard and stops (refinement of the spec: lets the wizard be run and tested outside Herdr).

## Review Focus

- **Config present but with a typo'd or extra key** (e.g. `test-gate`): the orchestrator must treat the required key as missing and start the wizard, and warn about the unknown key, not silently run without a test gate. → Task 4 Step 1 (check.sh asserts the wording exists in setup/orchestrate), Task 6 wizard test case B.
- **`test_gate: []` confirmed by the user:** implementer and reviewer must treat an empty gate as "nothing to run", not as a failure, and reviewer must still review. → Task 3 role text, Task 6 wizard test case C.
- **Orchestrator started in a repo whose `.claude/settings.json` does not enable the plugin:** worker agents would not find their role skills; the orchestrator must stop (or offer the fix in the wizard) before starting any agent. → Task 4 preconditions, Task 6 wizard test case A.
- **`main_branch` other than `main`** (e.g. `master`): every git command and the start prompt must use the configured name. → Task 6 wizard test case B uses `master`; check.sh bans the literal `main` in git commands of the skills.
- **Dry run with a missing config:** must report what is missing and change nothing (no wizard, no file writes). → Task 6 wizard test case D.

---

## File Structure

| Path | Responsibility |
|---|---|
| `.claude-plugin/plugin.json` | Plugin manifest. |
| `.claude-plugin/marketplace.json` | Marketplace listing this repo as the plugin (`source: "./"`). |
| `scripts/check.sh` | Static test gate of the plugin repo. |
| `scripts/make-fixture.sh` | Creates a throwaway git + td repo for wizard tests. |
| `templates/orchestrator.md` | Commented config template the wizard fills in. |
| `skills/orchestrate/SKILL.md` | Orchestrator: preconditions, loop, monitoring, error handling. |
| `skills/orchestrate/setup.md` | Setup wizard procedure. |
| `skills/implementer/SKILL.md` | Implementer role. |
| `skills/reviewer/SKILL.md` | Reviewer role. |
| `skills/planner/SKILL.md` | Planner role. |
| `README.md` | Install, dependencies, config reference, usage. |
| `docs/design.md` | Spec (exists). |

In the `game` repo (Task 7): `.claude/orchestrator.md` (new), `.claude/settings.json` (new), `.claude/skills/orchestrate/` and `.claude/orchestrator/prompts/` (deleted), `CLAUDE.md` (Agent orchestrator section), `docs/superpowers/specs/2026-10-14-agent-orchestrator-design.md` (superseded note).

---

### Task 1: Plugin scaffold and static check

**Files:**
- Create: `scripts/check.sh`
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`
- Create: `README.md`

**Interfaces:**
- Produces: `scripts/check.sh` — run from anywhere, exit 0 = green. Later tasks extend it by appending to the `checks` section.

- [ ] **Step 1: Create the branch**

```bash
cd /home/mne-adm/Git/personal/github.com/claude-orchestrator
git switch -c td/td-739c0f
```

- [ ] **Step 2: Write the failing check script**

`scripts/check.sh`:

```bash
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
	[ "$(jq -r '.name' .claude-plugin/marketplace.json)" = claude-orchestrator ] || err "marketplace name"
	[ "$(jq -r '.plugins[0].name' .claude-plugin/marketplace.json)" = claude-orchestrator ] || err "marketplace plugin name"
fi

# --- checks (extended by later tasks) --------------------------------------

[ "$fail" = 0 ] && echo "check.sh: all green"
exit "$fail"
```

```bash
chmod +x scripts/check.sh
```

- [ ] **Step 3: Run it, expect red**

Run: `./scripts/check.sh`
Expected: `FAIL: missing .claude-plugin/plugin.json`, `FAIL: missing .claude-plugin/marketplace.json`, exit 1.

- [ ] **Step 4: Write the manifests**

`.claude-plugin/plugin.json`:

```json
{
  "name": "claude-orchestrator",
  "description": "Works through all workable td issues of a repo with fresh implementer, reviewer and planner agents in Herdr tabs and git worktrees.",
  "version": "0.1.0",
  "author": {
    "name": "madic-creates",
    "url": "https://github.com/madic-creates"
  },
  "homepage": "https://github.com/madic-creates/claude-orchestrator",
  "repository": "https://github.com/madic-creates/claude-orchestrator",
  "license": "MIT"
}
```

`.claude-plugin/marketplace.json`:

```json
{
  "name": "claude-orchestrator",
  "owner": {
    "name": "madic-creates"
  },
  "metadata": {
    "description": "Agent orchestrator for td + Herdr + git worktrees",
    "version": "0.1.0"
  },
  "plugins": [
    {
      "name": "claude-orchestrator",
      "source": "./",
      "description": "Works through all workable td issues of a repo with fresh implementer, reviewer and planner agents in Herdr tabs and git worktrees.",
      "category": "development",
      "tags": ["orchestration", "agents", "td", "herdr", "worktrees"]
    }
  ]
}
```

- [ ] **Step 5: Write the README skeleton**

`README.md`:

````markdown
# claude-orchestrator

A Claude Code plugin that works through all workable [td](https://github.com/marcus/td) issues of a git repository on its own. It starts a fresh agent per issue and role — implementer, reviewer, planner — each in its own [Herdr](https://herdr.dev) tab and git worktree, checks the td state they leave behind, merges reviewed work into the main branch and notifies you only when it needs you.

Design: [`docs/design.md`](docs/design.md).

## Requirements

- Claude Code with auto mode
- Herdr (the orchestrator must run inside a Herdr pane)
- `td`, `git`, `jq`
- The [superpowers](https://github.com/obra/superpowers) plugin (implementers use `superpowers:test-driven-development`, planners `superpowers:writing-plans`)

## Install

Once per machine:

```bash
claude plugin marketplace add /path/to/claude-orchestrator   # or: madic-creates/claude-orchestrator
```

Once per repository (writes `enabledPlugins` into the committed `.claude/settings.json`, so worker agents in worktrees get the plugin too):

```bash
cd /path/to/repo
claude plugin install claude-orchestrator@claude-orchestrator --scope project
```

The setup wizard offers this step if it is missing.

After changing the plugin source: `claude plugin marketplace update claude-orchestrator` and `claude plugin update claude-orchestrator@claude-orchestrator`, then restart Claude Code.

## Usage

Inside a Herdr pane, in the repository's main working tree:

| Command | Effect |
|---|---|
| `/claude-orchestrator:orchestrate` | Run until nothing workable is left. |
| `… --dry-run` | Show what would be started, change nothing. |
| `… --builders N --reviewers M` | Override the slot counts from the config. |
| `… --setup` | Run only the setup wizard, then stop. |

## Configuration

See "Configuration reference" below.

## Development

`./scripts/check.sh` is the test gate: manifest validation, skill presence, template schema, and no project-specific terms in `skills/` and `templates/`.
````

- [ ] **Step 6: Run it, expect green**

Run: `./scripts/check.sh`
Expected: `check.sh: all green`, exit 0. If `claude plugin validate .` warns that the plugin has no components, that warning is expected until Task 3; in that case temporarily verify only that the output contains no `error` and continue (the warning disappears in Task 3, and Task 3 Step 4 must be fully green).

- [ ] **Step 7: Commit**

```bash
git add scripts/check.sh .claude-plugin/plugin.json .claude-plugin/marketplace.json README.md
git commit -m "feat: plugin scaffold, marketplace and static check (td-739c0f)"
```

---

### Task 2: Config template and configuration reference

**Files:**
- Create: `templates/orchestrator.md`
- Modify: `scripts/check.sh` (checks section)
- Modify: `README.md` (Configuration section)

**Interfaces:**
- Produces: `templates/orchestrator.md` with placeholders `{{main_branch}}`, `{{test_gate}}`, `{{specs_dir}}`, `{{plans_dir}}`, `{{builders}}`, `{{reviewers}}`, `{{legacy_main_mode}}` — the wizard (Task 5) replaces them. Optional keys whose value is unset are written as commented lines.

- [ ] **Step 1: Add the failing template check**

Append to the checks section of `scripts/check.sh`:

```bash
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
```

- [ ] **Step 2: Run it, expect red**

Run: `./scripts/check.sh`
Expected: `FAIL: missing templates/orchestrator.md`, exit 1.

- [ ] **Step 3: Write the template**

`templates/orchestrator.md`:

```markdown
---
# claude-orchestrator config. Reference: README.md of the claude-orchestrator plugin.
config_version: 1
# Branch that reviewers merge into and worktrees branch from.
main_branch: {{main_branch}}
# Shell commands run from the worktree root; all must exit 0. [] = no gate.
test_gate: {{test_gate}}
# Where specs and plans live. Without specs_dir the planner role is disabled.
specs_dir: {{specs_dir}}
plans_dir: {{plans_dir}}
# Parallel agents. --builders / --reviewers override these.
builders: {{builders}}
reviewers: {{reviewers}}
# Minutes per agent attempt; one extension of the same length is granted.
budgets: { implementer: 90, reviewer: 45, planner: 60 }
# true: in_review issues without a td/<id> branch are reviewed on the main branch.
legacy_main_mode: {{legacy_main_mode}}
---

<!--
Optional additions per role. Each role reads its own section after the
frontmatter. Conventions that already live in CLAUDE.md do not belong here.
-->

## Implementer

## Reviewer

## Planner
```

- [ ] **Step 4: Run it, expect green**

Run: `./scripts/check.sh`
Expected: `check.sh: all green` (or only the no-components warning noted in Task 1 Step 6).

- [ ] **Step 5: Write the configuration reference**

Replace the `## Configuration` section of `README.md` with:

````markdown
## Configuration

Each repository has one committed file, `.claude/orchestrator.md`. The setup wizard creates it; `/claude-orchestrator:orchestrate --setup` runs the wizard again.

```markdown
---
config_version: 1
main_branch: main
test_gate:
  - ./run_tests.sh
specs_dir: docs/specs
plans_dir: docs/plans
builders: 2
reviewers: 1
budgets: { implementer: 90, reviewer: 45, planner: 60 }
legacy_main_mode: false
---

## Implementer
Run `npm ci` first in a fresh worktree.

## Reviewer

## Planner
```

| Key | Required | Default | Meaning |
|---|---|---|---|
| `config_version` | yes | – | Must be `1`. |
| `main_branch` | yes | – | Branch reviewers merge into and worktrees branch from. |
| `test_gate` | yes | – | Shell commands run from the worktree root; all must exit 0. `[]` means no gate. |
| `specs_dir` | no | unset | Where specs live. Unset → the planner role is disabled and `plan` issues are skipped. |
| `plans_dir` | no | unset | Where plans live. Required when `specs_dir` is set. |
| `builders` | no | 2 | Builder slots (implementer or planner). |
| `reviewers` | no | 1 | Reviewer slots. |
| `budgets` | no | 90/45/60 | Minutes per attempt for implementer/reviewer/planner. |
| `legacy_main_mode` | no | `false` | Review `in_review` issues that have no `td/<id>` branch directly on the main branch (work done before the repo used git). |

Unknown keys are ignored with a warning. A missing required key, an unparseable frontmatter or an unknown `config_version` starts the wizard.

The optional sections `## Implementer`, `## Reviewer`, `## Planner` are read by that role only. Use them for orchestrator-specific additions; general conventions belong in `CLAUDE.md`.

Fixed conventions: worktrees at `.worktrees/<id>` (add `.worktrees/` to `.gitignore`), branches `td/<id>`, commit messages end with `(<issue id>)`, labels `needs-human`, `stuck`, `agent-blocked`, `plan`.

### Labels

| Label | Meaning |
|---|---|
| `plan` | Handled by the planner: turns a spec into a plan and td issues. |
| `needs-human` | Needs a decision from you. Skipped until you remove the label. |
| `stuck` | Failed 3 attempts. Blocked in td; branch kept. |
| `agent-blocked` | The issue's agent waits at a prompt in its tab. |
````

- [ ] **Step 6: Commit**

```bash
git add templates/orchestrator.md scripts/check.sh README.md
git commit -m "feat: config template and configuration reference (td-739c0f)"
```

---

### Task 3: Role skills

**Files:**
- Create: `skills/implementer/SKILL.md`
- Create: `skills/reviewer/SKILL.md`
- Create: `skills/planner/SKILL.md`
- Modify: `scripts/check.sh` (checks section)

**Interfaces:**
- Consumes: config keys from Task 2.
- Produces: skills `claude-orchestrator:implementer|reviewer|planner`. Start-prompt parameters (exact names): `ISSUE_ID`, `BRANCH`, `MAIN_REPO`, `MAIN_BRANCH`, `MODE` (`worktree`|`main`, reviewer only), `REWORK` (`yes`|`no`, implementer/planner). Final reply lines: `DONE <id>`, `APPROVED <id>`, `REJECTED <id>`, `NEEDS-HUMAN <id>`.

- [ ] **Step 1: Add the failing skill checks**

Append to the checks section of `scripts/check.sh`:

```bash
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
```

- [ ] **Step 2: Run it, expect red**

Run: `./scripts/check.sh`
Expected: `FAIL: missing skills/orchestrate/SKILL.md` and the same for implementer, reviewer, planner; exit 1.

- [ ] **Step 3: Write the three role skills**

`skills/implementer/SKILL.md`:

````markdown
---
name: implementer
description: Implementer role of claude-orchestrator. Use only when a start prompt says "Use skill claude-orchestrator:implementer" with ISSUE_ID, BRANCH, MAIN_REPO and MAIN_BRANCH.
user-invocable: false
---

# Role: Implementer

You implement exactly one td issue, then hand it to an independent reviewer. You were started by the orchestrator; nobody is watching you. Never ask the user questions — when you cannot proceed, use "Cannot proceed" below and stop.

Your start prompt gives you: `ISSUE_ID`, `BRANCH`, `MAIN_REPO`, `MAIN_BRANCH`, `REWORK` (`yes` if a reviewer rejected an earlier attempt).

## Config

Read `<MAIN_REPO>/.claude/orchestrator.md`: the frontmatter (`test_gate`, `specs_dir`, `plans_dir`) and the `## Implementer` section, if it has content. Then follow the repository's `CLAUDE.md` (language, style, test conventions). The `## Implementer` section takes precedence over this skill where they conflict on repo-specific details (setup commands, generated files).

## Steps

1. `td start <ISSUE_ID>` (on rework, `td start` again is fine), then `td context <ISSUE_ID>`.
2. `git rev-parse --abbrev-ref HEAD` must print `<BRANCH>`. If not, "Cannot proceed".
3. Find the plan task or spec section for the issue in `plans_dir` and `specs_dir` (if set). Match by a task code in the title (e.g. `P1-T08`) or by the title text.
   - If no plan or spec covers the issue and the description alone is not enough to implement it without product or design decisions: "Cannot proceed" and stop.
4. If `REWORK=yes`, read the newest log entry starting with `Rejected:` and the previous handoff in `td context`; fix exactly what was rejected. If the rejection is a rebase conflict with `<MAIN_BRANCH>`, run `git rebase <MAIN_BRANCH>` on your branch and resolve the conflicts.
5. Implement with TDD (superpowers:test-driven-development) following the repository's test conventions: failing test, minimal code, green.
6. Other agents merge into `<MAIN_BRANCH>` while you work. Commit your work, then `git rebase <MAIN_BRANCH>` and resolve any conflicts, so the reviewer gets a branch on top of the current `<MAIN_BRANCH>`. Then run every `test_gate` command in order from the worktree root. All must exit 0; do not hand over red tests. An empty `test_gate` means there is nothing to run. Afterwards `git status --porcelain` must be empty (commit generated files that belong to the change).
7. Commit on `<BRANCH>` with messages ending in `(<ISSUE_ID>)`. Never commit to `<MAIN_BRANCH>` and never merge into it; rebasing your own branch onto it is allowed.
8. `td link <ISSUE_ID> <changed files>` and `td log -i <ISSUE_ID> "<what you did>"`.
9. `td handoff <ISSUE_ID> --done "..." --remaining "..." --decision "..." --uncertain "..."`.
10. `td review <ISSUE_ID>`. Then reply with one line, `DONE <ISSUE_ID>`, and stop.

## Deferred work

Anything you deliberately leave out gets its own td issue immediately (`td create "..." --type <type> --priority <P>`).

## Cannot proceed

```bash
td log -i <ISSUE_ID> --blocker "<concrete reason>"
td update <ISSUE_ID> --labels <existing labels plus needs-human> -m "<what decision or input is needed>"
td unstart <ISSUE_ID>
```
Then reply `NEEDS-HUMAN <ISSUE_ID>` and stop. Leave your commits on the branch.
````

`skills/reviewer/SKILL.md`:

````markdown
---
name: reviewer
description: Reviewer role of claude-orchestrator. Use only when a start prompt says "Use skill claude-orchestrator:reviewer" with ISSUE_ID, BRANCH, MAIN_REPO, MAIN_BRANCH and MODE.
user-invocable: false
---

# Role: Reviewer

You independently review one td issue and either merge it into the main branch or reject it. You were started by the orchestrator; nobody is watching you. Never ask the user questions.

Your start prompt gives you: `ISSUE_ID`, `BRANCH`, `MAIN_REPO`, `MAIN_BRANCH`, `MODE` (`worktree` or `main`).

## Config

Read `<MAIN_REPO>/.claude/orchestrator.md`: the frontmatter (`test_gate`, `specs_dir`, `plans_dir`) and the `## Reviewer` section, if it has content. Then follow the repository's `CLAUDE.md`.

**Running the test gate** below means: run every `test_gate` command in order from your working directory; all must exit 0. An empty `test_gate` means there is nothing to run — review the code all the more carefully.

## Steps (both modes)

1. `td context <ISSUE_ID>`. Read the handoff, logs and linked files.
2. Read the plan task / spec section the issue implements (in `plans_dir` / `specs_dir`, if set).
3. Review for: correctness against plan and spec, tests that actually test the behaviour, `CLAUDE.md` conventions, no unrelated changes, deferred work captured as td issues.
4. Run the test gate yourself. Red → "Reject".

## MODE=worktree

5. Review the change set: `git diff <MAIN_BRANCH>...<BRANCH>` and `git log <MAIN_BRANCH>..<BRANCH> --oneline`. If the issue was rejected before, also check that every point of the newest `Rejected:` log entry is addressed.
   - Empty diff and `git -C <MAIN_REPO> branch --merged <MAIN_BRANCH>` lists `<BRANCH>`: an earlier reviewer already merged it. Go straight to step 8.
   - `git status --porcelain` in the worktree must be empty; uncommitted changes → "Reject" ("uncommitted changes in worktree: <paths>").
6. If you would reject: go to "Reject".
7. Merge:
   ```bash
   git rebase <MAIN_BRANCH>
   ```
   then run the test gate again, then
   ```bash
   git -C <MAIN_REPO> status --porcelain
   ```
   - Rebase conflict → `git rebase --abort`, then "Reject" with reason "rebase conflict with <MAIN_BRANCH>: <files>".
   - Test gate red after the rebase → "Reject" with the failing commands and tests.
   - `status --porcelain` prints anything → do NOT merge. Run
     `td update <ISSUE_ID> --labels <existing labels plus needs-human> -m "Approved by review but the main working tree is dirty: <paths>"`,
     reply `NEEDS-HUMAN <ISSUE_ID>` and stop. The issue stays `in_review`; once the user cleans the main working tree and removes the label, it is reviewed again.
   - Otherwise: `git -C <MAIN_REPO> merge --ff-only <BRANCH>`. If that fails → "Reject" with the git error.
8. `td approve <ISSUE_ID> --reason "<summary of what you checked>"`. If the issue still carries the label `needs-human`, remove it: `td update <ISSUE_ID> --labels <existing labels minus needs-human>` (`--labels ""` if none remain). Reply `APPROVED <ISSUE_ID>` and stop.

## MODE=main (only when the orchestrator passes it: work done before the repo used git)

The code is already on `<MAIN_BRANCH>`; there is no branch diff.

5. Review the files from `td files <ISSUE_ID>` and the handoff in their current state.
6. Do not edit code. If you would reject: go to "Reject" (the orchestrator gives the rework a branch).
7. Otherwise `td approve <ISSUE_ID> --reason "<summary>"` and remove a leftover `needs-human` label as in step 8 of MODE=worktree. Reply `APPROVED <ISSUE_ID>` and stop.

## Reject

```bash
td reject <ISSUE_ID> --reason "<numbered, concrete, actionable findings with file:line>"
```
Reply `REJECTED <ISSUE_ID>` and stop. Never fix the code yourself.
````

`skills/planner/SKILL.md`:

````markdown
---
name: planner
description: Planner role of claude-orchestrator. Use only when a start prompt says "Use skill claude-orchestrator:planner" with ISSUE_ID, BRANCH, MAIN_REPO and MAIN_BRANCH.
user-invocable: false
---

# Role: Planner

You turn one plan issue into an implementation plan and td issues. You were started by the orchestrator; nobody is watching you. Never ask the user questions.

Your start prompt gives you: `ISSUE_ID`, `BRANCH`, `MAIN_REPO`, `MAIN_BRANCH`, `REWORK`.

## Config

Read `<MAIN_REPO>/.claude/orchestrator.md`: the frontmatter (`specs_dir`, `plans_dir`) and the `## Planner` section, if it has content. Then follow the repository's `CLAUDE.md`. The orchestrator starts you only when `specs_dir` is set; if it is not, "Cannot proceed".

## Steps

1. `td start <ISSUE_ID>`, `td context <ISSUE_ID>`. If an earlier log line `Plan: <path>; epic <epic-id>; tasks <ids>` exists, this is a rework: update that plan file and those issues instead of creating new ones.
2. Find the spec that covers the issue's scope in `specs_dir`. Read existing plans in `plans_dir` for format and for what is already built.
   - If no spec covers the scope, or the spec leaves product or design decisions open that the plan would need: "Cannot proceed" (list the open decisions) and stop. Do not invent product or design decisions.
3. Write the plan with superpowers:writing-plans into `<plans_dir>/<YYYY-MM-DD>-<name>.md`. Skip that skill's execution-handoff question; nobody will answer it.
4. Commit the plan on `<BRANCH>` with a message ending in `(<ISSUE_ID>)`.
5. Create the td issues:
   - one epic: `td epic create "<plan title>"`
   - one feature per plan task, titled `P<N>-T<NN> <task name>`, each with `td update <task> --parent <epic>`
   - dependencies between tasks with `td dep add <task> <depends-on>`, mirroring the plan order
   - every task that has no other dependency depends on the plan issue itself: `td dep add <task> <ISSUE_ID>` — so no task starts before the plan is reviewed and merged into `<MAIN_BRANCH>`
   - priority: same as `<ISSUE_ID>`
6. `td log -i <ISSUE_ID> "Plan: <path>; epic <epic-id>; tasks <ids>"`, `td handoff ...`, `td review <ISSUE_ID>`.
7. Reply `DONE <ISSUE_ID>` and stop.

## Cannot proceed

```bash
td log -i <ISSUE_ID> --blocker "<open decisions>"
td update <ISSUE_ID> --labels <existing labels plus needs-human> -m "<open decisions>"
td unstart <ISSUE_ID>
```
Reply `NEEDS-HUMAN <ISSUE_ID>` and stop.
````

Note: v1's planner used `td tree add-child <epic> <task>`; the current td CLI rejects that form (`td tree` takes one argument). `td update <task> --parent <epic>` is the working form.

- [ ] **Step 4: Run it, expect only the orchestrate skill missing**

Run: `./scripts/check.sh`
Expected: exactly one failure, `FAIL: missing skills/orchestrate/SKILL.md` (Task 4 adds it). If `claude plugin validate skills` warns about `user-invocable`, remove that frontmatter line from all three skills and re-run: the descriptions alone keep the roles from triggering by accident.

- [ ] **Step 5: Commit**

```bash
git add skills/implementer skills/reviewer skills/planner scripts/check.sh
git commit -m "feat: generic implementer, reviewer and planner role skills (td-739c0f)"
```

---

### Task 4: Orchestrator skill

**Files:**
- Create: `skills/orchestrate/SKILL.md`
- Modify: `scripts/check.sh` (checks section)

**Interfaces:**
- Consumes: role skills and start-prompt parameters (Task 3), config keys (Task 2).
- Produces: `/claude-orchestrator:orchestrate [--dry-run] [--setup] [--builders N] [--reviewers M]`; it reads `setup.md` from its own base directory (Task 5).

- [ ] **Step 1: Add the failing content checks**

Append to the checks section of `scripts/check.sh`:

```bash
# orchestrator: key rules present
o=skills/orchestrate/SKILL.md
if [ -f "$o" ]; then
	for needle in 'Use skill claude-orchestrator:' 'setup.md' '--setup' '--dry-run' \
		'legacy_main_mode' 'specs_dir' 'claude-orchestrator@claude-orchestrator' \
		'unknown key' '<MAIN_BRANCH>' 'orchestrator: prompted' 'agent-blocked'; do
		grep -qF -- "$needle" "$o" || err "$o lacks: $needle"
	done
fi
```

- [ ] **Step 2: Run it, expect red**

Run: `./scripts/check.sh`
Expected: `FAIL: missing skills/orchestrate/SKILL.md`, exit 1.

- [ ] **Step 3: Write the orchestrator skill**

`skills/orchestrate/SKILL.md`:

````markdown
---
name: orchestrate
description: Run the claude-orchestrator — works through all workable td issues of this repo by starting fresh implementer, reviewer and planner agents in Herdr tabs and git worktrees. Use when the user types /claude-orchestrator:orchestrate or /orchestrate (optionally --dry-run, --setup, --builders N, --reviewers M).
---

# Orchestrator

You orchestrate. You start, prompt and monitor other agents and react to the td state they leave behind. You never read or edit code, never run tests, never review work, and never answer an agent's question or permission prompt (single exception: "Folder-trust dialog" below). Commands you run: `herdr`, `td`, read-only `git` (`status`, `branch --list`, `worktree list`, `rev-parse`, `symbolic-ref`, `check-ignore`), plus `git worktree add`, `git worktree remove`, `git branch -d` and `git -C <worktree> rebase --abort` for worktree housekeeping. You may read `<MAIN_REPO>/.claude/orchestrator.md` and `<MAIN_REPO>/.claude/settings.json`. The user is not watching; reach them only through `herdr notification show`. The one exception is the setup wizard, which runs before any agent starts.

Design: `docs/design.md` in the claude-orchestrator plugin repository.

## Arguments

- `--dry-run`: see "Dry run".
- `--setup`: read `setup.md` in this skill's base directory, follow it, then stop. No Herdr needed.
- `--builders N`, `--reviewers M`: override the slot counts from the config.

## Shell rules

- Run each `herdr`/`td`/`git` command as its own Bash call (no long `&&` chains); auto mode rejects compound commands more readily.
- Shell variables do not survive between Bash calls. Determine `MAIN_REPO` and `MAIN_BRANCH` once (Preconditions) and write the **literal values** into every later command. Below, `<MAIN_REPO>` and `<MAIN_BRANCH>` mean those literals.
- Every wait command (`agent prompt --wait`, `agent wait`, `pane wait-output`) gets the Bash tool parameter `timeout: 600000`; the Bash default of 2 minutes would cut it off.
- Never paste free text from td (rejection reasons, comments, titles) into a command line. Backticks and quotes in it would be executed by your shell.

## Config

Read `<MAIN_REPO>/.claude/orchestrator.md` and parse its YAML frontmatter. It is **valid** when it parses, `config_version` is `1`, `main_branch` is a non-empty string, `test_gate` is a list (possibly empty), and `plans_dir` is set whenever `specs_dir` is set. For every unknown key, print one line `warning: unknown key <key> in .claude/orchestrator.md` and ignore it — an unknown key never stands in for a required one (`test-gate` does not count as `test_gate`). Defaults for unset optional keys: `builders` 2, `reviewers` 1, `budgets` implementer 90 / reviewer 45 / planner 60 minutes, `legacy_main_mode` false, `specs_dir`/`plans_dir` unset.

Remember `<MAIN_BRANCH>` = `main_branch`, the slot counts (after `--builders`/`--reviewers`), the budgets, `legacy_main_mode`, and whether `specs_dir` is set (**planner enabled**).

## Preconditions

1. `git rev-parse --show-toplevel` → remember the printed path as `<MAIN_REPO>`. If it is inside a `.worktrees/` directory, say the orchestrator must run in the main working tree and stop.
2. Config: if the file is missing or not valid (see "Config"): with `--dry-run`, list the missing or invalid keys and stop; otherwise read `setup.md` in this skill's base directory and follow it, then re-read the config. If it is still not valid, stop.
3. `test "${HERDR_ENV:-}" = 1` — otherwise say you are not inside Herdr and stop.
4. `command -v td`, `command -v herdr` — both must print a path.
5. `<MAIN_REPO>/.claude/settings.json` must enable `claude-orchestrator@claude-orchestrator` (`enabledPlugins` entry `true`). Otherwise worker agents in worktrees would not find their role skills: run the wizard's step "Plugin enabled for the project" (in `setup.md`), and stop if the user declines.
6. `git -C <MAIN_REPO> rev-parse --abbrev-ref HEAD` must print `<MAIN_BRANCH>`.
7. `git -C <MAIN_REPO> status --porcelain` must print nothing — reviewers refuse to merge into a dirty main working tree. Otherwise notify the user with the paths and stop.
8. `echo $HERDR_WORKSPACE_ID` → remember it as `<ORCH_WS>`, your own workspace. Every agent gets its own tab there, so the user sees all agents in one place.
9. `herdr status` once.

## Dry run (`--dry-run`)

Report failed preconditions 3–7 instead of stopping. Do "Resume" and "Choose the next action" read-only, then print which agents you would start right now to fill the slots, followed by the ordered queue of the remaining workable issues (role, issue, mode, worktree create/reuse), plus the issues you would skip and why. Start nothing, change nothing, write no files, then stop.

## Slots

Agents run in parallel, each in its own worktree and tab:
- **Builder slots** (implementer or planner): config `builders`.
- **Reviewer slots**: config `reviewers`.

An agent occupies its slot while it is `working`, or settled but not yet evaluated. Agents waiting at a prompt (`agent-blocked`) free their slot. Never run two agents for the same issue.

## Ownership log

Every time you start an agent, log it on the issue: `td log -i <id> "orchestrator: started <name>"`. Every time you have delivered its start prompt, log `td log -i <id> "orchestrator: prompted <name>"`. These lines tell a restarted orchestrator which issues it owns and whether an agent ever got its task.

## Resume (every start, and at the top of every loop iteration)

1. `herdr agent list`. Live agents named `impl-*`, `rev-*`, `plan-*` are yours (`impl-a8b408` → `td-a8b408`).
   - If the issue's logs have no `orchestrator: prompted <name>` after the latest `orchestrator: started <name>`, the agent never got its task: when it is `idle`, send the start prompt ("Start an agent").
   - Otherwise it is an active agent; "Main loop" monitors it. If it is `blocked`, handle as "Agent blocked" (once; do not re-notify for an agent already labelled `agent-blocked`).
2. Agents labelled `agent-blocked` that are no longer `blocked`: remove the label (keep all other labels) and continue as in step 1.
3. Issues labelled `agent-blocked` without a live agent: remove that label.
4. **Stranded issues:** an issue `in_progress` with an `orchestrator: started …` log line but no live agent of yours is a failed attempt that nobody cleaned up. Log `orchestrator: attempt N failed: agent gone`, then `td unstart <id>`.

## Choose the next action

Gather:
```bash
td list --status in_review --json
td query "rework()" --json -n 0
td ready --json
```
Exclude epics, issues with labels `needs-human`, `stuck` or `agent-blocked`, and issues with a live agent.

**Attempts** of an issue (from `td show <id> --json` → `.logs`) = log messages starting with `orchestrator: attempt` + log messages starting with `Rejected:`. Before applying any rule to an issue, compute its attempts; at 3 or more apply "Stuck" to it instead and pick again.

**Role** of an issue: label `plan` → **planner**, otherwise **implementer**. If the planner is not enabled (no `specs_dir`), a `plan` issue is not workable; report it at the end as `planner disabled: no specs_dir`.

Fill free slots from these candidate lists:

- **Reviewer slot:** an `in_review` issue → **reviewer**. `MODE=worktree` if `git -C <MAIN_REPO> branch --list td/<id>` prints something. Otherwise `MODE=main` if `legacy_main_mode` is true; if it is false, the issue is not workable (report `no branch td/<id>`). Before a `MODE=worktree` review, re-check `git -C <MAIN_REPO> status --porcelain`; if it prints anything, notify the user, start no further reviewers and let "End of run" report it.
- **Builder slot:** first a `rework()` issue that is `open` → its role with `REWORK=yes`; otherwise a ready issue (in `td ready` order) → its role with `REWORK=no`.

Repeat until every slot is full or no candidate is left.

## Worktree (implementer, planner, reviewer in MODE=worktree)

Worktrees live at `<MAIN_REPO>/.worktrees/<id>` on branch `td/<id>`. Use plain git (not `herdr worktree`, which would open an extra workspace):

- `git -C <MAIN_REPO> worktree list`: if a worktree for branch `td/<id>` exists, reuse its path. A previous agent may have been stopped (timeout, crash) in the middle of a rebase, which leaves the worktree on a detached HEAD with conflict markers. Before starting the new agent, always run `git -C <worktree path> rebase --abort` as its own command: `fatal: no rebase in progress` is the normal case and means nothing to do; if it succeeds, log `td log -i <id> "orchestrator: aborted leftover rebase in <worktree path>"`. If it fails with any other error, do not start the agent; handle the issue as "Agent blocked" with summary `worktree stuck in rebase`.
- Else if `git -C <MAIN_REPO> branch --list td/<id>` prints something: `git -C <MAIN_REPO> worktree add <MAIN_REPO>/.worktrees/<id> td/<id>`.
- Else: `git -C <MAIN_REPO> worktree add -b td/<id> <MAIN_REPO>/.worktrees/<id> <MAIN_BRANCH>`.

For `MODE=main` reviews there is no worktree; the agent runs in `<MAIN_REPO>`.

## Start an agent

Names: `impl-<id without td->`, `rev-<...>`, `plan-<...>`.

```bash
herdr tab create --workspace <ORCH_WS> --cwd <worktree path or MAIN_REPO> --label <name> --no-focus   # .result.tab.tab_id and .result.root_pane.pane_id
herdr agent start <name> --kind claude --pane <root pane of that tab> --timeout 60000 -- --permission-mode auto
```
One tab per agent; the tab label is the agent name. After a restart, `herdr agent list` gives each agent's `tab_id`. Then log `orchestrator: started <name>`. If the pane is not yet an available shell, `herdr pane wait-output <pane> --regex '[$%#>❯] ?$' --timeout 10000` and retry once. `agent_not_ready` → read the screen (`herdr agent read <name> --source visible --lines 40`): the folder-trust dialog → "Folder-trust dialog"; anything else → "Agent blocked" (the start prompt is sent later by "Resume" step 1).

Start prompt — always exactly this one line, built only from IDs and paths:
```
Use skill claude-orchestrator:<implementer|reviewer|planner>. ISSUE_ID=<id> BRANCH=td/<id> MAIN_REPO=<MAIN_REPO> MAIN_BRANCH=<MAIN_BRANCH> MODE=<worktree|main> REWORK=<yes|no>
```
Send it without waiting for completion, then confirm the agent picked it up (Bash `timeout: 600000`):
```bash
herdr agent prompt <name> "<start prompt>"
herdr agent wait <name> --until working --until blocked --timeout 30000
```
Once `agent prompt` reports the submission, log `orchestrator: prompted <name>` — its timestamp is the agent's start time. `blocked` → "Agent blocked". A timeout here does not prove the prompt was lost: check `herdr agent get` and read the screen; never resend blindly.

## Folder-trust dialog (the only dialog you may answer)

Allowed only if the screen shows Claude's "Quick safety check: Is this a project you created or one you trust?" **and** the path under "Accessing workspace:" is `<MAIN_REPO>/.worktrees/<id>` for a worktree you created or reused for that issue. Then:
```bash
herdr agent send-keys <name> down enter
herdr agent wait <name> --timeout 30000
```
Expected: `idle`, then send the start prompt. Any other dialog, or any other path → "Agent blocked".

## Main loop

Repeat until "End of run":

1. "Resume" (housekeeping, adopting agents).
2. "Choose the next action" and start agents for every free slot.
3. Wait for the active agent most likely to finish first (the one with the least remaining budget), for at most 2 minutes (Bash `timeout: 600000`):
   ```bash
   herdr agent wait <name> --timeout 120000
   ```
   A timeout here is normal.
4. `herdr agent list` and, for every active agent of yours:
   - `idle` or `done` → "Check the outcome"; its slot becomes free.
   - `blocked` → "Agent blocked".
   - gone → "Agent exited or crashed".
   - `working` past its budget → "Timeout".

**Budget** per agent: from the config `budgets` for its role, counted from the timestamp of its latest `orchestrator: prompted <name>` log line (so it survives a restart). At budget, if the agent is still `working`, grant one extension of the same length (log `orchestrator: extended <name>`); after that → "Timeout".

To read an agent's output use `herdr agent read <name> --source visible --lines 60` (Claude runs on the alternate screen; `recent-unwrapped` misses its replies).

## Check the outcome (td only)

`td show <id> --json`:
- implementer/planner: expected status `in_review`, or label `needs-human`.
- reviewer: expected `closed`, or rejected (status `open`, newest log starts with `Rejected:`), or label `needs-human` on an issue that is not `closed`.

Expected → close the agent's tab (`herdr tab close <tab>`) and continue. If the reviewer closed the issue in `MODE=worktree`: remove the worktree (`git -C <MAIN_REPO> worktree remove <MAIN_REPO>/.worktrees/<id>`) and, as a separate command, delete the branch only if it is merged (`git -C <MAIN_REPO> branch -d td/<id>`; `-d` refuses unmerged branches — if it refuses, log it and leave it). If a closed issue still carries the label `needs-human`, remove it (`td update <id> --labels <existing labels minus needs-human>`), so closed issues never show up as needing the user.

Label `needs-human` appeared (issue not `closed`) → notify (`herdr notification show "Orchestrator: needs you" --body "<id> — see td comments" --sound request`), close the tab, continue.

Unexpected (status unchanged) and no `orchestrator: follow-up <name>` log line yet → send one follow-up prompt (as in "Start an agent", without waiting for completion), repeating the full start prompt: `Your td workflow for <id> is not finished (status <status>). <start prompt>`, and log `orchestrator: follow-up <name>`. The agent stays active and keeps its slot. Still unexpected after the follow-up → "Failed attempt" with reason `workflow not completed (status <status>)`.

## Failed attempt

```bash
herdr tab close <tab>
td log -i <id> --blocker "orchestrator: attempt N failed: <reason>"
```
If the agent was an implementer or planner and the issue is `in_progress`: `td unstart <id>`, so it can be picked again. A reviewer's issue stays `in_review` and is reviewed again (attempts permitting).

## Agent blocked

Do not send keys or answers. `herdr agent read <name> --source visible --lines 60`, then:
```bash
td log -i <id> --blocker "orchestrator: agent <name> blocked: <one-line summary of the dialog>"
td update <id> --labels <existing labels plus agent-blocked>
herdr notification show "Orchestrator: agent waiting" --body "<name> (<id>) waits at a prompt — answer it in its tab" --sound request
```
Leave the tab open; its slot is free for other work. "Resume" picks the agent up again once it is no longer `blocked`.

## Timeout

`herdr agent send-keys <name> ctrl+c`, then "Failed attempt" with reason `timeout after <min> min`.

## Agent exited or crashed

`herdr agent get <name>` fails or shows no agent → "Failed attempt" with reason `agent exited`.

## Stuck

```bash
td update <id> --labels <existing labels plus stuck>
td block <id> --reason "orchestrator: 3 failed attempts — see logs; branch td/<id> kept"
herdr notification show "Orchestrator: issue stuck" --body "<id>" --sound request
```
`td block` fails for an `in_review` issue; that is fine, the `stuck` label already excludes it. Keep the worktree and branch.

## End of run

When no slot can be filled and no agent of yours is active (only `agent-blocked` agents may remain): print a summary — issues closed this run, `stuck`, `needs-human`, `agent-blocked` (agents still waiting at a prompt, with their tabs), and what remains open with the reason it is not workable. Then `herdr notification show "Orchestrator: run finished" --body "<n> closed, <n> stuck, <n> need you" --sound done` and stop. Agents waiting at a prompt stay open; the user answers them and runs the orchestrator again, which adopts them.

## Output

- Keep your own output short: one line per action (`→ rev-a51fb9 (main mode)`, `✓ td-a51fb9 closed`), and after each loop iteration that changed something a one-line slot overview (`builders 2/2: impl-x, impl-y · reviewers 1/1: rev-z`).
````

Before writing: diff this text against v1 (`/home/mne-adm/Git/personal/github.com/game/.claude/skills/orchestrate/SKILL.md`). Every v1 rule must still be present; the only intended differences are the ones listed in the spec section "Orchestrator". If v1 contains a rule this text lacks, add it.

- [ ] **Step 4: Run it, expect green**

Run: `./scripts/check.sh`
Expected: `check.sh: all green`, exit 0. (`setup.md` does not exist yet; check.sh only checks that SKILL.md mentions it.)

- [ ] **Step 5: Commit**

```bash
git add skills/orchestrate/SKILL.md scripts/check.sh
git commit -m "feat: generic orchestrator skill driven by .claude/orchestrator.md (td-739c0f)"
```

---

### Task 5: Setup wizard

**Files:**
- Create: `skills/orchestrate/setup.md`
- Create: `scripts/make-fixture.sh`
- Modify: `scripts/check.sh` (checks section)

**Interfaces:**
- Consumes: `templates/orchestrator.md` placeholders (Task 2); "Config" validity rules and precondition 5 (Task 4).
- Produces: a valid `.claude/orchestrator.md` committed on the main branch; `scripts/make-fixture.sh <dir> [branch]` for Task 6.

- [ ] **Step 1: Add the failing wizard checks**

Append to the checks section of `scripts/check.sh`:

```bash
# wizard: present and covers every step
w=skills/orchestrate/setup.md
if [ ! -f "$w" ]; then
	err "missing $w"
else
	for needle in 'AskUserQuestion' '(Detected)' 'test_gate' 'command -v' 'check-ignore' \
		'.worktrees/' 'claude plugin install claude-orchestrator@claude-orchestrator --scope project' \
		'templates/orchestrator.md' 'chore: claude-orchestrator config' 'unknown key' '[]'; do
		grep -qF -- "$needle" "$w" || err "$w lacks: $needle"
	done
fi
[ -x scripts/make-fixture.sh ] || err "missing executable scripts/make-fixture.sh"
```

- [ ] **Step 2: Run it, expect red**

Run: `./scripts/check.sh`
Expected: `FAIL: missing skills/orchestrate/setup.md`, `FAIL: missing executable scripts/make-fixture.sh`, exit 1.

- [ ] **Step 3: Write the wizard**

`skills/orchestrate/setup.md`:

````markdown
# Setup wizard

Creates or completes `<MAIN_REPO>/.claude/orchestrator.md`. You run this before any agent starts, so here — and only here — you talk to the user, always through `AskUserQuestion`. Never run the test gate, never start agents.

The template is `templates/orchestrator.md` in the plugin root, two directories above this file (`<this skill's base directory>/../../templates/orchestrator.md`).

## 1. Detect (read-only)

If `.claude/orchestrator.md` exists, parse what you can: every valid existing value becomes the first proposal. Report each unknown key as `warning: unknown key <key>` and ask whether it was meant to be one of the known keys (a typo such as `test-gate`); never carry it over silently.

Otherwise detect:

- `main_branch`: `git -C <MAIN_REPO> symbolic-ref --short refs/remotes/origin/HEAD` (strip `origin/`); if that fails, `git -C <MAIN_REPO> rev-parse --abbrev-ref HEAD`.
- `test_gate`, in this order, collecting all hits:
  1. Test or check commands named in `CLAUDE.md` / `AGENTS.md` (look for "test", "check", "lint" near a command in backticks).
  2. Executable `*.sh` files in the repo root whose name contains `test`, `check` or `smoke`.
  3. `Makefile` / `justfile` targets `test` and `check` → `make test`, `just test`, …
  4. `package.json` script `test` → `npm test`.
  5. `pyproject.toml`, `pytest.ini` or `setup.cfg` with pytest config → `pytest`.
  6. `Cargo.toml` → `cargo test`. `go.mod` → `go test ./...`.
- `specs_dir`, `plans_dir`: directories named `specs` and `plans` (prefer siblings under the same parent), excluding `.git/`, `.worktrees/`, `node_modules/`: `find <MAIN_REPO> -type d \( -name specs -o -name plans \) -not -path '*/.git/*' -not -path '*/.worktrees/*' -not -path '*/node_modules/*'`. Store them relative to `<MAIN_REPO>`.
- `legacy_main_mode`: propose `true` only if `td list --status in_review --json` contains an issue for which `git -C <MAIN_REPO> branch --list td/<id>` prints nothing; otherwise `false`.
- `builders` 2, `reviewers` 1.

## 2. Confirm with the user

One `AskUserQuestion` call with up to four questions; the detected value is always the first option, labelled `<value> (Detected)`. Offer plausible alternatives as further options; "Other" is always available for free input.

1. **Main branch** — detected branch, other local branches (`git -C <MAIN_REPO> branch --format='%(refname:short)'`, at most two more).
2. **Test gate** — detected commands joined with ` && ` as one option; single commands as further options; option `No test gate ([])` with the description "Agents hand over and merge without running any tests". If the user picks `[]`, confirm it once more in a separate question before accepting.
3. **Specs and plans** — detected pair `specs: <dir>, plans: <dir>`; option `No planner (no specs_dir)`.
4. **Defaults** — `Keep defaults (2 builders, 1 reviewer, budgets 90/45/60 min, legacy_main_mode <detected>)` or `Change`. On `Change`, ask a second call for `builders`, `reviewers`, `legacy_main_mode`.

If the user's free input for the test gate contains several commands, split them on ` && ` or newlines into list items.

## 3. Check the test gate commands

For each command, take its first word. `./x` or `path/x` → `test -x <MAIN_REPO>/<path>`; otherwise `command -v <word>`. Show every failing command to the user and ask: fix (free input) or keep anyway.

## 4. `.gitignore`

`git -C <MAIN_REPO> check-ignore -q .worktrees/x` exits non-zero → ask whether to append `.worktrees/` to `<MAIN_REPO>/.gitignore` (create the file if missing). Declined → stop: worktrees would show up as untracked files and block every merge.

## 5. Plugin enabled for the project

`<MAIN_REPO>/.claude/settings.json` has `"enabledPlugins": {"claude-orchestrator@claude-orchestrator": true}`? Check with `jq -e '.enabledPlugins["claude-orchestrator@claude-orchestrator"] == true' <MAIN_REPO>/.claude/settings.json`. If not, ask whether to enable it, then run in `<MAIN_REPO>`:

```bash
claude plugin install claude-orchestrator@claude-orchestrator --scope project
```

If that command fails (for example because the marketplace is not added on this machine), merge the entry into `.claude/settings.json` yourself with `jq` (create `{}` first if the file is missing) and tell the user to run `claude plugin marketplace add <plugin repo or madic-creates/claude-orchestrator>`. Declined → stop: worker agents would not find their role skills.

## 6. Write the config

Read the template, replace the placeholders with the confirmed values and write `<MAIN_REPO>/.claude/orchestrator.md`:

- `{{main_branch}}` → the branch name.
- `{{test_gate}}` → a YAML block list, one `\n  - <command>` per command; `[]` when empty. Quote a command with `"…"` if it contains `: `, `#`, or starts with a YAML special character.
- `{{specs_dir}}`, `{{plans_dir}}` → the paths; when there is no planner, replace the whole line with `# specs_dir:` / `# plans_dir:` (commented out, i.e. unset).
- `{{builders}}`, `{{reviewers}}`, `{{legacy_main_mode}}` → the values.

If the file existed, keep its role sections' content unchanged and replace only the frontmatter. Show the written file to the user.

## 7. Commit

Ask: "Commit these files on `<MAIN_BRANCH>`?" listing `.claude/orchestrator.md` and, if changed, `.gitignore` and `.claude/settings.json`. On yes:

```bash
git -C <MAIN_REPO> add .claude/orchestrator.md
git -C <MAIN_REPO> commit -m "chore: claude-orchestrator config"
```
(add `.gitignore` and `.claude/settings.json` to the `git add` if they changed). On no: tell the user the run needs a clean main working tree and stop.

## 8. Done

With `--setup`: say the config is ready and stop. Otherwise return to the orchestrator's preconditions.
````

- [ ] **Step 4: Write the fixture script**

`scripts/make-fixture.sh`:

```bash
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
git add -A
git commit -q -m "fixture"
td init >/dev/null
echo "fixture ready: $dir (branch $branch)"
```

```bash
chmod +x scripts/make-fixture.sh
```

- [ ] **Step 5: Run it, expect green**

Run: `./scripts/check.sh`
Expected: `check.sh: all green`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add skills/orchestrate/setup.md scripts/make-fixture.sh scripts/check.sh
git commit -m "feat: setup wizard with detection, confirmation and fixture repo (td-739c0f)"
```

---

### Task 6: Wizard acceptance test

**Files:** none (manual test; results logged in td).

**Interfaces:**
- Consumes: everything from Tasks 1–5. Uses `claude --plugin-dir <plugin repo>` so the plugin source is tested without installing.

Each case runs an interactive Claude session in a fixture repo. The executing agent cannot answer `AskUserQuestion` dialogs of a nested session itself; run these cases in a Herdr tab and answer the wizard's questions as noted, or ask the user to do so. `<SCRATCH>` is the session scratchpad directory.

- [ ] **Step 1: Case A — fresh repo, defaults accepted**

```bash
./scripts/make-fixture.sh <SCRATCH>/fx-a
cd <SCRATCH>/fx-a && claude --plugin-dir /home/mne-adm/Git/personal/github.com/claude-orchestrator
```
Prompt: `/claude-orchestrator:orchestrate --setup`. Accept every `(Detected)` option, accept the `.gitignore` and plugin offers, confirm the commit.
Expected:
- proposals: main branch `main`, test gate `./run_tests.sh`, specs `docs/specs`, plans `docs/plans`, legacy_main_mode `false`.
- `.gitignore` contains `.worktrees/`; `.claude/settings.json` enables `claude-orchestrator@claude-orchestrator` (via `claude plugin install` or the `jq` fallback if the marketplace is not added yet — Task 7 adds it).
- `git -C <SCRATCH>/fx-a log --oneline -1` shows `chore: claude-orchestrator config`; `git status --porcelain` is empty.
- `python3 -c "import yaml,re,sys; t=open('.claude/orchestrator.md').read(); d=yaml.safe_load(re.match(r'^---\n(.*?)\n---\n',t,re.S).group(1)); print(d)"` prints `test_gate: ['./run_tests.sh']`, `main_branch: 'main'`.
- The wizard stopped after step 8 (no Herdr check, no agents).

- [ ] **Step 2: Case B — `master` branch and a typo'd key**

```bash
./scripts/make-fixture.sh <SCRATCH>/fx-b master
mkdir -p <SCRATCH>/fx-b/.claude
printf -- '---\nconfig_version: 1\nmain_branch: master\ntest-gate:\n  - ./run_tests.sh\n---\n' > <SCRATCH>/fx-b/.claude/orchestrator.md
git -C <SCRATCH>/fx-b add -A && git -C <SCRATCH>/fx-b commit -qm "typo config"
cd <SCRATCH>/fx-b && claude --plugin-dir /home/mne-adm/Git/personal/github.com/claude-orchestrator
```
Prompt: `/claude-orchestrator:orchestrate --setup`.
Expected: `warning: unknown key test-gate`, a question whether it was meant as `test_gate`; main branch proposal `master (Detected)`; the written frontmatter has `test_gate` and no `test-gate`; the commit lands on `master`.

- [ ] **Step 3: Case C — no test gate**

In `fx-a`, run `/claude-orchestrator:orchestrate --setup` again and pick `No test gate ([])`, confirm twice.
Expected: two confirmations; written `test_gate: []`; role sections unchanged.

- [ ] **Step 4: Case D — dry run with missing config**

```bash
./scripts/make-fixture.sh <SCRATCH>/fx-d
cd <SCRATCH>/fx-d && claude --plugin-dir /home/mne-adm/Git/personal/github.com/claude-orchestrator
```
Prompt: `/claude-orchestrator:orchestrate --dry-run`.
Expected: a report listing `.claude/orchestrator.md` as missing (required keys `config_version`, `main_branch`, `test_gate`); no question asked; `git status --porcelain` empty and no `.claude/` directory afterwards.

- [ ] **Step 5: Fix and record**

Any deviation → fix `setup.md` / `SKILL.md`, re-run `./scripts/check.sh` and the failed case, commit with `fix: <what> (td-739c0f)`. Then:

```bash
td log -i td-739c0f "Wizard acceptance cases A-D passed"
```

---

### Task 7: Install the plugin and migrate `game`

**Files (game repo, `/home/mne-adm/Git/personal/github.com/game`):**
- Create: `.claude/orchestrator.md`
- Create: `.claude/settings.json`
- Delete: `.claude/skills/orchestrate/SKILL.md`, `.claude/orchestrator/prompts/{implementer,reviewer,planner}.md`
- Modify: `CLAUDE.md` (section "Agent orchestrator")
- Modify: `docs/superpowers/specs/2026-10-14-agent-orchestrator-design.md` (status line)

**Interfaces:**
- Consumes: the merged plugin on `main` of the plugin repo.

- [ ] **Step 1: Make sure no orchestrator is running in `game`**

Run: `herdr agent list`
Expected: no live agent named `impl-*`, `rev-*` or `plan-*`. Otherwise stop and ask the user to finish or stop the running orchestrator first.

- [ ] **Step 2: Record the v1 reference dry run**

In a Herdr pane in `game` (fresh Claude session): `/orchestrate --dry-run`. Save the printed plan (agents to start, queue, skipped issues) to `<SCRATCH>/dryrun-v1.txt`.

- [ ] **Step 3: Merge the plugin branch and install the marketplace**

```bash
cd /home/mne-adm/Git/personal/github.com/claude-orchestrator
./scripts/check.sh
git switch main
git merge --ff-only td/td-739c0f
claude plugin marketplace add /home/mne-adm/Git/personal/github.com/claude-orchestrator
claude plugin marketplace list
```
Expected: check green; `claude-orchestrator` listed.

- [ ] **Step 4: Migrate on a game worktree branch**

```bash
cd /home/mne-adm/Git/personal/github.com/game
git worktree add -b td/td-739c0f .worktrees/td-739c0f main
cd .worktrees/td-739c0f
claude plugin install claude-orchestrator@claude-orchestrator --scope project
git rm -q .claude/skills/orchestrate/SKILL.md .claude/orchestrator/prompts/implementer.md .claude/orchestrator/prompts/reviewer.md .claude/orchestrator/prompts/planner.md
```

Check `.claude/settings.json` now contains `"claude-orchestrator@claude-orchestrator": true` under `enabledPlugins`; if the install wrote it elsewhere (main tree instead of worktree), move the file into the worktree.

Create `.claude/orchestrator.md`:

```markdown
---
# claude-orchestrator config. Reference: README.md of the claude-orchestrator plugin.
config_version: 1
# Branch that reviewers merge into and worktrees branch from.
main_branch: main
# Shell commands run from the worktree root; all must exit 0. [] = no gate.
test_gate:
  - ./run_tests.sh
  - ./smoke.sh
# Where specs and plans live. Without specs_dir the planner role is disabled.
specs_dir: docs/superpowers/specs
plans_dir: docs/superpowers/plans
# Parallel agents. --builders / --reviewers override these.
builders: 2
reviewers: 1
# Minutes per agent attempt; one extension of the same length is granted.
budgets: { implementer: 90, reviewer: 45, planner: 60 }
# true: in_review issues without a td/<id> branch are reviewed on the main branch.
legacy_main_mode: true
---

<!--
Optional additions per role. Each role reads its own section after the
frontmatter. Conventions that already live in CLAUDE.md do not belong here.
-->

## Implementer

- Tests are GUT tests; write the failing GUT test first.
- Code is statically typed GDScript (see CLAUDE.md).
- Commit the `.uid` files Godot generates for new scripts.
- In a fresh worktree, `./run_tests.sh` runs `godot --headless --import` for you; run it before calling Godot by hand.

## Reviewer

- New scripts must come with their committed `.uid` files.

## Planner

- Specs and plans follow the format of the existing files in `docs/superpowers/`. Do not invent game design.
```

- [ ] **Step 5: Update `CLAUDE.md` and the v1 spec**

In `CLAUDE.md`, replace the whole `## Agent orchestrator` section with:

```markdown
## Agent orchestrator

- Provided by the `claude-orchestrator` plugin (`/home/mne-adm/Git/personal/github.com/claude-orchestrator`, enabled in `.claude/settings.json`). Config: `.claude/orchestrator.md` (test gate, doc paths, role notes).
- Start in a Herdr pane with `/claude-orchestrator:orchestrate` (`--dry-run` to preview, `--setup` to re-run the config wizard). It works through all workable td issues with fresh implementer, reviewer and planner agents.
- Labels: `needs-human` (needs a user decision), `stuck` (3 failed attempts, branch kept), `agent-blocked` (agent waits at a prompt), `plan` (handled by the planner).
```

Also update the "Git is enabled" bullet's reference `See /orchestrate.` to `See the Agent orchestrator section.`

In `docs/superpowers/specs/2026-10-14-agent-orchestrator-design.md`, replace the line `- **Status:** draft, awaiting user review` with:

```markdown
- **Status:** superseded by the `claude-orchestrator` plugin (`claude-orchestrator/docs/design.md`, 2026-10-15)
```

- [ ] **Step 6: Run game's test gate**

```bash
./run_tests.sh && ./smoke.sh
git status --porcelain
```
Expected: both green (no code changed; this proves the branch is sound). Status lists only the intended files.

- [ ] **Step 7: Commit, merge, clean up**

```bash
git add .claude/orchestrator.md .claude/settings.json CLAUDE.md docs/superpowers/specs/2026-10-14-agent-orchestrator-design.md
git commit -m "chore: switch to the claude-orchestrator plugin (td-739c0f)"
```

This is the change that replaces `game`'s orchestrator; merging it into `main` follows the repo rule "only a reviewer merges". Submit for review (`td review`) and let a reviewer session merge it (`git -C /home/mne-adm/Git/personal/github.com/game merge --ff-only td/td-739c0f`, then `git worktree remove .worktrees/td-739c0f`, `git branch -d td/td-739c0f`).

- [ ] **Step 8: Compare dry runs**

After the merge, in a fresh Claude session in a Herdr pane in `game`: `/claude-orchestrator:orchestrate --dry-run`. Compare with `<SCRATCH>/dryrun-v1.txt`.
Expected: same agents, same queue, same skip reasons, except for issues whose td state changed in between (name them). The wizard must not start (config valid). Differences → fix in the plugin, re-run check.sh, commit `fix: … (td-739c0f)`, `claude plugin marketplace update claude-orchestrator`, `claude plugin update claude-orchestrator@claude-orchestrator`, restart the session, re-run the dry run.

---

### Task 8: Pilot run (user)

**Files:** none.

- [ ] **Step 1: Hand over to the user**

The user starts, in a Herdr pane in `game`: `/claude-orchestrator:orchestrate --builders 1 --reviewers 1` and lets it complete at least one issue end to end (worktree, implementer, reviewer, merge, cleanup).

- [ ] **Step 2: Record and close**

Problems found → one td issue each. Then `td log -i td-739c0f "Pilot run: <result>"` and close the epic once the pilot is clean.
