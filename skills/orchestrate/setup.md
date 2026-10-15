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

Check `jq -e '.enabledPlugins["td-orchestrator@td-orchestrator"] == true' <MAIN_REPO>/.claude/settings.json`. If it fails, ask whether to enable the plugin for this repository, then run in `<MAIN_REPO>`:

```bash
claude plugin install td-orchestrator@td-orchestrator --scope project
```

If that command fails (for example because the marketplace is not added on this machine), merge the entry into `.claude/settings.json` yourself with `jq` (create `{}` first if the file is missing) and tell the user to run `claude plugin marketplace add <path to the plugin repo, or madic-creates/claude-orchestrator>`. Declined → stop: worker agents would not find their role skills.

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
git -C <MAIN_REPO> commit -m "chore: td-orchestrator config"
```
(add `.gitignore` and `.claude/settings.json` to the `git add` if they changed). On no: tell the user the run needs a clean main working tree and stop.

## 8. Done

With `--setup`: say the config is ready and stop. Otherwise return to the orchestrator's preconditions.
