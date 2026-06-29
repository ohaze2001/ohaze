---
name: spec-to-codex-review
description: Audit a Claude-written spec with a fresh Codex exec before implementation and write a structured spec-review verdict.
---

# Spec To Codex Review (ohaze)

Use this skill in `/ohaze:ship` Phase 1.6 after Claude has drafted a spec from the approved feature brief and before Codex receives an implementation plan.

## Invocation Contract

Invoke as `Skill(ohaze:spec-to-codex-review)` with:

- `brief_path` (absolute): approved feature brief path.
- `spec_path` (absolute): Claude-written technical spec path.
- `code_refs` (list of absolute `file:line` refs): files Claude read in Phase 1.5 before writing the spec.
- `project_type` (string): caller's project type label.
- `main_repo_path` (absolute): project root.

Derived at call time:

- `feature_name`: derive from the spec filename or brief title.
- `work_dir`: `main_repo_path` before a worktree exists; `worktree_path` after one exists.

Side effect:

- Write verdict to `<work_dir>/.ohaze/spec-review-verdict.json`.
- Work dir semantics are intentional: before the ship worktree exists, the verdict lands in `<main_repo_path>/.ohaze/spec-review-verdict.json`; after worktree creation, it lands in `<worktree_path>/.ohaze/spec-review-verdict.json`. If Phase 1.6 ran pre-worktree, `/ohaze:ship` migrates or clears the temporary main-repo verdict after creating the worktree.

## Codex Invocation Contract

Run a one-shot Codex review in Claude Code harness background mode:

```bash
cd <work_dir> && codex exec \
  --sandbox danger-full-access \
  --skip-git-repo-check \
  --json \
  "$(cat <prompt_file>)" \
  < /dev/null
```

Rules:

- Use `codex exec`, NOT `codex exec resume`.
- Single-pass audit per ship: one fresh `codex exec` session, no thread reuse, no resume. The caller does not re-invoke this skill after applying fixes.
- Run from `main_repo_path` or `worktree_path` as the current working directory.
- Do NOT pass `--cd`.
- Do not use `nohup`, OS-level detachment, trailing `&`, pid files, or the `ScheduleWakeup` pattern.
- Dispatch with `Bash(run_in_background: true)` harness background. See `ohaze:codex-executor` Dispatch Mode Vocabulary for the distinction between harness background, forbidden OS-level background, and the documented foreground sync exceptions.
- Pass the prompt as the top-level CLI argument via `"$(cat <prompt_file>)"` and close stdin with `< /dev/null` to avoid the codex 0.137 stdin redirect silent crash.

## Prompt Template

Substitute `{spec_path}`, `{brief_path}`, `{code_refs}`, `{project_type}`, `{main_repo_path}`, and `{feature_name}` at call time. Pass the full XML block below to Codex.

````xml
<task>
You are about to implement the spec at {spec_path} for feature "{feature_name}".
Before you start coding, audit it along EXACTLY TWO axes only:

1. Does the spec cover the approved brief's requested behavior, scenarios, and
   out-of-scope boundaries?
2. Is there a concretely better implementation alternative with a measurable
   tradeoff?

Your job is NOT to nitpick design, rate prose quality, or pre-solve
implementer-stage questions. If a concern is about wording interpretation,
low-level implementation detail, or codebase fit, leave it for the implementer
via `missing_context_gating` or for Phase 5 cross-source review.
</task>

<inputs>
- Feature brief (what the user wants, in user-language): {brief_path}
- Spec (technical design, what you'll implement): {spec_path}
- Relevant code context (Claude read these while writing the spec): {code_refs}
- Project type: {project_type}
- Project root: {main_repo_path}
</inputs>

<review_dimensions>
Walk through these 2 dimensions in order. Do not skip any.

A) FUNCTIONAL COVERAGE (brief ↔ spec, both directions)
   - For each "完成的样子" checkbox in the brief: does the spec cover it?
     If not, report COVERAGE-GAP.
   - For each brief Scenario: is the requested outcome reachable through the
     spec? If not, report COVERAGE-GAP.
   - For each brief Out of Scope item: does the spec accidentally implement it?
     If so, report COVERAGE-DRIFT.
   - Does the spec add any new section, Task, behavior, or requirement that the
     brief did not ask for? If so, report COVERAGE-DRIFT.
   - Every finding from this dimension MUST cite a concrete brief line in
     `brief_anchor`. If you cannot cite the brief, the finding cannot block.

B) IMPLEMENTATION QUALITY (concrete alternative challenge)
   - For each non-trivial decision in the spec (library choice, architecture
     pattern, data structure, retry strategy, persistence model, etc.): is
     there a simpler, safer, cheaper, or better-UX alternative?
   - Only report ALT-DECISION when the alternative is concrete and measurably
     better. "Better" must quantify at least one tradeoff: code size or files
     touched, failure modes or blast radius, LLM calls / storage / latency, or
     impact on a brief scenario.
   - Every finding from this dimension MUST include `better_alternative` with
     `current_approach`, `proposed_alternative`, and `quantified_tradeoff`.
   - Do NOT report "I would have done it differently" without an alternative
     and quantified comparison.
</review_dimensions>

<scope_boundary>
The following implementer-stage concerns are OUT OF SCOPE for this audit:

- ambiguity in wording or interpretation. The implementer should use
  `missing_context_gating` when execution genuinely needs a decision.
- missing low-level details such as exact helper names, local control flow,
  retry constants, file path spelling, or internal signatures. The implementer
  should use `missing_context_gating` if these block execution.
- conflicts with existing code patterns, APIs, or helpers. The implementer
  should check the repo during execution; Phase 5 cross-source review remains
  the downstream firewall for integration and scope issues.

DO NOT report them here even if you notice them. They are handled by other
quality gates downstream. Reporting them here causes audit 越审越深 -- the
meta-problem this audit is intentionally designed to avoid.
</scope_boundary>

<constraints>
- Confidence gate: only report an issue if you are ≥ 7/10 confident it
  is a real problem inside the two dimensions above.
- Each issue must cite specific evidence: brief file:line, spec file:line, or
  code file:line. No broad claims without quoting the relevant line.
- Do NOT critique the brief's requirements (haze decides product scope,
  not you). You can flag brief↔spec coverage findings in dimension A, but
  you cannot say "this feature shouldn't exist".
- Do NOT suggest style changes, naming preferences, or formatting fixes.
- Each issue must be tagged with one closed enum value: {COVERAGE-GAP,
  COVERAGE-DRIFT, ALT-DECISION}. New categories are not allowed.
  - COVERAGE-GAP = spec omits requested brief behavior. `brief_anchor` REQUIRED.
  - COVERAGE-DRIFT = spec adds behavior the brief did not request or crosses
    a brief out-of-scope boundary. `brief_anchor` REQUIRED.
  - ALT-DECISION = spec chose an approach with a concrete, measurably better
    alternative. `better_alternative` REQUIRED.
- Each issue must be routed to one of: {fix-in-spec, ask-haze}.
  - fix-in-spec = Claude can resolve by editing the spec without user input
  - ask-haze = haze needs to decide on a product / scope / requirement
    question. Prefer fix-in-spec for technical decisions. You MAY route a
    technical decision to ask-haze ONLY when it has meaningful product
    impact (affects a brief scenario, cost, UX, or external dependency).
    Pure implementation-style choices (lib A vs lib B with same behavior,
    internal naming, control flow shape) MUST be fix-in-spec.
- Every issue MUST include `user_impact_description`. Use null only when
  the issue is purely technical with no user-facing impact (robustness
  edge cases observable to no user, micro-optimization, style). When
  non-null, write in PRODUCT LANGUAGE: describe what user-facing function
  is incomplete / broken / degraded. NEVER quote code identifiers,
  function names, file paths, or technical jargon in this field —
  those go in `problem`.
</constraints>

<output_format>
Return a single JSON object with this exact shape (no surrounding prose):

{
  "verdict": "PASS" | "NEEDS-CLARIFICATION",
  "summary": "<one sentence>",
  "issues": [
    {
      "id": "<short slug e.g. 'brief-scenario-uncovered'>",
      "category": "COVERAGE-GAP" | "COVERAGE-DRIFT" | "ALT-DECISION",
      "severity": "CRITICAL" | "IMPORTANT" | "NICE-TO-HAVE",
      "routing": "fix-in-spec" | "ask-haze",
      "evidence": "<file:line citation + quoted text>",
      "brief_anchor": "<brief file:line citation + quoted text; REQUIRED for COVERAGE-GAP and COVERAGE-DRIFT, optional for ALT-DECISION>",
      "better_alternative": {
        "current_approach": "<what the spec currently proposes>",
        "proposed_alternative": "<the concrete better approach>",
        "quantified_tradeoff": "<measurable comparison: size, risk, cost, latency, UX, or brief-scenario impact>"
      },
      "problem": "<technical description>",
      "user_impact_description": "<string in product language describing what user-facing function is incomplete/broken/degraded, OR null if purely technical with no user-facing impact>",
      "suggestion": "<concrete recommendation: either spec change text OR question to ask haze>",
      "confidence": <integer 7-10>
    }
  ]
}

Field consistency rules:
- `brief_anchor` is string or null; `better_alternative` is object or null.
- COVERAGE-GAP and COVERAGE-DRIFT MUST have non-empty `brief_anchor` and
  `better_alternative` MUST be null.
- ALT-DECISION MAY set `brief_anchor` to null, but MUST have a non-null
  `better_alternative` object with all three sub-fields:
  `current_approach`, `proposed_alternative`, `quantified_tradeoff`.

verdict = "PASS" if and only if issues contains zero CRITICAL items AND
zero IMPORTANT items. NICE-TO-HAVE items alone do NOT cause NEEDS-CLARIFICATION.
</output_format>
````

## Output Validation

After Codex returns, extract the final JSON object from the `--json` message stream via `BashOutput(codex_bg_id)` with `filter='"type":"message"'`, then validate:

- Top-level object only, no surrounding prose.
- `verdict` is `PASS` or `NEEDS-CLARIFICATION`.
- `summary` is a string.
- `issues` is an array.
- Each issue has `id`, `category`, `severity`, `routing`, `evidence`,
  `brief_anchor`, `better_alternative`, `problem`, `suggestion`, and integer
  `confidence`.
- Issue enums match the output schema above: category is one of
  `COVERAGE-GAP`, `COVERAGE-DRIFT`, `ALT-DECISION`; severity is one of
  `CRITICAL`, `IMPORTANT`, `NICE-TO-HAVE`; routing is one of `fix-in-spec`,
  `ask-haze`.
- If `category` is `COVERAGE-GAP` or `COVERAGE-DRIFT` and `brief_anchor` is
  null or empty, normalize `severity` to `NICE-TO-HAVE` before writing.
- If `category` is `ALT-DECISION` and `better_alternative` is null or lacks
  `current_approach`, `proposed_alternative`, or `quantified_tradeoff`, drop
  the issue before writing and surface a visible warning.
- The malformed JSON fallback issue with `id` = `codex-output-unparseable`
  is a schema exception: skip the `brief_anchor` downgrade rule and the
  `better_alternative` drop rule for that stub, preserving its IMPORTANT
  severity and `NEEDS-CLARIFICATION` verdict.
- Missing `user_impact_description` is not a retry reason; normalize it to `null` before writing so the main loop can downgrade it as a pure technical finding.
- After all normalize and drop rules run, recompute top-level `verdict` from
  the final `issues[]`: `PASS` iff zero `CRITICAL` or `IMPORTANT` items remain;
  otherwise `NEEDS-CLARIFICATION`. The malformed JSON fallback stub keeps
  `NEEDS-CLARIFICATION` regardless of the computed value.

Write the validated JSON to `<work_dir>/.ohaze/spec-review-verdict.json`.

## Malformed JSON Fallback

If Codex output is malformed JSON:

1. Retry once with the same prompt plus a stricter reminder: "Return only the JSON object matching `<output_format>`, with no Markdown fences and no prose."
2. If the second output is still malformed, write this stub verdict and surface a visible warning:

```json
{
  "verdict": "NEEDS-CLARIFICATION",
  "summary": "Codex spec review output was unparseable.",
  "issues": [
    {
      "id": "codex-output-unparseable",
      "category": "COVERAGE-GAP",
      "severity": "IMPORTANT",
      "routing": "ask-haze",
      "evidence": "codex spec review output: malformed JSON",
      "brief_anchor": "<fallback exception: review system fault, no specific brief line applicable>",
      "better_alternative": null,
      "problem": "Codex output unparseable",
      "user_impact_description": "Spec review could not confirm whether the planned behavior is clear enough to implement.",
      "suggestion": "Ask haze whether to proceed without spec review, revise the brief, or rerun the review manually.",
      "confidence": 10
    }
  ]
}
```

## Caller Handoff

Return control to `/ohaze:ship` Phase 1.6. The caller reads `<work_dir>/.ohaze/spec-review-verdict.json` once and handles PASS, `fix-in-spec`, and `ask-haze` in a single pass without re-invoking this skill. Phase 5 cross-source review is the second independent gate.
