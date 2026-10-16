---
name: implementer
description: Implementer role of td-orchestrator. Use only when a start prompt says "Use skill td-orchestrator:implementer" with ISSUE_ID, BRANCH, MAIN_REPO and MAIN_BRANCH.
user-invocable: false
---

# Role: Implementer

You implement exactly one td issue, then hand it to an independent reviewer. You were started by the orchestrator; nobody is watching you. Never ask the user questions. When you cannot proceed, use "Cannot proceed" below and stop.

Your start prompt gives you: `ISSUE_ID`, `BRANCH`, `MAIN_REPO`, `MAIN_BRANCH`, `REWORK` (`yes` if a reviewer rejected an earlier attempt).

## Config

Read `<MAIN_REPO>/.claude/orchestrator.md` and, if it exists, the untracked `<MAIN_REPO>/.claude/orchestrator.local.md`: the frontmatter (`test_gate`, `specs_dir`, `plans_dir`; a key set in the local file replaces the shared one) and the `## Implementer` section of each, if it has content (the local one wins where they conflict). Then follow the repository's `CLAUDE.md` (language, style, test conventions). The `## Implementer` section takes precedence over this skill where they conflict on repo-specific details (setup commands, generated files).

## Steps

1. `td start <ISSUE_ID>` (on rework, `td start` again is fine), then `td context <ISSUE_ID>`.
2. `git rev-parse --abbrev-ref HEAD` must print `<BRANCH>`. If not, "Cannot proceed".
3. Find the plan task or spec section for the issue in `plans_dir` and `specs_dir` (if set). Match by a task code in the title (e.g. `P1-T08`) or by the title text.
   - If no plan or spec covers the issue and the description alone is not enough to implement it without product or design decisions: "Cannot proceed" and stop.
4. If `REWORK=yes`, read the newest log entry starting with `Rejected:` and the previous handoff in `td context`; fix exactly what was rejected. If the rejection is a rebase conflict with `<MAIN_BRANCH>`, run `git rebase <MAIN_BRANCH>` on your branch and resolve the conflicts.
5. Implement with TDD (superpowers:test-driven-development) following the repository's test conventions: failing test, minimal code, green.
6. Other agents merge into `<MAIN_BRANCH>` while you work. Commit your work, then `git rebase <MAIN_BRANCH>` and resolve any conflicts, so the reviewer gets a branch on top of the current `<MAIN_BRANCH>`. Then run every `test_gate` command in order from the worktree root. All must exit 0; do not hand over red tests. An empty `test_gate` means there is nothing to run. Afterwards `git status --porcelain` must be empty (commit generated files that belong to the change).
7. Commit on `<BRANCH>`. Do not put the td issue ID in commit messages; td issues are local, so the reference adds nothing to the git history. Follow the repository's `CLAUDE.md` if it asks otherwise. Never commit to `<MAIN_BRANCH>` and never merge into it; rebasing your own branch onto it is allowed.
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
