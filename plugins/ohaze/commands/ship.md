---
description: End-to-end feature shipping. Brainstorm → plan → Codex execute → (later /ohaze:ship-review for review + finishing).
argument-hint: "[feature description]"
allowed-tools: Bash, Read, Write, Edit, Skill, Agent, AskUserQuestion
---

Orchestrate the ohaze workflow for the user's request. Treat the user's argument as the feature description:

`$ARGUMENTS`

If `$ARGUMENTS` is empty, ask the user what they want to ship before proceeding.

## Pre-flight

1. Verify both required plugins are present:
   ```bash
   ls ~/.claude/plugins/marketplaces/openai-codex/plugins/codex/.claude-plugin/plugin.json
   ls ~/.claude/plugins/cache/claude-plugins-official/superpowers/*/skills/brainstorming/SKILL.md
   ```
   If either is missing, stop and tell the user to install:
   - `/plugin install superpowers@claude-plugins-official`
   - `/plugin install codex@openai-codex`

2. Detect current project: `pwd` and `git rev-parse --show-toplevel`. Confirm with user this is the project they want to ship in.

## Phase 1 — Brainstorm (superpowers)

3. Invoke the `superpowers:brainstorming` skill.
   - It will lead the user through clarifying questions, design proposals, and write a spec to `docs/superpowers/specs/<date>-<topic>-design.md`.
   - DO NOT bypass any user-approval gates inside brainstorming.
   - Wait until the spec is committed and the user explicitly approves it.
   - **CRITICAL — Override brainstorming's terminal state:** brainstorming's last instruction says "invoke writing-plans skill" as the next step. DO NOT do that yet. Phase 2 (worktree) MUST run before writing-plans, otherwise Codex will write code on the wrong branch. After brainstorming finishes its spec self-review and the user approves the spec, proceed to Phase 2 explicitly.

## Phase 2 — Worktree (superpowers) — DO NOT SKIP

4. Invoke the `superpowers:using-git-worktrees` skill.
   - This step is **mandatory** even though brainstorming may have implied "go straight to writing-plans". Without this step the implementation lands on whatever branch the user happened to be on (often `main`), defeating the isolation guarantee.
   - Branch name: derive from the spec filename (e.g. spec `2026-05-08-login-page-design.md` → branch `feat/login-page`).
   - Capture the worktree path and base branch (typically `main`); these are needed in Phase 4 and Phase 5.
   - After the worktree is created and the clean test baseline passes, **`cd` into the worktree** before invoking writing-plans, so the plan and all subsequent work happens inside the isolated worktree.

## Phase 3 — Plan (superpowers)

5. Invoke the `superpowers:writing-plans` skill.
   - It saves the plan to `docs/superpowers/plans/<date>-<feature>.md`.
   - Capture the absolute plan file path.
   - **CRITICAL — Override writing-plans' built-in handoff:** at the end of writing-plans the skill will try to display its own prompt asking the user to choose between "Subagent-Driven" and "Inline Execution". DO NOT show that menu. DO NOT wait for the user to pick 1 or 2. The execution path is already decided by `/ohaze:ship` — it goes through Codex via Phase 4 below.
   - Instead, after the plan is saved and self-reviewed, present a different prompt:
     > "Plan saved to `<path>`. 请审阅后回复 'go' 继续，让 Codex 后台执行整份 plan。"
   - Wait for the user's approval of the **plan content** (not the execution method).
   - When the user approves, proceed directly to Phase 4. Do NOT invoke `superpowers:subagent-driven-development` or `superpowers:executing-plans` — those are explicitly out of the ohaze workflow.

## Phase 4 — Hand off to Codex (ohaze)

6. Invoke the `ohaze:plan-to-codex-prompt` skill with:
   - `plan_path`: the path captured in step 5
   - `project_test_command`: detect from project files (`package.json` → `npm test`, `Cargo.toml` → `cargo test`, `pyproject.toml` → `pytest`, etc.). If unclear, ask user.

   The skill returns a single XML prompt string. Capture it.

7. Invoke the `ohaze:codex-executor` skill with:
   - `codex_prompt`: the XML from step 6
   - `plan_path`: same as step 5
   - `base_ref`: base branch from step 4 (typically `main`)
   - `mode`: `--background` (V1 default)

   The skill dispatches `codex:codex-rescue` and tells the user how to proceed.

## Stop here

The skill ends `/ohaze:ship` after Phase 4. Codex runs in the background. Tell the user:

> "Phase 1-4 完成. Codex 在后台执行 plan. 下一步:
> - `/codex:status` — 查看 Codex 进度
> - `/codex:result` — Codex 跑完后查看结果
> - `/ohaze:ship-review` — 触发审查循环 + finishing (Codex 跑完后再调)"

DO NOT auto-poll. DO NOT trigger Phase 5 in this same `/ohaze:ship` invocation. The user invokes `/ohaze:ship-review` when they're ready.

## Persisting context for /ohaze:ship-review

To make `/ohaze:ship-review` self-sufficient (it runs in a possibly-different session), write a small handoff file at the end of Phase 4.

**IMPORTANT — order of operations** (the `Write` tool does NOT create parent directories, so the dir MUST exist first):

1. Run `mkdir -p .ohaze` via Bash (relative to the worktree path).
2. Verify the dir exists with `ls -d .ohaze`.
3. THEN use the `Write` tool (or `Bash` + heredoc) to create `.ohaze/current-ship.json`.

If you skip step 1, the first `Write` attempt will fail with "Error writing file", forcing a retry. Don't make that mistake — always `mkdir -p` first.

Handoff file shape:
```json
{
  "plan_path": "<absolute path>",
  "base_ref": "<branch>",
  "worktree_path": "<absolute path>",
  "spec_path": "<absolute path>",
  "started_at": "<ISO timestamp>",
  "retries": 0,
  "codex_run_id": "<task-xxx-yyy if Path A succeeded, else fill in after Path B>",
  "state": "running"
}
```

`.ohaze/` should be added to `.gitignore` (do this once via the worktree skill or here if missing).

## Failure modes

- User aborts during brainstorming or plan review: stop cleanly, leave the worktree in place, do not dispatch Codex.
- `superpowers:writing-plans` returns no usable plan path: stop and ask user.
- `ohaze:codex-executor` fails to dispatch (Codex unauthenticated, etc.): stop and surface the error.

## Notes

- This command does NOT call `superpowers:subagent-driven-development` or `superpowers:executing-plans`. Those are replaced by `ohaze:codex-executor` for the execution stage.
- This command does NOT call `superpowers:finishing-a-development-branch`. That happens in `/ohaze:ship-review` after the review loop.
