---
description: Show ohaze workflow status across all worktrees of the current project — what's running, what's waiting for review, what's stale.
argument-hint: ""
allowed-tools: Bash, Read
---

Render a consolidated status view of all ohaze workflows in the current git project.

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

1. **git status** — `git -C <path> status --short`
   - Empty → "干净"
   - Non-empty → "有未提交改动"

2. **ohaze handoff** — does `<path>/.ohaze/current-ship.json` exist?
   - If yes, parse and capture: `plan_path`, `started_at`, `retries`, `codex_job_id`, `codex_pid_file`, `codex_log_file` (older handoffs may have `codex_run_id` instead)
   - If no, this worktree is not in an active ship

3. **Codex job state** (only if handoff exists):
   ```bash
   # If codex_pid_file is set (new style — codex exec direct invocation):
   if [[ -f "$codex_pid_file" ]]; then
     pid=$(cat "$codex_pid_file")
     if kill -0 "$pid" 2>/dev/null; then
       status=running
       elapsed=$(ps -p "$pid" -o etime= | tr -d ' ')
     else
       # Process done. Tail log to check pass/fail.
       if grep -q "Final test status: PASS" "$codex_log_file" 2>/dev/null; then
         status=completed
       elif grep -q "Final test status: FAIL" "$codex_log_file" 2>/dev/null; then
         status=failed
       else
         status=completed  # finished without explicit verdict; treat as done
       fi
     fi
   fi
   ```

   Back-compat: legacy handoffs that predate 1.7.0 may carry only `codex_run_id` with no `pid_file`. For those, mark the codex job state as `unknown` — the codex plugin / `codex-companion.mjs` is no longer a dependency and is not consulted.

4. **Last activity** — modification time of newest file in worktree:
   ```bash
   find "<path>" -type f -not -path '*/node_modules/*' -not -path '*/.git/*' -printf '%T@\n' 2>/dev/null | sort -n | tail -1
   ```
   Compute days since now. If > 7 days and worktree is not the main, mark as `🟡 stale`.

## Step 4 — Remote PRs (best effort)

```bash
gh pr list --json number,title,state,headRefName,isDraft,reviewDecision 2>/dev/null
```

If `gh` is unavailable or fails, skip this section silently. Don't error.

## Step 5 — Render output

Use this exact layout:

```
项目: <basename> (<project_root>)

📍 主目录    <branch>   <git status summary>   <last activity human time>

🔧 worktrees:
  ┌─ <name>            分支:<branch>   状态: <emoji icon> <status text>
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

### Status icon mapping

| 情况 | icon | 文字 | 下一步 |
|---|---|---|---|
| 无 ohaze 任务 | ⚪ | 闲置 | — |
| Codex running | 🟡 | Codex 跑中 (job_id, elapsed) | `tail -f <codex_log_file>` |
| Codex completed, 未审查 | 🟢 | 等审查 | `cd <path> && /ohaze:ship-review` |
| review PASS, 未 finish | 🟢 | 等 finish | `cd <path> && /ohaze:ship-finish` |
| review FAIL, retries < 3 | 🟠 | 修复中 (retry N/3) | 等待续跑或 `/ohaze:ship-review --more` |
| review FAIL, retries >= 3 | 🔴 | 审查卡住 | 手动介入或 `/ohaze:ship-review --more` |
| 工作树脏 + 无 handoff | 🟡 | 有未提交改动 | `cd <path> && /ohaze:ship-finish` |
| 7 天未动 | 🟡 | stale | `git worktree remove <path>` |

## Step 6 — Summary line

After the table, print one line summarizing total state:

```
共 N 个 worktree | 1 跑中 | 2 等审查 | 1 stale | 3 远端 PR
```

## Failure modes

- `git worktree list` returns no output: just show the main worktree, note "no .worktrees/ directories"
- handoff JSON is malformed: skip that worktree's handoff fields, log a single line warning
- gh not authenticated: skip PR section silently

## Notes

- This command is **read-only**. It must not modify any worktree state, never auto-cleanup.
- If you're considering offering "auto-cleanup stale worktrees", that's a separate feature; do not bundle it here.
- Resolve all paths to absolute paths in the output for unambiguous copy-paste.
