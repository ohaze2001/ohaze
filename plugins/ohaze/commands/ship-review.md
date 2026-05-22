---
description: Resume an /ohaze:ship workflow after Codex finishes. Runs review loop (max 3 retries) then ohaze's 5-option finishing menu (with "继续修改" branch).
argument-hint: "[--more] (optional: continue past the 3-retry limit)"
allowed-tools: Bash, Read, Write, Edit, Skill, Agent, AskUserQuestion, ScheduleWakeup
---

Continue the workflow started by `/ohaze:ship` after the background Codex run completes.

`$ARGUMENTS`

## Pre-flight

1. Locate and read the handoff. `.ohaze/` lives inside the **worktree** (per `ship.md` Step B), not the main checkout. If the current `pwd` already contains `.ohaze/current-ship.json`, use it. Otherwise walk up from `pwd` to find a worktree with one. If still missing, tell user to run `/ohaze:ship` first.

   `cd` into the worktree for the rest of this command so all `.ohaze/*` paths resolve correctly and commits land in the right branch.

2. Verify Codex is actually done. Read `codex_pid_file` and `codex_log_file` from the handoff:

   ```bash
   if [[ -f "$codex_pid_file" ]] && kill -0 "$(cat "$codex_pid_file")" 2>/dev/null; then
     CODEX_ALIVE=1
   else
     CODEX_ALIVE=0
   fi
   ```

   **If Codex is still running (`CODEX_ALIVE=1`)**: do NOT exit. Re-schedule a wakeup and stop the turn:

   - Call `ScheduleWakeup(delaySeconds=600, reason="codex still running for <feature>, elapsed <N>m", prompt="/ohaze:ship-review")`.
   - Tell the user: *"Codex 还在跑 (pid=<pid>, elapsed=<N>m). 已重新 schedule 10 分钟后再 check, 自动接 Phase 5. 你可以继续别的事, 不需要手动回来."*
   - End the turn. The next wakeup re-enters this same Pre-flight Step 2.

   **If Codex is done (`CODEX_ALIVE=0`)**: check the tail of `<codex_log_file>` for the end-of-run report block. If the log shows an unhandled error, surface it and stop — do NOT proceed with review on incomplete work. Otherwise continue to Step 3 (and onward into Phase 5).

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
   - On FAIL, the skill loops: format issues → `codex exec resume <codex_session_id>` → re-review (up to 3 times; warned fallback only if the session id is missing)
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

## Phase 7 — Invoke `ohaze:finishing`

Once review verdict is PASS (or user accepted current state in step 5), invoke the `ohaze:finishing` skill. Pass the full finishing context from `.ohaze/current-ship.json` and the latest verdict path:

- `worktree_path`
- `base_ref`
- `branch`
- `plan_path`
- `spec_path`
- `retries`
- `linked_todo`
- `codex_session_id`
- `review_verdict_path`: `<worktree_path>/.ohaze/review-verdict.json`

The finishing skill owns Phase 7: project-type detection, recommended finish chain, document finish, terminal result files, cleanup ordering, and the modify sub-flow.

## Failure Modes

- `<codex_log_file>` tail shows Codex genuinely failed (not just incomplete): surface the error verbatim; do NOT enter review loop. Suggest the user run an exact `codex exec resume <codex_session_id> --sandbox danger-full-access --cd <worktree>` manually with a corrective prompt, or warn before using the `--last` fallback if the session id is absent.
- Reviewer subagent returns malformed verdict twice: fall back to asking user to read `git diff` and judge.
- Handoff file references a worktree path that no longer exists: stop, surface, ask user.
- Push fails (no remote, auth missing): surface error, hand back to menu (don't auto-retry).

## Notes

- The 5-option menu is owned by `ohaze:finishing`; we do NOT invoke `superpowers:finishing-a-development-branch`. This avoids menu duplication and keeps modify-flow inside the same orchestration.
- Modify loop iterations don't count against the 3-retry review cap — they're user-initiated, not reviewer-driven.
- After modify branches 5a (Codex) or 5b (Claude), finishing always returns to the menu.
