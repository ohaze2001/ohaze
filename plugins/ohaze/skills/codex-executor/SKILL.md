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

## Phase 4: Dispatch Codex

There are TWO paths. Try Path A first; fall back to Path B if A fails or returns empty stdout (typically because the subagent lacks Bash permission).

### Path A — preferred: codex:codex-rescue subagent

```
Agent(
  subagent_type="codex:codex-rescue",
  description="Execute plan via Codex",
  prompt=f"--background --write {codex_prompt}"
)
```

Notes:
- `--background --write` are routing flags consumed by the codex-rescue forwarder.
- Do NOT add any natural-language instruction outside the XML — the XML is the entire prompt.
- The subagent returns its stdout verbatim. Capture the codex run identifier from the response.

### Path B — fallback: direct Bash invocation

If Path A returns empty / errors / reports missing Bash permission, do NOT abort. Run the same command directly from the main session:

```bash
# Resolve current codex plugin install path
codex_root=$(ls -d ~/.claude/plugins/cache/openai-codex/codex/*/ | sort -V | tail -1)

# Dispatch the same task. Note: codex_prompt is the full XML string from
# ohaze:plan-to-codex-prompt — embed it as a single-quoted literal.
node "${codex_root}scripts/codex-companion.mjs" task --background --write '<codex_prompt>'
```

The stdout contains a line like `Codex Task started in the background as task-XXXXXXX-YYYYYY`. Extract the job ID.

### Why the fallback exists

Subagents in Claude Code require `Bash(node:*)` (or a more specific pattern) to be present in the user's `~/.claude/settings.json` `permissions.allow` array, because subagents have no interactive permission UI. If the user hasn't pre-approved this, Path A silently fails and Path B is the only way through. The functional result is the same — Codex runs the same prompt either way; we only lose the codex-rescue subagent's optional gpt-5-4-prompting refinement, which is redundant since `ohaze:plan-to-codex-prompt` already produces a tight XML contract.

### After dispatch (either path)

Immediately tell the user:

> "Codex 已后台执行 (run_id=`<id>`). 用 `/codex:status <id>` 看进度, 跑完后用 `/ohaze:ship-review` 触发审查."

Then stop. The session ends here. Phases 5-6 happen later in `/ohaze:ship-review`.

If the user passed `mode=--wait`, swap `--background` for `--wait` in the prompt and proceed inline to Phase 5 in the same turn.

## Phase 5: Claude-side Review

Trigger this when the Codex run completes (signaled by `/codex:status` reporting done, or invoked from `/ohaze:ship-review`).

### Phase 5.0: Apply Codex's pending changes as commits (REQUIRED)

Codex's sandbox blocks `.git/` writes (this is by design — see plan-to-codex-prompt's `<commit_handling>`), so Codex leaves uncommitted changes in the worktree. Before review, the orchestrator must commit those changes using the messages the plan specified.

1. Fetch Codex's final result: run `/codex:result <run_id>` (or read its output if already returned). Look for the `Commits made: skipped ...` line listing the intended commit messages.

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

PART 1 — Spec compliance:
- Read the plan file in full.
- Walk through `git diff {base_ref}...HEAD` and the commit log.
- For each Task in the plan: did Codex implement it? Are the listed Files actually changed? Are the test files present and tests actually written?
- Flag: missing tasks, extra unrequested changes, test files that exist but don't match the plan's specified test cases.

PART 2 — Code quality:
- Standard quality concerns: error handling, edge cases, naming, dead code, leaked secrets.
- Do NOT flag style nits the plan didn't require.
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
  2. Dispatch with `--resume` flag (continues the same Codex thread):
     ```
     Agent(
       subagent_type="codex:codex-rescue",
       description="Codex fix iteration {retry+1}",
       prompt=f"--resume --write {fix_prompt}"
     )
     ```
  3. Wait for completion (use `--wait` for retries since we're already mid-loop and the user is engaged).
  4. Increment retry counter.
  5. Re-run Phase 5 (review).

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

- **Codex dispatch fails (subagent returns nothing)**: report the failure, suggest `/codex:setup` if not yet run. Do not improvise an inline implementation.
- **Reviewer subagent returns malformed verdict**: re-dispatch the reviewer once with stricter format guidance. If it fails again, fall back to asking user to read `git diff` and decide.
- **Worktree state is dirty after Codex says done**: report it; do NOT auto-commit. Codex should have committed per the plan; dirty state means something is off.
