# td-orchestrator (repo: claude-orchestrator)

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

Once per repository (writes `enabledPlugins` into the committed `.claude/settings.json`, so everyone in the repo gets `/td-orchestrator:orchestrate`; worker agents are started with `--plugin-dir` and do not depend on it):

```bash
cd /path/to/repo
claude plugin install td-orchestrator@td-orchestrator --scope project
```

The setup wizard offers this step if it is missing.

After changing the plugin source: `claude plugin marketplace update td-orchestrator` and `claude plugin update td-orchestrator@td-orchestrator`, then restart Claude Code.

## Usage

Inside a Herdr pane, in the repository's main working tree:

| Command | Effect |
|---|---|
| `/td-orchestrator:orchestrate` | Run until nothing workable is left. |
| `… --dry-run` | Show what would be started, change nothing. |
| `… --builders N --reviewers M` | Override the slot counts from the config. |
| `… --setup` | Run only the setup wizard, then stop. |

## Configuration

Each repository has one committed file, `.claude/orchestrator.md`. The setup wizard creates it; `/td-orchestrator:orchestrate --setup` runs the wizard again.

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

## Development

`./scripts/check.sh` is the test gate: manifest validation, skill presence, template schema, and no project-specific terms in `skills/` and `templates/`.
