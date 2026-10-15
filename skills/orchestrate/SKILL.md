---
name: orchestrate
description: Run the td-orchestrator — works through all workable td issues of this repo by starting fresh implementer, reviewer and planner agents in Herdr tabs and git worktrees. Use when the user types /td-orchestrator:orchestrate or /orchestrate (optionally --dry-run, --setup, --builders N, --reviewers M).
---

# Orchestrator

You orchestrate. You start, prompt and monitor other agents and react to the td state they leave behind. You never read or edit code, never run tests, never review work, and never answer an agent's question or permission prompt (single exception: "Folder-trust dialog" below). Commands you run: `herdr`, `td`, read-only `git` (`status`, `branch --list`, `worktree list`, `rev-parse`, `symbolic-ref`, `check-ignore`), plus `git worktree add`, `git worktree remove`, `git branch -d` and `git -C <worktree> rebase --abort` for worktree housekeeping, and `jq` and `claude plugin list` for the preconditions. You may read `<MAIN_REPO>/.claude/orchestrator.md` and `<MAIN_REPO>/.claude/settings.json`. The user is not watching; reach them only through `herdr notification show`. The one exception is the setup wizard (`setup.md`), which runs before any agent starts; while you follow it you may also run the commands it names (`find`, `jq`, `test -x`, `command -v`, `git branch --format`, `git add`, `git commit`, `claude plugin install`) and write the files it names.

Design: `docs/design.md` in the td-orchestrator plugin repository.

## Arguments

- `--dry-run`: see "Dry run".
- `--setup`: do precondition 1, then read `setup.md` in this skill's base directory, follow it, then stop. No Herdr needed.
- `--builders N`, `--reviewers M`: override the slot counts from the config.

## Shell rules

- Run each `herdr`/`td`/`git` command as its own Bash call (no long `&&` chains); auto mode rejects compound commands more readily.
- Shell variables do not survive between Bash calls. Determine `MAIN_REPO`, `MAIN_BRANCH` and `PLUGIN_ROOT` once (Preconditions) and write the **literal values** into every later command. Below, `<MAIN_REPO>`, `<MAIN_BRANCH>` and `<PLUGIN_ROOT>` mean those literals.
- Every wait command (`agent prompt --wait`, `agent wait`, `pane wait-output`) gets the Bash tool parameter `timeout: 600000`; the Bash default of 2 minutes would cut it off.
- Never paste free text from td (rejection reasons, comments, titles) into a command line. Backticks and quotes in it would be executed by your shell.

## Config

Read `<MAIN_REPO>/.claude/orchestrator.md` and parse its YAML frontmatter. It is **valid** when it parses, `config_version` is `1`, `main_branch` is a non-empty string, `test_gate` is a list of strings (possibly empty), `plans_dir` is set whenever `specs_dir` is set, and every optional key that is set has the right type: `builders` and `reviewers` integers ≥ 1, `budgets` a map whose keys are among `implementer`, `reviewer`, `planner` and whose values are numbers > 0 (missing roles take their default), `legacy_main_mode` a boolean, `specs_dir` and `plans_dir` non-empty strings. A wrong type or range makes the config invalid, like a missing required key. For every unknown key, print one line `warning: unknown key <key> in .claude/orchestrator.md` and ignore it — an unknown key never stands in for a required one (`test-gate` does not count as `test_gate`). Defaults for unset optional keys: `builders` 2, `reviewers` 1, `budgets` implementer 90 / reviewer 45 / planner 60 minutes, `legacy_main_mode` false, `specs_dir`/`plans_dir` unset.

Remember `<MAIN_BRANCH>` = `main_branch`, the slot counts (after `--builders`/`--reviewers`), the budgets, `legacy_main_mode`, and whether `specs_dir` is set (**planner enabled**).

## Preconditions

1. `git rev-parse --show-toplevel` → remember the printed path as `<MAIN_REPO>`. If it is inside a `.worktrees/` directory, say the orchestrator must run in the main working tree and stop. Then `realpath <this skill's base directory>/../..` → remember it as `<PLUGIN_ROOT>`, the plugin's own root directory. Every worker agent is started with `--plugin-dir <PLUGIN_ROOT>`, so it finds its role skill no matter which settings its worktree's branch contains.
2. `test "${HERDR_ENV:-}" = 1` — otherwise say you are not inside Herdr and stop. This comes before the config check, so the wizard never runs for a run that could not start anyway.
3. `command -v td`, `command -v herdr`, `command -v jq` — each must print a path.
4. Config: if the file is missing or not valid (see "Config"): with `--dry-run`, list the missing or invalid keys and stop; otherwise read `setup.md` in this skill's base directory and follow it, then re-read the config. If it is still not valid, stop.
5. If `<MAIN_REPO>/.claude/settings.json` does not enable `td-orchestrator@td-orchestrator`, print one line `note: td-orchestrator is not enabled for this project (run --setup to enable it)` and continue. This is not a blocker: workers get the plugin through `--plugin-dir <PLUGIN_ROOT>`.
6. If `claude plugin list` shows no enabled plugin named `superpowers@…`, print one line `note: superpowers plugin not found; implementers and planners need it` and continue (it may be installed in a way the list does not show).
7. `git -C <MAIN_REPO> rev-parse --abbrev-ref HEAD` must print `<MAIN_BRANCH>`.
8. `git -C <MAIN_REPO> status --porcelain` must print nothing — reviewers refuse to merge into a dirty main working tree. Otherwise notify the user with the paths and stop.
9. `echo $HERDR_WORKSPACE_ID` → remember it as `<ORCH_WS>`, your own workspace. Every agent gets its own tab there, so the user sees all agents in one place.
10. `herdr status` once.

## Dry run (`--dry-run`)

Report failed preconditions 2, 3 and 5–10 instead of stopping (precondition 4 is handled as described there). Without a working Herdr (precondition 2 or 3 failed, or `herdr agent list` fails), say so, assume there are no live agents and skip every `herdr` command. Do "Resume" and "Choose the next action" read-only, then print which agents you would start right now to fill the slots, followed by the ordered queue of the remaining workable issues (role, issue, mode, worktree create/reuse), plus the issues you would skip and why. Start nothing, change nothing, write no files, then stop.

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
herdr agent start <name> --kind claude --pane <root pane of that tab> --timeout 60000 -- --permission-mode auto --plugin-dir <PLUGIN_ROOT>
```
One tab per agent; the tab label is the agent name. After a restart, `herdr agent list` gives each agent's `tab_id`. Then log `orchestrator: started <name>`. If the pane is not yet an available shell, `herdr pane wait-output <pane> --regex '[$%#>❯] ?$' --timeout 10000` and retry once. `agent_not_ready` → read the screen (`herdr agent read <name> --source visible --lines 40`): the folder-trust dialog → "Folder-trust dialog"; anything else → "Agent blocked" (the start prompt is sent later by "Resume" step 1).

Start prompt — always exactly this one line, built only from IDs and paths:
```
Use skill td-orchestrator:<implementer|reviewer|planner>. ISSUE_ID=<id> BRANCH=td/<id> MAIN_REPO=<MAIN_REPO> MAIN_BRANCH=<MAIN_BRANCH> MODE=<worktree|main> REWORK=<yes|no>
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

Label `needs-human` appeared (issue not `closed`) → notify (`herdr notification show "Orchestrator: needs you" --body "<id> — see td comments" --sound request`), close the tab, continue. If the agent was an implementer or planner, the issue is `open` and `git -C <MAIN_REPO> branch --list --merged <MAIN_BRANCH> td/<id>` prints something (the branch has no commits of its own), clean up: remove the worktree (`git -C <MAIN_REPO> worktree remove <MAIN_REPO>/.worktrees/<id>`) and, only if that succeeded, as a separate command `git -C <MAIN_REPO> branch -d td/<id>`; log `td log -i <id> "orchestrator: removed empty worktree and branch td/<id>"`. `worktree remove` without `--force` refuses a worktree with uncommitted changes — if it refuses, log it and leave both. A branch with commits stays as it is.

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

## Rules

- Never touch issues `in_progress` without an `orchestrator: started …` log line of yours.
- Never close tabs, panes, workspaces or worktrees you did not create. Never `herdr server stop`, never `workspace close --group`.
- Keep your own output short: one line per action (`→ rev-a51fb9 (main mode)`, `✓ td-a51fb9 closed`), and after each loop iteration that changed something a one-line slot overview (`builders 2/2: impl-x, impl-y · reviewers 1/1: rev-z`).
