---
description: Resume an /ohaze:ship workflow after Codex finishes. Runs the Claude-side review loop (max 3 retries) then superpowers:finishing-a-development-branch.
argument-hint: "[--more] (optional: continue past the 3-retry limit)"
allowed-tools: Bash, Read, Write, Edit, Skill, Agent, AskUserQuestion
---

Continue the workflow started by `/ohaze:ship` after the background Codex run completes.

`$ARGUMENTS`

## Pre-flight

1. Read `.ohaze/current-ship.json` from the project root. If missing, tell user to run `/ohaze:ship` first.

2. Verify Codex is actually done by running:
   ```bash
   /codex:status
   ```
   If still running, tell user to wait and try again. Do not proceed with review on incomplete work.

3. If `--more` flag is present in `$ARGUMENTS`, allow exceeding the 3-retry cap; otherwise honor it.

## Phase 5-6 — Review + Retry Loop (ohaze)

4. Invoke `ohaze:codex-executor` skill in **review mode**:
   - Pass: `plan_path`, `base_ref`, `worktree_path` from the handoff file
   - The skill fetches `/codex:result`, computes the diff, dispatches `superpowers:code-reviewer` subagent
   - On FAIL, the skill loops: format issues → `codex:codex-rescue --resume` → re-review (up to 3 times)
   - Update `.ohaze/current-ship.json` `retries` counter after each iteration

5. If after the loop the verdict is still FAIL and `--more` was not passed, the executor stops and presents 3 options to the user:
   - Continue retrying (`/ohaze:ship-review --more`)
   - Manually intervene (user fixes issues themselves)
   - Accept current state and proceed to finishing

   Wait for user choice.

## Phase 7 — Finishing (superpowers)

6. Once review verdict is PASS (or user accepted current state), invoke `superpowers:finishing-a-development-branch` skill.
   - It will verify tests, ask user merge / PR / keep-branch / discard, then clean up the worktree.

## Cleanup

7. After finishing succeeds, remove the handoff file:
   ```bash
   rm .ohaze/current-ship.json
   ```

8. Print a final summary:
   - Spec path
   - Plan path
   - Codex retries used
   - Final disposition (merged / PR-opened / kept / discarded)

## Failure modes

- `/codex:result` reports Codex failed (not just "found issues" but actually crashed): surface the stderr; do NOT enter the review loop on a non-implementation. Suggest `/codex:rescue --resume "<retry instruction>"` as recovery.
- Reviewer subagent returns malformed verdict twice in a row: fall back to asking user to read `git diff` and judge themselves.
- Handoff file references a worktree path that no longer exists: stop, surface the situation, ask user.

## Notes

- This command is idempotent for the review stage: running it twice when verdict is PASS just re-runs `superpowers:finishing-a-development-branch`, which itself handles already-merged state.
- It does NOT re-dispatch Codex from scratch. It only sends `--resume` follow-ups.
