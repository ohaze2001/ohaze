---
name: plan-to-codex-prompt
description: Use when handing an ohaze:writing-plans guidance plan to Codex for end-to-end execution. Thin wrapper that embeds the plan in the XML prompt contract that `codex exec` (via ohaze:codex-executor) expects.
---

# Plan → Codex Prompt

Translate an `ohaze:writing-plans` output (`docs/superpowers/plans/<date>-<feature>.md`) into a complete XML-block prompt that gets piped into `codex exec` by `ohaze:codex-executor`.

`ohaze:writing-plans` already produces a guidance-form plan (behavior contracts + acceptance criteria, no prescriptive code), so **this skill is a thin verbatim wrapper** — no distillation needed. The plan is the contract; Codex picks the implementation.

## When to invoke

- Inside `/ohaze:ship` after `ohaze:writing-plans` saves a plan and the user approves it.
- Standalone: when the user already has a guidance plan and wants to hand it off.

If the input plan is **not** from `ohaze:writing-plans` (e.g., it's a `superpowers:writing-plans` output with prescriptive code blocks), warn the user — Codex's autonomy will be lost. The right fix is to rewrite via `ohaze:writing-plans`, not to distill here.

## Inputs

- `plan_path` (required): absolute path to the guidance plan markdown file.
- `project_test_command` (optional): e.g. `npm test`, `pytest`, `cargo test`. If unknown, inspect the project root for `package.json` / `Cargo.toml` / `pyproject.toml` and infer the most likely command. If still ambiguous, ask the user.

## Output contract

Produce a single string ready to be written to a prompt file and piped into `codex exec` by `ohaze:codex-executor`. The string MUST follow this exact XML block layout, in this order:

```
<task>
Execute the guidance plan saved at {plan_path}. Each Task specifies WHAT must be true at completion (behavior contracts + acceptance criteria), not HOW to write it line by line. You decide the implementation. Honor the Files lists, behavior contracts, and acceptance criteria.

The plan content is reproduced below.

---PLAN START---
{full verbatim contents of plan.md, no truncation, no rewriting}
---PLAN END---
</task>

<completeness_contract>
Done means ALL of:
1. Every Task's Behavior Contract is met (the code does what the contract says).
2. Every Task's Acceptance Criteria are satisfied (tests pass, files exist, manual checks succeed, public interfaces conform).
3. The full project test command `{project_test_command}` reports zero failures.
4. The working tree contains the file changes described in the Files lists. Reasonable refactoring inside the listed files is allowed; touching files NOT in any Task's Files list is not.

Skip git commits — see <commit_handling> below.
</completeness_contract>

<commit_handling>
ohaze keeps commit authority at the orchestrator (Claude main session) by convention, not because of sandbox. You technically have permission to `git add` / `git commit` under `danger-full-access`, but **do NOT do it**. The orchestrator commits per-Task using a consistent message style, sometimes splits commits across Tasks based on file overlap, and integrates the commits into the vault-adapter discussions log. Self-committing breaks this pipeline.

For every Task's commit step in the plan: skip the actual `git` command. Consider the Task done as long as the code/test changes are written and verification passed.

In your final report (see <output_report>), set `Commits made: skipped (orchestrator handles)` and provide a suggested commit message **per Task** in the form `<type>(<area>): <one-line>` — the orchestrator may adjust.
</commit_handling>

<verification_loop>
After completing each Task, run `{project_test_command}`. If any test fails, fix it within the same Task before moving on. Do not proceed past a failing test.

At the very end, run `{project_test_command}` one more time and confirm zero failures before reporting done.
</verification_loop>

<implementation_autonomy>
The guidance plan tells you what each Task must accomplish. It does NOT prescribe how to write the code. You have autonomy over:
- Internal function names, variable names, control flow
- Choice of helper utilities (write inline vs extract to lib)
- Algorithm and data structure selection where the contract doesn't pin one
- Code organization within a Task's file list
- Test framing (so long as the acceptance criteria are testable)

You do NOT have autonomy over:
- Public interfaces / function signatures listed in the contract
- File paths in the Files lists
- Acceptance criteria (you must meet them, not invent your own)
- Cross-Task invariants (Task 2's contract cannot violate Task 1's)
</implementation_autonomy>

<grounding_rules>
- Stay within the file paths listed in the plan's Files: sections. New files allowed only if a Task's Create list permits.
- Do NOT change project dependencies (package.json / Cargo.toml / pyproject.toml additions) unless the plan explicitly adds them.
- Reasonable in-file refactoring is OK; cross-file refactoring that touches files not in any Task's Files list is NOT OK.
- Do NOT introduce new top-level config files unless the plan creates them.
</grounding_rules>

<missing_context_gating>
If a Task's contract is ambiguous, contradicts another Task, or requires information not present in the plan or repository, do NOT guess. Stop work on that Task, write a short note in your final report identifying the ambiguity, and continue with subsequent Tasks if they are independent.
</missing_context_gating>

<action_safety>
- Never push to a remote branch.
- Never force-push.
- Never delete files not explicitly listed for deletion in the plan.
- Never bypass git hooks (no --no-verify).
- Run only the commands needed for the task, plus the project test command.
</action_safety>

<output_report>
At the end, report in this format:
- Tasks completed: N / total
- Tasks with concerns: list any Task numbers where you flagged ambiguity or partial completion, with one-line explanation each
- Final test status: PASS / FAIL with summary
- Touched files: full list grouped by Create / Modify / Delete
- Commits made: skipped (sandbox blocks .git/) — provide one suggested commit message per Task in the form `<type>(<area>): <one-line>` so the orchestrator can apply them.
- Notable implementation choices: 2-5 bullets describing non-obvious decisions you made within the autonomy granted (e.g. "Chose lockfile under /tmp not /var/lock because hook runs as user not root", "Used jq instead of python for JSON merging because already a project dep"). This helps the reviewer understand intent.
</output_report>
```

## Notes for Claude when assembling the prompt

- The `{full verbatim contents of plan.md}` slot is non-negotiable for ohaze:writing-plans output. The plan is already the right size and shape (contract form). Do not summarize, reformat, or strip checkboxes.
- If `plan.md` is over 30,000 characters, embed it as-is anyway — Codex handles long plans fine.
- If `project_test_command` truly cannot be determined, leave the literal placeholder `{project_test_command}` AND stop before sending; ask the user. Do not guess `npm test` for a project that has no `package.json`.
- After producing the prompt string, the caller (typically `ohaze:codex-executor` skill) writes it to `<worktree>/.ohaze/codex-prompt.xml` and pipes it into `codex exec --sandbox danger-full-access` running in the background.

## What this skill does NOT do

- It does not invoke Codex. That is `ohaze:codex-executor`'s job.
- It does not modify the plan. The plan is the source of truth.
- It does not distill or rewrite the plan. `ohaze:writing-plans` already produced it in guidance form; if the input plan is prescriptive (e.g., from upstream `superpowers:writing-plans`), this skill warns rather than fixes.
- It does not split the plan into multiple Codex runs. End-to-end is a V1 design choice.
