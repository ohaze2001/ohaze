---
description: Re-enter finishing for an /ohaze:ship that was paused (option 3 "保持现状") or self-edited (option 5c). Optionally re-runs review, then shows the finishing menu.
argument-hint: "[--skip-review] (skip the optional re-review)"
allowed-tools: Bash, Read, Write, Edit, Skill, Agent, AskUserQuestion
---

Resume finishing for a previously paused ship.

`$ARGUMENTS`

## Pre-flight

1. Locate the handoff file. Search in priority:
   - `$(git rev-parse --show-toplevel)/.ohaze/current-ship.json` — preferred
   - If not found, fall back to walking up from `pwd` looking for `.ohaze/current-ship.json`

2. If no handoff file exists:
   - Run `/ohaze:status` to see if any worktree has one
   - Otherwise tell user: "没找到 ohaze handoff. 这个 ship 可能已经 finish 过了, 或者你需要先跑 /ohaze:ship 启动一个."
   - Stop.

3. Parse the handoff. Capture: `plan_path`, `base_ref`, `worktree_path`, `spec_path`, `state`, `retries`.

4. Verify the worktree still exists at `worktree_path`. If gone:
   - Tell user "Worktree `<path>` 已删除. handoff 是 stale, 我帮你清掉."
   - `rm <handoff>`
   - Stop.

5. `cd <worktree_path>` for the rest of this command (so commits land in the right place).

## Vault Context (pre-finish read)

Silently load vault context before proceeding. Do NOT summarize to the user.

```bash
PROJECT_NAME=$(basename $(git rev-parse --show-toplevel 2>/dev/null || echo ""))
VAULT="$HOME/Brain"
```

6. Read (best-effort — skip silently if missing):
   - `${VAULT}/20_Projects/${PROJECT_NAME}/discussions/<feature>.md` — the running log of this exact ship, to understand what decisions and pauses happened before this finish
   - `${VAULT}/20_Projects/${PROJECT_NAME}/progress.md` — recent completions, so you can give the user a meaningful status update ("this is your 3rd feature shipped this week")

   Use this context only to inform the finishing conversation — e.g., mention if there were multiple review retries, or if the user has been on a shipping streak.

## Step 1 — Detect uncommitted changes (likely from option 5c self-edit)

```bash
git status --short
```

If output is non-empty:

> "检测到 worktree 有未提交改动:"
> ```
> <git status --short output>
> ```
> "你刚才手动改的吗? 1. 是, 帮我 commit  /  2. 不是, 让我先看一下"

If user picks 1:
- Show the diff:
  ```bash
  git diff
  git diff --cached
  ```
- Ask for commit message: "commit 信息?" (suggest a default like `refactor: manual adjustments after review`)
- Run `git add -A && git commit -m "<message>"`

If user picks 2: stop, let user inspect / edit / commit themselves, tell them to re-run `/ohaze:ship-finish` when ready.

## Step 2 — Optional re-review

If `--skip-review` flag is present, skip this step.

Otherwise ask:
> "要先跑一次 review 再 finish 吗? (推荐, 因为可能有手改未审过)"
> "1. 是, 跑 review"
> "2. 否, 直接进 finishing 菜单"

If 1:
- Invoke `ohaze:codex-executor` skill in **review mode** (Phase 5.1 + 5.2 only — skip 5.0 because Step 1 already committed any pending work).
- If FAIL: enter the review-fix loop just like `/ohaze:ship-review` does (max 3 retries, increment `.ohaze/current-ship.json` retries).
- If PASS: continue to Step 3.

If 2: continue to Step 3 directly.

## Step 2.5 — Surface ADVERSARIAL findings (if any)

If Step 2 ran a re-review, or if the prior verdict file at `<worktree>/.ohaze/review-verdict.json` exists, check its `issues` for entries starting with `ADVERSARIAL:`. Surface them to the user **without commentary** before the menu:

```
⚠️ Reviewer 提出的对抗式发现（不阻塞, 设计层判断）：
  - ADVERSARIAL: ...
```

Then proceed. If no ADVERSARIAL findings, skip silently.

## Step 3 — Finishing Menu

Present the same 5-option menu as `/ohaze:ship-review`:

```
请选择:
1. 推送到远端
2. 创建 Pull Request
3. 保持现状 (再次保留, 稍后用 /ohaze:ship-finish 回来)
4. 丢弃此次工作
5. 继续修改 (小改动)
```

The behavior of each option is **identical to `/ohaze:ship-review`'s Phase 7**. Reuse that logic — do not duplicate it. This includes writing `.ohaze/ship-result.json` before each terminal action (options 1/2/4) as described there.

## Cleanup

- Options 1 / 2 / 4: write `ship-result.json` first (vault hook), then remove handoff file.
- Option 3: keep handoff (state = "kept"), tell user how to come back.
- Option 5: enter modify sub-flow, loop back to menu.

## Final Summary

After a terminal action, print:
- Spec path
- Plan path
- Codex review retries used
- Modify iterations used (if any)
- Manual edits detected and committed (if any)
- Final disposition

## Failure Modes

- Handoff file is malformed: report the field that's broken, do NOT auto-fix, ask user.
- Worktree has merge conflicts (unmerged paths): stop, ask user to resolve manually.
- Detached HEAD in worktree: stop, surface "worktree is in detached state, manual intervention required".

## Notes

- `/ohaze:ship-finish` is idempotent for state=kept — running it twice when nothing changed just re-presents the menu.
- It does NOT re-dispatch Codex from scratch. For that use `/ohaze:ship` again (a fresh ship).
- This command exists primarily so you can pause via option 3 or 5c and pick up later without losing state.
