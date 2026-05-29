---
name: finishing
description: Owns ohaze workflow Phase 7: finishing menu, ordered finish-chain execution, document finish, and modify sub-flow. Invoked by ship-review.md and ship-finish.md.
---

# Finishing

Own Phase 7 of `/ohaze:ship`: detect project type, present the finishing menu, execute the selected finish chain, run document finish before commits, and handle the modify sub-flow. `/ohaze:ship-review` and `/ohaze:ship-finish` invoke `ohaze:finishing`; they do not duplicate this menu.

## Inputs

Read these from caller context and `.ohaze/current-ship.json` inside the worktree:

- `worktree_path`
- `base_ref`
- `branch`
- `plan_path`
- `spec_path`
- `retries`
- `linked_todo`
- `codex_session_id`
- `review_verdict_path`: `<worktree_path>/.ohaze/review-verdict.json`

If vault context reads fail, continue without blocking the finishing flow.

## Detect Project Type

Detect from the **main repo**, not the linked worktree:

```bash
main_repo_path=$(git -C <worktree_path> worktree list --porcelain | awk '/^worktree /{print $2; exit}')
remote_name=$(git -C "$main_repo_path" remote 2>/dev/null | head -1)
```

- No remote output means `project_type = "local"`.
- Any remote output means `project_type = "remote"`.

Write the detected `project_type` field back into `.ohaze/current-ship.json` with the Write tool or a structured JSON edit that preserves the rest of the handoff.

## Finish Preferences

Read `~/.ohaze/finish-prefs.json` best-effort. Use the entry matching `project_type` as the recommended chain.

If `~/.ohaze/finish-prefs.json` does not exist, the matching entry is absent, or the JSON is damaged, fall back to the built-in defaults. Damaged JSON is non-blocking; tell the user one short warning and continue.

Built-in default chains:

```json
{
  "local": ["doc-finish", "commit", "merge", "remove-worktree"],
  "remote": ["doc-finish", "commit", "merge", "push", "remove-worktree"]
}
```

When the user chooses menu option 1 or option 5, write the final chain back to `~/.ohaze/finish-prefs.json` under the detected `project_type`. Preference read/write failures are best-effort and must not block finishing.

## Menu

Before asking, print:

- Detected `project_type`: `local` or `remote`
- Full recommended chain, in order, so the user can see exactly what option 1 will do

Use `AskUserQuestion` with exactly these five choices:

1. 执行推荐收尾（一键到底）
2. 继续修改
3. 丢弃此次工作
4. 先不处理（worktree 留着，稍后 `/ohaze:ship-finish`）
5. 自定义收尾方案

Option 4 does nothing destructive. Update `.ohaze/current-ship.json` so `state = "kept"`, then tell the user the worktree path and that `/ohaze:ship-finish` resumes the workflow.

Option 5 is not free text. Present the supported steps as building blocks and let the user choose an ordered chain from:

`doc-finish` / `commit` / `merge` / `push` / `pr` / `remove-worktree` / `keep-worktree`

Then execute that chain with the same step contract as the recommended chain.

## Chain Execution Contract

Execute a finish chain one step at a time, in order. Valid steps are:

- `doc-finish`
- `commit`
- `merge`
- `push`
- `pr`
- `remove-worktree`
- `keep-worktree`

After each step, check its success criterion: command exit code and, where relevant, expected git state or expected output. **任一步失败立即中止**: do not execute later steps, report the failed step name plus the original error text, preserve `.ohaze/current-ship.json` in a recoverable state, and return to the menu.

Hard constraint: **merge 成功 push 失败禁止删 worktree**. If `merge` succeeds but `push` fails, do not execute `remove-worktree`; keep the worktree and branch so the user can retry or recover the push.

## Step: doc-finish

`doc-finish` is the document finishing step and it must run before `commit`. It combines progress-contract updates and drift repair into one preview patch before any docs commit is created.

It handles both classes of document change:

1. Progress machine-readable contract:
   - Append an appropriate `[Unreleased]` or version entry to `CHANGELOG.md`.
   - Bump the manifest `version`.
   - Tick the exact `linked_todo` line in the source project `CLAUDE.md` "当前目标" section from `- [ ]` to `- [x]`.
2. Drift repair:
   - Read `review_verdict_path`.
   - Extract `doc_drift`, a string array from `review-verdict.json`.
   - Generate a synchronization patch for descriptive sections in the target project `CLAUDE.md`.

Merge both classes into one patch preview. Present the preview to the user and offer:

- Accept all
- Skip all
- Select individual hunks/items

Apply only the accepted parts. If there are no document changes, skip this step silently.

Document changes are committed by the chain's `commit` step as a separate `docs:` commit. Code changes should already have been committed before review by `ohaze:codex-executor` Phase 5.0.

## Step: commit

Commit pending accepted document changes before terminal actions.

- If there are accepted `doc-finish` changes, create a separate `docs:` commit.
- If the worktree is clean, this step succeeds without creating a commit.
- Do not bypass hooks.

## Step: merge

Merge the work branch into `<base_ref>` in the main repo.

Before merging, pre-compute commits from the branch so vault-adapter can record them after a fast-forward:

```bash
PRE_MERGE_COMMITS=$(git -C "$main_repo_path" log "<base_ref>..<branch>" --oneline 2>/dev/null)
PRE_MERGE_COUNT=$(printf '%s' "$PRE_MERGE_COMMITS" | grep -c . || echo 0)
git -C "$main_repo_path" checkout <base_ref>
git -C "$main_repo_path" merge <branch> --ff-only
```

Why this order matters: after `git merge --ff-only`, `<base_ref>..HEAD` can be empty in the worktree because both refs point at the same commit. `ship-result.json` must embed the pre-computed commits so the vault hook does not record "Commits 数量 = 0".

If `--ff-only` fails because `<base_ref>` advanced during the ship, surface the error and ask:

> Fast-forward 失败 — `<base_ref>` 在 ship 期间有新提交。选项:
> 1. 创建 merge commit (`git merge --no-ff <branch>`)
> 2. 退出, 我自己处理 (rebase 或 cherry-pick)

If the user picks 1, run `git merge <branch> --no-ff -m "merge: <feature> via ohaze"`. If the user picks 2, stop and keep the handoff for `/ohaze:ship-finish`.

## Step: push

Push the branch:

```bash
git -C <worktree_path> push -u origin <branch>
```

If push fails because of no remote, auth, rejected update, or any other reason, surface the error verbatim, stop the chain, keep `.ohaze/current-ship.json`, keep the branch and worktree, and return to the menu. If this follows a successful `merge`, the "merge 成功 push 失败禁止删 worktree" rule applies.

## Step: pr

Push the branch if needed, then create a PR:

```bash
git -C <worktree_path> push -u origin <branch>
gh pr create --base <base_ref> --head <branch> --title "<derived from spec or commit>" --body "<see template>"
```

PR body:

```markdown
Generated via /ohaze:ship.

**Spec:** <spec_path>
**Plan:** <plan_path>
**Codex retries:** <N>
**Reviewer verdict:** PASS

Auto-generated by ohaze.
```

If push or `gh pr create` fails, surface the exact error, stop the chain, preserve the handoff and worktree, and return to the menu.

## Terminal Result Files And Cleanup Order

For every terminal action (`merge`, `push`, `pr`, `discard`) finish in this strict A4 order:

1. Use the **Write tool** (not Bash heredoc) to write `<worktree_path>/.ohaze/ship-result.json`.
2. Run `rm <worktree_path>/.ohaze/current-ship.json` by Bash as the handoff removal / pre-bash fallback.
3. Delete or remove the worktree only after steps 1 and 2. The worktree deletion must be last.

The vault hook needs the worktree and handoff alive when `ship-result.json` is written. Do not use `cat > file <<EOF`; the PostToolUse hook only fires for the Write tool.

Schemas are unchanged from the old Phase 7:

Merge:

```json
{
  "action": "merge",
  "branch": "<branch>",
  "target": "<base_ref>",
  "commits": "<PRE_MERGE_COMMITS string verbatim, newlines preserved>",
  "commit_count": <PRE_MERGE_COUNT>
}
```

Push:

```json
{"action":"push","branch":"<branch>","remote":"origin"}
```

PR:

```json
{"action":"pr","branch":"<branch>","remote":"origin","pr_url":"<pr_url>","pr_number":<pr_number>}
```

Discard:

```json
{"action":"discard","branch":"<branch>"}
```

`remove-worktree` removes the linked worktree and branch only after the terminal result order above has completed.

**Before removing, `cd "$main_repo_path"` first.** The session has almost certainly `cd`'d into the worktree (`ship.md` Phase 2 and `ship-finish.md` both do). Removing a worktree while the session's shell cwd is still inside it leaves the cwd pointing at a deleted directory; the next hook of any kind (`UserPromptSubmit` / `Stop` / `SessionEnd`) then gets spawned from that dead cwd and Claude Code surfaces a hook failure (`posix_spawn '/bin/sh' ENOENT`, or a `getcwd: cannot access parent directories` error). The spawn fails *before* the hook script runs, so no amount of hook-side guarding can recover it — the only fix is to never leave the session cwd inside a to-be-deleted worktree.

```bash
cd "$main_repo_path"
git worktree remove <worktree_path>
git branch -D <branch>
```

For discard, confirm with the user first, then (still after `cd "$main_repo_path"`) use `git worktree remove --force <worktree_path>`.

`keep-worktree` leaves the worktree in place and reports its path.

## Modify Sub-Flow

Menu option 2 enters the existing modify flow. After any modify branch completes, loop back to this five-option finishing menu.

Ask the user for `change_description`, then ask who handles it:

1. Codex 续跑 (适合需要遵循 plan 风格、跨文件改动)
2. Claude 主线程直接改 (适合改名、加注释、修单行 bug)
3. 我自己改 (退出, 我去 .worktrees 改完跑 /ohaze:ship-finish 回来)

### 5a — Codex 续跑

Build a delta prompt:

```xml
<task>
The implementation in this worktree was reviewed and approved, but the user wants this small adjustment before finishing:

{change_description}

Apply the change. Stay narrow — only this adjustment, do not refactor anything else.
</task>

<commit_handling>
Sandbox blocks .git/. Do not commit. Just write the changes; orchestrator will commit with a `refactor:` or `fix:` style message.
</commit_handling>

<verification_loop>
After applying, run `{project_test_command}`. All tests must pass.
</verification_loop>

<action_safety>
- Only the requested adjustment, nothing else.
- No new dependencies.
- Don't touch unrelated files.
</action_safety>
```

Write the prompt to `<worktree_path>/.ohaze/codex-modify.xml` with the Write tool. Then resume the same Codex thread:

```bash
codex exec resume <codex_session_id> \
  --sandbox danger-full-access \
  --cd <worktree_path> \
  < <worktree_path>/.ohaze/codex-modify.xml \
  2>&1 | tee -a <codex_log_file>
```

If `codex_session_id` is missing or null, degrade to `codex exec resume --last` only after printing a prominent warning to the user and appending it to the Codex log: `WARNING: session id 缺失，并行 ship 下 resume 可能不精确`. This fallback is not silent.

Foreground execution is fine here because the user is engaged.

After Codex returns, run `ohaze:codex-executor` Phase 5.0 again to commit pending changes with a message derived from `change_description`. Then ask whether to re-run review. If yes, re-dispatch review without incrementing the retry counter because this is user-initiated modify, not reviewer retry. Loop back to the finishing menu.

### 5b — Claude 主线程直接改

Inspect relevant files with Read, apply the requested narrow edit with Edit or Write, then run the project test command if one exists:

```bash
cd <worktree_path> && <project_test_command>
```

If checks pass, commit with a suitable `refactor:` or `fix:` style message. If checks fail, report the failure and ask whether to fix or hand back. Then ask whether to re-run review and loop back to the menu.

### 5c — 我自己改 (self-edit)

Update `.ohaze/current-ship.json` with `state = "self-edit-pending"`. Tell the user:

> 退出当前 session. 去 `<worktree_path>` 改完代码后, 跑 `/ohaze:ship-finish` 回来继续.

Stop.

## Final Summary

After terminal actions, print:

- Spec path
- Plan path
- Codex retries used
- Modify-loop iterations, if any
- Final disposition

## Failure Modes

- Preference read/write failure: warn briefly if useful, then continue with defaults.
- Damaged `~/.ohaze/finish-prefs.json`: warn once and use built-in defaults.
- Vault context read failure: skip silently or note only if it affects the user-visible decision.
- Handoff malformed or missing required fields: stop and report the broken field.
- Worktree missing or detached: stop and ask for manual intervention.
- Push/PR failure: surface the exact error and return to the menu.
- Merge `--ff-only` failure: use the merge-commit vs exit prompt above.
