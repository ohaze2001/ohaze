---
name: finishing
description: Owns ohaze workflow Phase 7 — project-type/category detection, finishing menu (6 options plus conditional Security Review), ordered finish-chain execution, document finish, and modify sub-flow.
---

# Finishing (ohaze)

Own Phase 7 of `/ohaze:ship`: detect project type, present the finishing menu, execute the selected finish chain, run document finish before commits, and handle the modify sub-flow. `/ohaze:ship-review` and `/ohaze:ship-finish` invoke this skill; they do not duplicate the menu.

## Inputs

From the caller (read from `.ohaze/current-ship.json` + the latest verdict file):

- `worktree_path`, `main_repo_path`
- `base_ref`, `branch`
- `plan_path`, `spec_path`
- `retries`, `linked_todo`
- `thread_id` (for modify 2a + 6th-option ADVERSARIAL fix; `codex exec resume <thread_id>` without `--sandbox`)
- `review_verdict_path` — `<worktree_path>/.ohaze/review-verdict.json` (consumed for verdict + DOC-DRIFT items)
- `findings_detail_path` — `<worktree_path>/.ohaze/findings-detail.json` (single source of truth for ADVERSARIAL display)
- optional `brief_path` — used to inspect brief metadata such as `has_external_input: true`
- optional: `codex_bg_id`, `project_test_command`

## Detect Project Type

Detect from the **main repo**, not the linked worktree:

```bash
remote_name=$(git -C "$main_repo_path" remote 2>/dev/null | head -1)
```

- No remote output means `project_type = "local"`.
- Any remote output means `project_type = "remote"`.

Write the detected `project_type` field back into `.ohaze/current-ship.json` (Write tool, structural safety — no hook dependency).

Also detect and write `project_category` into `.ohaze/current-ship.json` using Read-modify-Write (read full file, preserve all fields, override `project_category` only). This is separate from `project_type`: `project_type` remains `local | remote` for finish preferences; `project_category` is `web | api | cli | plugin | agent | other` for Security Review routing.

Heuristic:

- Read manifest names and scripts (`package.json`, app framework config, API server files), plus brief/spec keywords if available.
- `web`: browser UI, Next/Vite/React app, public frontend.
- `api`: HTTP endpoints, webhooks, server routes, public service boundary.
- `cli`: command-line tool.
- `plugin`: Claude/Codex plugin or skill package.
- `agent`: autonomous workflow/agent runtime.
- `other`: default if uncertain.

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
- Whether ADVERSARIAL findings are present in `findings-detail.json` with `user_impact_description != null` (gates whether option 6 appears)
- Whether the conditional Security Review item is available.

Read `<worktree_path>/.ohaze/findings-detail.json` and compute:

```
findings = detail.findings or []
adversarial_user_facing = [
  f for f in findings
  if f.severity == "ADVERSARIAL" and f.user_impact_description != null
]
skipped_adversarial_count = len([
  f for f in findings
  if f.severity == "ADVERSARIAL" and f.user_impact_description == null
])
has_adversarial = len(adversarial_user_facing) > 0
```

Security Review trigger:

| Trigger | Source |
|---|---|
| `project_category in {web, api}` | `.ohaze/current-ship.json.project_category` written above |
| `has_external_input: true` | brief metadata, or explicit brief/spec language about external user input |

Use `AskUserQuestion` with question `"Codex 跑完了,接下来怎么收尾?"`. The menu has **6 options when `has_adversarial`**, **5 options otherwise**, and may show a 7th conditional item:

1. 执行推荐收尾 (一键到底)
2. 继续修改
3. 丢弃此次工作
4. 先不处理 (worktree 留着, 稍后 `/ohaze:ship-finish`)
5. 自定义收尾方案
6. **修复对抗审查后收尾** (仅当存在 ADVERSARIAL findings — 见 §6th Option below)
7. 安全审查 (可选,适用于 web/API 项目) (仅当 Security Review trigger 命中)

Option 4 does nothing destructive. Update `.ohaze/current-ship.json` so `state = "kept"`, then tell the user the worktree path and that `/ohaze:ship-finish` resumes the workflow.

Option 5 is not free text. Present the supported steps as building blocks and let the user choose an ordered chain from:

`doc-finish` / `commit` / `merge` / `push` / `pr` / `remove-worktree` / `keep-worktree`

Then execute that chain with the same step contract as the recommended chain.

> Note on AskUserQuestion: the menu has more options than a single AskUserQuestion call easily fits. Match the existing presentation pattern in this skill — group / paginate as the prior version did for 5 options, extending naturally to 6.

## 6th Option: 修复对抗审查后收尾 (conditional, ADVERSARIAL-driven)

This option only appears in the menu when `<worktree_path>/.ohaze/findings-detail.json` contains ADVERSARIAL findings where `user_impact_description != null`. Pure technical ADVERSARIAL findings are skipped by default and stay inspectable in `.ohaze/findings-detail.json`.

Before selection, display only product-language findings:

```
📋 Reviewer 审查完毕

🔴 CRITICAL / IMPORTANT: <N> 条 — Codex 在 retry loop 修复中(无需 haze 介入)

🟡 ADVERSARIAL (user-facing,需要你决策): <M> 条
  1. <user_impact_description>
     建议: fix(改 Y) / accept(接受这个 tradeoff)
  2. ...

🟢 已 skip 的纯技术细节: <K> 条
   → 完整清单: .ohaze/findings-detail.json
```

Selecting it runs an ADVERSARIAL-fix mini-loop before any terminal action:

1. **Select which ADVERSARIAL items to fix.** Use `AskUserQuestion` (multi-select) with question `"哪些对抗审查 finding 要修?"`, listing `user_impact_description` only. Do not surface raw `evidence`, file paths, function names, or `technical_description` in the haze-facing menu. The selected findings still carry technical detail from `findings-detail.json` into the Codex fix prompt.

2. **Build a fix prompt** mirroring `ohaze:codex-executor` Phase 6's structure (issues + anti-regression + action-safety + verification-loop), but with the selected ADVERSARIAL items as `<task>` content. Be explicit that these are design-level concerns the user has accepted as actionable.

3. **Write** the prompt to `<worktree_path>/.ohaze/codex-adversarial-fix.xml` via Write tool.

4. **Dispatch FOREGROUND with stdout tee** (not `run_in_background`). The user is engaged at the menu — they expect the fix to finish before continuing. More importantly: skills cannot be resumed mid-execution across a `run_in_background` turn boundary, so a backgrounded dispatch here would leave steps 5-7 (commit / re-review / finish chain) unreachable after the harness re-invoked into a slash command at top level. Foreground keeps the finishing skill alive for the entire mini-loop.

   **Foreground tees stdout to a file** so step 5's Codex-report extraction has an addressable artifact (foreground commands don't produce a `codex_bg_id`, so `BashOutput(handoff.codex_bg_id)` would read the stale ORIGINAL Phase 4 dispatch's stream — silently wrong commit messages):

   ```bash
   cd <worktree_path> && codex exec resume <thread_id> \
     "$(cat <worktree_path>/.ohaze/codex-adversarial-fix.xml)" \
     --json \
     | tee <worktree_path>/.ohaze/codex-adversarial-fix-output.jsonl
   ```

   This option remains a documented `foreground sync` exception in `ohaze:codex-executor` Dispatch Mode Vocabulary. Since codex 0.140+, `codex exec resume` accepts a top-level PROMPT argument, so we pass the fix prompt as an arg (no stdin redirect, no residual stdin silent crash surface).

   Command flag asymmetry (persistent behavior, verified against codex 0.137 through 0.144.5):
   - `codex exec resume` does **NOT** accept `--cd` (only top-level `codex exec` does). Change directory in the shell first.
   - `codex exec resume` does **NOT** accept `--sandbox`. Sandbox is inherited from the initial dispatch.

   If `thread_id` is missing, fall back to `cd <worktree_path> && codex exec resume --last "$(cat <fix prompt>)" --json | tee <output-file>` with a prominent WARNING (same fallback rule as `ohaze:codex-executor` Phase 6).

5. **Auto-commit Codex's changes** via `ohaze:codex-executor` Phase 5.0 — but pass an explicit `codex_report_source` pointing at the teed file (`<worktree_path>/.ohaze/codex-adversarial-fix-output.jsonl`), NOT `BashOutput(codex_bg_id)`. Phase 5.0's report extraction step accepts either a `codex_bg_id` (background path) or a `codex_report_source` file path (foreground path); for this mini-loop, only the latter has the just-completed fix's report. Without this override Phase 5.0 would read the original dispatch's stale stream and use wrong per-Task commit messages.

6. **Re-run review** (asked, not automatic — give the user a choice "要复验吗?"). Re-review does NOT increment the retry counter (user-initiated, not reviewer-driven). If FAIL on re-review, loop back to the menu so the user can decide next steps. If PASS (or skipped), proceed to the chosen finish chain.

7. **Then execute the finish chain** (whatever the user picks afterward — recommended or custom).

## 7th Option: Security Review (conditional)

Menu label:

```text
7. 安全审查 (可选,适用于 web/API 项目)
```

Show this item when either trigger is true:

- `project_category in {web,api}` from `current-ship.json`.
- Brief metadata or inferred brief/spec language has `has_external_input: true`.

When selected, dispatch a one-shot Codex review, foreground and synchronous, borrowing `/cso`-style coverage:

- Review OWASP Top 10.
- Review STRIDE.
- Confidence gate: only report findings with confidence ≥ 8/10.
- Every finding MUST include a concrete exploit scenario, not a vague theoretical issue.
- Every finding MUST include `user_impact_description` using the Task 4 product-language contract.

Security review findings are written into `<worktree_path>/.ohaze/findings-detail.json` as ADVERSARIAL findings, then merged into the existing 6th-option flow:

```json
{
  "severity": "ADVERSARIAL",
  "evidence": "<file:line + quoted text>",
  "technical_description": "<security issue + concrete exploit scenario>",
  "user_impact_description": "<product-language impact, or null only if purely technical>",
  "shown_to_user": <true when displayed through option 6>,
  "auto_handled": null
}
```

Append or merge these findings by reading the existing detail file, preserving existing fields, adding the new ADVERSARIAL entries, and writing the full object back. Then return to the menu so haze can use option 6 to fix or accept.

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

**真相源** = `spec_path` + `plan_path` + Codex's final report + `git diff <base_ref>..HEAD`. This is the ship scenario — Codex did the work outside the conversation, so we do NOT use neat's "对话为真相源" model.

**Codex report fallback chain** (since v2.1.3 tee — read via `ohaze:codex-executor` Phase 5.0 step 1 background path, which already encodes this order):

1. **Primary (same-session)**: `BashOutput(codex_bg_id) filter='"type":"message"'` — live stream from harness background task.
2. **Cross-session fallback (v2.1.3+)**: if `BashOutput` returns "no such task" (harness lost bg_id after `/exit`), read the persistent tee file: `Bash(tail -c 200000 <worktree_path>/.ohaze/codex-output.jsonl)` then scan for the final `agent_message` event. Phase 4 Step 2 guarantees this file exists for any v2.1.3+ dispatch.
3. **End-stage degradation**: if both Codex sources are unavailable (pre-v2.1.3 worktree or manual `.ohaze/` cleanup), doc-finish degrades gracefully — proceed with `spec_path + plan_path + git diff` only and emit one short warning: `WARNING: Codex report unavailable (codex_bg_id stale + tee file missing); doc-finish proceeding without it. CHANGELOG entries / drift detection may miss Codex-side context.` Do NOT read `codex-prompt.xml` as a fallback — that file is the INPUT prompt fed into Codex, not Codex's output, so reading it gives no information about what Codex actually did.

It handles **four classes** of document change (internalized from `neat`'s four-piece routing):

### Class 1 — Progress machine-readable contract

- Append an appropriate `[Unreleased]` or version entry to `CHANGELOG.md` at `main_repo_path`, following `~/Project/hazeflow/_shared/versioning.md ## CHANGELOG 写作风格`:
  - 单 bullet ≤ 200 字符.
  - 视角 = 消费者感知.
  - 末尾必带 commit hash (可选追加 spec/plan path link).
  - 禁内嵌过程性内容; forbidden-detail清单只引用 versioning.md, do not duplicate it here.
- Bump the manifest `version` (`package.json` / `Cargo.toml` / `.claude-plugin/plugin.json` / etc.).
- Prune the exact `linked_todo` line from the main project `ROADMAP.md` "## 当前主线" section: when found, 整行删除 (matched by the exact todo text, stored in handoff per `ship.md` Step A). WHY: `~/CLAUDE.md` iron law says "CHANGELOG 朝过去 / ROADMAP 朝未来", so shipped current-line todos leave the future dashboard instead of becoming completed checkmarks.
- Branches:
  - `linked_todo` is `null` → skip this sub-step silently (no todo was linked at ship time).
  - `linked_todo` non-null AND exact text found in `ROADMAP.md` `## 当前主线` → 整行删除; do not leave `- [x]`, `~~strikethrough~~`, or a blank line.
  - `linked_todo` non-null BUT exact text NOT found in `ROADMAP.md` `## 当前主线` (cross-version case: pre-F8 handoff captured from CLAUDE.md before the F8 contract; OR user manually edited ROADMAP between ship dispatch and finish): emit one explicit WARNING and skip the prune — `WARNING: linked_todo "<text>" not found in <main_repo_path>/ROADMAP.md ## 当前主线. Either the handoff was created before the linked_todo→ROADMAP.md contract (pre-F8), or the ROADMAP was edited mid-ship. Prune skipped; please prune manually if the todo still belongs there.` Continue to the other Class steps.
  - If pruning leaves `## 当前主线` with only its topic sentence and no todo lines, keep the topic sentence intact; this records that the current mainline is cleared without forcing an empty section rewrite.

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

### 2a — Codex 续跑

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

Write to `<worktree_path>/.ohaze/codex-modify.xml` via Write tool. Then dispatch **FOREGROUND with stdout tee** (same reasoning as the 6th-option mini-loop — user is engaged, and skills cannot be resumed mid-execution across a `run_in_background` turn boundary):

```bash
cd <worktree_path> && codex exec resume <thread_id> \
  "$(cat <worktree_path>/.ohaze/codex-modify.xml)" \
  --json \
  | tee <worktree_path>/.ohaze/codex-modify-output.jsonl
```

This modify 2a path remains a documented `foreground sync` exception in `ohaze:codex-executor` Dispatch Mode Vocabulary. Since codex 0.140+, `codex exec resume` accepts a top-level PROMPT argument, so we pass the modify prompt as an arg (no stdin redirect, no residual stdin silent crash surface).

Command flag asymmetry (persistent behavior, verified against codex 0.137 through 0.144.5):
- `codex exec resume` does **NOT** accept `--cd` (only top-level `codex exec` does). Change directory in the shell first.
- `codex exec resume` does **NOT** accept `--sandbox`. Sandbox is inherited from the initial dispatch.

If `thread_id` is missing, fall back to `cd <worktree_path> && codex exec resume --last "$(cat <modify prompt>)" --json | tee <output-file>` with a prominent WARNING.

After Codex returns (foreground), run `ohaze:codex-executor` Phase 5.0 — pass `codex_report_source=<worktree_path>/.ohaze/codex-modify-output.jsonl` so Phase 5.0 reads the just-completed modify's report (not the stale Phase 4 dispatch's `BashOutput(codex_bg_id)`). Commit pending changes with a message derived from `change_description`. Then ask whether to re-run review. Re-review does NOT increment the retry counter (user-initiated, not reviewer-driven). Loop back to the finishing menu.

### 2b — Claude 主线程直接改

Inspect relevant files with Read, apply the requested narrow edit with Edit or Write, then run the project test command if one exists:

```bash
cd <worktree_path> && <project_test_command>
```

If checks pass, commit with a suitable `refactor:` or `fix:` style message. If checks fail, report the failure and ask whether to fix or hand back. Then ask whether to re-run review and loop back to the menu.

### 2c — 我自己改 (self-edit)

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
- Codex resume in option 6 / modify 2a fails to find prior thread: fall back to fresh `codex exec` with embedded original goal, log warning.
