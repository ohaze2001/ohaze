---
description: End-to-end feature shipping. Brainstorm → worktree+spec → plan → Codex execute (run_in_background; harness re-invokes into /ohaze:ship-review on completion). v2.0.0 — zero runtime external skill deps, no vault, no ScheduleWakeup.
argument-hint: "<feature description> [--project <abs-path>]"
allowed-tools: Bash, BashOutput, Read, Write, Edit, Skill, Agent, AskUserQuestion
---

Orchestrate the ohaze v2 ship workflow for the user's request.

`$ARGUMENTS`

Treat `$ARGUMENTS` as the feature description, plus an optional `--project <abs-path>` flag that **explicitly** names the target project. If `$ARGUMENTS` is empty, ask the user what they want to ship before proceeding.

> **Why explicit project path:** Claude Code's harness can reset the shell cwd between turns (especially after background tasks, worktree teardowns, and re-invokes). Detecting the project via `pwd` / `git rev-parse --show-toplevel` is unreliable mid-flow — dogfood proved it. Therefore the project path is captured **once at Pre-flight** from the `--project` flag (or, on first run only, from a confirmed `pwd`), then stored in the handoff and used everywhere downstream. **Never re-detect with `pwd` later in the flow.**

## Pre-flight

### 1. Hard dependency: codex CLI

```bash
command -v codex
```

If missing, stop and tell the user to install it (`npm install -g @openai/codex`) and authenticate (`codex login`). The `codex` plugin is NOT a dependency — ship calls the `codex` CLI binary directly.

### 2. Resolve `main_repo_path` (explicit, not detected)

- If `--project <abs-path>` was passed in `$ARGUMENTS`: use that absolute path as `main_repo_path`. Verify it exists and contains a `.git` (or is a git worktree).
- Otherwise: confirm with the user via `AskUserQuestion`:
  > "未指定 --project。当前 pwd 是 `<pwd>`,作为本次 ship 的目标项目对吗?" (Yes / No / 让我重输)
  - If yes, `main_repo_path = $(git rev-parse --show-toplevel)` at this moment.
  - If no, stop and ask the user to re-invoke with `--project <abs-path>`.

Store `main_repo_path` in memory now — it goes into the handoff in step 8.

### 3. Branch safety check

Run inside `main_repo_path`:

```bash
git -C "$main_repo_path" branch --show-current
git -C "$main_repo_path" status --porcelain
```

- If the working tree is dirty with changes **not** related to this ship (any non-empty `status --porcelain` output), stop and report to the user. Do not proceed — this prevents brainstorming on a workspace that may belong to a parallel session.
- The current branch matters less here (ship will create its own feature branch in Phase 2), but mention it in the report if not on the project's default branch.

### 4. Four-piece documentation completeness (内化 md-init)

Detect project type from the manifest, then verify the four-piece set exists at `main_repo_path`:

| Project type | Required files |
|---|---|
| 发行产品 (has manifest like package.json/Cargo.toml/plugin.json + intended for external consumption) | `CLAUDE.md` + `README.md` + `ROADMAP.md` + `CHANGELOG.md` |
| 工作流项目 (internal entry, no external manifest) | `CLAUDE.md` only |
| 入口项目 (top-level planning) | not enforced |

**Only act if files are missing.** If all required files exist, skip silently — completeness checks should not interrupt the auto flow.

If any required file is missing:
1. Ask the user once via `AskUserQuestion` which project type this is (auto-detect a best guess from the manifest first).
2. For each missing file, scaffold a minimal valid stub (per the four-piece contract in the global CLAUDE.md). Commit the scaffold on the **main** branch as `docs: scaffold 四件套 for ohaze ship pre-flight` before proceeding.

The logic is internalized here — do NOT invoke any external `md-init` skill/command. This keeps ohaze self-contained.

## Phase 1 — Brainstorm (text-only, no file write)

Invoke `ohaze:brainstorming` (the self-hosted fork). Pass the feature description as the topic.

- Runs **inside `main_repo_path`** (main branch, no worktree yet). The fork is text-only — it does NOT write to `docs/superpowers/specs/` and does NOT invoke writing-plans.
- The fork's terminal state is "design approved". Wait for it.
- Capture the **approved design content** from the conversation — you will write it to a spec file in Phase 2 after the worktree exists.
- Also capture a short **feature slug** (kebab-case, ≤ 4 words, e.g. `2fa-login`, `accordion-ui`, `v2-refactor`). This becomes both the branch name suffix and the spec filename suffix. You may derive it from `$ARGUMENTS` or ask the user once if ambiguous.

## Phase 2 — Worktree + write spec (worktree-first; spec lands on feat branch, main stays clean)

### 2a. Create the worktree

Invoke `ohaze:using-git-worktrees` (the self-hosted fork). Pass:

- Working dir: `main_repo_path`
- Desired branch name: `feat/<slug>` (`fix/<slug>` if the feature is clearly a regression fix; `hotfix/<slug>` only for production hotfixes — match the global git policy in `~/CLAUDE.md`).
- Capture `worktree_path` and `main_repo_path` (the fork records `main_repo_path` automatically; you already have it from Pre-flight — assert they match).

After the fork returns, `cd` into `worktree_path` for the rest of the ship.

### 2b. Write the spec file inside the worktree, then commit on the feat branch

- Spec path: `docs/superpowers/specs/<YYYY-MM-DD>-<slug>-design.md` (use the same slug as the branch).
- Write the approved design from Phase 1, formatted as a normal spec doc.
- Commit on the feature branch:

  ```bash
  git -C "$worktree_path" add docs/superpowers/specs/<file>
  git -C "$worktree_path" commit -m "docs(spec): <slug> 设计"
  ```

- `main` is never touched in this Phase — that's the entire point of worktree-first.

Capture `spec_path` (absolute, inside worktree) for the handoff.

## Phase 3 — Plan (ohaze)

Invoke `ohaze:writing-plans`. It saves a **guidance plan** (behavior contracts + acceptance criteria, no prescriptive code bodies) to `docs/superpowers/plans/<date>-<feature>.md` inside the worktree.

- Capture `plan_path` (absolute, inside worktree).
- The skill presents an ohaze-specific 'go' prompt at the end. Wait for the user's 'go'.
- DO NOT invoke `superpowers:subagent-driven-development` or `superpowers:executing-plans` — those execution models are explicitly out of the ohaze workflow.

## Phase 4 — Hand off to Codex (run_in_background, no nohup, no ScheduleWakeup)

### 4a. Translate plan → XML prompt

Invoke `ohaze:plan-to-codex-prompt` with:

- `plan_path`: from Phase 3
- `project_test_command`: detect from the project (`package.json` → `npm test`, `Cargo.toml` → `cargo test`, `pyproject.toml` → `pytest`, etc.). If none exists (e.g., this is a Markdown-only plugin), the per-Task `Acceptance Criteria` in the plan are the verification mechanism — pass a placeholder that tells Codex this, or ask the user.

The skill returns a single XML prompt string. Capture it.

### 4b. Dispatch via `ohaze:codex-executor`

Invoke `ohaze:codex-executor` with:

- `mode`: `'dispatch'` (required — initial Phase 4 entry. Without this explicit value codex-executor's missing-mode fallback degrades to 'dispatch' anyway, but the contract requires it explicit)
- `codex_prompt`: the XML from 4a
- `plan_path`: same as Phase 3
- `spec_path`: from Phase 2b
- `base_ref`: the parent branch (typically `main`)
- `worktree_path`, `main_repo_path`: from Phase 2
- `project_test_command`: same as 4a

The executor:
1. Writes the prompt to `<worktree>/.ohaze/codex-prompt.xml` (Write tool, for shell-quoting safety).
2. Dispatches `codex exec --sandbox danger-full-access --skip-git-repo-check --cd <worktree> --json < <prompt>` via `Bash(run_in_background: true)`. **No `nohup`, no `&`, no `> log 2>&1`.**
3. Captures `thread_id` (from the first `--json` `thread.started` event) and `codex_bg_id` (the background task id returned by the harness).
4. Persists those to `.ohaze/current-ship.json`.

### 4c. Report and let go

> "Phase 1–4 完成. Codex 在后台跑 (codex_bg_id=`<id>`, thread_id=`<UUID|null>`, sandbox=`danger-full-access`).
>
> Codex 进程退出后,harness 会自动唤醒主 agent 进 `/ohaze:ship-review`, **无需 ScheduleWakeup**.
>
> 想看进度: `BashOutput <codex_bg_id>` 读流式 --json 事件.
>
> ⚠️ **请保持 session 不要 `/exit`**: 后台 codex 是当前 session 的子进程, `/exit` 会立即杀死它 (SIGHUP), 状态会永久卡在 `running`. v2.0.0 已显式放弃跨 session 韧性 (spec §3, A 方案: 无 ScheduleWakeup 兜底). 如果必须中断, 用 `Ctrl+C` 然后从 finishing 菜单 option 4 「先不处理」状态化暂停; 想完全丢弃跑 `git worktree remove --force <worktree>` 手动清理."

**Do not call `ScheduleWakeup`.** v2 control flow relies entirely on harness re-invoke after `run_in_background` completion. No fallback wakeup is set — see spec §3 A-plan and `/ohaze:ship-review`'s state-gate for ghost-wake defense.

Then the main agent's turn ends. Phase 5/6/7 happen via re-invoke + `/ohaze:ship-review`.

## Persisting context — `.ohaze/current-ship.json` (authoritative schema)

> This is the **authoritative schema** for ship handoff state. Every command/skill that reads/writes the handoff (`/ohaze:ship-review`, `/ohaze:ship-finish`, `/ohaze:status`, `ohaze:codex-executor`, `ohaze:finishing`) MUST conform to it. Adding new fields requires a spec update; removing/renaming requires a coordinated change across all consumers.

### Step A — Link to a `linked_todo` (optional precision tick)

Per the global four-piece contract (`~/CLAUDE.md`), the dashboard checkboxes live in **`ROADMAP.md` `## 当前主线`** (CLAUDE.md is for agent instructions, NOT for tracking todos). Scan `<main_repo_path>/ROADMAP.md`'s `## 当前主线` section for pending `- [ ]` lines.

If any exist, use `AskUserQuestion` to let the user pick which one (or "无对应 todo") this ship corresponds to. Store the **exact todo text without the `- [ ] ` prefix** as `linked_todo` so `doc-finish` (in `ohaze:finishing`) can later tick it precisely **inside `ROADMAP.md` `## 当前主线`**. If no pending todos exist or the user picks "无对应", set `linked_todo: null` and proceed silently.

Backward compatibility: if `ROADMAP.md` is absent (this is a 工作流项目 that only has `CLAUDE.md` — see §Pre-flight Step 4 project-type detection) OR `## 当前主线` section is missing, set `linked_todo: null` without scanning CLAUDE.md (no fallback — keeping todos out of CLAUDE.md is a contract, not a preference).

### Step B — Write the handoff file

```bash
mkdir -p <worktree_path>/.ohaze
```

Then use the **Write tool** to create `<worktree_path>/.ohaze/current-ship.json`. The Write tool is preferred for **structural safety** (the JSON contains arbitrary user strings); there is **no hook dependency** anymore — vault has been stripped from ohaze (a Bash heredoc would also work but is quoting-fragile).

Schema:

```json
{
  "state": "running",
  "slug": "<feature-slug>",
  "branch": "feat/<slug>",
  "base_ref": "main",
  "worktree_path": "<absolute path inside repo, e.g. /path/.worktrees/feat-slug>",
  "main_repo_path": "<absolute main repo path>",
  "spec_path": "<absolute path to docs/superpowers/specs/<date>-<slug>-design.md>",
  "plan_path": "<absolute path to docs/superpowers/plans/<date>-<feature>.md>",
  "retries": 0,
  "thread_id": "<codex --json thread.started UUID, or null if capture failed>",
  "codex_bg_id": "<Bash(run_in_background) task id>",
  "linked_todo": "<exact todo text from Step A, or null>",
  "project_type": null
}
```

Field semantics:

- `state` enum: `running` | `codex_done` | `review_fail` | `kept` | `self-edit-pending` | `done` | `discarded`. This is the **state gate** that `/ohaze:ship-review` (and the harness re-invoke path) consults first to decide what to do — see `/ohaze:ship-review` for the full action table.
- `slug`: used everywhere (branch name suffix, spec/plan filename suffix).
- `branch`: full branch ref (`feat/<slug>` / `fix/<slug>` / `hotfix/<slug>`).
- `worktree_path`: the linked worktree where Codex runs.
- `main_repo_path`: required for teardown (`cd "$main_repo_path"` before `git worktree remove` — see `ohaze:using-git-worktrees` "Removing a Worktree Safely").
- `thread_id`: passed to `codex exec resume <thread_id>` (without `--sandbox`) in retry / modify / 6th-option finishing flows.
- `codex_bg_id`: read with `BashOutput <codex_bg_id>` to inspect Codex progress or extract the final report.
- `linked_todo`: ticked by `doc-finish`.
- `project_type`: stays `null` here; `ohaze:finishing` detects `local` / `remote` in Phase 7 and writes it back.

**Removed in v2 (do not re-introduce):** `codex_session_id` (renamed to `thread_id`), `codex_run_id`, `codex_job_id`, `codex_pid_file`, `codex_log_file`, `codex_thread_resume`, `started_at`. All were tied to the legacy nohup+ScheduleWakeup+vault-adapter pipeline.

### Step C — Ensure `.worktrees/` and `.ohaze/` are gitignored

If `.gitignore` (at `main_repo_path`) doesn't already ignore `.worktrees/` and `.ohaze/`, add them and commit on `main` once. Both are runtime artifacts, never committed.

## Failure modes

- `codex` CLI missing → stop and tell user how to install.
- User aborts during brainstorming or plan review → stop cleanly, leave the worktree in place, do not dispatch Codex.
- `ohaze:writing-plans` returns no usable plan path → stop and ask user.
- `ohaze:codex-executor` fails to dispatch (Codex unauthenticated, etc.) → stop and surface the error verbatim.
- Working tree dirty at Pre-flight → stop; possibly a parallel session, do not auto-recover.

## Notes

- This command does NOT call `superpowers:*` skills. brainstorming + using-git-worktrees + writing-plans are all self-hosted under `plugins/ohaze/skills/`.
- This command does NOT call `superpowers:subagent-driven-development` or `superpowers:executing-plans`. Codex is the implementer.
- This command does NOT call `superpowers:finishing-a-development-branch`. That happens in `ohaze:finishing` (Phase 7), invoked via `/ohaze:ship-review`.
- This command does NOT call `ScheduleWakeup`. v2 control flow = `run_in_background` + harness re-invoke + idempotent state gate. The state gate in `/ohaze:ship-review` is the only ghost-wake defense.
