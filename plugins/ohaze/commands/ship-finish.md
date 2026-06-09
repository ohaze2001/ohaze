---
description: Re-enter finishing for an /ohaze:ship that was paused (option 4 「先不处理」, option 2c 「我自己改」) or self-edited. Idempotent state-gate entry; optionally re-runs review, then shows the 6-option finishing menu.
argument-hint: "[--skip-review] (skip the optional re-review)"
allowed-tools: Bash, BashOutput, Read, Write, Edit, Skill, Agent, AskUserQuestion
---

Resume finishing for a previously paused ship.

`$ARGUMENTS`

## Pre-flight — Idempotent state gate (same defense as /ohaze:ship-review)

### 1. Locate the handoff file

Search in priority:

- `$(git rev-parse --show-toplevel)/.ohaze/current-ship.json` — preferred (when run from inside the worktree)
- If not found, walk up from `pwd` looking for `.ohaze/current-ship.json`
- If still not found, walk the parent repo's `git worktree list` for any worktree with one

If no handoff exists:
- Run `/ohaze:status` to see if any worktree has one elsewhere.
- Otherwise tell user: "没找到 ohaze handoff. 这个 ship 可能已经 finish 过了, 或者你需要先跑 /ohaze:ship 启动一个."
- Stop. Do NOT prompt; this is a stray invocation.

### 2. Parse the handoff

Capture: `plan_path`, `spec_path`, `base_ref`, `worktree_path`, `main_repo_path`, `state`, `retries`, `branch`, `slug`, `linked_todo`, `thread_id`, `codex_bg_id`, `project_type`.

### 3. State gate

Act per this table (identical defense to `/ohaze:ship-review` — entry symmetry intentional):

| `state` value | Action |
|---|---|
| missing / file absent | Stop silently. |
| `done` / `discarded` | Stop silently — already finished. Idempotent no-op. |
| `running` | Codex still working. Tell user to wait for harness re-invoke (or `/ohaze:ship-review` after completion). End. |
| `codex_done` / `review_fail` | The review loop hasn't run / finished yet — suggest `/ohaze:ship-review` instead. End. |
| `kept` | Normal resume: continue into Step 1 below. |
| `self-edit-pending` | Normal resume after manual edit: continue into Step 1 below. |

### 4. Verify the worktree still exists

If `worktree_path` is gone (user removed it manually, or a parallel session cleaned up):

- Tell user "Worktree `<path>` 已删除. handoff 是 stale, 我帮你清掉."
- `rm <handoff>`
- Stop.

### 5. `cd <worktree_path>`

So all `.ohaze/*` paths resolve correctly and commits land on the right branch.

## Step 1 — Detect uncommitted changes (likely from option 2c self-edit)

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
- Show the diff with `git diff` / `git diff --cached`.
- Ask for commit message: "commit 信息?" (suggest a default like `refactor: manual adjustments after review`)
- Run `git add -A && git commit -m "<message>"`. Do not bypass hooks.

If user picks 2: stop, let user inspect / edit / commit themselves, tell them to re-run `/ohaze:ship-finish` when ready.

## Step 2 — Optional re-review

If `--skip-review` flag is present, skip this step.

Otherwise ask:

> "要先跑一次 review 再 finish 吗? (推荐, 因为可能有手改未审过)"
> "1. 是, 跑 review"
> "2. 否, 直接进 finishing 菜单"

If 1:
- Invoke `ohaze:codex-executor` with **`mode='review'`** (REQUIRED — skips Phase 4 dispatch, enters at Phase 5.0. Step 1 already committed any pending work so Phase 5.0 is a no-op in this path).
- Pass `thread_id` from the handoff for any potential resume (resume drops `--sandbox` per codex 0.137).
- If FAIL: enter the review-fix loop just like `/ohaze:ship-review` does (max 3 retries, increment `.ohaze/current-ship.json.retries`, `codex exec resume <thread_id>` via `Bash(run_in_background)` — no `--sandbox`).
- If PASS: continue to Step 3.

If 2: continue to Step 3 directly.

## Step 2.5 — Surface ADVERSARIAL findings (if any)

If Step 2 ran a re-review, or if the prior verdict file at `<worktree>/.ohaze/review-verdict.json` exists, check its `issues[]` for entries starting with `ADVERSARIAL:`. Surface them to the user **without commentary** before the menu:

```
⚠️ Reviewer 提出的对抗式发现 (不阻塞, 设计层判断):
  - ADVERSARIAL: ...

如要批量修复对抗审查发现, finishing 菜单会出现「修复对抗审查后收尾」项 (仅当有 ADVERSARIAL 时).
```

Then proceed. If no ADVERSARIAL findings, skip silently.

## Step 3 — Invoke `ohaze:finishing`

Invoke the `ohaze:finishing` skill. Pass the full finishing context from `.ohaze/current-ship.json` and the latest verdict path:

- `worktree_path`
- `main_repo_path`
- `base_ref`
- `branch`
- `plan_path`
- `spec_path`
- `retries`
- `linked_todo`
- `thread_id` (for modify sub-flow 5a / 6th-option ADVERSARIAL fix; resume without `--sandbox`)
- `review_verdict_path`: `<worktree_path>/.ohaze/review-verdict.json`

The finishing skill owns project-type detection, recommended finish chain, document finish (neat-style routing internalized), the 6-option menu (6th option appears only when ADVERSARIAL findings exist), terminal result cleanup, and the modify sub-flow.

## Failure Modes

- Handoff file is malformed: report the field that's broken, do NOT auto-fix, ask user.
- Worktree has merge conflicts (unmerged paths): stop, ask user to resolve manually.
- Detached HEAD in worktree: stop, surface "worktree is in detached state, manual intervention required".

## Notes

- `/ohaze:ship-finish` is idempotent: the state gate makes it safe to invoke twice. Running on `state=done` is a no-op.
- It does NOT re-dispatch Codex from scratch. For that use `/ohaze:ship` again (a fresh ship).
- This command exists so you can pause via finish menu option 4 (`kept`) or option 2c (`self-edit-pending`) and pick up later without losing state.
- This command does NOT call `ScheduleWakeup` and does NOT poll pid files. v2 control flow = `run_in_background` + harness re-invoke + idempotent state gate.
