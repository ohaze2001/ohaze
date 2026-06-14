---
name: debug-to-codex-prompt
description: Use when handing a systematic-debugging investigation + fix plan to Codex for execution within /ohaze:debug Phase 4. Thin XML wrapper that embeds scope-lock file whitelist + investigation context + fix plan + verification loop + anti-regression contract.
---

# Debug → Codex Prompt

Translate a completed `/ohaze:debug` investigation into a single XML prompt string ready to pass to `ohaze:codex-executor` as `codex_prompt`.

This skill is a wrapper, not a reviewer. Do not redo root-cause analysis, do not revise the fix plan, and do not widen scope. If required inputs are malformed, fail loudly so `/ohaze:debug` can preserve the worktree and report the issue.

## Invocation Contract

Inputs:

- `investigation_path` (absolute path, required): points at the investigation note in the worktree.
- `scope_lock_files` (list of absolute paths, required): must be non-empty; every entry must be under `worktree_path`.
- `fix_plan` (markdown string, required): must contain either the Variant A or Variant B anti-regression contract from `ohaze:systematic-debugging`.
- `project_test_command` (string, required): either an aggregate test command or the sentinel `'(per-Task acceptance assertions inline in plan)'`.
- `worktree_path` (absolute path, required): isolated workspace Codex will edit.
- `main_repo_path` (absolute path, required): read-only reference checkout.
- `base_ref` (string, required): review base, normally `main`.

Output:

- A single XML string ready to pass to `ohaze:codex-executor` as `codex_prompt`.

Validation before output:

- Read `investigation_path` and embed its contents verbatim.
- Reject empty `scope_lock_files`.
- Reject any `scope_lock_files` entry that is not an absolute path under `worktree_path`.
- Reject `fix_plan` if it lacks an Anti-regression contract with `Variant A` or `Variant B`.
- Substitute call-time values for all placeholders. The returned XML MUST NOT leave literal placeholders like `{project_test_command}`, `{worktree_path}`, `{main_repo_path}`, or `{base_ref}`.

## XML Template

Return the XML elements below in this exact top-level order.

```xml
<task>
The root-cause investigation is complete. Your job is to execute the fix plan inside {worktree_path}, write or preserve the required regression evidence, verify, and report.

Do NOT redo root-cause investigation. Do NOT broaden scope. Do NOT edit outside <editable_files>.
</task>

<investigation>
{verbatim contents of investigation_path}
</investigation>

<fix_plan>
{verbatim fix_plan markdown}
</fix_plan>

<editable_files>
You MAY modify these files (and only these files):
{newline-separated absolute paths from scope_lock_files}
</editable_files>

<readonly>
Everything else is READONLY.

You must NOT WRITE/MODIFY/DELETE/CREATE outside <editable_files>. If the fix plan cannot be completed without another file, stop and report this exact escape hatch line instead of silently violating scope:

scope_lock_breach_requested: <file> — reason: <why>

main_repo_path is read-only reference context: {main_repo_path}
base_ref for review is: {base_ref}
</readonly>

<commit_handling>
ohaze orchestrator handles commits. Leave all changes uncommitted. Do not run git add, git commit, git push, or PR commands.
</commit_handling>

<verification_loop>
Use the anti-regression contract from <fix_plan> and report which variant you executed.

Variant A: for aggregate project test commands. First create or update the failing regression test and run the narrow command that demonstrates it fails pre-fix. Then implement the fix and run the full suite post-fix with {project_test_command}. Your report must include the failing-test evidence, full-suite command, exit status, and tail output.

Variant B: for Markdown-only projects or sentinel project_test_command = '(per-Task acceptance assertions inline in plan)'. Run per-assertion grep, JSON-load, structure checks, and a dogfood smoke check that directly covers the changed contract. Your report must include every assertion command, exit status, and tail output where useful.
</verification_loop>

<anti_regression>
- No refactor while you're there.
- No rename for consistency.
- No error handling not specified in fix_plan.
- 1-2 files better than 5 files when the root cause is narrow.
- Preserve behavior outside the root cause and scope lock.
</anti_regression>

<output_format>
Your final message MUST contain:

Tasks completed: one-line summary.
Touched files: list absolute paths; this must match <editable_files> exactly unless a scope_lock_breach_requested line is reported.
Test verification output: command + exit + tail.
Suggested commit message: fix: <one-liner>
Scope lock breach section: empty if none, OR scope_lock_breach_requested details.
</output_format>
```

## Assembly Notes

- The `<investigation>` section embeds `investigation_path` verbatim.
- The `<fix_plan>` section embeds `fix_plan` verbatim, including its Variant A or Variant B anti-regression contract.
- The `<editable_files>` section uses only `scope_lock_files`; no other downstream input may widen it.
- XML escaping is required only where the host tool requires it. Preserve human-readable markdown content as much as possible.
- After returning the XML string, `/ohaze:debug` writes it to `<worktree_path>/.ohaze/codex-debug-prompt.xml` and calls `codex-executor` in dispatch mode.

## What This Skill Does Not Do

- It does not invoke Codex.
- It does not modify files.
- It does not commit.
- It does not run review.
- It does not infer additional editable files.
