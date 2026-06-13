---
description: End-to-end feature shipping. BDD brief → Claude spec → Codex spec audit → worktree brief+spec → plan → Phase 3.5 default-go → Codex execute.
argument-hint: "<feature description> [--project <abs-path>]"
allowed-tools: Bash, BashOutput, Read, Write, Edit, Skill, Agent, AskUserQuestion
---

Orchestrate the ohaze v2.1 ship workflow for the user's request.

`$ARGUMENTS`

Treat `$ARGUMENTS` as the feature description, plus optional `--project <abs-path>`. If empty, ask what the user wants to ship.

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

If dirty with unrelated work, stop. Verify the four-piece docs set (`CLAUDE.md`, `README.md`, `ROADMAP.md`, `CHANGELOG.md`) only when the target project type requires it; scaffold missing files on main before shipping.

## Phase 1 — BDD Brainstorm (brief only)

Invoke `ohaze:brainstorming` with the feature description.

- Runs inside `main_repo_path`, before any worktree exists.
- Terminal state is `brief approved`.
- Spec is no longer produced in Phase 1.
- Capture the approved feature brief content and a kebab-case `slug` (≤ 4 words).

> **Phase 1 BLOCKING gate (brief approval is haze's signal, not yours):** `ohaze:brainstorming` MUST present the full brief to haze and wait for haze's explicit assent ("approve" / "通过" / "OK" / "可以" / "好" / equivalent) before declaring `brief approved`. Self-declaration based on "the template looks filled in" is forbidden. If you cannot point to a specific haze message in this conversation that gave explicit assent on the brief as a whole, you are NOT past Phase 1 — present the brief and stop until haze responds.
>
> **Phase 1 hand-off invariant:** ONCE `ohaze:brainstorming` has cleared the Brief Approval Gate and declared `brief approved`, continue in the same assistant turn to Phase 1.5. This is a return-from-subroutine signal, not a place to stop. The two are independent: gate is BLOCKING (wait for haze), hand-off is NON-BLOCKING (do not wait).

## Phase 1.5 — Claude Auto-Writes Spec

Claude writes the implementation spec from the approved brief. Haze does not review the spec by default.

### Mandatory code-reading before writing

Before writing the spec, list and read relevant files in these 4 categories:

1. Same-area existing code / content.
2. Caller-callee or producer-consumer neighbors.
3. Related existing spec / plan cross-reference.
4. CHANGELOG similar entries and prior decisions.

The spec MUST cite concrete `file:line` references. If a category is genuinely absent, state that in the spec instead of inventing context.

### 5 boundary-question triggers

Use `AskUserQuestion` only when one of these product-impact triggers is hit. Each question is single-point, not an open dialog:

1. External API choice or dependency affects functionality, cost, or launch path.
2. Deployment target or launch impact needs a product decision.
3. Significant conflict with existing patterns would break a promised brief scenario.
4. Cost / billing impact changes user or operator expectations.
5. Multiple technical options have visible tradeoff in cost, performance, or UX.

Pure technical choices such as library A vs library B with equivalent behavior, internal naming, helper extraction, or control-flow shape MUST be self-decided by Claude.

### Outputs

- Brief landing path: `<worktree>/docs/ohaze/briefs/<YYYY-MM-DD>-<slug>-brief.md`.
- Spec landing path: `<worktree>/docs/ohaze/specs/<YYYY-MM-DD>-<slug>-design.md`.
- Before the worktree exists, keep the approved brief and drafted spec in memory or a temporary main-repo `.ohaze/` artifact only if needed for Phase 1.6.
- After spec drafting, write back into the brief's `Claude 替你决定的关键技术方向` section with one line per technical decision for haze's post-hoc review.

## Phase 1.6 — Codex Audits Spec

Invoke `Skill(ohaze:spec-to-codex-review)` with:

- `brief_path`: absolute path to the brief draft/landing file.
- `spec_path`: absolute path to the spec draft/landing file.
- `code_refs`: list of absolute `file:line` refs Claude read in Phase 1.5.
- `project_type`: current project type string.
- `main_repo_path`: absolute project root.

The skill writes `<work_dir>/.ohaze/spec-review-verdict.json`. `work_dir` is `main_repo_path` before the worktree exists and `worktree_path` after it exists.

Read the verdict:

- `PASS` → proceed to Phase 2.
- `NEEDS-CLARIFICATION` → route each issue:
  - `fix-in-spec`: Claude edits the spec and reruns Phase 1.6.
  - `ask-haze`: batch all product/scope questions into one `AskUserQuestion`, edit the spec with answers, and rerun Phase 1.6.

Loop max is 2 review iterations. On iteration 3+ with remaining issues, surface 3 options to haze: accept current spec as-is / revise brief / drop feature.

If Phase 1.6 ran pre-worktree and created `<main_repo_path>/.ohaze/spec-review-verdict.json`, migrate or clean that temporary verdict after Phase 2 creates the worktree.

## Phase 2 — Worktree + Write Brief And Spec

### 2a. Create the worktree

Invoke `ohaze:using-git-worktrees` with:

- Working dir: `main_repo_path`
- Desired branch: `feat/<slug>` (`fix/<slug>` for clear regressions, `hotfix/<slug>` only for production hotfixes)

Capture `worktree_path`, assert `main_repo_path` matches, then `cd` into `worktree_path`.

### 2b. Write both brief and spec, then commit

Write:

- `docs/ohaze/briefs/<YYYY-MM-DD>-<slug>-brief.md`
- `docs/ohaze/specs/<YYYY-MM-DD>-<slug>-design.md`

Commit both on the feature branch:

```bash
git -C "$worktree_path" add docs/ohaze/briefs/<file> docs/ohaze/specs/<file>
git -C "$worktree_path" commit -m "docs(brief+spec): <slug> 设计"
```

Capture absolute `brief_path` and `spec_path`.

## Phase 3 — Plan (ohaze)

Invoke `ohaze:writing-plans`. It saves a guidance plan to `docs/ohaze/plans/<date>-<feature>.md`.

- Capture absolute `plan_path`.
- Do not invoke `superpowers:subagent-driven-development` or `superpowers:executing-plans`; Codex is the implementer.
- The skill hands back to Phase 3.5 instead of waiting.

## Phase 3.5 — Plan Summary + Default-Go

Print a one-line user-facing summary:

```text
📋 Plan 写好了 → docs/ohaze/plans/<file>.md, 拆了 <N> 个 Task,涉及 <X / Y / Z 三块>, 准备进 Codex 实现
```

Then ask one single-point `AskUserQuestion` before Phase 4 dispatch. This is the real interruption window.

Use exactly two choices:

- `go` — **Recommended**. Proceed to Phase 4 dispatch.
- `打断` — Pause before dispatch and enter the modify/cancel branch owned by `ohaze:finishing`.

Default-go semantics in v2.1 mean the recommended choice is `go` and the prompt is intentionally minimal; it does **not** mean dispatching before haze has an input boundary. If haze chooses `go`, proceed to Phase 4 immediately in the same resumed turn. If haze chooses `打断` or provides other non-go content, do not dispatch Codex; route to the modify/cancel branch. Keep the prompt product-language only and do not show task-level implementation detail unless the user explicitly asks.

## Phase 4 — Hand Off To Codex (run_in_background, no nohup, no ScheduleWakeup)

### 4a. Translate plan to XML

Invoke `ohaze:plan-to-codex-prompt` with:

- `plan_path`
- `project_test_command`: detected from project files, or `'(per-Task acceptance assertions inline in plan)'` for Markdown-only plugins.

Capture the XML prompt.

### 4b. Dispatch via `ohaze:codex-executor`

Invoke `ohaze:codex-executor` with:

- `mode`: `'dispatch'`
- `codex_prompt`: XML from 4a
- `plan_path`
- `spec_path`
- `base_ref`
- `worktree_path`
- `main_repo_path`
- `project_test_command`

The executor writes `<worktree>/.ohaze/codex-prompt.xml`, dispatches `codex exec --sandbox danger-full-access --skip-git-repo-check --cd <worktree> --json` via `Bash(run_in_background: true)`, captures `thread_id` and `codex_bg_id`, and persists them into `.ohaze/current-ship.json`.

Report that Codex is running in the background and the harness will re-invoke `/ohaze:ship-review` on completion. Do not call `ScheduleWakeup`.

## Persisting Context — `.ohaze/current-ship.json`

This is the authoritative handoff schema. Every mutator MUST use Read-modify-Write: read the full file, preserve all fields, override only the intended field(s), and write the full object.

### Step A — Link to `linked_todo`

Scan `<main_repo_path>/ROADMAP.md` `## 当前主线` for pending lines and ask once which one this ship corresponds to. Store exact text without `- [ ]`, or `null`.

### Step B — Write the handoff

Create `<worktree_path>/.ohaze/current-ship.json` with:

```json
{
  "state": "running",
  "slug": "<feature-slug>",
  "branch": "feat/<slug>",
  "base_ref": "main",
  "worktree_path": "<absolute worktree path>",
  "main_repo_path": "<absolute main repo path>",
  "brief_path": "<absolute path to docs/ohaze/briefs/<date>-<slug>-brief.md>",
  "spec_path": "<absolute path to docs/ohaze/specs/<date>-<slug>-design.md>",
  "plan_path": "<absolute path to docs/ohaze/plans/<date>-<feature>.md>",
  "spec_review_iteration": 0,
  "retries": 0,
  "thread_id": "<codex --json thread.started UUID, or null>",
  "codex_bg_id": "<Bash(run_in_background) task id>",
  "linked_todo": "<exact todo text, or null>",
  "project_type": null,
  "project_category": null
}
```

Field semantics:

- `brief_path`: Phase 2b brief file, consumed by finishing/doc-finish and Security Review trigger logic.
- `spec_review_iteration`: Phase 1.6 loop counter, default 0; separate from Phase 6 `retries`.
- `project_category`: `web | api | cli | plugin | agent | other | null`; set to `null` here and later filled by `ohaze:finishing`.
- Existing fields keep their v2.0 meanings.

### Step C — Ensure runtime paths are ignored

Ensure `.worktrees/` and `.ohaze/` are ignored. These are runtime artifacts, never committed.

## Failure Modes

- `codex` CLI missing → stop and tell user how to install/authenticate.
- User cancels during Phase 1 → stop cleanly and leave no ship artifacts.
- Phase 1.5 cannot find relevant code in a new project → note "全新模块,无历史 ref" in the spec and continue.
- Phase 1.6 verdict malformed twice → follow `spec-to-codex-review` fallback and surface the warning.
- Phase 1.6 loop exceeds 2 → haze chooses accept current spec / revise brief / drop feature.
- `ohaze:writing-plans` returns no usable plan path → stop and ask user.
- `ohaze:codex-executor` fails to dispatch → surface the error verbatim.

## Notes

- This command does not call `ScheduleWakeup`.
- This command does not call external Superpowers execution flows.
- Every phase handoff must be explicit and continue in the same turn unless the user interrupts.
