# debug-command — Guidance Plan

> **For Codex (the executor):** Each Task below specifies WHAT must be true at completion, not HOW to write it line by line. You have autonomy over internal naming, control flow, helper extraction, and algorithm choice. You do NOT have autonomy over public interfaces, file paths in Files lists, acceptance criteria, or cross-Task invariants. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `/ohaze:debug` as ohaze's second flow tier — bug-fix mode that shares ship's worktree/cross-source-review/finishing infrastructure but replaces feature-dev phases (BDD brainstorm, spec audit) with systematic-debugging 4-phase root-cause investigation + scope-lock + 3 conditional gates (G1/G2/G3). Also add reverse reframe checkpoints at 3 points in `/ohaze:ship` so users who accidentally start ship for a bug get nudged toward debug.

**Architecture:** Independent command + 2 new skills, no fork in `ship.md`. `commands/debug.md` orchestrates debug end-to-end; `skills/systematic-debugging/` (forked from superpowers v5.1.0, MIT) drives Phase 3 investigation and produces a 3-piece terminal output (investigation_report + scope_lock_files + fix_plan); `skills/debug-to-codex-prompt/` translates that into a Codex XML with `<editable_files>` whitelist enforcement. Worktree is created early (right after Pre-flight) so all investigation runs inside isolation. `current-ship.json` gains a `ship_mode` field that ship-review reads to gate L2 (scope_lock breach detection) + G3 (>5 file blast radius) — debug mode only. KD6 three-layer defense substitutes "physical write freeze" since codex 0.137 lacks file-level sandbox.

**Tech Stack:** Markdown plugin (no static code). Bash + git + codex CLI 0.137. JSON for handoff schema (`.ohaze/current-ship.json`, `.ohaze/findings-detail.json`). Existing ohaze skills `codex-executor`, `finishing`, `using-git-worktrees` are reused unchanged.

**Spec reference:** `docs/ohaze/specs/2026-06-15-debug-command-design.md` is the single source of truth. This plan cross-references spec section numbers for context; do NOT re-derive design decisions, just implement the contracts.

**Pre-flight context:** Worktree already exists at `/Users/apple/Project/ohaze/.worktrees/debug-command` on branch `feat/debug-command` from `main`. Brief + spec already committed in `docs/ohaze/{briefs,specs}/2026-06-15-debug-command-*.md`. All work in this Task list lands on `feat/debug-command`.

---

## File Structure

| File | Responsibility | Status |
|---|---|---|
| `plugins/ohaze/commands/debug.md` | `/ohaze:debug` command orchestration: pre-flight → worktree → systematic-debugging → debug-to-codex-prompt → codex-executor dispatch → handoff JSON | **Create** |
| `plugins/ohaze/skills/systematic-debugging/SKILL.md` | 4-phase root-cause investigation contract + G1 conditional gate + scope_lock_files & fix_plan output | **Create (fork)** |
| `plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md` | XML translation: investigation + fix_plan + scope_lock_files → codex prompt with `<editable_files>` enforcement + anti-regression contract | **Create** |
| `plugins/ohaze/commands/ship.md` | Add 3 reframe checkpoints (Phase 1 / Phase 1.5 / Phase 3) + `ship_mode` field default in handoff | **Modify** |
| `plugins/ohaze/commands/ship-review.md` | Add Phase 5.-0.5 touched-files collector + L2 scope_lock enforcement + G3 blast-radius gate (all debug-mode only) | **Modify** |
| `plugins/ohaze/.claude-plugin/plugin.json` | Bump 2.1.3 → 2.2.0 | **Modify** |
| `CHANGELOG.md` | Promote [Unreleased] to [2.2.0]; add debug-command Added entries | **Modify** |
| `ROADMAP.md` | Move debug backlog item to 当前主线 with all checkboxes ticked; remove from Backlog | **Modify** |
| `CLAUDE.md` | Add debug command + 2 new skills to 关键文件/入口; bump 版本; add Agent 行为约定 for debug | **Modify** |
| `README.md` | Add `/ohaze:debug` to command list with one-line description | **Modify** |
| `plugins/ohaze/skills/codex-executor/SKILL.md` | UNCHANGED | — |
| `plugins/ohaze/skills/finishing/SKILL.md` | UNCHANGED | — |
| `plugins/ohaze/skills/spec-to-codex-review/SKILL.md` | UNCHANGED | — |
| `plugins/ohaze/commands/ship-finish.md` | UNCHANGED | — |
| `plugins/ohaze/commands/status.md` | UNCHANGED (state-based detection auto-handles debug ships) | — |

---

## Task 1: `commands/debug.md` — `/ohaze:debug` orchestration

**Files:**
- Create: `plugins/ohaze/commands/debug.md`

**Behavior Contract:**

- **Public interface (slash command frontmatter)**:
  ```yaml
  description: <one-line, see spec for full text>
  argument-hint: "<symptom> [--cause=<猜测原因>] [--project <abs-path>]"
  allowed-tools: Bash, BashOutput, KillBash, Read, Write, Edit, Skill, Agent, AskUserQuestion
  ```
- **Inputs from `$ARGUMENTS`**: required `<symptom>` string + optional `--cause=<text>` + optional `--project <abs-path>`. Empty `$ARGUMENTS` triggers AskUserQuestion for symptom.
- **Outputs**:
  - Background codex dispatch in progress with `Bash(run_in_background:true)` (harness background, never OS-level)
  - `<worktree_path>/.ohaze/current-ship.json` written with `ship_mode: "debug"` handoff (exact schema below)
  - `<worktree_path>/.ohaze/investigation-<slug>.md` written (gitignored, never committed)
  - One user-facing report message stating Codex is running, with `codex_bg_id` and `thread_id`
- **Side effects**: creates worktree at `.worktrees/<slug>/`, creates feat branch, dispatches codex; does NOT commit anything itself (investigation note stays uncommitted as runtime artifact)
- **Error boundaries**:
  - codex CLI missing → stop with install instructions (spec §Failure Modes)
  - User cancels Phase 3 systematic-debugging G1/G2 → clean exit; if worktree built, route through finishing menu Option 3 (discard); otherwise no-op
  - systematic-debugging cannot form a hypothesis (no reproducible bug) → stop and surface; preserve worktree for haze manual continuation
  - debug-to-codex-prompt failure → surface error verbatim; preserve worktree
  - codex-executor dispatch failure → set `state=dispatch_failed`, clear `codex_bg_id`/`thread_id` to null (same hygiene as ship Phase 4 Step 2.5)
- **Invariants that must hold**:
  - Worktree is created BEFORE systematic-debugging runs (per KD10 — investigation must not pollute main_repo_path)
  - systematic-debugging Phase 1-4 produces three artifacts in conversation: `investigation_report` (markdown), `scope_lock_files` (list of absolute paths under worktree_path), `fix_plan` (markdown with mandatory anti-regression contract section)
  - debug-to-codex-prompt is the ONLY downstream user of `scope_lock_files` for the XML `<editable_files>` block
  - codex-executor is invoked with `mode='dispatch'` (NEVER `'review'` from this command)
  - The command MUST NOT call `ohaze:brainstorming`, `ohaze:writing-plans`, or `ohaze:spec-to-codex-review` anywhere

- **Handoff schema for `<worktree_path>/.ohaze/current-ship.json`** (Write tool, preserving ship.md Write Protocol):
  ```json
  {
    "state": "running",
    "ship_mode": "debug",
    "slug": "<feature-slug>",
    "branch": "feat/<slug> or fix/<slug>",
    "base_ref": "main",
    "worktree_path": "<absolute>",
    "main_repo_path": "<absolute>",
    "investigation_path": "<absolute path to .ohaze/investigation-<slug>.md>",
    "scope_lock_files": ["<absolute>", "..."],
    "cause_hypothesis": "<string or null>",
    "plan_path": "<absolute path to codex-debug-prompt.xml inside .ohaze/>",
    "spec_path": null,
    "brief_path": null,
    "spec_review_iteration": 0,
    "retries": 0,
    "thread_id": "<UUID or null>",
    "codex_bg_id": "<bg task id>",
    "linked_todo": "<exact todo or null>",
    "project_type": null,
    "project_category": null
  }
  ```

- **Slug derivation**: kebab-case ≤ 4 words derived from `<symptom>` first sentence + recent git context (e.g. "codex resume dropping thread_id" → `codex-resume-thread-id`). Codex chooses the exact algorithm; the only invariant is: matches `^[a-z][a-z0-9-]{0,40}$` and is unique vs existing `.worktrees/` entries.

**Acceptance Criteria:**

- [ ] Manual check: `test -f plugins/ohaze/commands/debug.md`
- [ ] Interface conformance: file frontmatter contains `description:`, `argument-hint: "<symptom>` (literal text), and the exact `allowed-tools:` line listing all 9 tools in any order
- [ ] Skill invocations present: grep matches for `Skill(ohaze:systematic-debugging)`, `Skill(ohaze:debug-to-codex-prompt)`, `Skill(ohaze:codex-executor)`
- [ ] Mode contract: grep matches for `mode='dispatch'` literal substring
- [ ] Handoff schema keys present: grep matches for `"ship_mode": "debug"`, `"investigation_path"`, `"scope_lock_files"`, `"cause_hypothesis"`
- [ ] Branch contract: grep matches for `feat/<slug>` or `fix/<slug>` pattern (file mentions both options)
- [ ] Forbidden skills NOT invoked: `grep -qE 'Skill\(ohaze:(brainstorming|writing-plans|spec-to-codex-review)\)' plugins/ohaze/commands/debug.md` returns exit code 1 (no match)
- [ ] Worktree-first ordering: in the prose, Phase 2 (worktree creation) precedes Phase 3 (systematic-debugging invocation)

**TDD Sequence:**
- [ ] Step 1: Sketch the failing acceptance grep set in your scratch — confirm each is checkable BEFORE writing the file
- [ ] Step 2: Write `plugins/ohaze/commands/debug.md` per the Behavior Contract
- [ ] Step 3: Run the acceptance grep set — all should pass
- [ ] Step 4: Run the forbidden-skills grep (acceptance #7) — confirm it returns exit code 1
- [ ] Step 5: Commit. Suggested message: `feat(debug): /ohaze:debug 命令编排`

**Cross-Task Dependencies:**
- Depends on Task 2's `ohaze:systematic-debugging` skill (consumes its 3-piece terminal output)
- Depends on Task 3's `ohaze:debug-to-codex-prompt` skill (consumes its XML output)
- Provides `ship_mode='debug'` handoff schema consumed by Task 5's ship-review modifications

---

## Task 2: `skills/systematic-debugging/SKILL.md` — fork + ohaze adaptation

**Files:**
- Create: `plugins/ohaze/skills/systematic-debugging/SKILL.md`

**Behavior Contract:**

- **Base**: forked from `~/.claude/plugins/cache/claude-plugins-official/superpowers/5.1.0/skills/systematic-debugging/SKILL.md` (297 lines, MIT, Jesse Vincent). Preserve: Iron Law, 4-phase rhythm, Red Flags, Common Rationalizations sections verbatim or near-verbatim. Drop: "Real-World Impact" and "Quick Reference" tail sections.
- **Public skill interface (frontmatter)**:
  ```yaml
  name: systematic-debugging
  description: Use within /ohaze:debug Phase 3 to drive root-cause investigation (4 phases) and produce investigation report + scope-lock file list + fix plan. Owns G1 root-cause-deviation gate and G2 3-strike escalation.
  ```
- **Invocation Contract section** (new, inserted right after Overview):
  - Inputs: `symptom` (string, required), `cause_hypothesis` (string or null), `worktree_path` (string, required, isolated workspace), `main_repo_path` (string, required, read-only reference)
  - Terminal-state outputs (returned in conversation, NOT written to files by this skill):
    - `investigation_report` (markdown, multi-section: Phase 1/2/3/4 outputs)
    - `scope_lock_files` (list of absolute paths under `worktree_path` only)
    - `fix_plan` (markdown including Root cause, Files+lines, MANDATORY Anti-regression contract section per spec, Anti-regression note)
  - Forbidden actions: write files, dispatch codex, commit/merge/PR, modify `main_repo_path` (all investigation commands MUST be scoped to `worktree_path`)
- **G1 Root Cause Deviation Gate** (added at end of Phase 1):
  - If `cause_hypothesis is null` → G1 inactive, proceed to Phase 2
  - Otherwise compare Phase 1's hypothesis to `cause_hypothesis` for semantic alignment (not verbatim match)
  - On material divergence → trigger AskUserQuestion with exactly 3 options: `接受调研根因 (Recommended)`, `重新调研`, `退出`
  - Decision persists in conversation memory for caller's reporting
- **scope_lock_files derivation** (added in Phase 3 Hypothesis section):
  - Once a hypothesis is formed, enumerate absolute paths the fix WILL touch (conservative: include test/fixture files if needed; exclude "neighbors I might check for consistency")
  - Output as flat list of absolute paths under `worktree_path`
  - This list is physically hard-coded into codex's prompt by debug-to-codex-prompt as `<editable_files>`; review enforcement is L2 in spec KD6
- **fix_plan production** (added at end of Phase 4 Implementation):
  - Claude main thread DOES NOT modify code in this skill — produce `fix_plan` markdown instead
  - fix_plan MUST include 4 sub-sections: (a) Root cause (one sentence), (b) The change (files+lines+expected diff shape), (c) Anti-regression contract (Variant A for projects with aggregate test command — failing regression test pre-fix, full suite post-fix; Variant B for Markdown-only / sentinel `project_test_command` — grep/JSON-load/structure assertions + dogfood smoke check), (d) Anti-regression note (what NOT to touch even if "looks related")
- **G2 3-Strike Escalation** (replaces upstream's "Question Architecture" sub-section):
  - If Phase 3 forms ≥ 3 distinct hypotheses that all fail testing → STOP
  - Trigger AskUserQuestion with 3 options: `换思路`, `升级 ship`, `放弃`
  - Note alongside: codex-executor Phase 6 has its OWN max-3 retry for fix execution — they stack, do not conflict
- **Attribution section** at end with: fork source URL, MIT, list of ohaze changes (G1, scope_lock_files, fix_plan, ohaze hand-off, "haze" wording, dropped sections)

**Acceptance Criteria:**

- [ ] Manual check: `test -f plugins/ohaze/skills/systematic-debugging/SKILL.md`
- [ ] Frontmatter: `grep -q '^name: systematic-debugging$' plugins/ohaze/skills/systematic-debugging/SKILL.md`
- [ ] Iron Law preserved (the only verbatim string from upstream): `grep -q 'NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST' plugins/ohaze/skills/systematic-debugging/SKILL.md`
- [ ] All 4 phases present: grep for each of `Phase 1: Root Cause Investigation`, `Phase 2: Pattern Analysis`, `Phase 3: Hypothesis`, `Phase 4: Implementation`
- [ ] Invocation Contract section exists: `grep -q '^## Invocation Contract' plugins/ohaze/skills/systematic-debugging/SKILL.md`
- [ ] Inputs documented: grep for each of `symptom`, `cause_hypothesis`, `worktree_path`, `main_repo_path` literally
- [ ] Three terminal outputs documented: grep for each of `investigation_report`, `scope_lock_files`, `fix_plan`
- [ ] G1 + G2 sections present: grep for `G1 — Root Cause Deviation Gate` and `G2 — 3-Strike Escalation`
- [ ] Anti-regression contract guidance present in Phase 4 section: grep for both `Variant A` and `Variant B`, and for `failing regression test` and `dogfood smoke`
- [ ] Worktree-scoping rule present: `grep -q 'MUST be scoped to.*worktree_path' plugins/ohaze/skills/systematic-debugging/SKILL.md` (or equivalent phrasing about not touching main_repo_path)
- [ ] Attribution present: grep for `Forked from` and `MIT license`
- [ ] Dropped sections gone: `grep -q '^## Real-World Impact' SKILL.md` returns exit code 1; `grep -q '^## Quick Reference' SKILL.md` returns exit code 1

**TDD Sequence:**
- [ ] Step 1: Read the upstream `~/.claude/plugins/cache/claude-plugins-official/superpowers/5.1.0/skills/systematic-debugging/SKILL.md` fully to anchor on the verbatim sections that must survive
- [ ] Step 2: Write `plugins/ohaze/skills/systematic-debugging/SKILL.md` integrating the upstream skeleton + ohaze additions per Behavior Contract
- [ ] Step 3: Run the acceptance grep set; fix mismatches
- [ ] Step 4: Run the "forbidden dropped sections" greps; confirm both return exit code 1
- [ ] Step 5: Commit. Suggested message: `feat(systematic-debugging): fork v5.1.0 + ohaze G1/G2/scope_lock/fix_plan`

**Cross-Task Dependencies:**
- Provides 3-piece terminal output (`investigation_report` / `scope_lock_files` / `fix_plan`) consumed by Task 1's debug.md orchestration AND Task 3's debug-to-codex-prompt
- Independent of Task 4/5/6/7 — can be implemented in parallel with Task 3

---

## Task 3: `skills/debug-to-codex-prompt/SKILL.md` — XML translation skill

**Files:**
- Create: `plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md`

**Behavior Contract:**

- **Public skill interface (frontmatter)**:
  ```yaml
  name: debug-to-codex-prompt
  description: Use when handing a systematic-debugging investigation + fix plan to Codex for execution within /ohaze:debug Phase 4. Thin XML wrapper that embeds scope-lock file whitelist + investigation context + fix plan + verification loop + anti-regression contract.
  ```
- **Invocation Contract section**:
  - Inputs: `investigation_path` (abs, required, points at investigation note in worktree), `scope_lock_files` (list of abs paths, required, must be non-empty), `fix_plan` (markdown string, required, must contain Variant A or Variant B anti-regression contract section verbatim from Task 2), `project_test_command` (string, required — either an aggregate command OR sentinel `'(per-Task acceptance assertions inline in plan)'`), `worktree_path` (abs, required), `main_repo_path` (abs, required), `base_ref` (string, required)
  - Output: an XML string ready to pass to `ohaze:codex-executor` as `codex_prompt`
- **XML template MUST contain these 9 named sections in order** (each a top-level XML element):
  1. `<task>` — preamble: investigation done, your job is execute + write regression test + verify; do NOT redo root cause
  2. `<investigation>` — content of `investigation_path` embedded verbatim
  3. `<fix_plan>` — `fix_plan` markdown embedded verbatim (this carries the Variant A/B anti-regression contract through to codex)
  4. `<editable_files>` — newline-separated `scope_lock_files` absolute paths with header line "You MAY modify these files (and only these files):"
  5. `<readonly>` — explicit "Everything else is READONLY" block + escape hatch protocol: codex MUST report `scope_lock_breach_requested: <file> — reason: <why>` rather than silently violate; codex must NOT WRITE/MODIFY/DELETE/CREATE outside whitelist
  6. `<commit_handling>` — ohaze orchestrator handles commits; codex leaves changes uncommitted
  7. `<verification_loop>` — references spec Task 3 verification_loop two-variant structure: Variant A (failing test pre-fix, full suite post-fix) or Variant B (per-assertion grep/JSON-load + dogfood smoke) per `project_test_command` value; reports must include variant identifier + required evidence
  8. `<anti_regression>` — "no refactor while you're there", "no rename for consistency", "no error handling not specified in fix_plan", "1-2 files better than 5 files" rules
  9. `<output_format>` — final message MUST contain: Tasks completed (one-line summary), Touched files (must match `<editable_files>` exactly), Test verification output (command + exit + tail), Suggested commit message (`fix: <one-liner>`), Scope lock breach section (empty if none, OR `scope_lock_breach_requested` details)
- **Substitution semantics**: placeholders like `{project_test_command}` and `{worktree_path}` are templated at call time, NOT left as literal placeholders in the returned XML

**Acceptance Criteria:**

- [ ] Manual check: `test -f plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md`
- [ ] Frontmatter: `grep -q '^name: debug-to-codex-prompt$' plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md`
- [ ] Invocation Contract section: `grep -q '^## Invocation Contract' SKILL.md`
- [ ] All 7 required inputs documented: grep for each of `investigation_path`, `scope_lock_files`, `fix_plan`, `project_test_command`, `worktree_path`, `main_repo_path`, `base_ref`
- [ ] All 9 XML sections present in template: grep for each of `<task>`, `<investigation>`, `<fix_plan>`, `<editable_files>`, `<readonly>`, `<commit_handling>`, `<verification_loop>`, `<anti_regression>`, `<output_format>`
- [ ] Escape hatch protocol: `grep -q 'scope_lock_breach_requested' SKILL.md`
- [ ] Variant A + Variant B mentioned in verification_loop section: grep for both `Variant A` and `Variant B`
- [ ] Codex-executor handoff documented: `grep -q 'codex-executor' SKILL.md`
- [ ] No superpowers runtime dependency introduced: `grep -qE 'superpowers:[a-z-]+' plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md` returns exit code 1

**TDD Sequence:**
- [ ] Step 1: Sketch the XML template structure with all 9 sections as a draft
- [ ] Step 2: Write `plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md` per the Behavior Contract
- [ ] Step 3: Run the acceptance grep set; fix mismatches
- [ ] Step 4: Verify the forbidden `superpowers:` grep returns exit code 1
- [ ] Step 5: Commit. Suggested message: `feat(debug-to-codex-prompt): scope-lock XML wrapper skill`

**Cross-Task Dependencies:**
- Consumes Task 2's `scope_lock_files` and `fix_plan` (must use these output names verbatim)
- Provides XML string consumed by Task 1's debug.md → codex-executor invocation
- Independent of Task 4/5/6/7 — can be implemented in parallel with Task 2

---

## Task 4: `commands/ship.md` — 3 reframe checkpoints + `ship_mode` field

**Files:**
- Modify: `plugins/ohaze/commands/ship.md`

**Behavior Contract:**

- **Checkpoint 1: Phase 1 → 1.5 reframe** (insert at end of `## Phase 1 — BDD Brainstorm` section, AFTER the "Phase 1 hand-off invariant" blockquote, BEFORE `## Phase 1.5` section)
  - **Trigger condition**: After brief approved, inspect the approved brief content. Count signals:
    1. Every Scenario phrases problem-elimination ("修复 X" / "Fix X") rather than positive capability
    2. Out of Scope section lists "新 feature" or equivalent exclusion
    3. "完成的样子" Checklist items all about restoring expected behavior
    4. Body contains stack traces, error messages, or bug ticket references
  - **Behavior**: If ≥ 2 of 4 signals match → trigger ONE AskUserQuestion with exactly 2 options: `切到 /ohaze:debug (Recommended)`, `继续 ship`
  - **Routing on accept**: clean exit, no worktree built yet; print "Ship 流程已干净退出, 请打 `/ohaze:debug \"<symptom>\"` 重启" with a symptom template derived from brief title
  - **Routing on decline**: continue silently to Phase 1.5
  - **Routing on < 2 signals**: silent skip, proceed silently to Phase 1.5
- **Checkpoint 2: Mid-spec reframe** (insert at end of `### Mandatory code-reading before writing` subsection, BEFORE `### 5 boundary-question triggers` subsection)
  - **Trigger condition**: After mandatory code-reading, inspect read code refs. Count signals:
    1. Refs dominated by stack-trace files / error log files / files mentioned in recent CHANGELOG.md `## [Unreleased] Fixed` entries
    2. Brief's reframed core problem is "X is broken" / "X stopped working" rather than "users need X"
    3. Most recent commit on `main` (`git log -1 --oneline`) was a feature add AND this ship would conflict with that area for a fix
  - **Behavior**: If ≥ 2 of 3 signals match → trigger ONE AskUserQuestion with same 2 options as Checkpoint 1
  - **Routing**: same as Checkpoint 1
- **Checkpoint 3: Post-plan reframe** (insert at end of `## Phase 3 — Plan (ohaze)` section, BEFORE `## Phase 3.5 — Plan Summary + Default-Go` section)
  - **Trigger condition**: After plan_path returned, inspect plan shape. Count signals:
    1. All Tasks phrased as "restore X" / "fix Y" / no new public interface added
    2. All Acceptance Criteria about returning to known-good state rather than introducing capability
    3. Plan touches ≤ 3 files total AND none is a new file
  - **Behavior**: If ≥ 2 of 3 signals match → trigger ONE AskUserQuestion with 2 options: `切到 /ohaze:debug (Recommended)`, `继续 ship`
  - **Routing on accept**: clean exit per finishing menu Option 3 discard path (worktree IS built at this point), then tell haze to run `/ohaze:debug`. Reference KD9 for the manual-restart rationale.
  - **Routing on decline**: proceed silently to Phase 3.5
- **`ship_mode` field default** (in `## Persisting Context — `.ohaze/current-ship.json`` Step B JSON template):
  - Add field `"ship_mode": "ship"` to the JSON template object, in a position adjacent to `"state"` and `"slug"` for readability
  - Add a Field Semantics bullet: "`ship_mode`: enum `\"ship\" | \"debug\"`, defaults to `\"ship\"` in this file. `/ohaze:debug` writes `\"debug\"` explicitly. Downstream (`ship-review`, `finishing`) routes by this; v2.2.0 only `ship-review` actually branches (L2 scope_lock + G3 blast-radius)."

**Acceptance Criteria:**

- [ ] All 3 checkpoint headers present: grep for each of `Phase 1 → 1.5 reframe checkpoint`, `Mid-spec reframe checkpoint`, `Post-plan reframe checkpoint`
- [ ] All 3 prompt strings present and distinct: `grep -c '是否切到 \`/ohaze:debug\`' plugins/ohaze/commands/ship.md` returns a number ≥ 3
- [ ] Manual-restart language: `grep -q 'manual restart' plugins/ohaze/commands/ship.md` OR `grep -q 'KD9' plugins/ohaze/commands/ship.md` (link to spec rationale)
- [ ] Symptom-template line: `grep -q '请打 .ohaze:debug' plugins/ohaze/commands/ship.md`
- [ ] `ship_mode` default in handoff JSON: `grep -q '"ship_mode": "ship"' plugins/ohaze/commands/ship.md`
- [ ] `ship_mode` field semantics documented: `grep -qE 'ship_mode.*(enum|"ship".*"debug")' plugins/ohaze/commands/ship.md`
- [ ] Other handoff fields preserved (regression guard): grep for `"slug"`, `"state"`, `"worktree_path"`, `"main_repo_path"`, `"plan_path"` — all should be present in the JSON template
- [ ] No removal of Phase 1/1.5/3 existing content: line count of ship.md should INCREASE vs base; structural sections `## Phase 1 — BDD Brainstorm`, `## Phase 1.5 — Claude Auto-Writes Spec`, `## Phase 3 — Plan (ohaze)` all still present

**TDD Sequence:**
- [ ] Step 1: Read current `plugins/ohaze/commands/ship.md` to anchor insertion positions
- [ ] Step 2: Apply 3 checkpoint inserts + JSON field addition + field semantics bullet via Edit tool
- [ ] Step 3: Run the acceptance grep set
- [ ] Step 4: Diff vs base to confirm changes are additive only (no deletions outside the JSON template; the JSON template gains one key)
- [ ] Step 5: Commit. Suggested message: `feat(ship): 3 reframe checkpoints + ship_mode field`

**Cross-Task Dependencies:**
- Provides `ship_mode` default consumed by Task 5's ship-review.md branching
- Independent of Tasks 1/2/3 in implementation order

---

## Task 5: `commands/ship-review.md` — Phase 5.-0.5 touched-files collector + L2 + G3

**Files:**
- Modify: `plugins/ohaze/commands/ship-review.md`

**Behavior Contract:**

- **Position**: All 3 new sections insert AFTER `Step 3a (state liveness transition)`, BEFORE the existing Phase 5.0 commit step (which lives inside `ohaze:codex-executor` invocation in `mode='review'`)
- **Section 1: Phase 5.-0.5 — Compute `touched_files_abs`** (debug mode only, shared by L2 and G3)
  - **Trigger**: Read `.ohaze/current-ship.json.ship_mode`. If `!= "debug"` (or field missing → treat as `"ship"`): skip this AND L2 AND G3 entirely; proceed to Phase 5.0
  - **Inputs**: `<worktree_path>`, `<base_ref>` from handoff
  - **Outputs (in-memory variable for downstream sections)**: `touched_files_abs` — array of absolute paths under `worktree_path` representing the union of (a) files changed in commits since `<base_ref>` (`git diff --name-only <base_ref>..HEAD`), (b) files dirty in working tree (`git diff --name-only HEAD`), (c) untracked but not git-ignored files (`git ls-files --others --exclude-standard`), de-duplicated, normalized to absolute paths under `worktree_path`
  - **Side effects**: none (read-only git ops)
- **Section 2: L2 — scope_lock_files Boundary Enforcement** (debug mode only, runs AFTER Phase 5.-0.5, BEFORE G3)
  - **Trigger**: `ship_mode == "debug"` AND `scope_lock_files` (from handoff) is non-empty
  - **Logic**: Compute `breached_files = touched_files_abs - scope_lock_files` (absolute-path set difference)
  - **On non-empty breach**:
    - Read `<worktree_path>/.ohaze/findings-detail.json` (create if missing with `{"iteration":<retries>,"findings":[]}`)
    - Append a CRITICAL finding object with `severity`/`evidence`/`technical_description`/`user_impact_description`/`shown_to_user:false`/`auto_handled:"retry-fix"` fields (exact shape in spec Task 5 Section 5.2)
    - Write back findings-detail.json (preserve unknown top-level fields, override only `iteration` + `findings`)
    - Append parallel CRITICAL string entry to `<worktree_path>/.ohaze/review-verdict.json.issues` (format: `"CRITICAL: scope_lock breach — <file>"`)
    - Set verdict to `"FAIL"` if currently PASS (so codex-executor Phase 6 enters retry loop)
  - **On empty breach**: proceed to G3 (Section 3)
- **Section 3: G3 — Blast-Radius Gate** (debug mode only, runs AFTER L2)
  - **Trigger**: `ship_mode == "debug"` (handoff missing → treat as `"ship"` → skip)
  - **Logic**: Use the same `touched_files_abs` array from Phase 5.-0.5; compute `count = length(touched_files_abs)`
  - **If `count <= 5`**: skip gate, proceed to Phase 5.0
  - **If `count > 5`**: trigger AskUserQuestion with exactly 3 options:
    1. `接受宽修` — proceed to Phase 5.0 normally
    2. `缩 scope` — dispatch a `codex exec resume <thread_id>` with anti-regression prompt naming current touched files (reuses codex-executor Phase 6 fix-prompt template, but issued from ship-review, not via FAIL verdict). After resume completes and harness re-invokes ship-review, re-run Phase 5.-0.5 + L2 + G3 (loop max 2; on 3rd entry → escalate to Option 3)
    3. `升级 ship` — set `.ohaze/current-ship.json.state = "blast_radius_escalated"` (new state enum value), surface a warning, stop. Haze re-runs `/ohaze:ship` for the full flow.
- **New state value**: `blast_radius_escalated` MUST be added to the state-table near the top of ship-review.md (next to `running`, `codex_done`, `review_fail`, `dispatch_failed`, etc.)
- **Order invariant**: Phase 5.-0.5 → L2 → G3 → existing Phase 5.0. L2 and G3 read the SAME `touched_files_abs` snapshot.
- **Backward compatibility invariant**: when `ship_mode` field is absent from handoff (legacy v2.1.x ships), all 3 new sections behave as no-ops (treat as `"ship"` → skip)

**Acceptance Criteria:**

- [ ] All 3 section headers present: grep for `Phase 5.-0.5`, `L2 — scope_lock_files Boundary Enforcement`, `G3 — Blast-Radius Gate`
- [ ] `touched_files_abs` mentioned in all 3 sections: `grep -c 'touched_files_abs' plugins/ohaze/commands/ship-review.md` ≥ 3
- [ ] `ship_mode` branching: `grep -q 'ship_mode' plugins/ohaze/commands/ship-review.md`
- [ ] All 3 git data sources for collector: grep matches `git diff --name-only` (twice or with both `..HEAD` and `HEAD` variants) AND `git ls-files --others --exclude-standard`
- [ ] Path normalization mentioned: grep for `realpath` OR `absolute path` (case-insensitive); the collector must convert to absolute paths
- [ ] L2 fields: grep for `scope_lock_files`, `breached_files`, `auto_handled.*retry-fix`
- [ ] G3 threshold: `grep -qE '5 (文件|files)' plugins/ohaze/commands/ship-review.md`
- [ ] G3 options: grep for each of `接受宽修`, `缩 scope`, `升级 ship`
- [ ] New state value: grep for `blast_radius_escalated`
- [ ] Backward compatibility documented: grep for `missing.*ship` OR `treat as.*ship` OR equivalent phrase about legacy handoff fallback
- [ ] Existing structure preserved: `## Pre-flight`, `Step 3a`, `## Phase 5`, `## Phase 6.5`, `## Phase 7` all still present (regression guard)

**TDD Sequence:**
- [ ] Step 1: Read current `plugins/ohaze/commands/ship-review.md` to anchor insertion position (right after Step 3a)
- [ ] Step 2: Add Phase 5.-0.5 + L2 + G3 sections + state-table entry via Edit tool
- [ ] Step 3: Run the acceptance grep set
- [ ] Step 4: Diff vs base to confirm existing Step 3a / Phase 5 / Phase 6.5 / Phase 7 are intact
- [ ] Step 5: Commit. Suggested message: `feat(ship-review): debug-mode L2 scope_lock + G3 blast-radius`

**Cross-Task Dependencies:**
- Consumes `ship_mode` field from Task 4's ship.md
- Consumes `scope_lock_files` field from Task 1's debug.md handoff
- Independent of Tasks 2/3/6/7

---

## Task 6: Documentation finishing (plugin.json + CHANGELOG + ROADMAP + CLAUDE + README)

**Files:**
- Modify: `plugins/ohaze/.claude-plugin/plugin.json`
- Modify: `CHANGELOG.md`
- Modify: `ROADMAP.md`
- Modify: `CLAUDE.md`
- Modify: `README.md`

**Behavior Contract:**

- **`plugin.json`**: `version` field changes from `"2.1.3"` to `"2.2.0"` (MINOR bump per SemVer — added 1 new command + 2 new skills, no breaking change)
- **`CHANGELOG.md`**:
  - The existing `## [Unreleased]` Fixed sub-entry (codex-output-persistence) PLUS three new `## [Unreleased]` Added items (debug-command, ship reverse-reframe, ship_mode field) all move into one new section `## [2.2.0] - 2026-06-15` with a theme line and proper Added/Fixed subsections
  - A fresh empty `## [Unreleased]` block remains at the top (with empty Added/Changed/Fixed/Removed subsections, ready for next ship)
  - The three Added items have these IDs (slug suffixes) so future cross-refs can grep: `debug-command`, `ship-reverse-reframe`, `ship_mode-field`
  - A `### Migration` subsection documents the backward-compatible `ship_mode` default for legacy v2.1.x handoffs
- **`ROADMAP.md`**:
  - `## 当前主线` section is rewritten with theme "v2.2.0 流程档位扩展" and 3 checked items: debug command, reverse reframe checkpoints, ship_mode + ship-review branching (all `- [x]`)
  - The 1st Backlog item (the bullet starting with `**`/ohaze:debug` 命令`) is REMOVED from `## Backlog`
  - Other Backlog items (auto-ship, loop, superpowers diff watcher, plan-drift audit, schema validator) remain UNCHANGED
  - A NEW Backlog item added: monitor superpowers v5.1.0 `systematic-debugging/SKILL.md` upstream drift (paired with the existing brainstorming / using-git-worktrees / writing-plans watcher)
- **`CLAUDE.md`** (`/Users/apple/Project/ohaze/CLAUDE.md` — the project-level one):
  - `## 项目类型` 版本 field: `2.1.3` → `2.2.0`
  - `## 关键文件 / 入口`:
    - 入口 line gains `/debug` between `ship` and `ship-review` (becomes 5 slash commands instead of 4)
    - 核心 skills line gains `systematic-debugging` (fork) and `debug-to-codex-prompt`
  - `## Agent 行为约定 - 项目特殊约定`: append a bullet noting `/ohaze:debug` is independent from `/ohaze:ship`, uses `ship_mode` handoff field for downstream branching, and that ship-review G3 blast-radius only triggers in debug mode
  - `## Agent 行为约定 - 流程序`: append a parallel `debug 流程序: pre-flight → worktree → systematic-debugging (含 G1) → debug-to-codex-prompt → Codex execute → ship-review (含 L2 + G3) → ship-finishing`
- **`README.md`**: in the command list (or equivalent intro section), add ONE line about `/ohaze:debug` — "bug fix mode, systematic 4-phase investigation + scope lock + 3 conditional gates, lighter than ship". Codex chooses placement matching existing ship/ship-review/ship-finish/status entries' layout.

**Acceptance Criteria:**

- [ ] Version consistency across 3 sources: all three of the following return the same `2.2.0` string:
  - `python3 -c "import json; print(json.load(open('plugins/ohaze/.claude-plugin/plugin.json'))['version'])"`
  - `grep -oE '## \[2\.2\.0\]' CHANGELOG.md | head -1`
  - `grep -oE '版本.*2\.2\.0' CLAUDE.md | head -1`
- [ ] CHANGELOG fresh `[Unreleased]` block present: `grep -q '^## \[Unreleased\]' CHANGELOG.md` AND that block appears BEFORE `## [2.2.0]` in the file
- [ ] CHANGELOG 3 new Added IDs present: grep for `debug-command`, `ship-reverse-reframe`, `ship_mode-field`
- [ ] CHANGELOG migration note present: `grep -q 'Migration' CHANGELOG.md` AND grep matches a sentence about `ship_mode` default or legacy handoff
- [ ] ROADMAP 当前主线 has 3 checked items: `grep -cE '^- \[x\]' ROADMAP.md` returns ≥ 3
- [ ] ROADMAP debug backlog item REMOVED: `grep -qE '^- \*\*.*/ohaze:debug. 命令.流程档位.*轻' ROADMAP.md` returns exit code 1
- [ ] ROADMAP auto-ship/loop backlog items PRESERVED: grep for both `/ohaze:auto-ship` and `/ohaze:loop` in Backlog section
- [ ] CLAUDE.md mentions both new skills: grep for `systematic-debugging` AND `debug-to-codex-prompt`
- [ ] CLAUDE.md mentions debug command + debug flow: grep for `/ohaze:debug` AND `debug 流程序`
- [ ] README mentions `/ohaze:debug` with descriptive context: `grep -qE '/ohaze:debug.*(bug|修复|fix)' README.md`
- [ ] Old [Unreleased] codex-output-persistence content moved to [2.2.0] Fixed (regression guard): `grep -q 'codex-output-persistence' CHANGELOG.md` AND the match line is AFTER `## [2.2.0]` line in the file (use `grep -n` + line-number compare)

**TDD Sequence:**
- [ ] Step 1: Read current `CHANGELOG.md`, `ROADMAP.md`, `CLAUDE.md`, `README.md`, `plugin.json` to anchor edit positions
- [ ] Step 2: Apply all 5 file edits via Edit tool (or Write for plugin.json + CHANGELOG given larger restructure)
- [ ] Step 3: Run the acceptance grep set + cross-source version consistency check
- [ ] Step 4: Run the regression-guard grep (auto-ship/loop items still in backlog; old codex-output-persistence still recorded just under new version block)
- [ ] Step 5: Commit. Suggested message: `docs(release): v2.2.0 debug-command + ship reframe + ship_mode`

**Cross-Task Dependencies:**
- Should run LAST (after Tasks 1-5 land the implementation) so docs accurately describe the just-completed work
- Reads no source of truth from earlier Tasks except the file paths created by Tasks 1-3 (so doc text mentions them)

---

## Task 7: Dogfood end-to-end read-only smoke verification

**Files:**
- None (read-only assertions)

**Behavior Contract:**

- This Task adds NO files. It runs the spec's anti-regression Variant B equivalents — structural assertions + dogfood-grade smoke against the final state of Tasks 1-6.
- All assertion commands run from `<worktree_path>` (the feat/debug-command worktree, not main repo).
- Failures here are Codex's signal to revisit earlier Tasks before final report.
- The Task's "output" is a clean exit status across the assertion list, mirrored into Codex's final report under `<verification_loop>` Variant B.

**Acceptance Criteria:**

- [ ] **A. plugin.json valid + version 2.2.0**:
  ```bash
  python3 -c "import json; v = json.load(open('plugins/ohaze/.claude-plugin/plugin.json'))['version']; assert v == '2.2.0', f'expected 2.2.0 got {v}'"
  ```
- [ ] **B. Both new skill frontmatter valid**:
  ```bash
  python3 -c "
  import re
  for path in [
      'plugins/ohaze/skills/systematic-debugging/SKILL.md',
      'plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md',
  ]:
      content = open(path).read()
      assert content.startswith('---\n'), f'{path}: missing frontmatter'
      m = re.search(r'^name: (\S+)', content, re.M)
      assert m, f'{path}: missing name field'
      assert m.group(1) == path.split('/')[-2], f'{path}: name mismatch'
  "
  ```
- [ ] **C. debug.md frontmatter + key skill invocations**:
  ```bash
  grep -q '^description:' plugins/ohaze/commands/debug.md
  grep -q 'Skill(ohaze:systematic-debugging)' plugins/ohaze/commands/debug.md
  grep -q 'Skill(ohaze:debug-to-codex-prompt)' plugins/ohaze/commands/debug.md
  grep -q 'Skill(ohaze:codex-executor)' plugins/ohaze/commands/debug.md
  ```
- [ ] **D. ship.md has all 3 reframe checkpoints + ship_mode field**:
  ```bash
  test $(grep -c 'reframe checkpoint' plugins/ohaze/commands/ship.md) -ge 3
  grep -q '"ship_mode": "ship"' plugins/ohaze/commands/ship.md
  ```
- [ ] **E. ship-review.md has L2/G3/Phase 5.-0.5 with shared touched_files_abs**:
  ```bash
  grep -q 'Phase 5.-0.5' plugins/ohaze/commands/ship-review.md
  grep -q 'L2 — scope_lock_files Boundary Enforcement' plugins/ohaze/commands/ship-review.md
  grep -q 'G3 — Blast-Radius Gate' plugins/ohaze/commands/ship-review.md
  test $(grep -c 'touched_files_abs' plugins/ohaze/commands/ship-review.md) -ge 3
  grep -q 'blast_radius_escalated' plugins/ohaze/commands/ship-review.md
  ```
- [ ] **F. No new superpowers runtime dependency introduced** (all 3 new files):
  ```bash
  ! grep -qE 'superpowers:[a-z-]+' plugins/ohaze/commands/debug.md
  ! grep -qE 'superpowers:[a-z-]+' plugins/ohaze/skills/systematic-debugging/SKILL.md
  ! grep -qE 'superpowers:[a-z-]+' plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md
  ```
- [ ] **G. CHANGELOG/ROADMAP/CLAUDE version consistency**:
  ```bash
  grep -q '"version": "2.2.0"' plugins/ohaze/.claude-plugin/plugin.json
  grep -q '## \[2.2.0\]' CHANGELOG.md
  grep -q '版本: 2.2.0' CLAUDE.md
  ```
- [ ] **H. ROADMAP debug backlog removed; current 当前主线 has ≥3 checked items**:
  ```bash
  ! grep -qE '^- \*\*.*/ohaze:debug. 命令.流程档位.*轻' ROADMAP.md
  test $(grep -cE '^- \[x\]' ROADMAP.md) -ge 3
  ```
- [ ] **I. Cross-file reference completeness**:
  ```bash
  grep -q 'codex-executor' plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md
  ! grep -qE 'codex-executor' plugins/ohaze/skills/systematic-debugging/SKILL.md  # systematic-debugging is Phase 3, never invokes codex
  ```
- [ ] **J. Critical no-regression for existing skills**:
  - `plugins/ohaze/skills/codex-executor/SKILL.md` MUST be unchanged in this branch (use `git diff main..HEAD -- plugins/ohaze/skills/codex-executor/SKILL.md` — empty output expected)
  - `plugins/ohaze/skills/finishing/SKILL.md` MUST be unchanged
  - `plugins/ohaze/skills/spec-to-codex-review/SKILL.md` MUST be unchanged
  - `plugins/ohaze/commands/ship-finish.md` MUST be unchanged
  - `plugins/ohaze/commands/status.md` MUST be unchanged

**TDD Sequence:**
- [ ] Step 1: After Tasks 1-6 complete, run assertions A-J in order; capture each command's exit status
- [ ] Step 2: Any failure → Codex returns to the failing Task, fixes, re-runs that Task's local acceptance + this Task's relevant assertion
- [ ] Step 3: All A-J pass → assemble Variant B report for the final structured message: per-assertion table (command + exit status), dogfood smoke = "all read-only assertions on the just-built ship pass"
- [ ] Step 4: No commit needed (this Task touches no files); report inline in final message instead

**Cross-Task Dependencies:**
- Depends on Tasks 1-6 all complete; this is the closing verification gate
- Provides the Variant B `verification_loop` evidence Codex includes in its final report

---

## Out of Scope (regression-protected)

These were considered and explicitly NOT included in this ship:

1. **Independent `/ohaze:debug-review` / `/ohaze:debug-finish` commands** — debug ship reuses `/ohaze:ship-review` and `/ohaze:ship-finish` via `ship_mode` field routing. No new entry commands.
2. **Modifications to `codex-executor` or `finishing` skills** — both unchanged; Task 7 Assertion J verifies via `git diff main..HEAD --` returns empty for those files.
3. **Auto-classify symptom or AI-route bug type** — haze provides symptom explicitly; no AI classifier.
4. **Cross-command reframe in `/ohaze:auto-ship` or `/ohaze:loop`** — neither command exists in v2.2.0; this ship only adds reframe to `/ohaze:ship`.
5. **Inline-fix tooling for small bugs** — out of scope per brief; haze handles inline manually in editor.
6. **Dynamic G3 threshold (per project type)** — v2.2 hardcodes `> 5 files`. Future tuning after dogfood.
7. **Independent `docs/ohaze/debug/` doc directory** — investigation note lives at `<worktree>/.ohaze/investigation-<slug>.md` (gitignored, never committed); the only persistent record post-ship is CHANGELOG Fixed entry per ship.
8. **Debug-specific finishing menu** — reuse ship's 6-option menu (+ 7th Security Review when applicable).
9. **G3 retry loop > 2 iterations** — v2.2 caps at 2 attempts; 3rd → escalate to ship.
10. **Drop or fork `systematic-debugging` upstream watcher** — Attribution section + new Backlog item track upstream drift.

---

## Self-Review Notes

- **Spec coverage**: All 7 spec Tasks map 1:1 to plan Tasks 1-7 with stable Task numbers. Spec sections (Context & Goal, Architecture, File Structure, Tasks, Out of Scope, Risks, Verification, Self-Review) are all referenced or mapped — no orphan section.
- **Placeholder scan**: No TBD / TODO / "appropriate handling" / "handle edge cases" in any Task. Each Acceptance Criteria is a checkable grep, test, or python assertion.
- **Contract leakage check**: Task 2 and Task 3 deliberately do NOT embed the full SKILL.md content — only signatures and section names. Task 5 embeds the JSON finding-object shape (data, not implementation). Task 6 documents file-level field changes (version bumps, section moves) without writing the full document text. No prescriptive command sequences in plan body (only inside Acceptance Criteria as test assertions, which is allowed).
- **Contract consistency**: Skill output names (`investigation_report` / `scope_lock_files` / `fix_plan`) appear identically in Tasks 1, 2, 3 (consumer and producer agree). Handoff JSON keys consistent across Tasks 1, 4, 5.
- **Acceptance checkability**: Every Acceptance Criteria is either a `test -f`, `grep -q`, `grep -c ... -ge N`, `! grep -qE`, `python3 -c "assert ..."`, or `git diff ... --` empty check. All are runnable and produce a clear pass/fail.
- **Cross-Task ordering**: Task 7 depends on 1-6 complete. Tasks 1-5 can be implemented in any order or in parallel (no shared file edits except 4+5 share read-only handoff schema reference). Task 6 should run last so doc text reflects landed implementation.
