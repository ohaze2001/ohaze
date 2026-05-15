---
name: plan-to-codex-prompt
description: Use when handing a superpowers writing-plans output to Codex for end-to-end execution. Distills the plan into a guidance contract (intent + interfaces + acceptance), then wraps it in the XML prompt the codex:codex-rescue subagent expects.
---

# Plan → Codex Prompt

Translate a `superpowers:writing-plans` output (`docs/superpowers/plans/<date>-<feature>.md`) into a complete XML-block prompt for the `codex:codex-rescue` subagent.

**Design philosophy**: `superpowers:writing-plans` produces highly prescriptive plans with complete code in every step. That's fine for human engineers, but it kills Codex's local decision-making and reduces it to a typist. This skill **distills** the plan into a guidance contract — intent, interfaces, files, acceptance — and lets Codex pick the implementation.

## When to invoke

- Inside `/ohaze:ship` after `superpowers:writing-plans` saves a plan and the user approves it.
- Standalone: when the user already has a plan.md and wants to hand it off.

## Inputs

- `plan_path` (required): absolute path to the plan markdown file.
- `project_test_command` (optional): e.g. `npm test`, `pytest`, `cargo test`. If unknown, inspect the project root for `package.json` / `Cargo.toml` / `pyproject.toml` and infer the most likely command. If still ambiguous, ask the user.

## Phase 1 — Distill plan into guidance

Read the plan at `plan_path`. Produce a **guidance plan** by applying the rules below. Write the result to `<plan_path basename>.guidance.md` in the same directory (e.g. `docs/superpowers/plans/2026-05-16-foo.md` → `docs/superpowers/plans/2026-05-16-foo.guidance.md`). This file is what Codex sees.

### Keep (these are contracts, not implementation)

- Title and one-line goal / overview
- The complete **Task list** (numbering, titles, ordering)
- For each Task: **Files Affected** list with absolute or repo-relative paths (Create / Modify / Test)
- For each Task: **behavior contract** — what the code must do, including inputs, outputs, side effects, error boundaries
- For each Task: **acceptance criteria** — what tests must pass, what files must exist, what manual checks succeed
- **Interface schemas** — JSON request/response shapes, log line formats, exit codes, env var names that other components depend on
- **Type / function signatures** without bodies (signatures are contracts)
- Configuration files content (JSON / YAML / TOML) — these are data, not code
- Non-Goals (explicit exclusions)
- Risks and their mitigations (strategy, not code)
- Cross-Task invariants (e.g. "Task 2 must not change Task 1's API")

### Strip (these are implementation prescription)

- Complete **function bodies** (> 3 lines of executable code inside a function)
- Complete **executable scripts** (bash / python / shell snippets meant to be copy-pasted)
- Specific variable names and internal control flow ("`local N=0; if (( TOTAL > N ))`")
- Tool-specific syntax when the intent is portable (`sed`, `awk`, `grep` one-liners — describe the intent: "extract lines after marker", not the command)
- Step-by-step granularity within a Task ("Step 3.1 write this line; Step 3.2 write that line")
- TDD's per-line code blocks — replace with "Write a test that asserts <behavior>"

### Gray zones (judgment calls)

- **Test code**: if a test's exact assertion is the acceptance criterion, keep it. If it's testing implementation details, abstract to "Test that <behavior>".
- **Tiny utility functions** (< 5 lines): keep only if they're effectively contracts (type guards, validators). Otherwise strip.
- **Algorithms** with a specific correctness requirement: describe the algorithm at concept level, not the implementation.

### Output structure

The guidance plan should look like:

```markdown
# Guidance Plan: <feature>

> One-line goal.

## Tasks Overview

1. <Task 1 title>
2. <Task 2 title>
...

## Task 1: <title>

**Files**:
- Create: `path/to/new.ts`
- Modify: `path/to/existing.ts`
- Test: `path/to/new.test.ts`

**Behavior contract**:
- The function `foo(x: string): Promise<Bar>` should return ... when ..., and throw ... when ...
- Side effect: writes a row to <table> with shape `{...}`
- Error boundary: if <X>, fail with <error code> — do not retry

**Acceptance**:
- `npm test path/to/new.test.ts` passes
- Manual: `curl /api/foo` returns 200 with shape `{...}`

## Task 2: ...
```

## Phase 2 — Wrap guidance into XML prompt

Once the guidance plan is written to disk, produce the XML prompt string for `codex:codex-rescue`. Use this exact layout:

```
<task>
Execute the implementation guidance saved at {guidance_plan_path}. Each Task describes WHAT must be true at completion, not HOW to write it line by line. You decide the implementation. Honor the Files lists, behavior contracts, and acceptance criteria.

The full original plan is at {plan_path} for reference if you need additional context on rationale. The guidance plan is the authoritative source for what to do; the original plan is supplementary.

The guidance content is reproduced below.

---GUIDANCE START---
{full contents of the .guidance.md file}
---GUIDANCE END---
</task>

<completeness_contract>
Done means ALL of:
1. Every Task's behavior contract is met (the code does what the contract says).
2. Every Task's acceptance criteria are satisfied (tests pass, files exist, manual checks succeed).
3. The full project test command `{project_test_command}` reports zero failures.
4. The working tree contains the file changes described in the Files lists. Extra reasonable refactoring inside the listed files is allowed; touching files NOT in any Task's Files list is not.

Skip git commits — see <commit_handling> below.
</completeness_contract>

<commit_handling>
You are running inside Codex's `workspace-write` sandbox, which **blocks all writes to `.git/`**. Do NOT run `git add`, `git commit`, `git stash`, or any command that modifies git state. The sandbox will reject it with "Operation not permitted".

For every Task's commit step: skip the actual `git` command. Consider the Task done as long as the code/test changes are written and verification passed. The orchestrator (Claude main session) will commit afterwards.

In your final report (see <output_report>), set `Commits made: skipped (sandbox blocks .git/, orchestrator will commit)` and provide a suggested commit message **per Task** in the form `feat(<area>): <one-line>` or `fix(<area>): <one-line>` — the orchestrator may adjust.
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
- Stay within the file paths listed in the guidance plan's Files: sections. New files allowed only if a Task's Create list permits.
- Do NOT change project dependencies (package.json / Cargo.toml / pyproject.toml additions).
- Reasonable in-file refactoring is OK; cross-file refactoring that touches files not in any Task is NOT OK.
- Do NOT introduce new top-level config files unless guidance creates them.
</grounding_rules>

<missing_context_gating>
If a Task's contract is ambiguous, contradicts another Task, or requires information not present in the guidance or repository, do NOT guess. Stop work on that Task, write a short note in your final report identifying the ambiguity, and continue with subsequent Tasks if they are independent.
</missing_context_gating>

<action_safety>
- Never push to a remote branch.
- Never force-push.
- Never delete files not explicitly listed for deletion in the guidance.
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

- **Phase 1 distill is not optional**. Do not feed the raw `plan.md` directly into the XML.
- The `.guidance.md` file is a sibling of `plan.md`. If the user wants to compare or override the distillation, they can edit `.guidance.md` and re-invoke this skill (it overwrites on re-run).
- Preserve the guidance plan's structure (Tasks, Files, contracts, acceptance) in the XML — do not summarize further when embedding.
- If `plan.md` is already guidance-shaped (no code blocks > 3 lines, no full scripts), distillation should be near-identity. Don't introduce changes for the sake of it.
- If `project_test_command` cannot be determined, leave the literal placeholder `{project_test_command}` AND stop before sending; ask the user.
- After producing the prompt string, the caller (typically `ohaze:codex-executor` skill) will pass it to `codex:codex-rescue` along with `--background --write` flags.

## What this skill does NOT do

- It does not invoke Codex. That is `ohaze:codex-executor`'s job.
- It does not delete the original plan. Both `<plan>.md` (full, prescriptive) and `<plan>.guidance.md` (distilled, contract-only) coexist.
- It does not split the plan into multiple Codex runs. End-to-end is a V1 design choice.

## Why this design

Before this change, `plan-to-codex-prompt` was a thin verbatim wrapper. Codex received writing-plans' fully-prescribed implementation (complete function bodies, sed one-liners, variable names) and degraded to a typist. The reviewer then caught "Codex didn't do anything clever" — but there was nowhere to be clever.

After this change, the same upstream `superpowers:writing-plans` runs (we don't touch a shared skill that other workflows depend on), but the **transition boundary** between "engineer-facing plan" and "Codex-facing prompt" actively converts prescription into contract. Codex keeps the ship's Task structure and acceptance criteria, but the implementation lives in its hands.
