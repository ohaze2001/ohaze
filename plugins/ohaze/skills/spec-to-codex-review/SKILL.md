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
- No thread reuse, no resume, fresh session every review iteration.
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
Before you start coding, audit it from the implementer's perspective.

Your job is NOT to nitpick design or rate prose quality. Your job is to find
the spec issues that WILL block you (or another implementer) at execution time:
ambiguity that forces a guess, missing constraints that force a rework,
contradictions with existing code that force a redesign, scope drift from
what the user actually asked for.
</task>

<inputs>
- Feature brief (what the user wants, in user-language): {brief_path}
- Spec (technical design, what you'll implement): {spec_path}
- Relevant code context (Claude read these while writing the spec): {code_refs}
- Project type: {project_type}
- Project root: {main_repo_path}
</inputs>

<review_dimensions>
Walk through these 5 dimensions in order. Do not skip any.

A) BRIEF ↔ SPEC ALIGNMENT (scope drift)
   - For each "完成的样子" checkbox in the brief: is there a corresponding
     section in the spec that covers it?
   - Does the spec add anything the brief did NOT ask for? (scope creep)
   - Does the spec remove or skip anything the brief asked for? (scope cut)
   - Out-of-scope items in the brief: does the spec accidentally implement them?

B) AMBIGUITY (2-interpretation test)
   - For each requirement / behavior / interface in the spec: read it twice
     and pretend you are a different implementer the second time. Did you
     reach the same conclusion both times?
   - Specifically check: data flow direction, error handling boundaries,
     concurrency assumptions, what state is owned by whom, idempotency
     expectations, what counts as "success".
   - For each ambiguity found: quote the exact spec text and list the ≥ 2
     reasonable interpretations.

C) MISSING DETAILS (implementer "卡住" test)
   - Walk a hypothetical first hour of implementation. At which point would
     you have to stop and ask a question that the spec does not answer?
   - Check for: missing input/output formats, undefined error states,
     undefined timeouts/retries/limits, missing file paths, undefined
     interface signatures, missing dependency on external state (env vars,
     config files, network).

D) CONFLICTS WITH EXISTING CODE
   - Read the {code_refs} files. For each: does the spec contradict an
     established pattern, API, or invariant in this code?
   - Does the spec assume a function / module / type exists that does not?
   - Does the spec assume a function / module / type does NOT exist that
     actually does (so the implementer should reuse instead of recreate)?

E) TECHNICAL DECISION CHALLENGE
   - For each non-trivial decision in the spec (library choice, architecture
     pattern, data structure, retry strategy, etc.): is there a simpler,
     safer, or cheaper alternative the spec did not consider?
   - Only flag if your alternative is concretely better (cite the
     comparison). Do NOT flag "I would have done it differently" without
     a specific tradeoff argument.
</review_dimensions>

<constraints>
- Confidence gate: only report an issue if you are ≥ 7/10 confident it
  is a real problem. Skip "this might be confusing" — only report
  "this WILL force a guess / WILL cause rework / WILL conflict with X".
- Each issue must cite specific evidence: spec file:line OR code file:line.
  No "the spec is unclear about errors" without quoting the line.
- Do NOT critique the brief's requirements (haze decides product scope,
  not you). You can flag brief↔spec drift in dimension A, but you cannot
  say "this feature shouldn't exist".
- Do NOT suggest style changes, naming preferences, or formatting fixes.
- Each issue must be tagged with one of: {AMBIGUITY, MISSING, CONFLICT,
  DRIFT, ALT-DECISION} and routed to one of: {fix-in-spec, ask-haze}.
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
      "id": "<short slug e.g. 'auth-flow-ambiguous'>",
      "category": "AMBIGUITY" | "MISSING" | "CONFLICT" | "DRIFT" | "ALT-DECISION",
      "severity": "CRITICAL" | "IMPORTANT" | "NICE-TO-HAVE",
      "routing": "fix-in-spec" | "ask-haze",
      "evidence": "<file:line citation + quoted text>",
      "problem": "<technical description>",
      "user_impact_description": "<string in product language describing what user-facing function is incomplete/broken/degraded, OR null if purely technical with no user-facing impact>",
      "suggestion": "<concrete recommendation: either spec change text OR question to ask haze>",
      "confidence": <integer 7-10>
    }
  ]
}

verdict = "PASS" if and only if issues contains zero CRITICAL items AND
zero IMPORTANT items. NICE-TO-HAVE items alone do NOT cause NEEDS-CLARIFICATION.
</output_format>
````

## Background completion protocol

After dispatch, use this six-step protocol:

1. Run a 30s dispatch liveness check via `BashOutput(codex_bg_id)` with `filter='thread.started'`. If no `thread.started` appears, call `KillBash(codex_bg_id)`, re-dispatch once with the same prompt file and command, and repeat the 30s liveness check. If the second attempt fails, write the `codex-output-unparseable` stub verdict from "Malformed JSON Fallback" and return to the caller.
2. Once liveness passes, wait for Codex completion with `TaskOutput(task_id, block=true, timeout=300000)`. This is the harness-native primitive dogfood-verified on 2026-06-13 in this ship's spec audit iter 2/3.
3. After Codex completes, extract the final JSON object from the `--json` message stream via `BashOutput(codex_bg_id)` with `filter='"type":"message"'`.
4. Validate the JSON object and write it to `<work_dir>/.ohaze/spec-review-verdict.json`.
5. If the JSON is malformed, follow the "Malformed JSON Fallback" section: retry once with stricter output guidance, then write the stub verdict if it is still malformed.
6. Return control to the caller.

Defensive fallback: if `TaskOutput` is rejected by the harness or times out, write `<work_dir>/.ohaze/spec-audit-handoff.json` with fields `state="spec_audit_running"`, `codex_bg_id`, `brief_path`, and `spec_path`, end the current turn, and let the harness re-invoke continue from the handoff. This is a defensive path only; the dogfood happy path uses `TaskOutput`.

## Output Validation

When the Background completion protocol reaches validation, check:

- Top-level object only, no surrounding prose.
- `verdict` is `PASS` or `NEEDS-CLARIFICATION`.
- `summary` is a string.
- `issues` is an array.
- Each issue has `id`, `category`, `severity`, `routing`, `evidence`, `problem`, `suggestion`, and integer `confidence`.
- Issue enums match the output schema above.
- Missing `user_impact_description` is not a retry reason; normalize it to `null` before writing so the main loop can downgrade it as a pure technical finding.

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
      "category": "MISSING",
      "severity": "IMPORTANT",
      "routing": "ask-haze",
      "evidence": "codex spec review output: malformed JSON",
      "problem": "Codex output unparseable",
      "user_impact_description": "Spec review could not confirm whether the planned behavior is clear enough to implement.",
      "suggestion": "Ask haze whether to proceed without spec review, revise the brief, or rerun the review manually.",
      "confidence": 10
    }
  ]
}
```

## Caller Handoff

Return control to `/ohaze:ship` Phase 1.6. The caller reads `<work_dir>/.ohaze/spec-review-verdict.json` and handles PASS, `fix-in-spec`, `ask-haze`, and max-2 loop escalation.
