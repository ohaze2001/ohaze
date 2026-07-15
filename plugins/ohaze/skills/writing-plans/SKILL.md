---
name: writing-plans
description: Use when you have a spec or requirements for a multi-step task that will be executed by Codex; saves guidance plans under docs/ohaze/plans/.
---

# Writing Plans (ohaze)

## Overview

Write **guidance-first implementation plans** for downstream Codex execution. The plan tells Codex *what* must be true at each Task's completion (behavior contracts, interfaces, files affected, acceptance criteria) without prescribing *how* (no complete function bodies, no variable names, no line-by-line steps).

This skill is forked-and-adapted from `superpowers:writing-plans` (Jesse Vincent, MIT). Architecture, TDD rhythm, Task decomposition, self-review — all preserved. The change is **what goes inside each Task**: contracts instead of code.

**Why**: Codex is a capable implementer, not a typist. When you hand it a plan that already contains every variable name and every line of code, it degrades to dictation and you lose its judgment. Plans that bound the contract but leave the implementation open give Codex room to make local quality decisions.

**Announce at start:** "I'm using the ohaze:writing-plans skill to create the guidance plan."

**Context:** If working in an isolated worktree, it should have been created via the `ohaze:using-git-worktrees` skill at execution time.

**Save plans to:** `docs/ohaze/plans/YYYY-MM-DD-<feature-name>.md`

---

## Reading the Spec — Handle Implementation Details

The input spec is a design document for humans. It often contains implementation details — complete function bodies, executable scripts, specific variable names, sed/awk one-liners, runner pseudocode — that were useful for the human design discussion but are **NOT** meant to be transcribed into the plan verbatim.

**The plan carries the contract; Codex picks the implementation.** When you encounter implementation details in the spec, transform them:

| Spec contains | Plan should have |
|---|---|
| Complete function body (more than 3 executable lines) | Behavior Contract: signature + inputs/outputs/side-effects/error-boundaries |
| Complete executable script | Behavior Contract: entry point + invariants (lockfile, timeout, exit codes) + side effects |
| Specific internal variable names (`N`, `TOTAL`, `ERR_NOTICE`) | (omit — Codex picks names) |
| Hardcoded `sed`/`awk`/`grep` one-liners | Intent only: "extract lines after marker", not the syntax |
| "Step 3.1: write this line; Step 3.2: write that line" | Acceptance: "after execution, file contains <expected content>" |

### Concrete example

If the spec has this:

````bash
consume_errors_log() {
  local logfile="$HOME/Brain/99_System/Logs/hook-errors.log"
  local marker="$HOME/Brain/99_System/Logs/hook-errors.last-read"
  [[ ! -f "$logfile" ]] && return

  local N=0
  [[ -f "$marker" ]] && N=$(cat "$marker")
  local TOTAL=$(wc -l < "$logfile")

  if (( TOTAL > N )); then
    ERR_NOTICE=$(tail -n $((TOTAL - N)) "$logfile" | tail -n 3)
    echo "$TOTAL" > "$marker"
  fi
}
````

Your Task should describe:

> **Files**:
> - Modify: `vault-system/hooks/lib/common.sh` (add function)
> - Test: `vault-system/hooks/tests/test-common.sh`
>
> **Behavior Contract**:
> - Public: `consume_errors_log()` — no arguments, no return value
> - Reads `$HOME/Brain/99_System/Logs/hook-errors.log` from the marker position to end of file, captures **at most the last 3 unread lines** into env var `ERR_NOTICE`
> - Updates marker at `$HOME/Brain/99_System/Logs/hook-errors.last-read` to the current total line count
> - Tolerates missing log file (return silently, no error) or missing marker (treat as 0 unread)
>
> **Acceptance**:
> - [ ] Test: with marker at 0 and log containing 5 lines, `ERR_NOTICE` contains the last 3 lines and marker is updated to 5
> - [ ] Test: missing log file → function returns silently, no error written
> - [ ] Test: missing marker → all log lines are treated as unread
>
> (Reference: spec §5.3 for original design discussion)

Do **NOT** copy the bash function body into the plan. The contract above is what Codex needs; how to implement it (variable naming, control flow, whether to use `awk` instead of the loop) is Codex's choice.

### What to keep from the spec verbatim

These belong in the spec **and** in the plan unchanged — they're contracts, not implementation:

- **Interface signatures** (function/method/CLI args/HTTP routes) — these are the contract surface
- **JSON / YAML / TOML config blocks** — these are data, not code
- **Log line / output format examples** — locking these locks the contract
- **Error message text users will see** — that's UX, not implementation
- **Test assertion text when the assertion IS the acceptance criterion** — copy verbatim

### Why this matters

If you transcribe the spec's code into the plan, two things go wrong:

1. **Codex degrades to a typist** — it executes by character, not by reasoning. You lose its judgment on edge cases, helper extraction, error path design.
2. **Bugs propagate verbatim** — specs are design-time artifacts, often imperfect. Transcribing them locks the imperfection into shipped code. The plan-as-contract pattern lets Codex catch and fix design-time mistakes during implementation.

Transcribing also makes the plan brittle: a single variable rename in the spec forces a re-edit of the plan.

---

## Scope Check

If the spec covers multiple independent subsystems, it should have been broken into sub-project specs during brainstorming. If it wasn't, suggest breaking this into separate plans — one per subsystem. Each plan should produce working, testable software on its own.

---

## File Structure

Before defining tasks, map out which files will be created or modified and what each one is responsible for. This is where decomposition decisions get locked in.

- Design units with clear boundaries and well-defined interfaces. Each file has one clear responsibility.
- Prefer smaller, focused files over large ones that do too much.
- Files that change together should live together. Split by responsibility, not by technical layer.
- In existing codebases, follow established patterns. Don't unilaterally restructure unless a file you're modifying has grown unwieldy.

This structure informs the task decomposition. Each task should produce self-contained changes that make sense independently.

---

## Bite-Sized Task Granularity

Each Task is a unit of work that produces a self-contained, testable change.

**Each step within a Task is one action (2-5 minutes)**:
- "Write the failing test asserting <behavior>" — step
- "Verify it fails for the right reason" — step
- "Implement the minimal code to satisfy the contract" — step
- "Verify all tests pass" — step
- "Commit with suggested message: <type>(<area>): <one-line>" — step

Note the contrast with the upstream superpowers writing-plans: steps still exist, but they describe **actions on the contract**, not code-block recipes.

---

## Plan Document Header

**Every plan MUST start with this header:**

```markdown
# [Feature Name] — Guidance Plan

> **For Codex (the executor):** Each Task below specifies WHAT must be true at completion, not HOW to write it line by line. You have autonomy over internal naming, control flow, helper extraction, and algorithm choice. You do NOT have autonomy over public interfaces, file paths in Files lists, acceptance criteria, or cross-Task invariants. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach — the WHY of the design, not the HOW of the implementation]

**Tech Stack:** [Key technologies/libraries already in use, that this work plugs into]

---
```

---

## Task Structure (guidance form)

> **禁列四件套 as Task deliverables:** Do not put `CLAUDE.md`, `README.md`, `ROADMAP.md`, `CHANGELOG.md`, or the project manifest (`plugin.json` / `package.json` / `Cargo.toml` / etc.) in any Task's Files list for routine doc synchronization. These writes are closed by `ohaze:finishing`'s `doc-finish` step. Acceptance Criteria must not assert four-piece side effects such as "CHANGELOG entry exists" or "ROADMAP ticked". If the spec says the four-piece must be updated, add one note at the end of the plan: `四件套同步由 doc-finish 收口`; do not create a Task for it.

Every Task uses this exact structure:

````markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.ext`
- Modify: `exact/path/to/existing.ext`
- Test: `tests/exact/path/to/test.ext`

**Behavior Contract:**
- **Public interface(s)**: function signatures, class methods, CLI args, HTTP endpoints, log line format — whatever this Task exposes to other Tasks or external callers. List signatures only (e.g. `parseConfig(path: string): Config` — no body).
- **Inputs**: type constraints, valid ranges, accepted formats
- **Outputs**: return shape, written files, network calls, log writes
- **Side effects**: any state mutation outside the function's own return (DB writes, file writes, env mutations)
- **Error boundaries**: which conditions raise, which conditions fail-soft, which conditions retry
- **Invariants that must hold**: e.g. "function is idempotent", "lockfile prevents concurrent invocation"

**Acceptance Criteria:**
- [ ] Test: [describe what the test asserts — the behavior under test, not the test code itself]
- [ ] Test: [another assertion]
- [ ] Manual check (if applicable): [describe the manual verification, e.g. "running `./run.sh` produces a file at X containing Y"]
- [ ] Interface conformance: public signatures match what the Behavior Contract listed

**TDD Sequence:**
- [ ] Step 1: Write a failing test that asserts the behaviors listed in Acceptance Criteria
- [ ] Step 2: Run the test, confirm it fails for the reason you expect
- [ ] Step 3: Implement code satisfying the Behavior Contract — your choice on internal structure
- [ ] Step 4: Run tests, confirm all pass
- [ ] Step 5: Optional in-file refactor for clarity, if it doesn't change the Contract
- [ ] Step 6: Commit. Suggested message: `<type>(<area>): <one-line summary>`. The orchestrator may rewrite — that's fine.

**Cross-Task Dependencies (if any):**
- "Depends on Task M's <interface>" — list the contract surface this Task consumes from earlier Tasks
- "Provides <interface> for Task K" — list what later Tasks depend on
````

### Acceptable code blocks inside a Task

These are the **only** kinds of code blocks that belong in a Task:

1. **Interface signatures** — function/method/class signatures **without bodies**
2. **Type definitions** — TypeScript interfaces, Python TypedDict, Rust structs, etc. (data shapes are contracts)
3. **JSON/YAML/TOML config samples** — these are data, not implementation
4. **Log line / output format examples** — to lock the contract
5. **Test assertions** — only when the assertion text *is* the acceptance criterion (e.g. "assert response.status == 200"). Not full test functions.

These are **forbidden** code blocks:

- Complete function bodies (> 3 executable lines)
- Complete shell scripts
- Specific `sed` / `awk` / `grep` one-liners
- Step-by-step "write this line then that line" walkthroughs

---

## No Placeholders

Every step must contain real, actionable content. These are **plan failures** — never write them:

- "TBD", "TODO", "implement later", "fill in details"
- "Add appropriate error handling" — say *which* errors, *what* boundary
- "Handle edge cases" — list the edge cases that matter
- "Write tests for the above" — list the behaviors to test
- "Similar to Task N" — restate the contract (the reader may be reading Tasks out of order)
- Acceptance criteria that aren't checkable ("should work well")
- References to interfaces, types, or files not defined in any Task or import
- 四件套写入 as Task deliverables (`CLAUDE.md` / `README.md` / `ROADMAP.md` / `CHANGELOG.md` / manifest) — delete them from the Task and hang them under `doc-finish` closure per the Task Structure `禁列四件套` callout.

---

## Calibration: where to draw the line

Two failure modes to avoid:

**Too prescriptive** (the upstream superpowers behavior we're avoiding):
- Writing complete `function foo() { ... }` bodies
- Specifying variable names like `let N = 0; let TOTAL = wc -l ...`
- Telling Codex which library function to call internally

**Too vague** (a guidance plan failing the other way):
- "Build the feature" — no behaviors, no files, no acceptance
- Acceptance like "it works" — no checkable assertion
- Missing public interface signatures — Codex can't know what to expose

Sweet spot: **a senior engineer reading this plan should know exactly what to deliver, but a junior engineer reading it might not know which library calls to use** — that's intentional. We're delegating implementation, not delegating understanding.

---

## Remember

- Exact file paths always
- Contract per Task, not code per Task
- Acceptance criteria must be checkable (test assertion, file existence, command output, signature match)
- DRY, YAGNI, TDD, frequent commits — the discipline survives the formatting change

---

## Self-Review

After writing the complete plan, look at the spec with fresh eyes and check:

**1. Spec coverage:** Skim each section/requirement in the spec. Can you point to a Task that implements it? List any gaps and add Tasks for them.

**2. Placeholder scan:** Search your plan for red flags — TBD/TODO/"appropriate"/"handle edge cases". Replace with concrete contracts or behaviors.

**3. Contract leakage:** Search your plan for forbidden code blocks (complete function bodies, shell scripts, sed/awk one-liners). Replace with behavior descriptions. **Pay special attention to code blocks copied from the spec** — those are the most common source of leakage. The spec is allowed to have them (it's a human discussion artifact); the plan is not (it's a Codex execution contract). Apply the transformation table from "Reading the Spec" section.

**4. Contract consistency:** Do interface signatures used in later Tasks match what earlier Tasks declared? A function called `clearLayers()` in Task 3 but `clearFullLayers()` in Task 7 is a bug.

**5. Acceptance checkability:** For each Acceptance Criteria, can you imagine the exact bash command or assertion that proves it? If not, sharpen it.

If you find issues, fix them inline. No need to re-review — just fix and move on.

---

## Optional: Plan Document Reviewer

For larger plans (≥ 4 Tasks or > 200 lines), optionally dispatch the plan-document-reviewer subagent using the prompt in `plan-document-reviewer-prompt.md`. It catches gaps the self-review may have missed. For small plans, skip — the self-review is enough.

---

## Execution Handoff

After saving the plan, do NOT show superpowers:writing-plans' "Subagent-Driven vs Inline Execution" menu — that menu belongs to a different execution model.

Inside the ohaze flow (`/ohaze:ship`), emit a one-line summary and hand control back to Phase 3.5. Do not wait for a user "go"; `/ohaze:ship` owns default-go and interruptibility.

Use this format:

> "📋 Plan saved → `docs/ohaze/plans/<filename>.md`, <N> Tasks, areas: <X>/<Y>/<Z>. Handing back to /ohaze:ship Phase 3.5 which will summarize and dispatch Codex."

This "hand back" line is a return-from-subroutine signal, NOT an end-of-turn signal. `/ohaze:ship` Phase 3.5 proceeds in the same turn, prints the user-facing plan summary, applies default-go, and dispatches Codex unless the user interrupts with non-go content.

If invoked standalone (not inside `/ohaze:ship`), just print:

> "Guidance plan saved to `docs/ohaze/plans/<filename>.md`. Standalone mode: next step is to hand it to Codex via `ohaze:plan-to-codex-prompt`, or invoke `/ohaze:ship` to dispatch through the full flow."

---

## What this skill does NOT do

- It does not execute the plan. That's `codex exec` (dispatched by `ohaze:codex-executor`).
- It does not invoke `superpowers:subagent-driven-development` or `superpowers:executing-plans`. Those are different execution models incompatible with ohaze's Codex-end-to-end flow.
- It does not write the spec. That's `/ohaze:ship` Phase 1.5 (Claude writes it from the `ohaze:brainstorming` brief).
- It does not modify or distill an existing plan. For that, edit the file or re-invoke this skill against the spec.

---

## Attribution

Forked from `superpowers:writing-plans` v5.1.0 (Jesse Vincent, MIT license, https://github.com/obra/superpowers). The architectural skeleton (Scope Check, File Structure, Bite-Sized Tasks, Plan Header, Self-Review, plan-document-reviewer pattern) is preserved verbatim or near-verbatim. The Task Structure section was rewritten to produce contracts instead of code. The "Calibration", "Acceptable code blocks", and "Contract leakage" sections were added.
