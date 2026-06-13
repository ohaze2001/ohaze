---
name: codex-executor
description: Use when the ohaze workflow needs to dispatch a plan to Codex and run the post-execution adversarial review loop. Owns Codex dispatch (run_in_background, thread_id capture, no nohup), cross-source review (general-purpose subagent + real test run), and the up-to-3-retry review-fix cycle with stuck-detection upgrade.
---

# Codex Executor (ohaze)

Hand a translated XML prompt to Codex via the `codex` CLI, then run the Claude-side cross-source review loop. Owns Phases 4–6 of `/ohaze:ship`.

## When to invoke

- Inside `/ohaze:ship` after `ohaze:plan-to-codex-prompt` produces an XML prompt.
- Inside `/ohaze:ship-review` (after the harness re-invokes the main agent because the background Codex run completed) to run the review-fix loop.
- Inside `ohaze:finishing` Step 2a (modify sub-flow: Codex 续跑) or Step 6 (修复对抗审查后收尾) to dispatch a follow-up fix.

## Inputs

- `mode` (required, enum): `'dispatch'` for initial Codex run (enter at Phase 4) or `'review'` for re-entry after Codex completion (skip Phase 4, enter at Phase 5.0). Callers `/ohaze:ship` Phase 4 pass `mode='dispatch'`; `/ohaze:ship-review` Phase 5–6 and `/ohaze:ship-finish` Step 2 re-review pass `mode='review'`.
- `codex_prompt` (required when `mode='dispatch'`): the full XML string from `ohaze:plan-to-codex-prompt`. Ignored when `mode='review'`.
- `plan_path` (required): the absolute path to the plan markdown under `docs/ohaze/plans/`, used by the reviewer.
- `spec_path` (required for `mode='review'`): the absolute path to the spec markdown under `docs/ohaze/specs/`, substituted into the reviewer prompt template (the `{spec_path}` token in the PART 1 contract-compliance section). Callers `ship.md` Phase 4b / `ship-review.md` / `ship-finish.md` all pass this.
- `base_ref` (required): the git ref Codex's work started from (typically the worktree's parent branch, e.g. `main`).
- `worktree_path` (required for review/retry): the ship worktree path.
- `main_repo_path` (optional, recommended): used only if a fallback (e.g. fresh `codex exec` after exact resume fails) needs to know the main checkout location.
- `project_test_command` (required for review): the command the reviewer runs to verify behavior (e.g. `npm test`, `pytest`). For Markdown-only plugins where no aggregate command exists, pass a sentinel like `'(per-Task acceptance assertions inline in plan)'` — the reviewer's PART 2.5 then runs the per-Task grep/test assertions instead of an aggregate command.
- `thread_id` (optional but expected for retry/modify/6th-option resume): read from `.ohaze/current-ship.json`; used for exact `cd <worktree> && codex exec resume <thread_id>` (no `--cd`, no `--sandbox`).
- `codex_report_source` (optional, foreground-path only): absolute file path to a teed `.ohaze/codex-*-output.jsonl`. When set, Phase 5.0 reads Codex's final report from this file instead of `BashOutput(codex_bg_id)`. Callers `ohaze:finishing` 6th option + modify 2a pass this because their foreground dispatches don't produce a new `codex_bg_id` — without this override, Phase 5.0 would read the stale background dispatch's stream and use wrong commit messages.

### Mode branching contract

- **`mode='dispatch'`** (initial): enter at Phase 4 Step 1 (write prompt file → dispatch background → capture `thread_id` + `codex_bg_id` → persist → report and return).
- **`mode='review'`** (re-entry after `state=codex_done` or `state=review_fail`): skip Phase 4 entirely. Enter at Phase 5.0 (Apply Codex's pending changes as commits) → Phase 5.1 (Compute diff) → Phase 5.2 (Dispatch reviewer) → Phase 5.3 (Write verdict) → Phase 6 (Retry loop if FAIL). Re-using the same codex thread for any retry dispatches (via `cd <worktree> && codex exec resume <thread_id>`).

If `mode` is missing or invalid, default to `'dispatch'` and warn the user — strict validation isn't worth a hard fail here, but the warning ensures the caller knows the contract drifted.

## Dispatch Mode Vocabulary

Use these terms consistently across ohaze so "background" is never ambiguous:

- **harness background** (allowed and required except for documented architecture exceptions): `Bash(run_in_background: true)`. Claude Code's harness owns the Bash child process, the main agent retains a task id for `BashOutput(<id>)`, and the harness re-invokes the main agent when Codex exits.
- **OS-level background** (forbidden): `nohup codex exec ... &`, `codex exec ... > log 2>&1 &`, `echo $! > pid_file`, or any pattern that detaches Codex from the harness session and pairs it with `ScheduleWakeup`. This is the removed v1 path.
- **foreground sync** (allowed only for the finishing 6th-option and modify 2a architecture exceptions): `Bash(...)` without `run_in_background: true`, where the main agent blocks until Codex returns. The finishing skill needs this to stay alive across commit / re-review / finish-chain mini-loops.

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

Use Claude Code's `Bash` tool with `run_in_background: true` (harness background; see Dispatch Mode Vocabulary). The harness tracks the background task and re-invokes the main agent automatically when the process exits.

```bash
codex exec \
  --sandbox danger-full-access \
  --skip-git-repo-check \
  --cd <worktree_path> \
  --json \
  "$(cat <prompt_file>)" \
  < /dev/null
```

**Strict rules for this dispatch:**

- **No `nohup`, no trailing `&`, no `> log 2>&1`, no `echo $! > pid_file`** — those are OS-level background patterns forbidden by the Dispatch Mode Vocabulary. Use harness background only.
- **Must include `--json`** so we can parse the streamed event log for `thread.started` and the final message.
- **Must run inside a real git project directory** (`--cd <worktree_path>` points at the ship worktree). codex exec exits non-zero in `/tmp` or any non-git path.
- **Must close stdin with `< /dev/null`**. codex 0.137 can silently crash when the initial `codex exec --json` prompt is provided via stdin redirect; passing the prompt as the top-level CLI argument and closing stdin avoids that transport failure.
- **Must dispatch with `Bash(run_in_background: true)`** so the harness owns completion and re-invocation. See Dispatch Mode Vocabulary for why OS-level background is forbidden.

### Step 2.5 — Dispatch liveness check

Immediately after dispatch, run a bounded 30s transport check:

1. Call `BashOutput(codex_bg_id)` with `filter='thread.started'` and wait up to 30 seconds for the first event.
2. If no `thread.started` appears, call `KillBash(codex_bg_id)`.
3. Re-dispatch once using the same prompt file and the same command from Step 2, then repeat the same 30s `thread.started` liveness check.
4. If the second attempt also fails, transition `.ohaze/current-ship.json.state` to `dispatch_failed` via Read-modify-Write (preserve all other fields, clear `codex_bg_id` and `thread_id` to `null`), then surface this warning verbatim and stop: `WARNING: codex initial dispatch failed liveness check twice; codex 0.137 stdin crash or pre-thread transport failure. State transitioned to dispatch_failed; rerun /ohaze:ship or /ohaze:ship-review to resume.`
5. If the check passes, proceed to Step 3 to capture `thread_id` and `codex_bg_id`.

This liveness check is a transport-layer crash detector, not a completion poll.

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

Don't poll asynchronously for completion, don't sleep, don't `ScheduleWakeup`. The ONLY bounded synchronous poll allowed is the 30s dispatch-liveness check immediately after dispatch (Phase 4 initial + Phase 6 retry + spec-to-codex-review Phase 1.6) to detect codex 0.137 stdin silent crash; this is a transport-layer crash detector, not a completion poll. Report to the user and return control to the caller; the main agent's turn ends. The harness will re-invoke the main agent when the background codex task exits, and `/ohaze:ship-review`'s idempotent state gate will pick up from there.

> "Codex 在后台跑 (codex_bg_id=`<id>`, thread_id=`<UUID|null>`, sandbox=`danger-full-access`).
> 进程完成后 harness 会自动唤醒主 agent 进 review,无需手动触发。
> 中途想看进度: `BashOutput <codex_bg_id>` 读流式 --json 事件。"

## Phase 5: Claude-side Review (cross-source + real test run)

Triggered when the background Codex task completes — the harness re-invokes the main agent, `/ohaze:ship-review`'s pre-flight state gate sees `state == "codex_done"`, and dispatches review. The user can also invoke `/ohaze:ship-review` manually; the state gate handles both entry paths identically.

### Phase 5.0: Apply Codex's pending changes as commits (REQUIRED)

ohaze keeps commit authority at the orchestrator (Claude main session) by convention — see `plan-to-codex-prompt`'s `<commit_handling>`. Codex therefore leaves uncommitted changes in the worktree; the orchestrator commits them before review.

1. Read Codex's final report from the `--json` stream. Source depends on dispatch mode:
   - **Background path (default, set by Phase 4 / Phase 6 retry)**: `BashOutput(codex_bg_id) filter='"type":"message"'` reads the streamed `--json` events. The `filter` parameter is REQUIRED — codex's full `--json` stream for a multi-hour run can reach 5-20 MB; without filter the entire buffer would be pulled into context and likely exhaust the window. The filter keeps only the structured-report message events. (Same defense as ship-review.md Step 3a's filter usage.)
   - **Foreground path (set by `ohaze:finishing` 6th option / modify 2a)**: caller passes input `codex_report_source` = absolute path to a teed `.ohaze/codex-*-output.jsonl` file. Use `Bash(tail -c 200000 <file>)` then scan for the final `message` event. **Do not** use `BashOutput(codex_bg_id)` on this path — `codex_bg_id` still points at the prior background dispatch (stale stream).

   The final `message` event contains the structured report (Tasks completed / Touched files / Notable choices / suggested per-Task commit messages). **Do not rely on `-o/--output-last-message`** — that flag does not produce a file when `--json` is set (verified against codex 0.137 in dogfood).

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

> Note on state transition: `state = "codex_done"` was already written by `ship-review.md` Step 3a BEFORE this skill was invoked in review mode — `ship-review.md` owns the gate transition (see ship-review.md §3a "Why this lives here, not in codex-executor"). Do NOT re-write it here. The earlier v2 redundant write ("if it isn't already") was removed as part of code-review-2 #R8 to honor the ownership claim and avoid a Read-modify-Write race that the v2 schema does not guard against.

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

### Phase 5.3: Write `review-verdict.json` and `findings-detail.json`

After the reviewer returns, write the verdict to disk. The Write tool is preferred for structural safety (the JSON contains arbitrary user strings; heredocs are quoting hazards), but there is **no hook dependency** — vault has been stripped from ohaze.

Target files:

- `<worktree_path>/.ohaze/review-verdict.json`
- `<worktree_path>/.ohaze/findings-detail.json`

Write protocol: before overwriting either JSON file, read it if it already exists, preserve unknown top-level fields, and override only the fields owned by this phase (`iteration`, `verdict`, `issues`, `doc_drift` for `review-verdict.json`; `iteration`, `findings` for `findings-detail.json`). This mirrors `ship.md`'s Read-modify-Write rule: read full file → preserve all fields → write the full updated object.

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
- Each reviewer issue MUST carry `user_impact_description` internally. If the reviewer omits it, normalize to `null` before writing details.
- Include DOC-DRIFT findings in `doc_drift` as strings. Use `[]` when there is no document drift.
- For PASS without any ADVERSARIAL findings: `issues` is `[]`.
- For PASS with ADVERSARIAL findings: include them — they're advisory and consumed by `ohaze:finishing` (specifically the 6th finishing menu option "修复对抗审查后收尾", which only appears when ADVERSARIAL findings exist).
- For FAIL: include all CRITICAL/IMPORTANT/ADVERSARIAL entries — the user needs the full picture before retry.
- Do this in **every** iteration of the retry loop, not just on first verdict.

Also write `<worktree_path>/.ohaze/findings-detail.json` as the single source of truth for display routing:

```json
{
  "iteration": <current_retry_count>,
  "findings": [
    {
      "severity": "CRITICAL | IMPORTANT | NIT | ADVERSARIAL | NICE-TO-HAVE",
      "evidence": "<file:line + quoted text>",
      "technical_description": "<原始技术描述>",
      "user_impact_description": "<string|null>",
      "shown_to_user": <bool>,
      "auto_handled": "retry-fix | skip | null"
    }
  ]
}
```

Each iteration overwrites `iteration` and `findings`; this file is not an append-only log. Routing:

| Severity | `user_impact_description != null` | `user_impact_description == null` |
|---|---|---|
| CRITICAL | auto-retry-fix; record `shown_to_user: false`, `auto_handled: "retry-fix"` | auto-retry-fix; record `shown_to_user: false`, `auto_handled: "retry-fix"` |
| IMPORTANT | auto-retry-fix; record `shown_to_user: false`, `auto_handled: "retry-fix"` | auto-retry-fix; record `shown_to_user: false`, `auto_handled: "retry-fix"` |
| ADVERSARIAL | show to user in product language; record `shown_to_user: true`, `auto_handled: null` | default skip; record `shown_to_user: false`, `auto_handled: "skip"` |
| NIT | default skip; record `shown_to_user: false`, `auto_handled: "skip"` | default skip; record `shown_to_user: false`, `auto_handled: "skip"` |
| NICE-TO-HAVE | default skip; record `shown_to_user: false`, `auto_handled: "skip"` | default skip; record `shown_to_user: false`, `auto_handled: "skip"` |

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

Product-language field constraint:
- Every CRITICAL, IMPORTANT, NIT, ADVERSARIAL, and NICE-TO-HAVE issue object MUST include `user_impact_description`.
- Use `null` only for purely technical issues with no user-facing or scenario-level impact.
- When non-null, write product language: describe what user-facing function is incomplete, broken, or degraded.
- Do NOT put code identifiers, file paths, function names, variable names, or raw line numbers in `user_impact_description`; those belong in `evidence` and `technical_description`.

Return verdict in this exact format:

VERDICT: PASS or FAIL

VERDICT is FAIL **if and only if** at least one CRITICAL or IMPORTANT issue exists from PART 1/2/2.5 (including failing real test runs). ADVERSARIAL findings alone never cause FAIL.

If FAIL, list issues by severity:
- CRITICAL: {"evidence":"<file:line + quote>","technical_description":"<issue>","user_impact_description":"<product-language string or null>"}
- IMPORTANT: {"evidence":"<file:line + quote>","technical_description":"<issue>","user_impact_description":"<product-language string or null>"}
- NIT: {"evidence":"<file:line + quote>","technical_description":"<issue>","user_impact_description":"<product-language string or null>"}

ADVERSARIAL findings (always include if any, regardless of verdict):
- ADVERSARIAL: {"evidence":"<file:line, quote, or design-wide>","technical_description":"<design risk / approach concern>","user_impact_description":"<product-language string or null>"}

NICE-TO-HAVE findings (optional, details-only; never gate):
- NICE-TO-HAVE: {"evidence":"<file:line + quote>","technical_description":"<improvement>","user_impact_description":"<product-language string or null>"}

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
     <investigate_first>
     改动任何代码前,先写出根因诊断:
     - 违反的是哪个 contract / AC?
     - 上一轮为什么没修对? (具体证据)
     - 你的根因假设是什么? (证据支撑)
     如果说不清根因,直接停下报告,不要硬修。
     </investigate_first>

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

     `<investigate_first>` is per-retry Codex self-discipline inside the fix prompt: every retry must diagnose root cause before touching code. The stuck-detection diagnosis above is Claude main-loop cross-iteration control outside the prompt. They stack and do not conflict.

  4. Read `thread_id` from `.ohaze/current-ship.json`. Write the fix prompt to `<worktree_path>/.ohaze/codex-fix-iter<N>.xml` via Write tool, then dispatch.

     **Command — `codex exec resume` flag asymmetry vs initial dispatch (verified against codex 0.137):**
     - `codex exec resume` does **NOT** accept `--cd` (only top-level `codex exec` does). Empirical: `codex exec resume --help` does not list `-C/--cd`; passing it errors `unexpected argument '--cd'`. So we change working directory in the shell BEFORE invoking resume.
     - `codex exec resume` does **NOT** accept `--sandbox`. Sandbox is fixed at the initial `codex exec` and inherited by every resume; passing `--sandbox` to `resume` is rejected by codex 0.137.

     Dispatch via `Bash(run_in_background: true)`:

     ```bash
     cd <worktree_path> && codex exec resume <thread_id> \
       --json \
       < <worktree_path>/.ohaze/codex-fix-iter<N>.xml
     ```

     Because `codex exec resume` does not accept a top-level PROMPT argument in codex 0.137, this resume command must keep stdin redirect. Immediately after dispatch, run the same bounded transport liveness check as Phase 4 Step 2.5:

     1. Call `BashOutput(codex_bg_id)` with `filter='thread.started'` and wait up to 30 seconds.
     2. If no `thread.started` appears, call `KillBash(codex_bg_id)`.
     3. Re-dispatch once with the same `thread_id` and the same prompt file, then repeat the 30s liveness check.
     4. If the second attempt also fails, transition `.ohaze/current-ship.json.state` to `dispatch_failed` via Read-modify-Write (preserve all other fields, clear `codex_bg_id` to `null`; preserve `thread_id` for manual resume), then surface this warning verbatim and do not retry again: `WARNING: codex resume dispatch failed liveness check twice; codex 0.137 stdin crash. State transitioned to dispatch_failed. Suggest /ohaze:ship-review --more or manual resume.`
     5. If the check passes, continue with the `codex_bg_id` capture-and-persist rule below.

     This liveness check is a transport-layer crash detector, not a completion poll.

     **Capture the new `codex_bg_id`** returned by `Bash(run_in_background)` and **immediately update `.ohaze/current-ship.json.codex_bg_id`** per the Read-modify-Write protocol in `ship.md` §Write Protocol (Read full file → preserve all other fields → Write with `codex_bg_id` AND `retries` overridden in the same Write to minimize race surface). Every retry / modify / 6th-option resume returns a fresh background task id; downstream consumers (Phase 5.0 report extraction, `/ohaze:status` deep inspect, doc-finish 真相源, ship-review Step 3a liveness check) read this field and would otherwise hit a dead/old stream.

     Dispatching via `Bash(run_in_background: true)` lets the harness re-invoke the main agent on completion — same control-flow shape as Phase 4. The orchestrator does not wait synchronously.

     If `thread_id` is missing or `null`: print and append a prominent warning to the user — `WARNING: thread_id 缺失,resume 退化为 --last,并行 ship 下不精确` — only then dispatch the fallback `cd <worktree_path> && codex exec resume --last --json < <fix prompt>` (still no `--cd`, no `--sandbox`). Same `codex_bg_id` capture-and-persist rule applies.

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
- Does NOT schedule any `ScheduleWakeup` — the v2 control flow relies on `Bash(run_in_background: true)` harness background re-invoke. No fallback wakeup is set (A-plan: state gate is the only ghost-wake defense, see spec §3).
- Does NOT poll asynchronously for completion. The control-flow pattern is: `Bash(run_in_background: true)` harness background dispatch → bounded liveness check only → main turn ends → harness re-invokes on codex exit → `/ohaze:ship-review` state gate picks up. The ONLY bounded synchronous poll allowed is the 30s dispatch-liveness check immediately after dispatch (Phase 4 initial + Phase 6 retry + spec-to-codex-review Phase 1.6) to detect codex 0.137 stdin silent crash; this is a transport-layer crash detector, not a completion poll.

## Resume Boundary

Use `codex exec resume` only inside the same ship lifecycle: the review retry loop (Phase 6 above) and the finishing modify / 6th-option ADVERSARIAL-fix flows (`ohaze:finishing`). All use the captured `thread_id`, no `--sandbox`.

If a bug is found after finishing completes, start a **新 fix ship** with a new worktree, new plan, and new Codex session. Do **not** resume the old session post-finish. Feed the old feature's plan and relevant commits into the new ship prompt as explicit reference material instead of depending on Codex session memory.

## Failure modes and recovery

- **`codex` binary not found**: report the failure; tell the user to install (`npm install -g @openai/codex`) and authenticate (`codex login`). Do not improvise an inline implementation.
- **Background codex exits immediately**: the harness re-invokes the main agent quickly. Read `BashOutput(codex_bg_id)` — the tail will show why (auth issue, sandbox flag rejected by an old codex version, prompt file unreadable, exit 1 from non-git directory). Surface the actual error.
- **Reviewer subagent returns malformed verdict**: re-dispatch the reviewer once with stricter format guidance. If it fails again, fall back to asking the user to read `git diff` and decide.
- **Real test command unknown**: stop and ask the user. Do NOT guess `npm test` for a project that has no `package.json`; the spec's verification-before-completion requirement demands a real command.
- **Exact `codex exec resume <thread_id>` fails to find prior thread**: fall back to fresh `codex exec` with combined "original task + fix delta" prompt. Note in the retry log so the reviewer knows context may have been lost.
- **`thread_id` missing**: log `WARNING: thread_id 缺失,resume 退化为 --last,并行 ship 下不精确`, then and only then use fallback `cd <worktree_path> && codex exec resume --last --json` (no `--cd`, no `--sandbox`). Capture and persist the new `codex_bg_id` as with any other resume.
- **Stuck loop (same issues iter after iter)**: trigger the Phase 6 stuck-detection diagnosis — do not blindly burn retries 2 and 3.
