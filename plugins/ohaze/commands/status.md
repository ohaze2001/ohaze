---
description: Show ohaze workflow status across all worktrees of the current project — what's running, what's waiting for review, what's stale, what's done. Read-only.
argument-hint: ""
allowed-tools: Bash, BashOutput, Read
---

Render a consolidated status view of all ohaze workflows in the current git project. This command is **read-only** — it never modifies any worktree, handoff, or branch.

`$ARGUMENTS`

## Step 1 — Establish project root

```bash
project_root=$(git rev-parse --show-toplevel 2>/dev/null)
```

If that fails (not a git repo), tell the user "Not inside a git repository. Run /ohaze:status from a project root." and stop.

## Step 2 — Enumerate worktrees

```bash
git -C "$project_root" worktree list --porcelain
```

The output blocks look like:

```
worktree /path/to/main
HEAD <sha>
branch refs/heads/main

worktree /path/to/.worktrees/feat-foo
HEAD <sha>
branch refs/heads/feat/foo
```

Parse each block into `{path, branch, head_sha}`.

## Step 3 — Per-worktree state

For each worktree, gather:

### 3.1 — git status

```bash
git -C <path> status --short
```

- Empty → 干净
- Non-empty → 有未提交改动

### 3.2 — ohaze handoff

Does `<path>/.ohaze/current-ship.json` exist?

- If yes, parse and capture (per the authoritative schema in `commands/ship.md`): `state`, `slug`, `branch`, `plan_path`, `retries`, `thread_id`, `codex_bg_id`, `linked_todo`.
- If no, this worktree is not in an active ship.

The fields `codex_pid_file` / `codex_log_file` / `codex_job_id` / `codex_run_id` / `codex_session_id` / `started_at` are **legacy v1 fields** — they no longer exist in v2 handoffs. If you encounter them in an old handoff (predating v2.0.0), surface a one-line note ("legacy v1 handoff detected, fields ignored") and continue with whatever v2 fields are present.

### 3.3 — Codex job state (state-first; no pid polling)

Use the handoff's `state` field as the **primary judge**:

| `state` | Display |
|---|---|
| missing handoff | 闲置 |
| `running` | Codex 跑中 |
| `codex_done` | 等审查 |
| `review_fail` | 修复中 (retry N/3) |
| `kept` | 等 finish (option 4 暂存) |
| `self-edit-pending` | 等手改后 finish (option 2c) |
| `done` | 已完成 (一般 handoff 已被 finishing 删除; 若仍在, 是异常) |
| `discarded` | 已丢弃 (同上, 异常) |

`codex_bg_id` is only used for **deeper inspection on demand** (not for liveness judgment). If the user wants to see Codex's streamed output, they can run `BashOutput <codex_bg_id>` directly. Do NOT shell out to `kill -0 <pid>` or `ps -p <pid>` — those mechanisms predate `run_in_background` and have no place in v2 status.

### 3.4 — Last activity

Modification time of newest file in the worktree:

```bash
find "<path>" -type f -not -path '*/node_modules/*' -not -path '*/.git/*' -printf '%T@\n' 2>/dev/null | sort -n | tail -1
```

Compute days since now. If > 7 days and the worktree is not the main, mark as 🟡 stale.

## Step 4 — Remote PRs (best effort)

```bash
gh pr list --json number,title,state,headRefName,isDraft,reviewDecision 2>/dev/null
```

If `gh` is unavailable or fails, skip this section silently. Don't error.

## Step 5 — Render output

```
项目: <basename> (<project_root>)

📍 主目录    <branch>   <git status summary>   <last activity human time>

🔧 worktrees:
  ┌─ <name>            分支:<branch>   状态: <emoji> <state-derived text>
  │                                       下一步: <hint command>
  ├─ ...
  └─ ...

📊 远端 PRs (gh):
  #<num> <title>   <state>   <branch>   <reviewDecision>
  ...

⚠️ 提醒:
  - <name>: 7 天没动, 考虑 git worktree remove .worktrees/<name>
  - <name>: review 失败 3 次, 用 /ohaze:ship-review --more 强制续跑或手动介入
```

### Status icon mapping (state-driven)

| 情况 | icon | 文字 | 下一步 |
|---|---|---|---|
| 无 ohaze 任务 | ⚪ | 闲置 | — |
| `state = running` | 🟡 | Codex 跑中 (slug=<slug>) | 等 harness re-invoke, 或 `BashOutput <codex_bg_id>` 看流 |
| `state = codex_done` | 🟢 | 等审查 | `cd <path> && /ohaze:ship-review` |
| `state = review_fail` (retries < 3) | 🟠 | 修复中 (retry N/3) | 等 harness re-invoke, 或 `/ohaze:ship-review` |
| `state = review_fail` (retries >= 3) | 🔴 | 审查卡住 | 手动介入或 `/ohaze:ship-review --more` |
| `state = kept` | 🟢 | 等 finish | `cd <path> && /ohaze:ship-finish` |
| `state = self-edit-pending` | 🟡 | 等手改后 finish | `cd <path>` 改完跑 `/ohaze:ship-finish` |
| `state = done` / `discarded` (handoff 残留) | ⚠️ | 异常残留 | 手动清掉 `<path>/.ohaze/current-ship.json` |
| 工作树脏 + 无 handoff | 🟡 | 有未提交改动 | `cd <path> && /ohaze:ship-finish` (会进 self-edit 检测) |
| 7 天未动 | 🟡 | stale | `git worktree remove <path>` |

## Step 6 — Summary line

After the table, print one line summarizing total state:

```
共 N 个 worktree | 1 跑中 | 2 等审查 | 1 stale | 3 远端 PR
```

## Failure modes

- `git worktree list` returns no output: just show the main worktree, note "no .worktrees/ directories"
- handoff JSON malformed: skip that worktree's handoff fields, log a single line warning
- gh not authenticated: skip PR section silently

## Notes

- This command is **read-only**. It must not modify any worktree state, never auto-cleanup.
- If you're considering offering "auto-cleanup stale worktrees", that's a separate feature; do not bundle it here.
- Resolve all paths to absolute paths in the output for unambiguous copy-paste.
- v2 control flow note: liveness judgment is **state-first** (handoff field), not pid-first. The `run_in_background` task is owned by the harness, not by ohaze; we read its output on demand (`BashOutput`) but never poll its pid.
