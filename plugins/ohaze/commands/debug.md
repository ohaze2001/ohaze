---
description: Debug mode for ohaze workflow. Systematic 4-phase root cause investigation + scope-locked fix + cross-source review + finishing, lighter than /ohaze:ship for bug fixes.
argument-hint: "<symptom> [--cause=<猜测原因>] [--project <abs-path>]"
allowed-tools: Bash, BashOutput, KillBash, Read, Write, Edit, Skill, Agent, AskUserQuestion
---

Orchestrate the ohaze debug workflow for bug fixes.

`$ARGUMENTS`

Treat `$ARGUMENTS` as a required symptom string plus optional `--cause=<text>` and optional `--project <abs-path>`. If `$ARGUMENTS` is empty, use `AskUserQuestion` once with question `"这次要 debug 什么症状?"` to ask for the symptom before continuing. `--cause=` with an empty value is treated as `null`.

## Pre-flight

### 1. Hard dependency: codex CLI

```bash
command -v codex
```

If missing, stop and tell the user to install it (`npm install -g @openai/codex`) and authenticate (`codex login`).

### 2. Resolve `main_repo_path`

- If `--project <abs-path>` was passed: use it after verifying it exists and is a git repo or worktree.
- Otherwise ask once whether the current `pwd` is the target project. If yes, capture `git rev-parse --show-toplevel`; if no, ask the user to re-invoke with `--project`.

Store `main_repo_path` in memory. Never rediscover it from `pwd` later.

### 3. Branch and docs safety

Run in `main_repo_path`:

```bash
git -C "$main_repo_path" branch --show-current
git -C "$main_repo_path" status --porcelain
```

If dirty with unrelated work, stop. Verify the four-piece docs set (`CLAUDE.md`, `README.md`, `ROADMAP.md`, `CHANGELOG.md`) only when the target project type requires it; scaffold missing files on main before debugging.

### 4. Derive `slug`

Derive a unique kebab-case `slug` from the symptom's first sentence plus recent git context. The final value MUST match `^[a-z][a-z0-9-]{0,40}$`, SHOULD be at most 4 words, and MUST not collide with an existing `.worktrees/<slug>/` entry.

Use `fix/<slug>` by default for debug branches. `feat/<slug>` is allowed only when the investigation shows the requested repair is actually a feature-shaped compatibility addition. Mention both `feat/<slug>` and `fix/<slug>` in the handoff branch field as permitted patterns.

## Phase 2 — Worktree Creation

Create the isolated worktree immediately after Pre-flight and before any root-cause investigation. This ordering is mandatory: investigation commands MUST run inside `worktree_path`, not `main_repo_path`.

Invoke `ohaze:using-git-worktrees` with:

- Working dir: `main_repo_path`
- Desired branch: `fix/<slug>` by default, or `feat/<slug>` for feature-shaped fixes

Capture:

- `worktree_path`
- `branch`
- `base_ref`, defaulting to `main`

Assert `main_repo_path` still points to the original checkout, then `cd "$worktree_path"`.

If the user later cancels a debug gate after this point, route cleanup through `ohaze:finishing` menu Option 3 (discard). If cancellation happens before this point, exit cleanly with no cleanup.

## Phase 3 — Systematic Debugging Investigation

Invoke `Skill(ohaze:systematic-debugging)` with:

- `symptom`: parsed symptom string
- `cause_hypothesis`: parsed `--cause` string, or `null`
- `worktree_path`: absolute isolated workspace path
- `main_repo_path`: absolute read-only reference path

The skill owns root-cause investigation and the G1/G2 conditional gates. It MUST return these three terminal artifacts in the conversation:

- `investigation_report`: markdown containing Phase 1/2/3/4 outputs
- `scope_lock_files`: a flat list of absolute paths under `worktree_path`
- `fix_plan`: markdown with a mandatory anti-regression contract section

If the user cancels G1 or G2, exit cleanly. If the skill cannot form a hypothesis because the bug is not reproducible, stop and surface that result while preserving the worktree for manual continuation.

Write `investigation_report` to:

```text
<worktree_path>/.ohaze/investigation-<slug>.md
```

This investigation note is a runtime artifact. Ensure `.ohaze/` is gitignored and do not commit it.

## Phase 4a — Translate To Codex XML

Invoke `Skill(ohaze:debug-to-codex-prompt)` with:

- `investigation_path`: `<worktree_path>/.ohaze/investigation-<slug>.md`
- `scope_lock_files`: the list returned by systematic-debugging
- `fix_plan`: the markdown returned by systematic-debugging
- `project_test_command`: detected from project files, or `'(per-Task acceptance assertions inline in plan)'` for Markdown-only plugins
- `worktree_path`
- `main_repo_path`
- `base_ref`

`debug-to-codex-prompt` is the ONLY downstream user of `scope_lock_files` for the XML `<editable_files>` block. If this translation fails, surface the error verbatim and preserve the worktree.

Capture:

- XML string as `codex_prompt`
- `plan_path`: `<worktree_path>/.ohaze/codex-debug-prompt.xml`

## Phase 4b — Dispatch Via Codex Executor

Invoke `Skill(ohaze:codex-executor)` with:

- `mode`: `'dispatch'`
- `mode='dispatch'`
- `codex_prompt`: XML from Phase 4a
- `plan_path`: `<worktree_path>/.ohaze/codex-debug-prompt.xml`
- `spec_path`: `null`
- `base_ref`
- `worktree_path`
- `main_repo_path`
- `project_test_command`

The executor dispatches Codex with `Bash(run_in_background: true)` using the harness background mechanism. Never use OS-level backgrounding such as `nohup`, `&`, pid files, or polling loops.

If dispatch fails, write `<worktree_path>/.ohaze/current-ship.json` with `state = "dispatch_failed"` and both `codex_bg_id` and `thread_id` set to `null`, preserving the rest of the handoff object. Surface the executor error verbatim.

## Persisting Context — `.ohaze/current-ship.json`

This is the authoritative debug handoff schema. Every mutator MUST use Read-modify-Write: read the full file, preserve all fields, override only intended fields, and write the full object.

Create `<worktree_path>/.ohaze/current-ship.json` with:

```json
{
  "state": "running",
  "ship_mode": "debug",
  "slug": "<feature-slug>",
  "branch": "feat/<slug> or fix/<slug>",
  "base_ref": "main",
  "worktree_path": "<absolute>",
  "main_repo_path": "<absolute>",
  "investigation_path": "<absolute path to .ohaze/investigation-<slug>.md>",
  "scope_lock_files": ["<absolute>", "..."],
  "cause_hypothesis": "<string or null>",
  "plan_path": "<absolute path to codex-debug-prompt.xml inside .ohaze/>",
  "spec_path": null,
  "brief_path": null,
  "retries": 0,
  "thread_id": "<UUID or null>",
  "codex_bg_id": "<bg task id>",
  "linked_todo": "<exact todo or null>",
  "project_type": null,
  "project_category": null
}
```

Write the handoff after `codex-executor` returns dispatch metadata. If dispatch metadata is unavailable because dispatch failed, write the same schema with `state = "dispatch_failed"`, `thread_id = null`, and `codex_bg_id = null`.

## User-Facing Report

After successful dispatch, send one concise report:

```text
Codex 正在 debug worktree 中执行修复:
- worktree: <worktree_path>
- codex_bg_id: <codex_bg_id>
- thread_id: <thread_id>
- 后续: Codex 完成后会进入 /ohaze:ship-review, debug 模式会启用 scope_lock L2 和 G3 blast-radius gate.
```

## Failure Modes

- `codex` CLI missing: stop with install/auth instructions.
- User cancels systematic-debugging G1/G2: clean exit; if worktree exists, route through finishing menu Option 3 discard.
- systematic-debugging cannot form a hypothesis: stop and surface; preserve worktree for haze manual continuation.
- debug-to-codex-prompt failure: surface the error verbatim; preserve worktree.
- codex-executor dispatch failure: set `state = "dispatch_failed"`, clear `codex_bg_id` and `thread_id` to `null`, then stop.

## Notes

- This command does not call feature-development phases.
- This command does not call external Superpowers execution flows.
- This command does not call `ohaze:brainstorming`, `ohaze:writing-plans`, or `ohaze:spec-to-codex-review`.
- Worktree creation always precedes `Skill(ohaze:systematic-debugging)`.
