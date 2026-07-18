---
description: Resume an /ohaze:ship workflow (called by harness re-invoke after Codex background completes, or by the user manually). Idempotent state gate → review loop (max 3 retries with stuck-detection) → ohaze finishing menu (6 options; 6th appears only when ADVERSARIAL findings exist).
argument-hint: "[--more] (optional: continue past the 3-retry cap)"
allowed-tools: Bash, BashOutput, KillBash, Read, Write, Edit, Skill, Agent, AskUserQuestion
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
| `dispatch_failed` | Codex initial or retry dispatch failed liveness check twice (pre-thread transport failure; historically also codex 0.137 stdin crash, fixed in 0.140+). Surface `WARNING: ship is in dispatch_failed state. codex_bg_id is null (process killed). thread_id={value or null}.` and tell the user to either rerun `/ohaze:ship` (fresh dispatch, discards thread) or manually resume via `cd <worktree_path> && codex exec resume <thread_id> "<prompt>"` if thread_id is preserved. Do NOT auto-retry. End. |
| `blast_radius_escalated` | Debug-mode G3 escalated this repair out of `/ohaze:debug`. Surface a warning and tell haze to restart with `/ohaze:ship` for the full flow. End. |

> The gate eats ghost wake-ups, double `/ohaze:ship-review` invocations, and accidental re-invokes alike. There is no fallback `ScheduleWakeup` because dogfood (spec §3) proved harness re-invoke is reliable; A-plan: state gate is the only defense.

### 3a. `state=running` liveness-detect-and-transition (REQUIRED — fixes the gate's chicken-and-egg)

When the harness re-invokes the main agent after a `Bash(run_in_background)` Codex task completes, the harness does NOT mutate `current-ship.json` — that's ohaze's job. Without an explicit transition here, the gate would loop forever on `state=running`. So:

1. Read `codex_bg_id` from the handoff.
2. Call `BashOutput <codex_bg_id> filter='"type":"(message|error)"|panic|fatal|unhandled'` and inspect both the (now-bounded) filtered output and the task status. The `filter` parameter is REQUIRED — codex's `--json` stream for a multi-hour run can be 5-20 MB of intermediate event payloads; without filter the entire buffer would be pulled into context and exhaust the window before Step 3a can reason about it. The filter keeps only liveness/final-report-relevant events.
3. Decide by combining task status + presence of final `message` event in the filtered tail. Use this 3-way branch (note tiebreaker for the codex emit-final-then-exit race window):

   **(a) Task completed (background task status = `completed` or process exited):**
   - Scan the filtered tail for the final `message` event AND for any unhandled error.
   - If output looks normal (has a final `message` event, no unhandled error): **transition `state = "codex_done"`** via the Read-modify-Write protocol in `ship.md` §Write Protocol (Read full file → preserve all fields → Write with only `state` overridden), then fall through to Phase 5 (Review).
   - If output shows Codex died mid-run (unhandled error, no final `message`, or output is truncated): surface the error verbatim and stop. Do NOT enter review on incomplete work.

   **(b) Task still running BUT final `message` event already present in filtered tail (race-window tiebreaker):**
   - This is the codex emit-final-then-exit race window (tens of ms to seconds between the final JSON event emission and the actual process exit syscall; observed across 0.137–0.144.5). Without this tiebreaker we'd fall into branch (c) → end turn → and if the harness re-invoke that brought us here was the only one we'll get for this task, we'd deadlock.
   - Sleep briefly (~2s) via `Bash(sleep 2)`, then re-query `BashOutput <codex_bg_id> filter=...` once.
     - If task status is now `completed`: fall through to branch (a).
     - If task status is STILL `running` after the recheck (codex genuinely emitted a non-final message): fall through to branch (c) — truly wait.

   **(c) Task still running, no final `message` event in filtered tail:**
   - Codex is genuinely working. Tell the user `"Codex 还在跑 (codex_bg_id=<id>), 进程仍活. Harness 会在完成时自动再唤醒主 agent."` and end the turn. Do NOT transition state.

   **(d) `codex_bg_id` missing from handoff** (legacy v1 or capture failure):
   - Treat as if the task completed and proceed to scan whatever's available — but warn the user that liveness check is degraded.

> Why this lives here, not in codex-executor: the transition must happen BEFORE Phase 5 enters codex-executor, because codex-executor only runs in review mode when the gate says `codex_done`. ship-review.md owns the gate, so it owns the transition.

### 5. `--more` flag

If `--more` is present in `$ARGUMENTS`, allow the review-fix loop to exceed the 3-retry cap. Otherwise honor it.

## Phase 5.-0.5 — Compute `touched_files_abs`

This section is debug mode only and runs after Step 3a, before the existing Phase 5.0 commit step inside `ohaze:codex-executor`.

Read `.ohaze/current-ship.json.ship_mode`. If the field is missing, treat as `"ship"` for legacy v2.1.x handoff compatibility. If `ship_mode != "debug"`, skip Phase 5.-0.5, L2, and G3 entirely and proceed to Phase 5.0.

When `ship_mode == "debug"`, compute one read-only in-memory array named `touched_files_abs` from `<worktree_path>` and `<base_ref>`:

1. Files changed in commits since base:
   ```bash
   git -C "$worktree_path" diff --name-only "$base_ref"..HEAD
   ```
2. Files dirty in the working tree:
   ```bash
   git -C "$worktree_path" diff --name-only HEAD
   ```
3. Untracked files that are not git-ignored:
   ```bash
   git -C "$worktree_path" ls-files --others --exclude-standard
   ```

De-duplicate the union, normalize each entry to an absolute path under `worktree_path` using `realpath` or equivalent absolute path normalization, and store the result as `touched_files_abs`. This phase has no side effects.

## L2 — scope_lock_files Boundary Enforcement

This section is debug mode only and reads the same `touched_files_abs` snapshot computed in Phase 5.-0.5.

Trigger when `ship_mode == "debug"` and `scope_lock_files` from the handoff is non-empty. Normalize `scope_lock_files` to absolute paths under `worktree_path`, then compute:

```text
breached_files = touched_files_abs - scope_lock_files
```

If `breached_files` is empty, proceed to G3.

If `breached_files` is non-empty:

1. Read `<worktree_path>/.ohaze/findings-detail.json`; if missing, create the in-memory base object `{"iteration": <retries>, "findings": []}`.
2. Preserve unknown top-level fields, override only `iteration` and `findings`, and append one CRITICAL finding per breached file with this shape:
   ```json
   {
     "severity": "CRITICAL",
     "evidence": "touched_files_abs contains a path outside scope_lock_files: <absolute path>",
     "technical_description": "Debug scope_lock_files boundary was breached before review. breached_files includes <absolute path>.",
     "user_impact_description": "The debug fix changed files outside the agreed scope lock, increasing regression risk.",
     "shown_to_user": false,
     "auto_handled": "retry-fix"
   }
   ```
3. Write back `findings-detail.json`.
4. Append a parallel CRITICAL string entry to `<worktree_path>/.ohaze/review-verdict.json.issues` in this format: `CRITICAL: scope_lock breach — <file>`.
5. Set `.ohaze/review-verdict.json.verdict` to `"FAIL"` if it is currently `"PASS"` so the retry loop handles the breach.

## G3 — Blast-Radius Gate

This section is debug mode only and runs after L2, using the same `touched_files_abs` snapshot. If `ship_mode` is missing, treat as `"ship"` and skip for backward compatibility.

Compute `count = length(touched_files_abs)`.

- If `count <= 5 files`, skip G3 and proceed to Phase 5.0.
- If `count > 5 files`, trigger exactly one `AskUserQuestion` with exactly three options:
  1. `接受宽修` — proceed to Phase 5.0 normally.
  2. `缩 scope` — dispatch `codex exec resume <thread_id>` with an anti-regression prompt naming the current `touched_files_abs` files and asking Codex to reduce the blast radius. Reuse the Phase 6 fix-prompt structure, but issue it from `ship-review`, not via a FAIL verdict. After resume completes and the harness re-invokes `ship-review`, rerun Phase 5.-0.5, L2, and G3. Loop max is 2; on the 3rd G3 entry, escalate to Option 3.
  3. `升级 ship` — set `.ohaze/current-ship.json.state = "blast_radius_escalated"` using Read-modify-Write, surface a warning, and stop. Haze re-runs `/ohaze:ship` for the full flow.

Order invariant: Phase 5.-0.5 → L2 → G3 → existing Phase 5.0. L2 and G3 read the SAME `touched_files_abs` snapshot.

## Phase 5–6 — Review + Retry Loop (delegated to `ohaze:codex-executor`)

Invoke `ohaze:codex-executor` in review mode with:

- `mode`: `'review'` (required — REQUIRED to skip Phase 4 dispatch and enter at Phase 5.0. Without this explicit value, codex-executor's missing-mode fallback degrades to 'dispatch', which would re-dispatch a fresh Codex on top of the already-completed run)
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

Before the finishing menu, read `<worktree_path>/.ohaze/findings-detail.json` and filter for `severity == "ADVERSARIAL"`.

Show only ADVERSARIAL findings where `user_impact_description != null`. Never surface raw `evidence`, file paths, line numbers, function names, or `technical_description` in the haze-facing menu. Use product language only:

```
⚠️ Reviewer 提出的对抗式发现 (不阻塞 ship, 设计层判断, 你来决定要不要处理):

🔴 CRITICAL / IMPORTANT: <N> 条 — Codex 在 retry loop 修复中(无需 haze 介入)

🟡 ADVERSARIAL (user-facing,需要你决策): <M> 条
  1. <user_impact_description>
     建议: fix(改 Y) / accept(接受这个 tradeoff)
  2. ...

🟢 已 skip 的纯技术细节: <K> 条
   → 完整清单: .ohaze/findings-detail.json
```

The skipped count is the number of ADVERSARIAL findings whose `user_impact_description == null`. The full technical record remains in `.ohaze/findings-detail.json` for on-demand inspection.

Then proceed to Phase 7. Do not auto-loop into modify — the user decides whether to act on ADVERSARIAL items via the 6th finishing menu option.

If there are no ADVERSARIAL findings with product-language impact, skip this section silently.

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

- Background Codex genuinely failed (the `--json` stream tail shows an unhandled error, not just incomplete output): surface the error verbatim; do NOT enter review loop. Suggest the user re-run `cd <worktree> && codex exec resume <thread_id> "<corrective prompt>" --json` (NOT `--cd`, NOT `--sandbox` — both persistently rejected on resume, 0.137 起至 0.144.5 未变) manually, or warn before using the `--last` fallback if `thread_id` is absent.
- Reviewer subagent returns malformed verdict twice: fall back to asking the user to read `git diff` and judge.
- Handoff file references a worktree path that no longer exists: stop, surface, ask user.
- Push fails (no remote, auth missing): not this skill's problem — `ohaze:finishing` owns push/PR and surfaces those errors itself.

## Notes

- The 6-option finishing menu is owned by `ohaze:finishing` (not duplicated here). The 6th option ("修复对抗审查后收尾") only appears when the verdict contained ADVERSARIAL findings. The modify-flow stays inside `ohaze:finishing`.
- Modify-loop iterations don't count against the 3-retry review cap — they're user-initiated, not reviewer-driven.
- After modify branches (Codex / Claude / self-edit), finishing always returns to the menu.
- This command does NOT call `ScheduleWakeup` and does NOT poll pid files. v2 control flow = `run_in_background` + harness re-invoke + idempotent state gate. See `ohaze:codex-executor` Dispatch Mode Vocabulary for harness background vs forbidden OS-level background.
