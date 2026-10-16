---
# td-orchestrator config. Reference: README.md of the td-orchestrator plugin.
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
budgets: {{budgets}}
# true: in_review issues without a td/<id> branch are reviewed on the main branch.
legacy_main_mode: {{legacy_main_mode}}
---

<!--
Optional additions per role. Each role reads its own section after the
frontmatter. Conventions that already live in CLAUDE.md do not belong here.
## Orchestrator holds instructions for the orchestrator itself, e.g. extra
notifications. Personal settings go into the untracked
.claude/orchestrator.local.md (same format, every part optional).
-->

## Implementer

## Reviewer

## Planner

## Orchestrator
