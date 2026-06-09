---
description: Resume an /ohaze:ship workflow (called by harness re-invoke after Codex background completes, or by the user manually). Idempotent state gate → review loop (max 3 retries with stuck-detection) → ohaze finishing menu (6 options; 6th appears only when ADVERSARIAL findings exist).
argument-hint: "[--more] (optional: continue past the 3-retry cap)"
allowed-tools: Bash, BashOutput, Read, Write, Edit, Skill, Agent, AskUserQuestion
---

Continue the workflow started by `/ohaze:ship`. This command is the **state-gate entry point** — it is safe to invoke at any time (the gate decides what to do). It is also what the harness lands in via re-invoke after a `run_in_background` Codex task completes.

`$ARGUMENTS`

## Pre-flight — Idempotent state gate (唯一防幽灵唤醒/重入)

`.ohaze/` lives **inside the worktree** (per `ship.md` Step B), not the main checkout.

### 1. Locate the handoff

- If the current `pwd` already contains `.ohaze/current-ship.json`, use it.
- Otherwise, walk up from `pwd` looking for a `.ohaze/current-ship.json`.
- If still not found, walk the parent repo's `git worktree list` for any worktree that has one.

If **no handoff exists** anywhere, this is a stray invocation (a ghost-wake into a long-finished ship, a misclicked `/ohaze:ship-review`, etc.) — print one short note and stop. **Do NOT prompt the user, do NOT start a new ship, do NOT error.**

### 2. `cd` into the worktree

`cd <worktree_path>` so all `.ohaze/*` paths resolve correctly and any commits land on the right branch.

### 3. Read `state` and act

Read `state` from `<worktree>/.ohaze/current-ship.json` and act per this table. **This is the only ghost-wake defense in v2** — no ScheduleWakeup is ever set, so the only way a stray re-invoke can do damage is by ignoring this gate.

| `state` value | Action |
|---|---|
| missing key, or file absent | Stop silently — handoff is gone, this is a stray. |
| `done` or `discarded` | Stop silently — ship already finished. **Idempotent no-op.** This is what catches the wake-up that fires after a ship completed. |
| `running` | **Run the liveness-detect-and-transition flow** (Step 3a below). May transition to `codex_done` then continue, OR genuinely wait. |
| `codex_done` | Proceed to the review loop (Phase 5 below). |
| `review_fail` | Proceed to retry (Phase 6 in `ohaze:codex-executor`). Retry counter is already in the handoff. |
| `kept` | Tell the user the previous ship was paused via finish menu option 4 → suggest `/ohaze:ship-finish` to resume. End. |
| `self-edit-pending` | Tell the user the previous ship was paused via finish menu option 2c → suggest `/ohaze:ship-finish` after their manual edits. End. |

> The gate eats ghost wake-ups, double `/ohaze:ship-review` invocations, and accidental re-invokes alike. There is no fallback `ScheduleWakeup` because dogfood (spec §3) proved harness re-invoke is reliable; A-plan: state gate is the only defense.

### 3a. `state=running` liveness-detect-and-transition (REQUIRED — fixes the gate's chicken-and-egg)

When the harness re-invokes the main agent after a `Bash(run_in_background)` Codex task completes, the harness does NOT mutate `current-ship.json` — that's ohaze's job. Without an explicit transition here, the gate would loop forever on `state=running`. So:

1. Read `codex_bg_id` from the handoff.
2. Call `BashOutput <codex_bg_id>` and inspect both the streamed output and the task status (the BashOutput tool reports whether the background task is still running, completed, or killed):
   - **If the task is still running** (Codex hasn't exited yet, the background task status is still `running`): truly wait. Tell the user `"Codex 还在跑 (codex_bg_id=<id>), 进程仍活. Harness 会在完成时自动再唤醒主 agent."` and end the turn. Do NOT transition state.
   - **If the task has completed** (background task status = `completed` or process exited): scan the tail of its `--json` output for the final `message` event (Codex's structured report) AND for any unhandled error.
     - If output looks normal (has a final `message` event, no unhandled error): **transition `state = "codex_done"`** via Write tool on `current-ship.json`, then fall through to Phase 5 (Review). The transition write is the missing link that makes the state gate work.
     - If output shows Codex died mid-run (unhandled error, no final `message`, or output is truncated): surface the error verbatim to the user and stop. Do NOT enter review on incomplete work. Suggest the user inspect with `BashOutput <codex_bg_id>` and either manually fix or start a fresh `/ohaze:ship`.
   - **If `codex_bg_id` is missing from the handoff** (legacy v1 or capture failure): treat as if the task completed and proceed to scan output — but warn the user that liveness check is degraded.

> Why this lives here, not in codex-executor: the transition must happen BEFORE Phase 5 enters codex-executor, because codex-executor only runs in review mode when the gate says `codex_done`. ship-review.md owns the gate, so it owns the transition.

### 5. `--more` flag

If `--more` is present in `$ARGUMENTS`, allow the review-fix loop to exceed the 3-retry cap. Otherwise honor it.

## Phase 5–6 — Review + Retry Loop (delegated to `ohaze:codex-executor`)

Invoke `ohaze:codex-executor` in **review mode** with:

- `plan_path`, `spec_path`, `base_ref`, `worktree_path`, `main_repo_path`: from the handoff
- `thread_id`: from the handoff (used by retry's `codex exec resume <thread_id>` — no `--sandbox`)
- `project_test_command`: from the handoff (or re-detect from project files if absent)

The executor:

1. Phase 5.0 — auto-commit any pending changes Codex left behind (Codex by convention does not self-commit; see `plan-to-codex-prompt` `<commit_handling>`).
2. Phase 5.1 — compute `git diff <base_ref>...HEAD` for the reviewer.
3. Phase 5.2 — dispatch a `general-purpose` subagent for cross-source adversarial review with real test run (verification-before-completion internalized). The reviewer MUST be `general-purpose` — different model family from Codex by design.
4. Phase 5.3 — write `<worktree>/.ohaze/review-verdict.json` with `verdict`, `issues[]` (CRITICAL/IMPORTANT/ADVERSARIAL preserved), `doc_drift[]`.
5. On FAIL, the executor loops: stuck-detection diagnosis → format fix prompt → `codex exec resume <thread_id>` (re-dispatched via `run_in_background`, no `--sandbox`) → re-review (up to 3 iterations; warned `--last` fallback only if `thread_id` is missing).
6. Update `.ohaze/current-ship.json.retries` after each iteration.

If after 3 retries the verdict is still FAIL and `--more` was not passed, the executor stops and presents 3 options:

1. Continue retrying (`/ohaze:ship-review --more`)
2. Manually intervene (user fixes issues themselves) → tell user worktree path, exit
3. Accept current state and proceed to finishing → continue to Phase 7

Wait for user choice.

## Phase 6.5 — Surface ADVERSARIAL findings (if any)

Before the finishing menu, check `<worktree>/.ohaze/review-verdict.json.issues` for entries prefixed `ADVERSARIAL:`.

If yes, print them verbatim to the user **without commentary**:

```
⚠️ Reviewer 提出的对抗式发现 (不阻塞 ship, 设计层判断, 你来决定要不要处理):

  - ADVERSARIAL: <design risk> — <file:line>
  - ADVERSARIAL: <design risk> — <file:line>

如要批量修复后再收尾, finishing 菜单会出现「修复对抗审查后收尾」项 (仅当有 ADVERSARIAL 时存在).
```

Then proceed to Phase 7. Do not auto-loop into modify — the user decides whether to act on ADVERSARIAL items via the 6th finishing menu option.

If no ADVERSARIAL findings, skip this section silently.

## Phase 7 — Invoke `ohaze:finishing`

Once review verdict is PASS (or the user accepted current state above), invoke the `ohaze:finishing` skill. Pass the full finishing context from `.ohaze/current-ship.json` and the latest verdict path:

- `worktree_path`
- `main_repo_path`
- `base_ref`
- `branch`
- `plan_path`
- `spec_path`
- `retries`
- `linked_todo`
- `thread_id` (for modify sub-flow / 6th-option ADVERSARIAL fix; resume without `--sandbox`)
- `review_verdict_path`: `<worktree_path>/.ohaze/review-verdict.json`

The finishing skill owns: project-type detection, recommended finish chain, document finish (with neat-style routing internalized), the 6-option menu (6th option appears only when ADVERSARIAL findings exist), terminal result cleanup, and the modify sub-flow.

## Failure Modes

- Background Codex genuinely failed (the `--json` stream tail shows an unhandled error, not just incomplete output): surface the error verbatim; do NOT enter review loop. Suggest the user re-run `codex exec resume <thread_id> --cd <worktree> --json` (NOT `--sandbox` — sandbox is fixed at initial dispatch) manually with a corrective prompt, or warn before using the `--last` fallback if `thread_id` is absent.
- Reviewer subagent returns malformed verdict twice: fall back to asking the user to read `git diff` and judge.
- Handoff file references a worktree path that no longer exists: stop, surface, ask user.
- Push fails (no remote, auth missing): not this skill's problem — `ohaze:finishing` owns push/PR and surfaces those errors itself.

## Notes

- The 6-option finishing menu is owned by `ohaze:finishing` (not duplicated here). The 6th option ("修复对抗审查后收尾") only appears when the verdict contained ADVERSARIAL findings. The modify-flow stays inside `ohaze:finishing`.
- Modify-loop iterations don't count against the 3-retry review cap — they're user-initiated, not reviewer-driven.
- After modify branches (Codex / Claude / self-edit), finishing always returns to the menu.
- This command does NOT call `ScheduleWakeup` and does NOT poll pid files. v2 control flow = `run_in_background` + harness re-invoke + idempotent state gate.
