---
description: Resume an /ohaze:ship workflow after Codex finishes. Runs review loop (max 3 retries) then ohaze's 5-option finishing menu (with "继续修改" branch).
argument-hint: "[--more] (optional: continue past the 3-retry limit)"
allowed-tools: Bash, Read, Write, Edit, Skill, Agent, AskUserQuestion
---

Continue the workflow started by `/ohaze:ship` after the background Codex run completes.

`$ARGUMENTS`

## Pre-flight

1. Read `.ohaze/current-ship.json` from the project root. If missing, tell user to run `/ohaze:ship` first.

2. Verify Codex is actually done. Read `codex_pid_file` and `codex_log_file` from the handoff:

   ```bash
   if [[ -f "$codex_pid_file" ]] && kill -0 "$(cat "$codex_pid_file")" 2>/dev/null; then
     echo "Codex 还在跑 (pid=$(cat "$codex_pid_file")). 用 tail -f $codex_log_file 看进度, 跑完后再回 /ohaze:ship-review."
     exit 0
   fi
   ```

   If the pid file is missing or the process is no longer alive, Codex finished (or crashed). Check the tail of `<codex_log_file>` for the end-of-run report block. If the log shows an unhandled error, surface it and stop — do NOT proceed with review on incomplete work.

   Back-compat: older handoffs may have `codex_run_id` only (companion-issued task id). In that case fall back to `/codex:status <run_id>` — but those are legacy and shouldn't appear in new ships.

3. If `--more` flag is present in `$ARGUMENTS`, allow exceeding the 3-retry cap; otherwise honor it.

## Vault Context (pre-review read)

Before invoking the reviewer, silently load vault context to give the review better grounding. Do NOT summarize to the user.

```bash
PROJECT_NAME=$(basename $(git rev-parse --show-toplevel))
VAULT="$HOME/Brain"
PROJ_DIR="${VAULT}/20_Projects/${PROJECT_NAME}"
```

4. Read vault context (best-effort — skip silently if files don't exist):
   - `${PROJ_DIR}/decisions/` — the 3 most recent decision files: understand what patterns or standards have already been decided for this project, so the reviewer can flag violations
   - `${VAULT}/99_System/Logs/decision-patterns.md` — user's implicit preferences around code quality, commit style, and architecture

   Pass this context to the reviewer subagent (include it in the review prompt under a `<vault_context>` block). The reviewer should use it to:
   - Flag if the implementation contradicts a past project decision
   - Apply the user's coding preferences as additional quality criteria

## Phase 5-6 — Review + Retry Loop (ohaze)

4. Invoke `ohaze:codex-executor` skill in **review mode**:
   - Pass: `plan_path`, `base_ref`, `worktree_path` from the handoff file
   - The skill runs Phase 5.0 first (auto-commit any pending changes Codex left behind)
   - Then Phase 5.1 (compute diff) and Phase 5.2 (dispatch reviewer subagent)
   - On FAIL, the skill loops: format issues → `codex exec resume --last` → re-review (up to 3 times)
   - Update `.ohaze/current-ship.json` `retries` counter after each iteration

5. If after the loop the verdict is still FAIL and `--more` was not passed, the executor stops and presents 3 options to the user:
   - Continue retrying (`/ohaze:ship-review --more`)
   - Manually intervene (user fixes issues themselves) → tell user worktree path, exit
   - Accept current state and proceed to finishing → continue to Phase 7

   Wait for user choice.

## Phase 6.5 — Surface ADVERSARIAL findings (if any)

Before the finishing menu, check whether the latest review's `issues` array (in the verdict you just received from codex-executor, or read back from `.ohaze/review-verdict.json`) contains any lines prefixed `ADVERSARIAL:`.

If yes, print them verbatim to the user **without commentary**:

```
⚠️ Reviewer 提出的对抗式发现（不阻塞 ship, 设计层判断, 你来决定要不要处理）：

  - ADVERSARIAL: <design risk> — <file:line>
  - ADVERSARIAL: <design risk> — <file:line>
```

Then proceed to Phase 7. Do not auto-loop into modify — the user will pick option 5 if they want to act on these.

If no ADVERSARIAL findings, skip this section silently.

## Phase 7 — Finishing Menu (ohaze owns this — DO NOT invoke superpowers:finishing-a-development-branch directly)

Once review verdict is PASS (or user accepted current state in step 5), detect remote availability first:

```bash
HAS_REMOTE=$(git -C <main_repo_path> remote 2>/dev/null | head -1)
```

Then present this 6-option menu. If `$HAS_REMOTE` is empty, prepend this note:

```
⚠️ 当前仓库无 git remote，选项 2/3 会因 push 失败而无法完成 — 纯本地仓请选 1（本地合并）。
```

Menu:

```
实现完成, 测试 [N/N] 通过. 请选择:
1. 合并回主分支 (本地 git merge --ff-only, 适合纯本地仓 / 不开 PR)
2. 推送到远端 (git push, 不开 PR)
3. 创建 Pull Request (推 + gh pr create)
4. 保持现状 (稍后 /ohaze:ship-finish 处理)
5. 丢弃此次工作
6. 继续修改 (小改动)
```

Use `AskUserQuestion` with these 6 options. Do NOT default the recommendation — let the user pick deliberately.

### Option 1: 合并回主分支（本地）

For repos without a remote, or when you just want the worktree's commits to land on `<base_ref>` without opening a PR.

```bash
# 1. 找到主仓 checkout 位置（git worktree list 第一条 = 主 checkout）
main_repo_path=$(git -C <worktree_path> worktree list --porcelain | awk '/^worktree /{print $2; exit}')

# 2. 主仓切到 base_ref
git -C "$main_repo_path" checkout <base_ref>

# 3. fast-forward merge
git -C "$main_repo_path" merge <branch> --ff-only
```

If `--ff-only` fails (因为 `<base_ref>` 在 ship 期间前进了，不再是 worktree 的祖先), surface the error and ask:
> "Fast-forward 失败 — `<base_ref>` 在 ship 期间有新提交。选项:
> 1. 创建 merge commit (`git merge --no-ff <branch>`)
> 2. 退出, 我自己处理 (rebase 或 cherry-pick)"

If user picks 1: `git merge <branch> --no-ff -m "merge: <feature> via ohaze"`. If user picks 2: stop, leave handoff for `/ohaze:ship-finish` to resume.

On successful merge, write ship-result first (vault hook reads it before handoff is deleted), then cleanup in this order:

```bash
# 1. 写 ship-result.json —— vault hook 立刻读取并跑 E5 finish
cat > <main_repo_path>/.ohaze/ship-result.json << 'EOF'
{"action":"merge","branch":"<branch>","target":"<base_ref>"}
EOF

# 2. 删 handoff —— pre-bash 兜底触发 E5（如果 #1 失败 / sync_state 异常）
rm <main_repo_path>/.ohaze/current-ship.json
```

Then ask: "清理 worktree 和分支吗?" (1=clean / 2=keep). On clean (推荐, 因为分支已合并到 base):
```bash
git -C "$main_repo_path" worktree remove <worktree_path>
git -C "$main_repo_path" branch -D <branch>   # 已合并, 安全删
```

**重要**: handoff 必须在 worktree remove 之前删除，否则 vault-adapter 的 commits 收集和 CLAUDE.md 打勾会拿不到 worktree。`<ohaze_dir>` 在 finishing 流程里始终指 `<main_repo_path>/.ohaze/`，不是 worktree 内的。

### Option 2: 推送到远端

```bash
git -C <worktree_path> push -u origin <branch>
```

If push fails (no remote, auth, etc.): surface the error verbatim, do NOT retry, ask user how to proceed.

After successful push, write ship-result and delete handoff *before* any worktree cleanup (vault-adapter needs both to be in place):
```bash
# 1. ship-result.json — triggers vault E5 immediately
cat > <main_repo_path>/.ohaze/ship-result.json << 'EOF'
{"action":"push","branch":"<branch>","remote":"origin"}
EOF

# 2. delete handoff (pre-bash fallback for E5)
rm <main_repo_path>/.ohaze/current-ship.json
```

Then ask: "继续保留 worktree 还是清理?" (1=keep, 2=clean). On clean: `git worktree remove <worktree_path>` + `git branch -D <branch>` from the main checkout.

### Option 3: 创建 Pull Request

```bash
git -C <worktree_path> push -u origin <branch>
gh pr create --base <base_ref> --head <branch> --title "<derived from spec or commit>" --body "<see template below>"
```

PR body template:
```
Generated via /ohaze:ship.

**Spec:** <spec_path>
**Plan:** <plan_path>
**Codex retries:** <N>
**Reviewer verdict:** PASS

Auto-generated by ohaze.
```

After PR is created, write ship-result and delete handoff *before* any worktree cleanup:
```bash
# 1. ship-result.json — triggers vault E5 immediately
cat > <main_repo_path>/.ohaze/ship-result.json << 'EOF'
{"action":"pr","branch":"<branch>","remote":"origin","pr_url":"<pr_url>","pr_number":<pr_number>}
EOF

# 2. delete handoff (pre-bash fallback for E5)
rm <main_repo_path>/.ohaze/current-ship.json
```

Print the PR URL. Then same "keep or clean worktree" question.

### Option 4: 保持现状

Do nothing destructive. Update `.ohaze/current-ship.json` to set `state: "kept"` (so `/ohaze:status` and `/ohaze:ship-finish` know how to resume). Print:
> "Worktree 保留在 `<worktree_path>`. 想继续时跑 `/ohaze:ship-finish` 或 `cd <worktree_path>` 手改后再跑."

Stop.

### Option 5: 丢弃

Confirm with the user once (this is destructive):
> "这会删除分支 `<branch>` 和 worktree `<worktree_path>`, 所有提交丢失. 确认?"

On confirm, write ship-result and delete handoff *before* removing the worktree (vault-adapter needs the worktree present to collect commits for the decisions doc):
```bash
# 1. ship-result.json — triggers vault E5 immediately
cat > <main_repo_path>/.ohaze/ship-result.json << 'EOF'
{"action":"discard","branch":"<branch>"}
EOF

# 2. delete handoff (pre-bash fallback for E5)
rm <main_repo_path>/.ohaze/current-ship.json

# 3. tear down worktree + branch
git -C <main_repo_path> worktree remove --force <worktree_path>
git -C <main_repo_path> branch -D <branch>
```

### Option 6: 继续修改 (小改动)

Enter the modify sub-flow (see next section). After the modify sub-flow returns, **loop back to this 6-option menu** (the user might want to modify again, or now finish).

## Modify Sub-Flow (Option 6)

When user picks 6:

1. Ask user to describe the change:
   > "请描述改动 (可以是改名/加注释/修边界 case 之类的小事):"

2. Capture the description as `change_description`.

3. Ask who handles it:
   ```
   1. Codex 续跑 (适合需要遵循 plan 风格、跨文件改动)
   2. Claude 主线程直接改 (适合改名、加注释、修单行 bug)
   3. 我自己改 (退出, 我去 .worktrees 改完跑 /ohaze:ship-finish 回来)
   ```

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

Write the prompt to `<worktree>/.ohaze/codex-modify.xml` via the Write tool, then resume the same Codex thread (NOT a fresh one):

```bash
codex exec resume --last \
  --sandbox danger-full-access \
  --cd <worktree_path> \
  < <worktree>/.ohaze/codex-modify.xml \
  2>&1 | tee -a <codex_log_file>
```

Foreground (no `&`) — user is engaged, blocking is fine.

If `codex exec resume --last` cannot find the prior thread (rare; happens if codex was restarted between sessions), fall back to a fresh `codex exec` with the modify prompt embedded inside a `<task>` block referencing the original goal.

After Codex returns, run codex-executor's Phase 5.0 again (auto-commit pending changes with a derived message based on `change_description`).

Then ask:
> "改动已落地. 是否再跑一次 review 确认?"
> "1. 是 (推荐)"
> "2. 否, 直接回 finishing 菜单"

If 1: re-dispatch reviewer subagent (no retry counter increment, this is a user-initiated tweak).
Loop back to Phase 7 finishing menu.

### 5b — Claude 主线程直接改

Use `Read` to inspect relevant files, then `Edit` (or `Write` for new files) to apply the change. Run the project test command:
```bash
cd <worktree_path> && <project_test_command>
```

If tests pass: commit with message like `refactor: <one-line description>` or whatever fits.

If tests fail: report the failure, ask user "我修一下还是退回让你处理?" (1=fix, 2=hand back).

After commit, same review-or-skip prompt as 5a, then loop back to finishing menu.

### 5c — 我自己改 (self-edit)

Update `.ohaze/current-ship.json` set `state: "self-edit-pending"`. Tell user:
> "退出当前 session. 去 `<worktree_path>` 改完代码后, 跑 `/ohaze:ship-finish` 回来继续."

Stop.

## Cleanup (after terminal options 1/2/3/5)

The terminal options (1 merge / 2 push / 3 PR / 5 discard) each write `ship-result.json` and `rm` the handoff *before* tearing down the worktree — that ordering matters because vault-adapter needs both files present (and the worktree intact) to finalize the decisions doc and tick CLAUDE.md.

For option 4 (keep) and 6c (self-edit), the handoff stays so `/ohaze:ship-finish` can resume.

## Final Summary (after terminal options 1/2/3/5)

Print:
- Spec path
- Plan path
- Codex retries used (review-loop iterations only, modify-loop iterations excluded for clarity)
- Modify-loop iterations (separate counter)
- Final disposition (pushed / PR-opened / discarded)

## Failure Modes

- `<codex_log_file>` tail shows Codex genuinely failed (not just incomplete): surface the error verbatim; do NOT enter review loop. Suggest the user run `codex exec resume --last --sandbox danger-full-access --cd <worktree>` manually with a corrective prompt.
- Reviewer subagent returns malformed verdict twice: fall back to asking user to read `git diff` and judge.
- Handoff file references a worktree path that no longer exists: stop, surface, ask user.
- Push fails (no remote, auth missing): surface error, hand back to menu (don't auto-retry).

## Notes

- The 5-option menu is owned by ohaze; we do NOT invoke `superpowers:finishing-a-development-branch`. This avoids menu duplication and keeps modify-flow inside the same orchestration.
- Modify loop iterations don't count against the 3-retry review cap — they're user-initiated, not reviewer-driven.
- After option 5a (Codex) or 5b (Claude), we always return to the menu. Only options 1/2/4 are terminal.
