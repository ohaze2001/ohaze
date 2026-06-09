---
name: finishing
description: Owns ohaze workflow Phase 7 — project-type detection, finishing menu (6 options; 6th appears only when ADVERSARIAL findings exist), ordered finish-chain execution, document finish (neat-style four-piece routing internalized), and modify sub-flow. Invoked by ship-review.md and ship-finish.md.
---

# Finishing (ohaze)

Own Phase 7 of `/ohaze:ship`: detect project type, present the finishing menu, execute the selected finish chain, run document finish before commits, and handle the modify sub-flow. `/ohaze:ship-review` and `/ohaze:ship-finish` invoke this skill; they do not duplicate the menu.

## Inputs

From the caller (read from `.ohaze/current-ship.json` + the latest verdict file):

- `worktree_path`, `main_repo_path`
- `base_ref`, `branch`
- `plan_path`, `spec_path`
- `retries`, `linked_todo`
- `thread_id` (for modify 5a + 6th-option ADVERSARIAL fix; `codex exec resume <thread_id>` without `--sandbox`)
- `review_verdict_path` — `<worktree_path>/.ohaze/review-verdict.json` (consumed for ADVERSARIAL items + DOC-DRIFT items)
- optional: `codex_bg_id`, `project_test_command`

## Detect Project Type

Detect from the **main repo**, not the linked worktree:

```bash
remote_name=$(git -C "$main_repo_path" remote 2>/dev/null | head -1)
```

- No remote output means `project_type = "local"`.
- Any remote output means `project_type = "remote"`.

Write the detected `project_type` field back into `.ohaze/current-ship.json` (Write tool, structural safety — no hook dependency).

## Finish Preferences

Read `~/.ohaze/finish-prefs.json` best-effort. Use the entry matching `project_type` as the recommended chain.

If `~/.ohaze/finish-prefs.json` does not exist, the matching entry is absent, or the JSON is damaged, fall back to the built-in defaults. Damaged JSON is non-blocking; tell the user one short warning and continue.

Built-in default chains:

```json
{
  "local": ["doc-finish", "commit", "merge", "remove-worktree"],
  "remote": ["doc-finish", "commit", "merge", "push", "remove-worktree"]
}
```

When the user chooses menu option 1 or option 5 (custom), write the final chain back to `~/.ohaze/finish-prefs.json` under the detected `project_type`. Preference read/write failures are best-effort and must not block finishing.

## Menu

Before asking, print:

- Detected `project_type`: `local` or `remote`
- Full recommended chain, in order, so the user can see exactly what option 1 will do
- Whether ADVERSARIAL findings are present in `review_verdict_path.issues` (gates whether option 6 appears)

Read `review_verdict_path` and compute:

```
adversarial = [i for i in verdict.issues if i.startswith("ADVERSARIAL:")]
has_adversarial = len(adversarial) > 0
```

Use `AskUserQuestion` with the menu. The menu has **6 options when `has_adversarial`**, **5 options otherwise** (the 6th is conditionally shown):

1. 执行推荐收尾 (一键到底)
2. 继续修改
3. 丢弃此次工作
4. 先不处理 (worktree 留着, 稍后 `/ohaze:ship-finish`)
5. 自定义收尾方案
6. **修复对抗审查后收尾** (仅当存在 ADVERSARIAL findings — 见 §6th Option below)

Option 4 does nothing destructive. Update `.ohaze/current-ship.json` so `state = "kept"`, then tell the user the worktree path and that `/ohaze:ship-finish` resumes the workflow.

Option 5 is not free text. Present the supported steps as building blocks and let the user choose an ordered chain from:

`doc-finish` / `commit` / `merge` / `push` / `pr` / `remove-worktree` / `keep-worktree`

Then execute that chain with the same step contract as the recommended chain.

> Note on AskUserQuestion: the menu has more options than a single AskUserQuestion call easily fits. Match the existing presentation pattern in this skill — group / paginate as the prior version did for 5 options, extending naturally to 6.

## 6th Option: 修复对抗审查后收尾 (conditional, ADVERSARIAL-driven)

This option only appears in the menu when the latest `review-verdict.json.issues` contains entries prefixed `ADVERSARIAL:`. Selecting it runs an ADVERSARIAL-fix mini-loop before any terminal action:

1. **Select which ADVERSARIAL items to fix.** Use `AskUserQuestion` (multi-select) listing the ADVERSARIAL findings verbatim. The user can pick any subset (including all). If they pick none, return to the menu unchanged.

2. **Build a fix prompt** mirroring `ohaze:codex-executor` Phase 6's structure (issues + anti-regression + action-safety + verification-loop), but with the selected ADVERSARIAL items as `<task>` content. Be explicit that these are design-level concerns the user has accepted as actionable.

3. **Write** the prompt to `<worktree_path>/.ohaze/codex-adversarial-fix.xml` via Write tool.

4. **Dispatch** via `Bash(run_in_background: true)` (same pattern as Phase 4 / Phase 6):

   ```bash
   codex exec resume <thread_id> \
     --cd <worktree_path> \
     --json \
     < <worktree_path>/.ohaze/codex-adversarial-fix.xml
   ```

   `codex exec resume` MUST NOT include `--sandbox` (codex 0.137 rejects it; sandbox is inherited from initial dispatch). If `thread_id` is missing, fall back to `codex exec resume --last` with a prominent WARNING (same fallback rule as the retry loop).

5. **Wait for harness re-invoke** (same control flow as the rest of v2 — no ScheduleWakeup, no polling).

6. **Auto-commit Codex's changes** via `ohaze:codex-executor` Phase 5.0 (same as retry / modify).

7. **Re-run review** (asked, not automatic — give the user a choice "要复验吗?"). Re-review does NOT increment the retry counter (user-initiated, not reviewer-driven). If FAIL on re-review, loop back to the menu so the user can decide next steps. If PASS (or skipped), proceed to the chosen finish chain.

8. **Then execute the finish chain** (whatever the user picks afterward — recommended or custom).

## Chain Execution Contract

Execute a finish chain one step at a time, in order. Valid steps are:

- `doc-finish`
- `commit`
- `merge`
- `push`
- `pr`
- `remove-worktree`
- `keep-worktree`

After each step, check its success criterion: command exit code and, where relevant, expected git state or expected output. **任一步失败立即中止**: do not execute later steps, report the failed step name plus the original error text, preserve `.ohaze/current-ship.json` in a recoverable state, and return to the menu.

Hard constraint: **merge 成功 push 失败禁止删 worktree**. If `merge` succeeds but `push` fails, do not execute `remove-worktree`; keep the worktree and branch so the user can retry or recover the push.

## Step: doc-finish (内化 neat 路由)

`doc-finish` is the document finishing step and it must run before `commit`. It combines progress-contract updates and drift repair into one preview patch before any docs commit is created.

**真相源** = `spec_path` + `plan_path` + Codex's final report (read via `BashOutput <codex_bg_id>` from the `--json` stream, or from the saved `codex-prompt.xml` log) + `git diff <base_ref>..HEAD`. This is the ship scenario — Codex did the work outside the conversation, so we do NOT use neat's "对话为真相源" model.

It handles **four classes** of document change (internalized from `neat`'s four-piece routing):

### Class 1 — Progress machine-readable contract

- Append an appropriate `[Unreleased]` or version entry to `CHANGELOG.md` at `main_repo_path`.
- Bump the manifest `version` (`package.json` / `Cargo.toml` / `.claude-plugin/plugin.json` / etc.).
- Tick the exact `linked_todo` line in the main project `CLAUDE.md` "当前主线" section (or wherever the `- [ ]` lives) from `- [ ]` to `- [x]`.

### Class 2 — Drift repair (from review-verdict.json)

- Read `review_verdict_path.doc_drift` (string array of `<section>: <description>` items).
- Generate a synchronization patch for descriptive sections in the target project's `CLAUDE.md` / `README.md`.

### Class 3 — Forward-looking items (待办 / bug → ROADMAP)

Scan the spec / plan / Codex report for forward-looking items the ship surfaced but did not finish:

- 待办 / 新想法 / 下一步 → `ROADMAP.md` `## Backlog` (新条目, 按优先级追加; 置顶 = 下一步)
- 发现的 bug → `ROADMAP.md` `## Bug`

Do NOT log these in `CHANGELOG.md` (CHANGELOG is for done-and-shipped only — global契约).

### Class 4 — Architecture / convention / command changes (README + CLAUDE.md)

- 架构 / 约定变更 → `README.md` (人读) + `CLAUDE.md` (约束)
- 命令 / 入口变更 → `README.md`

### Boundary

止于四件套. 绝不写入 vault 决策层 (不向 ~/Brain 任何目录写). 措辞上避开直接列举 vault 内部目录名, 防与 acceptance grep 自我误伤.

### Preview and apply

Merge all four classes into one patch preview. Present the preview to the user and offer:

- Accept all
- Skip all
- Select individual hunks / items

Apply only the accepted parts. If there are no document changes, skip this step silently.

Document changes are committed by the chain's `commit` step as a separate `docs:` commit. Code changes should already have been committed before review by `ohaze:codex-executor` Phase 5.0.

## Step: commit

Commit pending accepted document changes before terminal actions.

- If there are accepted `doc-finish` changes, create a separate `docs:` commit on the feature branch (inside the worktree).
- If the worktree is clean, this step succeeds without creating a commit.
- Do not bypass hooks.

## Step: merge

Merge the work branch into `<base_ref>` in the main repo.

```bash
git -C "$main_repo_path" checkout <base_ref>
git -C "$main_repo_path" merge <branch> --ff-only
```

(No more `PRE_MERGE_COMMITS` / `PRE_MERGE_COUNT` pre-computation — that was a vault-adapter workaround for a `commits=0` artifact and is unneeded now that vault is stripped.)

If `--ff-only` fails because `<base_ref>` advanced during the ship, surface the error and ask:

> Fast-forward 失败 — `<base_ref>` 在 ship 期间有新提交。选项:
> 1. 创建 merge commit (`git merge --no-ff <branch>`)
> 2. 退出, 我自己处理 (rebase 或 cherry-pick)

If the user picks 1, run `git merge <branch> --no-ff -m "merge: <feature> via ohaze"`. If the user picks 2, stop and keep the handoff for `/ohaze:ship-finish`.

## Step: push

```bash
git -C <worktree_path> push -u origin <branch>
```

If push fails (no remote, auth, rejected update, anything), surface the error verbatim, stop the chain, keep `.ohaze/current-ship.json`, keep the branch and worktree, return to the menu. If this follows a successful `merge`, the "merge 成功 push 失败禁止删 worktree" rule applies.

## Step: pr

Push the branch if needed, then create a PR:

```bash
git -C <worktree_path> push -u origin <branch>
gh pr create --base <base_ref> --head <branch> --title "<derived from spec or commit>" --body "<see template>"
```

PR body:

```markdown
Generated via /ohaze:ship.

**Spec:** <spec_path>
**Plan:** <plan_path>
**Codex retries:** <retries>
**Reviewer verdict:** PASS

Auto-generated by ohaze.
```

If push or `gh pr create` fails, surface the exact error, stop the chain, preserve the handoff and worktree, return to the menu.

## Step: remove-worktree (cd back to main_repo_path FIRST)

For every terminal action (`merge`, `push`, `pr`, `discard`), do **NOT** write `ship-result.json` or anything similar — that file was a vault-adapter trigger and is gone in v2. Cleanup order is now simply:

1. `rm <worktree_path>/.ohaze/current-ship.json` (handoff is consumed; ship is finished).
2. **`cd "$main_repo_path"` BEFORE the worktree removal** — see `ohaze:using-git-worktrees` "Removing a Worktree Safely" for the cwd-dangling root cause (CC upstream #50960).
3. Remove the worktree and branch:

   ```bash
   cd "$main_repo_path"
   git worktree remove <worktree_path>
   git branch -D <branch>
   ```

For `discard`, confirm with the user first, then (still after `cd "$main_repo_path"`):

```bash
cd "$main_repo_path"
git worktree remove --force <worktree_path>
git branch -D <branch>
```

Set `.ohaze/current-ship.json.state` (in memory, file already removed) appropriately for final reporting: `done` for merge/push/pr success paths, `discarded` for the discard path. (The file is removed in step 1, so the state value lives only in the final summary printout.)

`keep-worktree` leaves the worktree in place and reports its path; in that case, do not remove `current-ship.json` — set `state = "kept"` instead.

## Modify Sub-Flow (option 2)

After any modify branch completes, loop back to the finishing menu (5 or 6 options depending on whether ADVERSARIAL findings still exist).

Ask the user for `change_description`, then who handles it:

1. Codex 续跑 (适合需要遵循 plan 风格, 跨文件改动)
2. Claude 主线程直接改 (适合改名, 加注释, 修单行 bug)
3. 我自己改 (退出, 我去 .worktrees 改完跑 /ohaze:ship-finish 回来)

### 5a — Codex 续跑

Build a delta prompt:

```xml
<task>
The implementation in this worktree was reviewed and approved, but the user wants this small adjustment before finishing:

{change_description}

Apply the change. Stay narrow — only this adjustment, do not refactor anything else.
</task>

<commit_handling>
ohaze orchestrator handles commits — leave changes uncommitted; the main session will commit with a `refactor:` or `fix:` style message.
</commit_handling>

<verification_loop>
After applying, run `{project_test_command}` (or the per-Task acceptance assertions for Markdown-only projects). All must pass.
</verification_loop>

<action_safety>
- Only the requested adjustment, nothing else.
- No new dependencies.
- Don't touch unrelated files.
</action_safety>
```

Write to `<worktree_path>/.ohaze/codex-modify.xml` via Write tool. Then dispatch:

```bash
codex exec resume <thread_id> \
  --cd <worktree_path> \
  --json \
  < <worktree_path>/.ohaze/codex-modify.xml
```

**No `--sandbox`** — sandbox is inherited from the initial dispatch and `codex exec resume` rejects the flag.

Dispatch via `Bash(run_in_background: true)` so the harness re-invokes the main agent on completion (same control flow as everywhere else in v2). If `thread_id` is missing, fall back to `codex exec resume --last` with a prominent WARNING.

After harness re-invokes and Codex returns, run `ohaze:codex-executor` Phase 5.0 to commit pending changes with a message derived from `change_description`. Then ask whether to re-run review. Re-review does NOT increment the retry counter (user-initiated, not reviewer-driven). Loop back to the finishing menu.

### 5b — Claude 主线程直接改

Inspect relevant files with Read, apply the requested narrow edit with Edit or Write, then run the project test command if one exists:

```bash
cd <worktree_path> && <project_test_command>
```

If checks pass, commit with a suitable `refactor:` or `fix:` style message. If checks fail, report the failure and ask whether to fix or hand back. Then ask whether to re-run review and loop back to the menu.

### 5c — 我自己改 (self-edit)

Update `.ohaze/current-ship.json` with `state = "self-edit-pending"`. Tell the user:

> 退出当前 session. 去 `<worktree_path>` 改完代码后, 跑 `/ohaze:ship-finish` 回来继续 — 状态门会从正确位置接续。

Stop.

## Final Summary

After terminal actions, print:

- Spec path
- Plan path
- Codex retries used
- Modify-loop iterations, if any
- ADVERSARIAL-fix iterations, if any (option 6)
- Final disposition (`done` / `discarded` / `kept`)

## Failure Modes

- Preference read/write failure: warn briefly if useful, then continue with defaults.
- Damaged `~/.ohaze/finish-prefs.json`: warn once and use built-in defaults.
- Handoff malformed or missing required fields: stop and report the broken field.
- Worktree missing or detached: stop and ask for manual intervention.
- Push/PR failure: surface the exact error and return to the menu.
- Merge `--ff-only` failure: use the merge-commit vs exit prompt above.
- Codex resume in option 6 / modify 5a fails to find prior thread: fall back to fresh `codex exec` with embedded original goal, log warning.
