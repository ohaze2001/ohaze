---
name: codex-executor
description: Use when ohaze workflow needs to dispatch a plan to Codex and run the post-execution review loop. Owns the Codex hand-off and the up-to-3-retry review-fix cycle.
---

# Codex Executor

Hand a translated XML prompt to Codex via the `codex` plugin, then run the Claude-side review loop. Owns Phases 4-6 of `/ohaze:ship`.

## When to invoke

- Inside `/ohaze:ship` after `ohaze:plan-to-codex-prompt` produces an XML prompt.
- Inside `/ohaze:ship-review` to resume the review-fix loop after a `--background` Codex run completes.

## Inputs

- `codex_prompt` (required): the full XML string from `ohaze:plan-to-codex-prompt`.
- `plan_path` (required): the absolute path to the plan markdown, used by the reviewer.
- `base_ref` (required): the git ref Codex's work started from (typically the worktree's parent branch, e.g. `main`).
- `mode` (optional, default `--background`): either `--background` or `--wait`.

## Phase 4: Dispatch Codex (direct `codex exec`, full-access sandbox)

ohaze bypasses the `codex-companion.mjs` task interface because that interface is hardcoded to `workspace-write` sandbox, which blocks writes outside the worktree (e.g., `~/Brain/`, `~/.claude/`, cross-project paths). Many ohaze ship plans legitimately need those writes — vault sync, global settings patches, registry registration.

Instead, invoke `codex exec` directly with `--sandbox danger-full-access`. The ship flow has already gated this through brainstorm → plan review → adversarial review, so the implicit trust boundary is at `/ohaze:ship` invocation, not at the Codex layer.

### Step 1 — Write prompt to a file (avoid shell quoting hell)

```bash
mkdir -p <worktree_path>/.ohaze
PROMPT_FILE=<worktree_path>/.ohaze/codex-prompt.xml
# Use the Write tool to write the full XML string to PROMPT_FILE
```

Use the Write tool (not a heredoc) for the prompt file. The XML contains backticks, dollar signs, and possibly other shell metachars — only Write is safe.

### Step 2 — Generate a job id, set log path

```bash
JOB_ID="ohaze-$(date +%s)-$$"
LOG_FILE=<worktree_path>/.ohaze/codex-${JOB_ID}.log
PID_FILE=<worktree_path>/.ohaze/codex-${JOB_ID}.pid
```

### Step 3 — Background-dispatch codex exec

Use Claude Code's `Bash(run_in_background: true)` so the main session is not blocked.

```bash
# Bash tool call with run_in_background=true.
# codex exec reads the prompt from stdin when "-" is the positional arg
# (or omitted entirely when stdin is piped).
nohup codex exec \
  --sandbox danger-full-access \
  --skip-git-repo-check \
  --cd <worktree_path> \
  < <prompt_file> \
  > <log_file> 2>&1 &
echo $! > <pid_file>
```

(Verify `codex exec --help` if the installed version's flags differ.)

### Step 4 — Persist job metadata to handoff

Update `.ohaze/current-ship.json` to include the job id, pid file, and log file. The retry / review flow uses these instead of a companion-issued run id.

```json
{
  ...
  "codex_job_id": "ohaze-1747431234-12345",
  "codex_pid_file": "<worktree>/.ohaze/codex-<job_id>.pid",
  "codex_log_file": "<worktree>/.ohaze/codex-<job_id>.log",
  "codex_thread_resume": false
}
```

(`codex_run_id` field — kept for vault-adapter back-compat — gets set to the same value as `codex_job_id`.)

### Step 5 — Report to user

> "Codex 已在后台跑 (job_id=`<id>`, sandbox=danger-full-access). 进度:
> - `tail -f <log_file>` — 实时日志
> - `ps -p $(cat <pid_file>)` — 进程状态
>
> 跑完后回 `/ohaze:ship-review`."

Then stop. Phases 5-6 happen in `/ohaze:ship-review`.

### About `--wait` mode

If the caller passed `mode=--wait`, drop the `&` and `run_in_background` — let `codex exec` run in the foreground and proceed inline to Phase 5 in the same turn.

### What about `codex:codex-rescue` subagent?

The codex-rescue subagent still goes through `codex-companion.mjs` and inherits its sandbox lockdown. ohaze no longer dispatches through it. If you need codex-rescue's gpt-5-4-prompting refinement layer, that's a separate use case (e.g., `/codex:rescue` for one-shot ad-hoc help) — not part of the ship flow.

## Phase 5: Claude-side Review

Trigger this when the Codex run completes (the pid in `<pid_file>` is no longer alive, or the log shows the end-of-run report). `/ohaze:ship-review` is the user-driven trigger to proceed.

### Phase 5.0: Apply Codex's pending changes as commits (REQUIRED)

Even though Codex now has full sandbox access (could commit itself), ohaze keeps commit authority at the orchestrator by convention — see plan-to-codex-prompt's `<commit_handling>`. This ensures consistent commit message style and lets the orchestrator group / split commits per Task.

Codex therefore leaves uncommitted changes in the worktree. Before review, the orchestrator must commit them using the messages the plan / Codex's report specified.

1. Fetch Codex's final result by reading `<log_file>` (the full Codex stdout) or its tail. Look for the report block that lists "suggested commit messages per Task" (see plan-to-codex-prompt's `<output_report>`).

2. Inspect what Codex left behind:
   ```bash
   git -C <worktree_path> status --short
   git -C <worktree_path> diff
   ```

3. If there are uncommitted changes:
   - **Single Task changed**: stage all changes and commit with the single message from Codex's report.
     ```bash
     git -C <worktree_path> add -A
     git -C <worktree_path> commit -m "<intended message from Codex report>"
     ```
   - **Multiple Tasks (multiple intended messages)**: try to split per-Task using the plan's `Files:` sections to determine which files belong to which Task. If splitting is not feasible (files overlap), fall back to one combined commit using the LAST intended message.
   - If `git commit` fails (hooks, etc.), surface the error and stop. Do NOT bypass hooks.

4. If working tree is already clean (Codex DID manage to commit, or there were no changes), skip step 3.

### Phase 5.1: Compute the diff to review

   ```bash
   git -C <worktree_path> diff <base_ref>...HEAD
   git -C <worktree_path> log --oneline <base_ref>..HEAD
   ```

### Phase 5.2: Dispatch the reviewer subagent
   ```
   Agent(
     subagent_type="superpowers:code-reviewer",
     description="Review Codex implementation against plan",
     prompt=<see review prompt template below>
   )
   ```

### Phase 5.3: Write review-verdict.json (vault hook trigger)

After the reviewer returns, **immediately** write the verdict to disk so the vault hook can capture it:

```bash
cat > <ohaze_dir>/review-verdict.json << 'EOF'
{
  "iteration": <current_retry_count>,
  "verdict": "<PASS|FAIL>",
  "issues": [
    "<CRITICAL: issue — file:line>",
    "<IMPORTANT: issue — file:line>",
    "<ADVERSARIAL: design risk — file:line>"
  ]
}
EOF
```

- `<ohaze_dir>` is the `.ohaze/` directory inside the worktree (same dir as `current-ship.json`).
- **Include all CRITICAL, IMPORTANT, and ADVERSARIAL findings in `issues`** with their prefix preserved. Skip NITs.
- For PASS without any ADVERSARIAL findings: `issues` is `[]`.
- For PASS with ADVERSARIAL findings: include them — vault adapter surfaces them in discussions as advisory.
- For FAIL: include all CRITICAL/IMPORTANT/ADVERSARIAL entries (the user needs the full picture before retry).
- This write triggers the `PostToolUse(Write)` hook → `vault-adapter.sh on-write` → `_handle_verdict`.
- Do this in **every** iteration of the retry loop, not just on first verdict.

### Review prompt template

```
You are reviewing Codex's implementation against the plan it was given.

Plan file: {plan_path}
Base branch: {base_ref}
Worktree: {worktree_path}

<vault_context>
{vault_context}
</vault_context>

Your three-part review:

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
- If vault_context is non-empty: also flag violations of past project decisions or user preferences noted there.

PART 3 — Adversarial review (design challenge):
This is NOT a stricter pass over PART 1/2. This is a different lens entirely. Even if the implementation is correct and clean, ask whether the chosen approach is the right one.

- Challenge the chosen approach: was there a simpler, safer, or more maintainable alternative the plan rejected or didn't consider?
- Challenge the design: are abstractions earning their complexity? Premature optimizations or speculative generality? Over-engineered for the stated requirement?
- Challenge the assumptions: what does this code assume about inputs, runtime, scale, concurrency, or future requirements that could break under real-world conditions?
- Challenge the tradeoffs: are tradeoffs documented? Are they the right ones?
- Findings here go under `ADVERSARIAL:` regardless of severity. They surface design risks the user should consciously accept or revise.
- **ADVERSARIAL findings do NOT cause FAIL by themselves**. They are advisory. PART 1/2 issues are what gate ship.

Return verdict in this exact format:

VERDICT: PASS or FAIL

VERDICT is FAIL **if and only if** at least one CRITICAL or IMPORTANT issue exists from PART 1/2. ADVERSARIAL findings alone never cause FAIL.

If FAIL, list issues by severity:
- CRITICAL: <issue> — <file:line>
- IMPORTANT: <issue> — <file:line>
- NIT: <issue> — <file:line>

ADVERSARIAL findings (always include if any, regardless of verdict):
- ADVERSARIAL: <design risk / approach concern> — <file:line or "design-wide">

If PASS with no ADVERSARIAL findings: one-line summary.
If PASS with ADVERSARIAL findings: one-line summary followed by the ADVERSARIAL list.
```

`{vault_context}` is assembled by the caller before dispatching — concatenate the content of the 3 most recent decision files from `~/Brain/20_Projects/{project}/decisions/` and `~/Brain/99_System/Logs/decision-patterns.md`. If those files don't exist, leave `{vault_context}` empty.

## Phase 6: Retry Loop (max 3 iterations)

Track retry counter starting at 0.

- If reviewer returns `VERDICT: PASS`: report success to user, end skill, caller proceeds to Phase 7 (`superpowers:finishing-a-development-branch`).

- If reviewer returns `VERDICT: FAIL` and retry < 3:
  1. Format the issues as a delta instruction:
     ```
     <task>
     The previous Codex run completed but the Claude-side reviewer found these issues. Fix them in the same worktree without changing anything else.

     Issues to fix:
     {bullet list of CRITICAL and IMPORTANT issues with file:line — DO NOT include ADVERSARIAL findings here; those are design-level concerns for the user to decide on, not for Codex to auto-fix}
     </task>

     <action_safety>
     - Only address the listed issues. Do not refactor anything else.
     - Do not introduce new files unless required to fix an issue.
     - Commit fixes with messages like "fix: <one-line summary of issue>".
     </action_safety>

     <verification_loop>
     After fixing, re-run the project test command. All tests must pass before reporting done.
     </verification_loop>
     ```
  2. Write the fix prompt to `<worktree>/.ohaze/codex-fix-iter<N>.xml` via Write tool, then dispatch with `codex exec resume --last` (continues the same Codex thread started in Phase 4):

     ```bash
     # Foreground for retries — user is engaged, no need to background
     codex exec resume --last \
       --sandbox danger-full-access \
       --cd <worktree_path> \
       < <worktree>/.ohaze/codex-fix-iter<N>.xml \
       2>&1 | tee -a <log_file>
     ```

     If `codex exec resume --last` fails to find the prior thread (e.g., codex was restarted between sessions), fall back to a fresh `codex exec` with the fix prompt embedded inside a `<task>` block that references the original goal (read it from the saved prompt file or the log).
  3. Increment retry counter; update `.ohaze/current-ship.json` `retries` field.
  4. Re-run Phase 5 (review).

- If reviewer returns `VERDICT: FAIL` and retry == 3:
  - Stop and report all 3 attempts' findings to the user in a structured summary:
    ```
    Codex 已尝试修复 3 次, 审查仍未通过. 当前状态:

    第 1 轮 issues: ...
    第 2 轮 issues: ...
    第 3 轮 issues: ...

    选项:
    1. 继续让 Codex 再试 1 次 (`/ohaze:ship-review --more`)
    2. 你手动介入修复
    3. 接受现状直接进入 finishing
    ```
  - Wait for user choice. Do NOT auto-retry past 3.

## What this skill does NOT do

- Does NOT translate plan to prompt — that's `ohaze:plan-to-codex-prompt`.
- Does NOT run brainstorming, planning, worktree setup, or finishing — those are superpowers skills, orchestrated by `/ohaze:ship`.
- Does NOT poll Codex status mid-run for `--background` mode. The `/ohaze:ship-review` command is the user-driven trigger to proceed.

## Failure modes and recovery

- **`codex` binary not found**: report the failure, suggest `/codex:setup` if not yet run. Do not improvise an inline implementation.
- **Background nohup exits immediately (pid no longer alive within 5s)**: tail the log file — Codex likely refused to start (auth issue, sandbox flag rejected by old codex version, prompt file unreadable). Surface the actual error.
- **Reviewer subagent returns malformed verdict**: re-dispatch the reviewer once with stricter format guidance. If it fails again, fall back to asking user to read `git diff` and decide.
- **Worktree state is dirty after Codex log says done**: read the log's `Notable implementation choices` and `Touched files` to confirm completion intent. The orchestrator should then commit per the Task message mapping in Phase 5.0.
- **`codex resume --last` fails to find prior thread**: fall back to fresh `codex exec` with combined "original task + fix delta" prompt. Note this in the retry log so the reviewer knows context may have been lost.
