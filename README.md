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

Once per repository (writes `enabledPlugins` into the committed `.claude/settings.json`, so worker agents in worktrees get the plugin too):

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

See "Configuration reference" below.

## Development

`./scripts/check.sh` is the test gate: manifest validation, skill presence, template schema, and no project-specific terms in `skills/` and `templates/`.
