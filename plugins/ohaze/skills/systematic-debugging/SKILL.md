---
name: systematic-debugging
description: Use within /ohaze:debug Phase 3 to drive root-cause investigation (4 phases) and produce investigation report + scope-lock file list + fix plan. Owns G1 root-cause-deviation gate and G2 3-strike escalation.
---

# Systematic Debugging

## Overview

Random fixes waste time and create new bugs. Quick patches mask underlying issues.

**Core principle:** ALWAYS find root cause before attempting fixes. Symptom fixes are failure.

**Violating the letter of this process is violating the spirit of debugging.**

## Invocation Contract

Inputs:

- `symptom` (string, required): the user-visible broken behavior.
- `cause_hypothesis` (string or null): haze's suspected cause, if provided with `--cause`.
- `worktree_path` (string, required): isolated workspace where every investigation command runs.
- `main_repo_path` (string, required): read-only reference checkout for comparison only.

Terminal-state outputs are returned in the conversation, NOT written to files by this skill:

- `investigation_report`: markdown with the Phase 1, Phase 2, Phase 3, and Phase 4 findings.
- `scope_lock_files`: flat list of absolute paths under `worktree_path` only.
- `fix_plan`: markdown containing Root cause, Files+lines, a MANDATORY Anti-regression contract section, and an Anti-regression note.

Forbidden actions:

- Do not write files.
- Do not dispatch Codex.
- Do not commit, merge, push, or open a PR.
- Do not modify `main_repo_path`.
- All investigation commands MUST be scoped to `worktree_path`; use `main_repo_path` only as read-only context.

## The Iron Law

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

If you haven't completed Phase 1, you cannot propose fixes.

## When to Use

Use inside `/ohaze:debug` for bug-fix work:

- Test failures
- Bugs in production
- Unexpected behavior
- Performance problems
- Build failures
- Integration issues

**Use this ESPECIALLY when:**

- Under time pressure, because emergencies make guessing tempting.
- "Just one quick fix" seems obvious.
- Multiple fixes have already failed.
- A previous fix did not work.
- The issue is not fully understood.

**Don't skip when:**

- Issue seems simple; simple bugs have root causes too.
- You're in a hurry; rushing guarantees rework.
- The likely fix looks small; the cause still needs evidence.

## The Four Phases

You MUST complete each phase before proceeding to the next.

### Phase 1: Root Cause Investigation

**BEFORE attempting ANY fix:**

1. **Read Error Messages Carefully**
   - Don't skip past errors or warnings.
   - They often contain the exact solution.
   - Read stack traces completely.
   - Note line numbers, file paths, error codes, and timestamps.

2. **Reproduce Consistently**
   - Can you trigger it reliably?
   - What are the exact steps?
   - Does it happen every time?
   - If not reproducible, gather more data and do not guess.

3. **Check Recent Changes**
   - What changed that could cause this?
   - Inspect git diff, recent commits, changelog entries, dependency changes, and config changes.
   - Compare environmental differences only after checking code and state.

4. **Gather Evidence in Multi-Component Systems**

   **WHEN system has multiple components (CI to build to signing, API to service to database):**

   **BEFORE proposing fixes, add diagnostic observations without editing files:**

   ```text
   For EACH component boundary:
     - Record what data enters the component.
     - Record what data exits the component.
     - Verify environment/config propagation.
     - Check state at each layer.
   ```

   Run the smallest read-only or existing-command probe that shows where the data first becomes wrong. Then investigate that component.

5. **Trace Data Flow**

   **WHEN error is deep in a call stack:**

   - Where does the bad value originate?
   - What called this with the bad value?
   - Keep tracing up until you find the source.
   - Fix at source, not at symptom.

#### G1 — Root Cause Deviation Gate

If `cause_hypothesis is null`, G1 is inactive; proceed to Phase 2.

If `cause_hypothesis` is present, compare Phase 1's emerging root-cause hypothesis to it for semantic alignment, not verbatim wording. On material divergence, trigger exactly one `AskUserQuestion` with question `"调研根因与你的猜测有出入,怎么处理?"` and exactly these three options:

1. `接受调研根因 (Recommended)` — accept the evidence-backed root cause and continue.
2. `重新调研` — return to Phase 1 and gather more evidence.
3. `退出` — stop the debug flow cleanly.

Persist the decision in conversation memory so `/ohaze:debug` can report whether haze accepted, requested reinvestigation, or exited.

### Phase 2: Pattern Analysis

**Find the pattern before fixing:**

1. **Find Working Examples**
   - Locate similar working code in the same codebase.
   - Identify what works that's similar to what's broken.

2. **Compare Against References**
   - If implementing a pattern, read the reference implementation completely.
   - Don't skim.
   - Understand the pattern fully before applying it.

3. **Identify Differences**
   - What's different between working and broken?
   - List every difference, however small.
   - Don't assume "that can't matter."

4. **Understand Dependencies**
   - What other components does this need?
   - What settings, config, environment, runtime state, or generated files does it assume?

Add Phase 2 results to `investigation_report`.

### Phase 3: Hypothesis

**Scientific method:**

1. **Form Single Hypothesis**
   - State clearly: "I think X is the root cause because Y."
   - Write it down in `investigation_report`.
   - Be specific, not vague.

2. **Test Minimally**
   - Use the smallest possible existing command, read-only probe, or reversible local observation to test the hypothesis.
   - One variable at a time.
   - Don't test multiple causes at once.

3. **Verify Before Continuing**
   - Did it explain the symptom? Yes: proceed to Phase 4.
   - Did it fail? Form a new hypothesis.
   - Don't add more fixes on top of a failed hypothesis.

4. **Derive `scope_lock_files`**
   - Once a hypothesis is confirmed, enumerate the absolute paths the fix WILL touch.
   - Include test, fixture, snapshot, or documentation files when the anti-regression contract requires them.
   - Exclude "neighbors I might inspect for consistency"; inspection is not editing.
   - Output a flat list of absolute paths under `worktree_path`.
   - This list is physically hard-coded into the downstream prompt as `<editable_files>`; review enforcement is L2 in the debug contract.

#### G2 — 3-Strike Escalation

If Phase 3 forms 3 or more distinct hypotheses that all fail testing, STOP. Trigger exactly one `AskUserQuestion` with question `"3 个假设全部失败,接下来怎么办?"` and exactly these three options:

1. `换思路` — return to Phase 1 and change the investigation strategy.
2. `升级 ship` — stop debug and tell haze to restart with `/ohaze:ship`.
3. `放弃` — exit cleanly.

The downstream execution retry loop has its own max-3 retry for fixing review findings. These two limits stack: G2 governs root-cause investigation before code execution; the later retry loop governs failed implementation or review fixes.

### Phase 4: Implementation

In this ohaze fork, Claude main thread DOES NOT modify code in this skill. Phase 4 produces a `fix_plan` for the execution step.

**Fix the root cause, not the symptom:**

1. **Create Failing Test Case Plan**
   - Simplest possible reproduction.
   - Automated test if the project has an aggregate test command.
   - One-off structural assertion if the project is Markdown-only.
   - Must fail before the fix for Variant A projects.

2. **Plan a Single Fix**
   - Address the root cause identified in Phase 1-3.
   - One coherent change at a time.
   - No "while I'm here" improvements.
   - No bundled refactoring.

3. **Plan Verification**
   - Which command proves the bug is fixed?
   - Which command proves no surrounding behavior regressed?
   - What output must be captured?

4. **If the Plan Cannot Be Bounded**
   - Stop and surface the uncertainty.
   - Do not expand `scope_lock_files` speculatively.
   - Ask haze whether to upgrade to ship or manually continue.

`fix_plan` MUST include these four sub-sections:

### Root cause

One sentence describing the actual root cause.

### The change

Files, relevant lines or sections, and expected diff shape.

### Anti-regression contract

Choose one variant and write it explicitly:

- **Variant A**: projects with an aggregate test command. Codex must write or update a failing regression test pre-fix, confirm the failing regression test catches the bug, implement the fix, then run the full suite post-fix.
- **Variant B**: Markdown-only projects or projects using the sentinel `project_test_command`. Codex must run grep, JSON-load, or structure assertions and a dogfood smoke check that directly exercises the changed contract.

The words `failing regression test` and `dogfood smoke` must appear in this section when applicable.

### Anti-regression note

State what NOT to touch even if it looks related: unrelated refactors, renames for consistency, neighboring cleanup, extra error handling, or files outside `scope_lock_files`.

## Red Flags - STOP and Follow Process

If you catch yourself thinking:

- "Quick fix for now, investigate later"
- "Just try changing X and see if it works"
- "Add multiple changes, run tests"
- "Skip the test, I'll manually verify"
- "It's probably X, let me fix that"
- "I don't fully understand but this might work"
- "Pattern says X but I'll adapt it differently"
- "Here are the main problems" followed by fixes without investigation
- Proposing solutions before tracing data flow
- "One more fix attempt" when already tried 2 or more
- Each fix reveals a new problem in a different place

**ALL of these mean: STOP. Return to Phase 1.**

**If 3 or more hypotheses failed:** trigger G2 instead of guessing.

## your human partner's Signals You're Doing It Wrong

**Watch for these redirections:**

- "Is that not happening?" - You assumed without verifying.
- "Will it show us...?" - You should have added evidence gathering.
- "Stop guessing" - You're proposing fixes without understanding.
- "Ultrathink this" - Question fundamentals, not just symptoms.
- "We're stuck?" - Your approach isn't working.

**When you see these:** STOP. Return to Phase 1.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Issue is simple, don't need process" | Simple issues have root causes too. Process is fast for simple bugs. |
| "Emergency, no time for process" | Systematic debugging is faster than guess-and-check thrashing. |
| "Just try this first, then investigate" | First fix sets the pattern. Do it right from the start. |
| "I'll write test after confirming fix works" | Untested fixes don't stick. Test first proves it. |
| "Multiple fixes at once saves time" | Can't isolate what worked. Causes new bugs. |
| "Reference too long, I'll adapt the pattern" | Partial understanding guarantees bugs. Read it completely. |
| "I see the problem, let me fix it" | Seeing symptoms is not understanding root cause. |
| "One more fix attempt" after 2 or more failures | 3 or more failures means stop and change strategy. |

## When Process Reveals "No Root Cause"

If systematic investigation reveals the issue is truly environmental, timing-dependent, or external:

1. You've completed the process.
2. Document what you investigated in `investigation_report`.
3. Include the bounded handling plan in `fix_plan`.
4. Add monitoring or logging only if it is inside `scope_lock_files` and directly required by the anti-regression contract.

But most "no root cause" cases are incomplete investigation. Prefer more evidence over broader fixes.

## Terminal Output Shape

At terminal state, return exactly these named pieces in the conversation:

```text
investigation_report:
<markdown with Phase 1, Phase 2, Phase 3, Phase 4 content>

scope_lock_files:
- <absolute path under worktree_path>
- <absolute path under worktree_path>

fix_plan:
<markdown with Root cause, The change, Anti-regression contract, Anti-regression note>
```

## Attribution

Forked from the official Superpowers `systematic-debugging/SKILL.md` v5.1.0 by Jesse Vincent, distributed under the MIT license.

ohaze changes:

- Added G1 — Root Cause Deviation Gate.
- Added `scope_lock_files` as a terminal hand-off artifact.
- Replaced direct implementation with `fix_plan` production.
- Added ohaze hand-off terminology and haze-facing gate options.
- Adjusted wording for the debug command flow.
- Dropped the upstream Real-World Impact and Quick Reference tail sections.
