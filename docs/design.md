# claude-orchestrator – Design

- **Date:** 2026-10-15
- **td issue:** td-b470d9 (epic td-739c0f, tracked in the `game` repo)
- **Status:** draft, awaiting user review
- **Supersedes:** `game/docs/superpowers/specs/2026-10-14-agent-orchestrator-design.md` (the repo-specific v1)

## Goal

A Claude Code plugin that lets a long-running AI agent (the **orchestrator**) work through as many td issues of *any* git + td repository as it can complete on its own. It starts, prompts and monitors fresh implementer, reviewer and planner agents in Herdr tabs, each in its own git worktree. The user is involved only through Herdr notifications.

The v1 orchestrator lived inside the `game` repo and hard-coded that repo's test scripts, document paths, branch name and Godot conventions. This design moves it into a standalone plugin and puts everything repo-specific into one config file per repo, created by a setup wizard.

## Success criteria

- In a repo with git, td and the plugin enabled, `/orchestrate` works through all workable td issues, exactly as v1 does in `game`.
- No file of the plugin mentions a specific project, language, test framework or directory layout.
- In a repo without a valid config, `/orchestrate` runs a wizard that detects sensible values, lets the user confirm or correct each one, writes the config and then continues the run.
- `game` behaves the same after the migration: `/orchestrate --dry-run` lists the same agents and queue as v1 did before the migration.

## Non-goals

- Supporting task trackers other than td, terminal multiplexers other than Herdr, or agents other than Claude Code.
- Making the worktree path, branch prefix or commit-message suffix configurable.
- Replacing superpowers: implementers use `superpowers:test-driven-development`, planners `superpowers:writing-plans`.
- Asking the user anything during an unattended run. The wizard runs only before the run starts.

## Repository and distribution

Repository: `/home/mne-adm/Git/personal/github.com/claude-orchestrator`, branch `main`, remote `origin` = `github.com/madic-creates/claude-orchestrator`. Pushing happens only when the user asks.

```
claude-orchestrator/
  .claude-plugin/plugin.json        # name: claude-orchestrator
  .claude-plugin/marketplace.json   # marketplace "claude-orchestrator" listing this plugin (source "./")
  skills/orchestrate/SKILL.md       # orchestrator: preconditions, loop, monitoring, error handling
  skills/orchestrate/setup.md       # wizard procedure, read only when the config is missing/invalid or on --setup
  skills/implementer/SKILL.md       # role: implementer
  skills/reviewer/SKILL.md          # role: reviewer
  skills/planner/SKILL.md           # role: planner
  templates/orchestrator.md         # commented config template, used by the wizard
  docs/design.md                    # this document
  README.md                         # install, dependencies, config reference
```

**Install, once per machine:** `claude plugin marketplace add /home/mne-adm/Git/personal/github.com/claude-orchestrator` (or the GitHub repo).
**Enable, once per repo:** install the plugin with project scope, which writes `enabledPlugins` into the repo's committed `.claude/settings.json`. Because that file is committed, every worktree (and therefore every worker agent) has the plugin enabled too. The wizard checks this and offers to do it.

**Dependencies** (checked as preconditions, listed in the README): Herdr (`HERDR_ENV=1`, `herdr` CLI), `td`, `git`, Claude Code auto mode, the superpowers plugin.

## Per-repo config: `.claude/orchestrator.md`

One Markdown file, committed in the repo. YAML frontmatter holds the structured values; the body holds optional free-text additions per role.

```markdown
---
config_version: 1
main_branch: main
test_gate:
  - ./run_tests.sh
  - ./smoke.sh
specs_dir: docs/superpowers/specs
plans_dir: docs/superpowers/plans
builders: 2
reviewers: 1
budgets: { implementer: 90, reviewer: 45, planner: 60 }
legacy_main_mode: true
---

## Implementer
Tests use GUT. Commit the `.uid` files Godot generates for new scripts.
Run `godot --headless --import` first in a fresh worktree.

## Reviewer

## Planner
```

| Key | Required | Default | Meaning |
|---|---|---|---|
| `config_version` | yes | – | Must be `1`. Any other value triggers the wizard. |
| `main_branch` | yes | – | Branch that reviewers merge into and worktrees branch from. |
| `test_gate` | yes | – | List of shell commands, run from the worktree root. All must exit 0. `[]` is allowed only after explicit confirmation in the wizard. |
| `specs_dir` | no | unset | Where specs live. Unset → the planner role is disabled; `plan` issues are skipped and reported as not workable. |
| `plans_dir` | no | unset | Where plans live. Required when `specs_dir` is set. |
| `builders` | no | 2 | Builder slots. `--builders N` overrides. |
| `reviewers` | no | 1 | Reviewer slots. `--reviewers M` overrides. |
| `budgets` | no | 90 / 45 / 60 | Minutes per agent attempt, per role. |
| `legacy_main_mode` | no | `false` | `true` enables `MODE=main` reviews for `in_review` issues without a `td/<id>` branch (work done before the repo used git). |

Unknown keys are ignored with a one-line warning.

The body sections `## Implementer`, `## Reviewer`, `## Planner` are optional. A role reads its own section, if present, after the frontmatter. Conventions that already live in the repo's `CLAUDE.md` do not belong here; the sections are for orchestrator-specific additions only.

Fixed conventions (not configurable): worktree `<MAIN_REPO>/.worktrees/<id>`, branch `td/<id>`, commit messages end with `(<ISSUE_ID>)`, agent names `impl-` / `rev-` / `plan-` + id without `td-`, labels `needs-human`, `stuck`, `agent-blocked`, `plan`.

## Setup wizard

`skills/orchestrate/setup.md`, read by the orchestrator only when needed.

**Triggers:** `.claude/orchestrator.md` missing; frontmatter not parseable; a required key missing; `config_version` not `1`; `plans_dir` missing while `specs_dir` is set; `/orchestrate --setup`.

With `--dry-run` the wizard does not run: the dry run reports which keys are missing or invalid and stops.

**Steps:**

1. **Detect** candidate values (read-only):
   - `main_branch`: `git symbolic-ref refs/remotes/origin/HEAD`, else the current branch.
   - `test_gate`: test/check commands named in `CLAUDE.md` / `AGENTS.md`; executable `*.sh` in the repo root whose name suggests tests (`test`, `check`, `smoke`); `Makefile` / `justfile` targets `test`, `check`; `package.json` script `test`; `pyproject.toml` / `pytest.ini` → `pytest`; `Cargo.toml` → `cargo test`; `go.mod` → `go test ./...`.
   - `specs_dir` / `plans_dir`: existing directories matching `**/specs` and `**/plans` (outside `.worktrees/`, `node_modules/`, `.git/`).
   - `legacy_main_mode`: proposed `true` only if `td list --status in_review` contains issues without a `td/<id>` branch.
   - Existing config values, if the file exists but is incomplete, are kept as the first proposal.
2. **Confirm** each value with the user via `AskUserQuestion`: detected value first ("(Detected)"), plausible alternatives, "Other" for free input. Up to four questions per call; optional keys with a default are asked in one final "keep defaults?" question.
3. **Check** the `test_gate` commands: each command's first word must resolve (`command -v`, or an executable file relative to the repo root). A failing check is shown to the user, who corrects or confirms it. The wizard never runs the test gate.
4. **`.gitignore`:** if `.worktrees/` is not ignored (`git check-ignore -q .worktrees/x`), offer to append it.
5. **Plugin enabled for the project:** if `.claude/settings.json` does not enable `claude-orchestrator@claude-orchestrator`, offer to add it (merging with existing content).
6. **Write** `.claude/orchestrator.md` from `templates/orchestrator.md` with the confirmed values and empty role sections, then show the result.
7. **Commit** the changed files on `main_branch` after the user's OK (`chore: claude-orchestrator config`, no td suffix required). The run needs a clean main working tree, so a declined commit ends the run with that explanation.
8. Continue with the normal preconditions.

The wizard is the only part of the orchestrator that talks to the user directly, and it runs only before any agent is started.

## Orchestrator (`skills/orchestrate/SKILL.md`)

Behaviour is v1's, with these changes:

- **Preconditions**, in order: inside Herdr; `td` and `herdr` on `PATH`; `<MAIN_REPO>` from `git rev-parse --show-toplevel`; valid config (otherwise the wizard); plugin enabled in the project's `.claude/settings.json`; current branch is `<MAIN_BRANCH>`; main working tree clean; `herdr status`.
- Every hard-coded `main` becomes `<MAIN_BRANCH>`. Like `<MAIN_REPO>`, it is written as a literal into every command.
- Slots and budgets come from the config; `--builders` / `--reviewers` override slots.
- `MODE=main` reviews exist only with `legacy_main_mode: true`. Otherwise an `in_review` issue without a `td/<id>` branch is reported as not workable (`no branch`).
- With `specs_dir` unset, issues labelled `plan` are reported as not workable (`planner disabled: no specs_dir`).
- **Start prompt**, still one line built only from IDs and paths:
  ```
  Use skill claude-orchestrator:<role>. ISSUE_ID=<id> BRANCH=td/<id> MAIN_REPO=<MAIN_REPO> MAIN_BRANCH=<MAIN_BRANCH> MODE=<worktree|main> REWORK=<yes|no>
  ```
- The spec reference points to this document.

Everything else is unchanged from v1: slots, ownership log lines, resume and adoption of live agents, attempts and `stuck`, the folder-trust exception, the follow-up prompt, timeouts with one extension, worktree reuse with `rebase --abort`, cleanup after merge, notifications, the end-of-run summary.

## Roles

Each role skill starts the same way:

1. Read `<MAIN_REPO>/.claude/orchestrator.md`: the frontmatter and the role's own body section, if present.
2. Follow the repo's `CLAUDE.md` for language, style and test conventions.

**Implementer:** v1 steps, with the plan/spec lookup in `plans_dir` / `specs_dir` (if set); TDD with `superpowers:test-driven-development` following the repo's test conventions; rebase onto `<MAIN_BRANCH>`; every `test_gate` command must pass; commits end with `(<ISSUE_ID>)`. No mention of any language or framework.

**Reviewer:** v1 steps, with `git diff <MAIN_BRANCH>...<BRANCH>`, the `test_gate` run before and after the rebase, fast-forward merge into `<MAIN_BRANCH>`. The `MODE=main` section stays, used only when the orchestrator passes `MODE=main`.

**Planner:** v1 steps, reading specs from `specs_dir` and writing the plan to `plans_dir/<YYYY-MM-DD>-<name>.md`. "Do not invent game design" becomes "do not invent product or design decisions".

The `needs-human` / "Cannot proceed" procedures and the one-line replies (`DONE`, `APPROVED`, `REJECTED`, `NEEDS-HUMAN`) are unchanged.

## Migration of `game`

Done while no orchestrator runs in `game`.

1. Before the change: run v1 `/orchestrate --dry-run` and keep its output as the reference.
2. Add `.claude/orchestrator.md` with the values shown above (including the Godot notes in `## Implementer`).
3. Add `.claude/settings.json` enabling `claude-orchestrator@claude-orchestrator`.
4. Delete `.claude/skills/orchestrate/` and `.claude/orchestrator/prompts/`.
5. Update the "Agent orchestrator" section of `CLAUDE.md` (plugin, config file, `/orchestrate --setup`).
6. Mark the v1 spec as superseded by this document.
7. `/orchestrate --dry-run` must match the reference.

## Error handling

Unchanged from v1 (attempts, `stuck` after 3, `agent-blocked`, timeouts, follow-up prompt, crashed agents). New cases:

| Situation | Reaction |
|---|---|
| Config missing or invalid | Wizard (interactive run) or report (dry run). |
| Wizard declined or aborted | Stop without starting agents; say what is missing. |
| Plugin not enabled for the project | Wizard offers to enable it; if declined, stop: worker agents would not find their role skills. |
| A worker agent cannot find its role skill | It lands in a state the orchestrator already handles (unexpected outcome → follow-up → failed attempt). The precondition check prevents this case. |

## Testing and rollout

There are no unit tests for Markdown skills. Verification:

1. `claude plugin validate` (or `claude plugin details`) on the plugin repo: manifest, marketplace and all four skills load.
2. `grep` over the plugin for project-specific terms (`godot`, `gdscript`, `GUT`, `run_tests`, `smoke`, `superpowers/specs`, `game`) finds nothing outside `docs/` and the README examples.
3. **Wizard test** in a throwaway repo in the scratchpad (git, `td init`, a `run_tests.sh`, a `docs/specs/`, no config): the wizard detects the values, asks, writes the config, offers `.gitignore` and settings, commits after the OK.
4. **`game` dry run** matches the v1 reference (migration step 7).
5. **Pilot run** in `game` with `--builders 1 --reviewers 1` on one small issue, started by the user in Herdr.
