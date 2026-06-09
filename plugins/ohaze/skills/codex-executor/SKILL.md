---
name: codex-executor
description: Use when the ohaze workflow needs to dispatch a plan to Codex and run the post-execution adversarial review loop. Owns Codex dispatch (run_in_background, thread_id capture, no nohup), cross-source review (general-purpose subagent + real test run), and the up-to-3-retry review-fix cycle with stuck-detection upgrade.
---

# Codex Executor (ohaze)

Hand a translated XML prompt to Codex via the `codex` CLI, then run the Claude-side cross-source review loop. Owns Phases 4–6 of `/ohaze:ship`.

## When to invoke

- Inside `/ohaze:ship` after `ohaze:plan-to-codex-prompt` produces an XML prompt.
- Inside `/ohaze:ship-review` (after the harness re-invokes the main agent because the background Codex run completed) to run the review-fix loop.
- Inside `ohaze:finishing` Step 5a (modify sub-flow) or Step 6 (修复对抗审查后收尾) to dispatch a follow-up fix.

## Inputs

- `codex_prompt` (required): the full XML string from `ohaze:plan-to-codex-prompt`.
- `plan_path` (required): the absolute path to the plan markdown, used by the reviewer.
- `base_ref` (required): the git ref Codex's work started from (typically the worktree's parent branch, e.g. `main`).
- `worktree_path` (required for review/retry): the ship worktree path.
- `project_test_command` (required for review): the command the reviewer runs to verify behavior (e.g. `npm test`, `pytest`).
- `thread_id` (optional but expected for retry): read from `.ohaze/current-ship.json`; used for exact `codex exec resume <thread_id>`.

## Phase 4: Dispatch Codex (`run_in_background`, full-access sandbox on the initial dispatch)

ohaze dispatches `codex exec` directly with `--sandbox danger-full-access` because ship plans legitimately need writes outside the worktree (cross-project paths, global settings, etc.). The trust boundary is at `/ohaze:ship` invocation — brainstorm → plan → adversarial review have already gated this.

### Step 1 — Write prompt to a file (avoid shell quoting hell)

```bash
mkdir -p <worktree_path>/.ohaze
PROMPT_FILE=<worktree_path>/.ohaze/codex-prompt.xml
# Use the Write tool to write the full XML string to PROMPT_FILE
```

Use the Write tool (not a heredoc) for the prompt file — the XML contains backticks, dollar signs, and other shell metachars. The reason is **structural safety**, not hook triggering (vault has been stripped from ohaze; no hook fires here).

### Step 2 — Background-dispatch `codex exec`

Use Claude Code's `Bash` tool with `run_in_background: true`. The harness tracks the background task and re-invokes the main agent automatically when the process exits.

```bash
codex exec \
  --sandbox danger-full-access \
  --skip-git-repo-check \
  --cd <worktree_path> \
  --json \
  < <prompt_file>
```

**Strict rules for this dispatch:**

- **No `nohup`, no trailing `&`, no `> log 2>&1`, no `echo $! > pid_file`** — the harness owns process tracking via `run_in_background`. Those legacy mechanisms predate harness re-invoke and have been removed.
- **Must include `--json`** so we can parse the streamed event log for `thread.started` and the final message.
- **Must run inside a real git project directory** (`--cd <worktree_path>` points at the ship worktree). codex exec exits non-zero in `/tmp` or any non-git path.

### Step 3 — Capture `thread_id` and `codex_bg_id`

- `codex_bg_id` = the background task id returned by Claude Code's `Bash(run_in_background: true)`. The main agent uses `BashOutput(codex_bg_id)` later to read the streamed `--json` events.
- `thread_id` = the UUID emitted in the **first** `--json` event:

  ```
  {"type":"thread.started","thread_id":"<UUID>"}
  ```

  The field name is **`thread_id`** (not `session_id`), matching the filename UUID in `~/.codex/sessions/.../rollout-*-<UUID>.jsonl`. Read the first few lines of the background output with `BashOutput` to extract it.

  If the first event cannot be parsed (rare — codex error before thread start), set `thread_id` to JSON `null`, surface one visible warning to the user, and continue. The retry path will then have to use the `--last` fallback (see Phase 6).

### Step 4 — Persist to handoff

Update `.ohaze/current-ship.json` to record:

```json
{
  ...
  "state": "running",
  "thread_id": "<UUID or null>",
  "codex_bg_id": "<background task id>"
}
```

The authoritative `current-ship.json` schema is defined in `commands/ship.md`; this skill only writes the Phase 4 fields. Legacy fields `codex_session_id` / `codex_run_id` / `codex_job_id` / `codex_pid_file` / `codex_log_file` / `codex_thread_resume` / `started_at` are **gone** — do not re-introduce them.

### Step 5 — Report and let go

Don't poll, don't sleep, don't `ScheduleWakeup`. Report to the user and return control to the caller; the main agent's turn ends. The harness will re-invoke the main agent when the background codex task exits, and `/ohaze:ship-review`'s idempotent state gate will pick up from there.

> "Codex 在后台跑 (codex_bg_id=`<id>`, thread_id=`<UUID|null>`, sandbox=`danger-full-access`).
> 进程完成后 harness 会自动唤醒主 agent 进 review,无需手动触发。
> 中途想看进度: `BashOutput <codex_bg_id>` 读流式 --json 事件。"

## Phase 5: Claude-side Review (cross-source + real test run)

Triggered when the background Codex task completes — the harness re-invokes the main agent, `/ohaze:ship-review`'s pre-flight state gate sees `state == "codex_done"`, and dispatches review. The user can also invoke `/ohaze:ship-review` manually; the state gate handles both entry paths identically.

### Phase 5.0: Apply Codex's pending changes as commits (REQUIRED)

ohaze keeps commit authority at the orchestrator (Claude main session) by convention — see `plan-to-codex-prompt`'s `<commit_handling>`. Codex therefore leaves uncommitted changes in the worktree; the orchestrator commits them before review.

1. Read Codex's final report from the `--json` stream via `BashOutput(codex_bg_id)`. The final `message` event contains the structured report (Tasks completed / Touched files / Notable choices / suggested per-Task commit messages). **Do not rely on `-o/--output-last-message`** — that flag does not produce a file when `--json` is set (verified against codex 0.137 in dogfood).

2. Inspect what Codex left behind:

   ```bash
   git -C <worktree_path> status --short
   git -C <worktree_path> diff
   ```

3. If there are uncommitted changes:
   - **Single Task changed**: stage all changes and commit with the single suggested message from Codex's report.
   - **Multiple Tasks (multiple suggested messages)**: try to split per-Task using the plan's `Files:` sections to determine which files belong to which Task. If splitting is not feasible (files overlap), fall back to one combined commit using the LAST suggested message.
   - If `git commit` fails (hooks, etc.), surface the error and stop. Do NOT bypass hooks.

4. If the working tree is already clean (Codex committed itself, or there were no changes), skip step 3.

After Phase 5.0, transition `current-ship.json.state = "codex_done"` if it isn't already.

### Phase 5.1: Compute the diff to review

```bash
git -C <worktree_path> diff <base_ref>...HEAD
git -C <worktree_path> log --oneline <base_ref>..HEAD
```

### Phase 5.2: Dispatch the reviewer subagent (异源对抗写死)

The reviewer **MUST** be a `general-purpose` subagent (which inherits the Opus main model), deliberately cross-source from Codex. The cross-source design is the whole point of ohaze's adversarial review — do not change this to a Codex self-review or `codex exec review`; both are same-source and architecturally invalid.

```
Agent(
  subagent_type="general-purpose",
  description="Adversarially review Codex implementation against plan (real test run required)",
  prompt=<see review prompt template below>
)
```

### Phase 5.3: Write `review-verdict.json`

After the reviewer returns, write the verdict to disk. The Write tool is preferred for structural safety (the JSON contains arbitrary user strings; heredocs are quoting hazards), but there is **no hook dependency** — vault has been stripped from ohaze.

Target file: `<worktree_path>/.ohaze/review-verdict.json`.

Content shape:

```json
{
  "iteration": <current_retry_count>,
  "verdict": "<PASS|FAIL>",
  "issues": [
    "<CRITICAL: issue — file:line>",
    "<IMPORTANT: issue — file:line>",
    "<ADVERSARIAL: design risk — file:line>"
  ],
  "doc_drift": [
    "<section>: <失真描述>"
  ]
}
```

- **Include all CRITICAL, IMPORTANT, and ADVERSARIAL findings in `issues`** with their prefix preserved. Skip NITs.
- Include DOC-DRIFT findings in `doc_drift` as strings. Use `[]` when there is no document drift.
- For PASS without any ADVERSARIAL findings: `issues` is `[]`.
- For PASS with ADVERSARIAL findings: include them — they're advisory and consumed by `ohaze:finishing` (specifically the 6th finishing menu option "修复对抗审查后收尾", which only appears when ADVERSARIAL findings exist).
- For FAIL: include all CRITICAL/IMPORTANT/ADVERSARIAL entries — the user needs the full picture before retry.
- Do this in **every** iteration of the retry loop, not just on first verdict.

### Review prompt template (实跑验证 + 异源对抗)

```
You are reviewing Codex's implementation against the plan it was given. You are deliberately a different model from the one that wrote the code — your job is adversarial cross-check, not rubber-stamp.

Plan file: {plan_path}
Spec file: {spec_path}
Base branch: {base_ref}
Worktree: {worktree_path}
Project test command: {project_test_command}
Codex's structured report (from --json stream): {codex_report}

Your four-part review (verification-before-completion internalized — evidence before assertions):

PART 1 — Contract compliance:
- Read the guidance plan at `{plan_path}` — this is what Codex was given. It contains Behavior Contracts, Files lists, and Acceptance Criteria per Task, not prescriptive code.
- Walk through `git diff {base_ref}...HEAD` and the commit log.
- For each Task in the plan: is the Behavior Contract met? Are the Files listed actually changed? Do the Acceptance Criteria hold (tests pass / files exist / public interfaces match the contract)?
- **Implementation autonomy is expected**: Codex chooses internal variable names, control flow, helper extraction, and algorithm details within each Task. Do NOT flag those as defects unless they violate a contract or acceptance criterion.
- Flag: unmet Behavior Contracts, missing Tasks, files modified outside the Files lists, Acceptance Criteria that don't hold, public interface signatures that differ from the contract.

PART 2 — Code quality:
- Standard quality concerns: error handling, edge cases, naming, dead code, leaked secrets.
- Do NOT flag style nits the plan didn't require.
- Do NOT flag "Codex's implementation choice differs from what I would have written" — that's autonomy by design.

PART 2.5 — **Real test run (verification-before-completion, mandatory)**:
- Run `{project_test_command}` from `{worktree_path}` and capture the **actual** output. Do not skip this. Do not infer pass/fail from the diff alone.
- If the project has no aggregate test command, run the per-Task acceptance assertions listed in the plan (grep/test/JSON-load commands) and capture each one's exit status.
- Quote real output in your verdict (not paraphrased). "tests pass" without evidence is not acceptable.
- A failing test or assertion is automatically CRITICAL.

PART 3 — DOC-DRIFT:
Detect whether this `git diff` makes the target project's `CLAUDE.md` / `README.md` / `ROADMAP.md` descriptive sections inaccurate or stale.

- Only inspect descriptive sections (architecture notes, key files, design decisions, external deps); 不检测 progress checkboxes — those are handled later by the document finishing step.
- Output doc-drift items as `<section>: <失真描述>`.
- DOC-DRIFT findings do **not** gate PASS/FAIL. They are advisory, consumed by `ohaze:finishing` `doc-finish`.

PART 4 — Adversarial review (design challenge):
This is NOT a stricter pass over PART 1/2. This is a different lens entirely. Even if the implementation is correct and clean, ask whether the chosen approach is the right one.

- Challenge the chosen approach: was there a simpler, safer, or more maintainable alternative the plan rejected or didn't consider?
- Challenge the design: are abstractions earning their complexity? Premature optimizations or speculative generality? Over-engineered for the stated requirement?
- Challenge the assumptions: what does this code assume about inputs, runtime, scale, concurrency, or future requirements that could break under real-world conditions?
- Challenge the tradeoffs: are tradeoffs documented? Are they the right ones?
- Findings here go under `ADVERSARIAL:` regardless of severity. They surface design risks the user should consciously accept or revise.
- **ADVERSARIAL findings do NOT cause FAIL by themselves**. They are advisory. PART 1/2/2.5 issues are what gate ship. The finishing menu's 6th option ("修复对抗审查后收尾") gives the user a structured path to fix accepted ADVERSARIAL items.

Return verdict in this exact format:

VERDICT: PASS or FAIL

VERDICT is FAIL **if and only if** at least one CRITICAL or IMPORTANT issue exists from PART 1/2/2.5 (including failing real test runs). ADVERSARIAL findings alone never cause FAIL.

If FAIL, list issues by severity:
- CRITICAL: <issue> — <file:line>
- IMPORTANT: <issue> — <file:line>
- NIT: <issue> — <file:line>

ADVERSARIAL findings (always include if any, regardless of verdict):
- ADVERSARIAL: <design risk / approach concern> — <file:line or "design-wide">

DOC-DRIFT findings (always include; use [] if none):
- DOC-DRIFT: <section>: <失真描述>

Real test run evidence (always include — even on PASS):
- Command: <project_test_command>
- Exit status: <code>
- Tail of output: <last ~20 lines or assertion summary>

If PASS with no ADVERSARIAL findings: one-line summary + real-test evidence.
If PASS with ADVERSARIAL findings: one-line summary + ADVERSARIAL list + real-test evidence.
```

## Phase 6: Retry Loop (max 3 iterations, stuck-detection upgrade)

Track retry counter starting at 0; persist in `.ohaze/current-ship.json.retries`.

- If reviewer returns `VERDICT: PASS`: report success, transition `state` (caller decides — usually proceeds to Phase 7 `ohaze:finishing`), end skill.

- If reviewer returns `VERDICT: FAIL` and `retries < 3`:

  1. **Stuck-detection diagnosis (internalized systematic-debugging)**: before blindly dispatching another resume, check whether the same class of issue keeps re-appearing across consecutive iterations.
     - If iteration N has issues that overlap substantially with iteration N-1's issues, ask one diagnostic question: **plan problem vs Codex execution problem?**
       - **Plan problem** (the contract itself is unclear / impossible / contradicts another Task): stop, surface the issue to the user, and recommend rolling back to revise the plan rather than dispatching yet another fix attempt. Do not silently burn the remaining retries.
       - **Execution problem** (the contract is right but Codex keeps missing it): continue with resume, but include explicit "anti-regression" guidance in the fix prompt (see step 3).
     - If the issues are different from last iteration, proceed normally to step 3.

  2. Transition `state = "review_fail"` and increment `retries`.

  3. Format a structured fix prompt:

     ```
     <task>
     The previous Codex run completed but the cross-source reviewer found these issues. Fix them in the same worktree without changing anything else.

     Issues to fix (each one specifies file:line + the contract / acceptance criterion it violates + what state must hold after the fix — *what*, not *how*. Do NOT include ADVERSARIAL findings; those are design-level concerns the user decides on, not for you to auto-fix):

     {bullet list of CRITICAL and IMPORTANT issues, each as: "<file:line> — violates {contract/AC ref from plan} — expected: <what>"}

     Real test failure evidence from the reviewer (if any):
     {quoted tail of failing test output}
     </task>

     <anti_regression>
     Previous iterations changed (and reviewer still found these issues):
     {bullet list of "iter N: changed X — still failing because Y" for prior iterations}
     Do not re-apply changes that were already shown not to fix the issue. If the contract is genuinely impossible, say so in your report instead of pretending another attempt.
     </anti_regression>

     <action_safety>
     - Only address the listed issues. Do not refactor anything else.
     - Do not introduce new files unless required to fix an issue.
     - Suggested commit messages: "fix: <one-line summary of issue>" per fix; orchestrator commits.
     </action_safety>

     <verification_loop>
     After fixing, re-run {project_test_command} (or the per-Task acceptance assertions). All must pass before reporting done.
     </verification_loop>
     ```

  4. Read `thread_id` from `.ohaze/current-ship.json`. Write the fix prompt to `<worktree_path>/.ohaze/codex-fix-iter<N>.xml` via Write tool, then dispatch:

     ```bash
     codex exec resume <thread_id> \
       --cd <worktree_path> \
       --json \
       < <worktree_path>/.ohaze/codex-fix-iter<N>.xml
     ```

     **`codex exec resume` MUST NOT include `--sandbox`.** The sandbox is fixed at the initial `codex exec` and inherited by every resume; passing `--sandbox` to `resume` is rejected by codex 0.137. (This was a real bug in the pre-v2 implementation.)

     Dispatch via `Bash(run_in_background: true)` again so the harness re-invokes the main agent on completion — same control-flow shape as Phase 4. The orchestrator does not wait synchronously.

     If `thread_id` is missing or `null`: print and append a prominent warning to the user — `WARNING: thread_id 缺失,resume 退化为 --last,并行 ship 下不精确` — only then dispatch the fallback `codex exec resume --last --cd <worktree_path> --json` (still no `--sandbox`).

     If exact resume fails to find the prior thread (rare — codex was restarted between sessions, or the rollout file was rotated): fall back to a fresh `codex exec` with a `<task>` that embeds both the original goal (re-read from the saved prompt file) and the fix delta. Note this in the retry log so the reviewer knows context may have been lost.

  5. Re-run Phase 5 (the harness re-invoke + state gate handles this).

- If reviewer returns `VERDICT: FAIL` and `retries == 3`:
  - Stop and report all 3 attempts' findings to the user in a structured summary:
    ```
    Codex 已尝试修复 3 次, 审查仍未通过. 当前状态:

    第 1 轮 issues: ...
    第 2 轮 issues: ...
    第 3 轮 issues: ...

    选项:
    1. 继续让 Codex 再试 1 次 (`/ohaze:ship-review --more`)
    2. 你手动介入修复
    3. 接受现状直接进入 finishing (ADVERSARIAL/IMPORTANT 可经第 6 项「修复对抗审查后收尾」补救)
    ```
  - Wait for user choice. Do NOT auto-retry past 3.

## What this skill does NOT do

- Does NOT translate plan to prompt — that's `ohaze:plan-to-codex-prompt`.
- Does NOT run brainstorming, planning, worktree setup, or finishing — those are owned by `ohaze:brainstorming` / `ohaze:writing-plans` / `ohaze:using-git-worktrees` / `ohaze:finishing`, orchestrated by `/ohaze:ship`.
- Does NOT schedule any `ScheduleWakeup` — the v2 control flow relies on `run_in_background` harness re-invoke. No fallback wakeup is set (A-plan: state gate is the only ghost-wake defense, see spec §3).
- Does NOT poll Codex synchronously. The control-flow pattern is: `Bash(run_in_background)` dispatch → main turn ends → harness re-invokes on codex exit → `/ohaze:ship-review` state gate picks up.

## Resume Boundary

Use `codex exec resume` only inside the same ship lifecycle: the review retry loop (Phase 6 above) and the finishing modify / 6th-option ADVERSARIAL-fix flows (`ohaze:finishing`). All use the captured `thread_id`, no `--sandbox`.

If a bug is found after finishing completes, start a **新 fix ship** with a new worktree, new plan, and new Codex session. Do **not** resume the old session post-finish. Feed the old feature's plan and relevant commits into the new ship prompt as explicit reference material instead of depending on Codex session memory.

## Failure modes and recovery

- **`codex` binary not found**: report the failure; tell the user to install (`npm install -g @openai/codex`) and authenticate (`codex login`). Do not improvise an inline implementation.
- **Background codex exits immediately**: the harness re-invokes the main agent quickly. Read `BashOutput(codex_bg_id)` — the tail will show why (auth issue, sandbox flag rejected by an old codex version, prompt file unreadable, exit 1 from non-git directory). Surface the actual error.
- **Reviewer subagent returns malformed verdict**: re-dispatch the reviewer once with stricter format guidance. If it fails again, fall back to asking the user to read `git diff` and decide.
- **Real test command unknown**: stop and ask the user. Do NOT guess `npm test` for a project that has no `package.json`; the spec's verification-before-completion requirement demands a real command.
- **Exact `codex exec resume <thread_id>` fails to find prior thread**: fall back to fresh `codex exec` with combined "original task + fix delta" prompt. Note in the retry log so the reviewer knows context may have been lost.
- **`thread_id` missing**: log `WARNING: thread_id 缺失,resume 退化为 --last,并行 ship 下不精确`, then and only then use fallback `codex exec resume --last` (no `--sandbox`).
- **Stuck loop (same issues iter after iter)**: trigger the Phase 6 stuck-detection diagnosis — do not blindly burn retries 2 and 3.
