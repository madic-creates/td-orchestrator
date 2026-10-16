# td-orchestrator

A Claude Code plugin that works through all workable [td](https://github.com/marcus/td) issues of a git repository on its own. It starts a fresh agent per issue and role (implementer, reviewer, planner), each in its own [Herdr](https://herdr.dev) tab and git worktree, checks the td state they leave behind, merges reviewed work into the main branch and notifies you only when it needs you.

Design: [`docs/design.md`](docs/design.md).

## Requirements

- Claude Code with auto mode
- Herdr (the orchestrator must run inside a Herdr pane)
- `td`, `git`, `jq`
- The [superpowers](https://github.com/obra/superpowers) plugin (implementers use `superpowers:test-driven-development`, planners `superpowers:writing-plans`)

## Install

Once per machine:

```bash
claude plugin marketplace add /path/to/td-orchestrator   # or: madic-creates/td-orchestrator
```

Once per repository. This writes `enabledPlugins` into the committed `.claude/settings.json`, so everyone in the repo gets `/td-orchestrator:orchestrate`. Worker agents are started with `--plugin-dir` and do not depend on it.

```bash
cd /path/to/repo
claude plugin install td-orchestrator@td-orchestrator --scope project
```

The setup wizard offers this step if it is missing.

Picking up plugin changes depends on how the marketplace was added:

- **Local directory** (`marketplace add /path/to/td-orchestrator`): the plugin is read straight from that folder, so edits take effect at the next session start or after `/reload-plugins`. `claude plugin update` has nothing to do here.
- **GitHub** (`marketplace add madic-creates/td-orchestrator`): run `claude plugin marketplace update td-orchestrator` and `claude plugin update td-orchestrator@td-orchestrator`, then restart Claude Code.

## Usage

Inside a Herdr pane, in the repository's main working tree:

| Command | Effect |
|---|---|
| `/td-orchestrator:orchestrate` | Run until nothing workable is left. |
| `… --dry-run` | Show what would be started, change nothing. |
| `… --builders N --reviewers M` | Override the slot counts from the config. |
| `… --setup` | Run only the setup wizard, then stop. |

## Configuration

Each repository has one committed file, `.claude/orchestrator.md`. The setup wizard creates it; `/td-orchestrator:orchestrate --setup` runs the wizard again. An optional untracked `.claude/orchestrator.local.md` adds personal settings (see "Local config").

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

## Orchestrator
```

| Key | Required | Default | Meaning |
|---|---|---|---|
| `config_version` | yes | none | Must be `1`. |
| `main_branch` | yes | none | Branch reviewers merge into and worktrees branch from. |
| `test_gate` | yes | none | Shell commands run from the worktree root; all must exit 0. `[]` means no gate. |
| `specs_dir` | no | unset | Where specs live. Unset → the planner role is disabled and `plan` issues are skipped. |
| `plans_dir` | no | unset | Where plans live. Required when `specs_dir` is set; may be set without it. |
| `builders` | no | 2 | Builder slots (implementer or planner). |
| `reviewers` | no | 1 | Reviewer slots. |
| `budgets` | no | 90/45/60 | Minutes per attempt for implementer/reviewer/planner. |
| `legacy_main_mode` | no | `false` | Review `in_review` issues that have no `td/<id>` branch directly on the main branch (work done before the repo used git). |

Unknown keys are ignored with a warning. A missing required key, an optional key with the wrong type or range, an unparseable frontmatter or an unknown `config_version` starts the wizard.

The optional sections `## Implementer`, `## Reviewer`, `## Planner` are read by that role only. Use them for orchestrator-specific additions; general conventions belong in `CLAUDE.md`. The optional section `## Orchestrator` holds instructions for the orchestrator itself (see below).

### Local config

`.claude/orchestrator.local.md` is an optional, untracked file for your own settings. It has the same format as `.claude/orchestrator.md`, and every part of it is optional:

- **Frontmatter:** each key set here replaces the shared value. `budgets` is merged per role, so `budgets: { implementer: 120 }` changes only the implementer budget. The merged result is validated like the shared file.
- **Sections:** each section is appended to the shared section of the same name. Where they conflict, the local one wins.

The file must be ignored by git, otherwise it would make the main working tree dirty. The setup wizard offers to add it to `.gitignore`, and the orchestrator stops if the file exists but is not ignored. The wizard never reads or writes this file.

```markdown
---
builders: 3
---

## Orchestrator
When the run finishes or an issue needs me, send a mail with
`mail -s "<subject>" me@example.com`, body on stdin.
```

The `## Orchestrator` section lets the orchestrator run the shell commands and call the tools (such as an MCP mail tool) it names, but only for the events it already handles: a precondition stops the run, an agent waits at a prompt, `needs-human`, `stuck`, a timeout, the end of the run. Its other limits stay: it never reads code, runs tests or answers agent prompts. A failing command only prints a warning.

Fixed conventions: worktrees at `.worktrees/<id>` (add `.worktrees/` and `.claude/orchestrator.local.md` to `.gitignore`), branches `td/<id>`, no td issue IDs in commit messages (td issues are local), labels `needs-human`, `stuck`, `agent-blocked`, `plan`.

### Labels

| Label | Meaning |
|---|---|
| `plan` | Handled by the planner: turns a spec into a plan and td issues. |
| `needs-human` | Needs a decision from you. Skipped until you remove the label. |
| `stuck` | Failed 3 attempts. Blocked in td; branch kept. |
| `agent-blocked` | The issue's agent waits at a prompt in its tab. |

## Development

`./scripts/check.sh` is the test gate: manifest validation, skill presence, template schema, and no project-specific terms in `skills/` and `templates/`. It needs the `claude` CLI, `jq` and `python3` with PyYAML. `./scripts/make-fixture.sh <dir>` creates a throwaway git + td repository for trying the setup wizard.

### Releasing

Users who installed from GitHub get a new copy only when `version` in `.claude-plugin/plugin.json` changes; commits pushed without a version bump do not reach them. To release:

1. Bump `version` in `.claude-plugin/plugin.json` (semver). Do not add `version` to the plugin entry in `marketplace.json`: `plugin.json` wins and `claude plugin validate` flags the mismatch.
2. Optionally tag the commit, e.g. `git tag v0.2.0 && git push --tags`. Claude Code does not need tags or GitHub releases; a tag only lets users pin a version with `claude plugin marketplace add madic-creates/td-orchestrator#v0.2.0`.

`metadata.version` in `marketplace.json` versions the catalog, not the plugin, and plays no part in updates. Installs from a local marketplace directory ignore `version` entirely.
