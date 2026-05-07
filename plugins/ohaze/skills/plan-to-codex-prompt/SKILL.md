---
name: plan-to-codex-prompt
description: Use when handing a superpowers writing-plans output to Codex for end-to-end execution. Wraps the plan.md content in the XML prompt contract that codex:codex-rescue expects.
---

# Plan → Codex Prompt

Translate a `superpowers:writing-plans` output (`docs/superpowers/plans/<date>-<feature>.md`) into a complete XML-block prompt for the `codex:codex-rescue` subagent.

The plan.md is already structured (Tasks with Files, Steps with code, TDD checkpoints), so this skill is a thin wrapper — not a rewrite. Preserve the plan content verbatim inside `<task>`.

## When to invoke

- Inside `/ohaze:ship` after `superpowers:writing-plans` saves a plan and the user approves it.
- Standalone: when the user already has a plan.md and wants to hand it off.

## Inputs

- `plan_path` (required): absolute path to the plan markdown file.
- `project_test_command` (optional): e.g. `npm test`, `pytest`, `cargo test`. If unknown, inspect the project root for `package.json` / `Cargo.toml` / `pyproject.toml` and infer the most likely command. If still ambiguous, ask the user.

## Output contract

Produce a single string ready to be passed as the `task` argument to `codex:codex-rescue`. The string MUST follow this exact XML block layout, in this order:

```
<task>
{one paragraph describing the goal: "Execute the implementation plan saved at {plan_path}. Follow each Task and each Step in order. For each Task, complete every step including the test verification and the commit step before moving on to the next Task."}

The plan content is reproduced below. Treat it as the authoritative source of truth.

---PLAN START---
{full verbatim contents of plan.md, no truncation, no rewriting}
---PLAN END---
</task>

<completeness_contract>
Done means ALL of:
1. Every Task's checkbox steps in the plan are completed.
2. Every commit step in the plan has been made (one commit per Task as the plan instructs).
3. The full project test command `{project_test_command}` reports zero failures.
4. `git status` is clean (no uncommitted changes, no untracked files left behind).
</completeness_contract>

<verification_loop>
After completing each Task's commit step, run `{project_test_command}`. If any test fails, fix the failing tests within the same Task before moving to the next Task. Do not proceed past a failing test.

At the very end, run `{project_test_command}` one more time and confirm zero failures before reporting done.
</verification_loop>

<grounding_rules>
- Stay strictly within the file paths listed in the plan's Files: sections (Create / Modify / Test).
- Do NOT modify files not explicitly referenced by the plan.
- Do NOT refactor adjacent code "while you are here".
- Do NOT upgrade or change project dependencies.
- Do NOT introduce new top-level files unless the plan creates them.
</grounding_rules>

<missing_context_gating>
If a Task's instructions are ambiguous, contradict each other, or require information not present in the plan or repository, do NOT guess. Stop work on that Task, write a short note in your final report identifying the ambiguity, and continue with subsequent Tasks if they are independent.
</missing_context_gating>

<action_safety>
- Never push to a remote branch.
- Never force-push.
- Never delete files not explicitly listed for deletion in the plan.
- Never bypass git hooks (no --no-verify).
- Run only the commands the plan instructs you to run, plus the project test command for verification.
</action_safety>

<output_report>
At the end, report in this format:
- Tasks completed: N / total
- Tasks with concerns: list any Task numbers where you flagged ambiguity or partial completion
- Final test status: PASS / FAIL with summary
- Touched files: full list grouped by Create / Modify / Delete
- Commits made: SHA + first line of each commit message
</output_report>
```

## Notes for Claude when assembling the prompt

- The `{full verbatim contents of plan.md}` slot is non-negotiable. Do not summarize, do not reformat, do not strip the checkboxes. Codex needs the exact step-by-step structure to follow the plan correctly.
- If `plan.md` is over 30,000 characters, embed it as-is anyway — Codex handles long plans fine.
- If `project_test_command` truly cannot be determined, leave the literal placeholder `{project_test_command}` AND stop before sending; ask the user. Do not guess `npm test` for a project that has no `package.json`.
- After producing the prompt string, the caller (typically `ohaze:codex-executor` skill) will pass it to `codex:codex-rescue` along with `--background --write` flags.

## What this skill does NOT do

- It does not invoke Codex. That is `ohaze:codex-executor`'s job.
- It does not modify the plan. The plan is the source of truth.
- It does not split the plan into multiple Codex runs. End-to-end is a V1 design choice.
