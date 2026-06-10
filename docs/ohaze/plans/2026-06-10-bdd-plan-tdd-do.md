# BDD plan + TDD do (ohaze v2.1.0) — Guidance Plan

> **For Codex (the executor):** Each Task below specifies WHAT must be true at completion, not HOW to write it line by line. You have autonomy over internal naming, control flow, helper extraction, and algorithm choice. You do NOT have autonomy over public interfaces, file paths in Files lists, acceptance criteria, or cross-Task invariants. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure ohaze ship flow so haze brainstorms in product/requirement language (BDD), Claude auto-drafts spec, Codex adversarially reviews spec, plan auto-progresses to Codex implementation without 'go' gate, reviewer findings are translated to product language with technical-detail persistence.

**Architecture:** Phase 1 brainstorming becomes BDD-flavored (user/scenarios/visible outcomes); new Phase 1.5 (Claude auto-writes spec with mandatory code-reading + 5 narrow boundary questions for haze) and Phase 1.6 (new `spec-to-codex-review` skill adversarially audits spec, max-2 loop); new Phase 3.5 (plan auto-progresses with summary, interruptible); Phase 6 retry prompt gets `<investigate_first>` block (Iron Law); Phase 7 gets conditional Security Review (7th menu item); all reviewer prompts gain `user_impact_description` field and `.ohaze/findings-detail.json` persistence; path convention migrates `docs/superpowers/{briefs,specs,plans}` → `docs/ohaze/{briefs,specs,plans}`.

**Tech Stack:** Markdown plugin (no test framework); plain JSON for handoff/verdict files; codex CLI 0.137 for spec/implementation review; XML prompts for codex consumption.

**Reference spec:** `docs/ohaze/specs/2026-06-09-bdd-plan-tdd-do-design.md` — the authoritative design. All contracts/paths/field names below are defined there.

---

## Task 1: New skill — `spec-to-codex-review`

**Files:**
- Create: `plugins/ohaze/skills/spec-to-codex-review/SKILL.md`

**Behavior Contract:**
- **Public interface(s)** — invocation via `Skill(ohaze:spec-to-codex-review)` with inputs: `brief_path` (abs), `spec_path` (abs), `code_refs` (list of abs file:line refs Claude read in Phase 1.5), `project_type` (string), `main_repo_path` (abs); side-effect output: `<work_dir>/.ohaze/spec-review-verdict.json` (work_dir = main_repo_path before worktree exists, worktree_path after)
- **What the skill does**: writes a one-shot `codex exec` invocation (no thread reuse, no resume, fresh session, NOT background) with the XML prompt template defined in spec §"Phase 1.6 — Codex 异源审 spec / Prompt 模板"; captures Codex's JSON output; validates the output is well-formed (see Acceptance below); writes `spec-review-verdict.json`
- **Output schema** (verbatim from spec):
  ```json
  {
    "verdict": "PASS" | "NEEDS-CLARIFICATION",
    "summary": "<one sentence>",
    "issues": [
      {
        "id": "<short slug>",
        "category": "AMBIGUITY" | "MISSING" | "CONFLICT" | "DRIFT" | "ALT-DECISION",
        "severity": "CRITICAL" | "IMPORTANT" | "NICE-TO-HAVE",
        "routing": "fix-in-spec" | "ask-haze",
        "evidence": "<file:line + quoted text>",
        "problem": "<technical description>",
        "user_impact_description": "<string in product language OR null>",
        "suggestion": "<concrete recommendation>",
        "confidence": <integer 7-10>
      }
    ]
  }
  ```
- **XML prompt template**: embed the FULL `<task>...</task>` + `<inputs>...</inputs>` + `<review_dimensions>...</review_dimensions>` + `<constraints>...</constraints>` + `<output_format>...</output_format>` block from spec §"Phase 1.6 — Codex 异源审 spec / Prompt 模板"; placeholders `{spec_path}`, `{brief_path}`, `{code_refs}`, `{project_type}`, `{main_repo_path}`, `{feature_name}` are substituted at call time
- **codex invocation contract**: must use `codex exec` (NOT `codex exec resume`); must use `--sandbox danger-full-access --skip-git-repo-check --json`; NO `--cd` (run from main_repo_path or worktree_path as cwd); NO `nohup`; NOT run_in_background — Phase 1.6 is synchronous (seconds, not minutes)
- **Error boundaries**:
  - Malformed JSON from Codex → one retry with stricter format reminder; second failure → write a stub verdict with `verdict: NEEDS-CLARIFICATION`, single issue `routing: ask-haze`, problem `"Codex output unparseable"`, and surface a visible warning
  - Missing `user_impact_description` field on any issue → bookkeeping: Claude's main loop will treat it as null (downgrade), not Codex's responsibility to retry

**Acceptance Criteria:**
- [ ] File exists at exact path; frontmatter `name: spec-to-codex-review` and `description: <one-line per spec>` present
- [ ] SKILL.md contains the entire XML prompt block from spec §Phase 1.6, verbatim, including all 5 review dimensions and the output_format JSON schema
- [ ] SKILL.md states the codex invocation contract explicitly: synchronous `codex exec` (not background), no `--cd`, no thread reuse, no resume
- [ ] SKILL.md documents the verdict landing path `<work_dir>/.ohaze/spec-review-verdict.json` and notes work_dir semantics (main pre-worktree, worktree post)
- [ ] SKILL.md documents the malformed-JSON fallback (one retry + stub verdict)
- [ ] Interface conformance: invocation contract surface matches what `ship.md` Phase 1.6 (Task 6) will call

**TDD Sequence:**
- [ ] Step 1: write the failing test = `grep -E "spec_path|brief_path|code_refs|project_type|main_repo_path" plugins/ohaze/skills/spec-to-codex-review/SKILL.md` returns ≥ 1 match per placeholder (negative test before file exists: file absent → exit non-zero)
- [ ] Step 2: confirm tests fail (file doesn't exist)
- [ ] Step 3: write `SKILL.md` satisfying the Behavior Contract
- [ ] Step 4: confirm placeholder greps pass + JSON schema block grep passes + invocation contract greps pass
- [ ] Step 5: optional self-review for clarity
- [ ] Step 6: commit. Suggested message: `feat(spec-to-codex-review): 新 skill 封装 Codex 反向审 spec XML prompt`

**Cross-Task Dependencies:**
- Provides: `Skill(ohaze:spec-to-codex-review)` invocation surface for Task 6 (ship.md Phase 1.6)

---

## Task 2: Refactor `brainstorming/SKILL.md` — BDD-flavored Phase 1

**Files:**
- Modify: `plugins/ohaze/skills/brainstorming/SKILL.md`

**Behavior Contract:**
- **What changes**: Phase 1 dialog rhythm shifts from technical design (architecture/components/data flow/error handling/testing) to user-needs (pain/reframe/user/visible outcome/out-of-scope/capability/scope-mode)
- **7 forcing-question hints** added as LLM guidance (NOT a strict checklist) — see spec §Phase 1 / "7 类 forcing questions" for exact category list. SKILL.md MUST document: hints are flexible (order, omission, follow-up depth, phrasing all LLM-judged per context)
- **4-mode scope reflection** added as the closing step of Phase 1 dialog (Expansion / Selective Expansion / Hold Scope / Reduction) — Claude proposes one + reason, haze approves/push-back
- **Terminal state changes** from "design approved" → "brief approved". SKILL.md MUST state: this fork does NOT write a spec file (spec is Phase 1.5 owned by ship.md); does NOT invoke writing-plans; does NOT recap full technical design back to haze (the gap haze flagged in v2.0)
- **Brief template embedded** in SKILL.md — verbatim from spec §"Feature brief 模板", containing sections: 这是干嘛的 / 给谁用 / 用户场景 (Scenarios) / 完成的样子 Checklist / 不做什么 / Scope 决策 / Claude 替你决定的关键技术方向 (后回填占位)
- **Hand-off contract**: terminal state declaration MUST explicitly state "handing back to /ohaze:ship Phase 2 — it will create worktree and write this brief + spec inside the worktree" (the same explicit-no-end-of-turn protocol the commit `dacf7c6` added)

**Acceptance Criteria:**
- [ ] `grep -E "用户场景|可见结果|pain|reframe|forcing" SKILL.md` matches ≥ 3 lines (BDD vocabulary present)
- [ ] `grep -c "architecture\|components\|data flow" SKILL.md` is significantly reduced vs. v2.0 baseline (technical vocabulary removed from Phase 1 guidance)
- [ ] `grep "Expansion\|Selective Expansion\|Hold Scope\|Reduction" SKILL.md` matches all 4 mode names
- [ ] `grep "brief approved" SKILL.md` matches; `grep "design approved" SKILL.md` does NOT match as a terminal-state phrase (search context: only as historical/contrast mention is acceptable)
- [ ] `grep -E "这是干嘛的|完成的样子|Scope 决策" SKILL.md` matches (brief template embedded)
- [ ] SKILL.md describes 7 forcing hints as flexible (LLM-judged), NOT a strict ordered checklist — grep for "灵活|hint|不强制|flexible"
- [ ] Frontmatter `description:` updated to mention BDD/needs-side wording

**TDD Sequence:**
- [ ] Step 1: write failing test = the greps above
- [ ] Step 2: confirm tests fail (current SKILL.md is v2.0 technical-dialog)
- [ ] Step 3: rewrite Phase 1 sections per the contract
- [ ] Step 4: confirm greps pass
- [ ] Step 5: self-review — ensure no "Cover: architecture, components, data flow, error handling, testing" left
- [ ] Step 6: commit. Suggested message: `feat(brainstorming): BDD-flavored Phase 1 (7 forcing hints + brief 模板 + scope 4-modes)`

**Cross-Task Dependencies:**
- Provides: brief approved hand-off surface consumed by Task 6 (ship.md Phase 1 → 1.5 transition)

---

## Task 3: Refactor `writing-plans/SKILL.md` — path + handoff

**Files:**
- Modify: `plugins/ohaze/skills/writing-plans/SKILL.md`

**Behavior Contract:**
- **Path change**: every `docs/superpowers/plans/` reference → `docs/ohaze/plans/`. Frontmatter `description` mentions ohaze path.
- **Execution Handoff section rewrite**: replace the "Wait for user's 'go'" gate with a plan-summary-emit pattern that hands back to ship.md Phase 3.5 (which owns the default-go logic). The skill MUST output a one-line summary of the plan (e.g. `📋 Plan saved → docs/ohaze/plans/<file>.md, <N> Tasks, areas: <X>/<Y>/<Z>`) and explicitly hand back to ship.md without waiting.
- **Hand-off explicit semantics**: same protocol commit `dacf7c6` introduced for brainstorming — terminal state must say "handing back to /ohaze:ship Phase 3.5 which will summarize and dispatch Codex" so orchestrator doesn't end-turn on hand-off
- **Standalone-invocation mode preserved**: when invoked outside ship.md, skill keeps a brief "next step: invoke `/ohaze:ship` to dispatch" message (do NOT remove standalone mode entirely)

**Acceptance Criteria:**
- [ ] `grep "docs/ohaze/plans/" SKILL.md` matches; `grep "docs/superpowers/plans/" SKILL.md` does NOT match
- [ ] `grep -c "Wait for user's 'go'" SKILL.md` returns 0
- [ ] `grep "Phase 3.5\|default-go\|hand back to" SKILL.md` matches
- [ ] Standalone-invocation branch still present (grep "standalone\|invoke `/ohaze:ship`")

**TDD Sequence:**
- [ ] Step 1: greps above
- [ ] Step 2: confirm failures (v2.0 has both paths and the 'go' gate)
- [ ] Step 3: edit SKILL.md
- [ ] Step 4: confirm greps pass
- [ ] Step 5: self-review
- [ ] Step 6: commit. Suggested message: `feat(writing-plans): 路径 ohaze + Execution Handoff 去 'go' gate`

**Cross-Task Dependencies:**
- Provides: plan-summary hand-off consumed by Task 6 (ship.md Phase 3.5)

---

## Task 4: Refactor `codex-executor/SKILL.md` — investigate_first + user_impact + findings persistence

**Files:**
- Modify: `plugins/ohaze/skills/codex-executor/SKILL.md`

**Behavior Contract:**
- **Phase 6 fix prompt — add `<investigate_first>` block as the FIRST block** (before existing `<task>`, `<anti_regression>`, `<action_safety>`, `<verification_loop>`). Exact content per spec §"Phase 6 — Iron Law":
  ```
  <investigate_first>
  改动任何代码前,先写出根因诊断:
  - 违反的是哪个 contract / AC?
  - 上一轮为什么没修对? (具体证据)
  - 你的根因假设是什么? (证据支撑)
  如果说不清根因,直接停下报告,不要硬修。
  </investigate_first>
  ```
- **Relationship to existing stuck-detection**: SKILL.md MUST add a clarifying paragraph stating `<investigate_first>` is per-retry Codex self-discipline (in-prompt), while stuck-detection is Claude main-loop cross-iteration check (out-of-prompt) — both stack, no conflict
- **Phase 5 reviewer prompt schema upgrade** — add `user_impact_description` to every issue object in the output verdict. Add a `<constraints>` directive (or equivalent) requiring product-language text in this field and forbidding code identifiers / file paths / function names; null only for purely technical issues. (Exact wording per spec §"Phase 1.6 prompt 模板修订" applied to Phase 5 template.)
- **Phase 5.3 verdict-write hook** — when writing `review-verdict.json`, ALSO append/overwrite `<worktree_path>/.ohaze/findings-detail.json` per spec §"持久化 — .ohaze/findings-detail.json" schema:
  ```json
  {
    "iteration": <number>,
    "findings": [
      { "severity": "...", "evidence": "...", "technical_description": "...",
        "user_impact_description": "<string|null>", "shown_to_user": <bool>,
        "auto_handled": "retry-fix | skip | null" }
    ]
  }
  ```
  Each iteration overwrites (single source of truth per ship lifecycle, not a log). Write Protocol per spec rules.
- **Display routing rules — encoded in SKILL.md as the "what callers see" contract** (consumed by Tasks 5, 7):
  - CRITICAL / IMPORTANT → auto-retry-fix (unchanged from v2.0)
  - ADVERSARIAL + `user_impact_description != null` → show to user in product language
  - ADVERSARIAL + `user_impact_description == null` → default skip (still recorded in findings-detail.json with `shown_to_user: false`, `auto_handled: skip`)
  - NIT / NICE-TO-HAVE → default skip
- **Path migration**: every `docs/superpowers/plans/` → `docs/ohaze/plans/`; every `docs/superpowers/specs/` → `docs/ohaze/specs/`

**Acceptance Criteria:**
- [ ] `grep -A 5 "investigate_first" SKILL.md` shows the block content (4-line investigation prompt)
- [ ] `grep "stuck-detection" SKILL.md` and `grep "investigate_first" SKILL.md` are within proximity (clarifying paragraph present)
- [ ] Phase 5 review prompt template includes `user_impact_description` field in the verdict output schema (grep for `user_impact_description`)
- [ ] Phase 5.3 documents writing both `review-verdict.json` AND `findings-detail.json`; both paths under `<worktree_path>/.ohaze/`
- [ ] Display routing rules table or equivalent prose lists all 5 severities × 2 user_impact states (or equivalent compressed encoding)
- [ ] `grep -c "docs/superpowers/" SKILL.md` returns 0; `grep -c "docs/ohaze/" SKILL.md` returns ≥ 2
- [ ] Phase 5.3 write protocol matches Read-modify-Write rules from `ship.md` (preserve all fields)

**TDD Sequence:**
- [ ] Step 1: greps above as failing tests
- [ ] Step 2: confirm v2.0 fails all (no investigate_first, no user_impact_description, no findings-detail.json)
- [ ] Step 3: edit SKILL.md
- [ ] Step 4: confirm greps pass
- [ ] Step 5: self-review — verify no v2.0 superpowers paths leak
- [ ] Step 6: commit. Suggested message: `feat(codex-executor): investigate_first + user_impact + findings-detail.json + 路径 ohaze`

**Cross-Task Dependencies:**
- Provides: `findings-detail.json` schema consumed by Tasks 5, 7; display routing contract consumed by Tasks 5, 7

---

## Task 5: Refactor `finishing/SKILL.md` — 7th menu item + ADVERSARIAL display update

**Files:**
- Modify: `plugins/ohaze/skills/finishing/SKILL.md`

**Behavior Contract:**
- **New 7th menu item — Security Review (conditional)**:
  - Trigger condition (OR): `project_category in {web, api}` (read from `current-ship.json`) OR brief metadata `has_external_input: true`
  - Menu label: `7. 安全审查 (可选,适用于 web/API 项目)`
  - When triggered, dispatch a one-shot codex review with prompt borrowing `/cso`-style: OWASP Top 10 + STRIDE; confidence ≥ 8/10 gate (stricter than Phase 1.6's 7/10); every finding MUST include concrete exploit scenario (not "could theoretically XSS"); every finding MUST include `user_impact_description` per Task 4 contract
  - Output: append findings to `<worktree_path>/.ohaze/findings-detail.json` as ADVERSARIAL category; merge into existing 6th menu item flow (fix or accept)
- **6th menu item — "修复对抗审查" display update**:
  - Read `<worktree_path>/.ohaze/findings-detail.json` (single source of truth post-Task 4)
  - Filter ADVERSARIAL findings to those with `user_impact_description != null`; display in product language per spec §"展示模板" pseudocode (🔴 / 🟡 / 🟢 sections)
  - Skipped ADVERSARIAL count (those with null user_impact) shown as a number with `.ohaze/findings-detail.json` reference for haze to inspect on demand
- **doc-finish path migration**: every `docs/superpowers/{specs,plans,briefs}/` → `docs/ohaze/{specs,plans,briefs}/` reference inside finishing logic
- **`project_category` field write**: finishing's project-type detection step (existing in v2.0) — extend to also set `project_category` (web / api / cli / plugin / agent / other) onto `current-ship.json` per spec data-contract §`current-ship.json`. Heuristic: read manifest + brief + spec keywords; LLM judgment OK; default `other` if uncertain

**Acceptance Criteria:**
- [ ] `grep "7\. 安全审查\|Security Review" SKILL.md` matches
- [ ] 7th item's prompt requirements documented: OWASP, STRIDE, confidence ≥ 8, exploit scenario, user_impact_description — all five present (grep each keyword)
- [ ] 6th item's display logic references `findings-detail.json` AND filters by `user_impact_description != null`
- [ ] `grep "🔴\|🟡\|🟢" SKILL.md` matches (display template embedded)
- [ ] `grep -c "docs/superpowers/" SKILL.md` returns 0
- [ ] `project_category` write logic present (grep "project_category" finds the write site + heuristic note)
- [ ] Conditional trigger logic documented: condition table or prose listing both triggers (`project_category in {web,api}` + `has_external_input: true`)

**TDD Sequence:**
- [ ] Step 1: greps above
- [ ] Step 2: confirm v2.0 fails (no 7th item, no findings-detail.json reference, no user_impact filter)
- [ ] Step 3: edit SKILL.md
- [ ] Step 4: confirm greps pass
- [ ] Step 5: self-review
- [ ] Step 6: commit. Suggested message: `feat(finishing): 7th 安全审查 + 6th 项产品语言展示 + project_category + 路径 ohaze`

**Cross-Task Dependencies:**
- Consumes: Task 4's `findings-detail.json` schema and display routing contract
- Provides: `project_category` write into `current-ship.json` consumed by Task 6's schema docs

---

## Task 6: Major rewrite — `commands/ship.md`

**Files:**
- Modify: `plugins/ohaze/commands/ship.md`

**Behavior Contract:**
- **Phase 1 invocation contract update**: Phase 1 now awaits "brief approved" terminal state (was "design approved"); spec is NO LONGER produced in Phase 1
- **NEW Phase 1.5 — Claude auto-writes spec**:
  - Pre-write step (mandatory code-reading): Claude lists 4 categories of relevant files (same-area / caller-callee / cross-ref spec-plan / CHANGELOG similar) and reads them; spec MUST cite `file:line` references
  - 5 boundary-question triggers (only when condition met): external API; deployment target / launch impact; significant architecture conflict with existing patterns; cost/billing impact; multiple technical options with user-visible tradeoff (cost/performance/UX). Each trigger uses `AskUserQuestion` (single-point, NOT open dialog). Pure-technical decisions (lib A vs lib B, internal naming, control-flow shape) MUST NOT trigger a haze question — Claude self-decides
  - After spec written: Claude writes back into the brief's "Claude 替你决定的关键技术方向" section a one-liner-per-decision summary for haze post-hoc review
  - Spec landing: `<worktree>/docs/ohaze/specs/<YYYY-MM-DD>-<slug>-design.md`
  - Brief landing: `<worktree>/docs/ohaze/briefs/<YYYY-MM-DD>-<slug>-brief.md`
- **NEW Phase 1.6 — Codex audits spec**:
  - Invoke `Skill(ohaze:spec-to-codex-review)` per Task 1's contract
  - Parse `<work_dir>/.ohaze/spec-review-verdict.json`
  - PASS → proceed to Phase 2 worktree (NOTE: if Phase 1.6 runs pre-worktree on main_repo_path, that's allowed per spec; the verdict file is then migrated/cleaned post-worktree creation per spec §"verdict 落点")
  - NEEDS-CLARIFICATION → route per `issue.routing`: `fix-in-spec` → Claude edits spec, increments `spec_review_iteration`, re-runs Phase 1.6; `ask-haze` issues batched into single `AskUserQuestion`, then Claude edits spec with answers, re-runs
  - Loop max 2 iterations; iteration 3+ surfaces to haze with 3 options (accept-as-is / revise brief / drop feature)
- **Phase 2b update**: write BOTH brief AND spec into worktree; commit BOTH on the feat branch with message `docs(brief+spec): <slug> 设计`. Capture both `brief_path` AND `spec_path`.
- **NEW Phase 3.5 — Plan one-line summary + default-go**:
  - Claude generates plan summary in the form: `📋 Plan 写好了 → docs/ohaze/plans/<file>.md, 拆了 <N> 个 Task,涉及 <X / Y / Z 三块>, 准备进 Codex 实现,可打断`
  - Default-go: Claude proceeds directly to Phase 4 dispatch in the SAME turn (no 'go' wait)
  - Interruptibility: if haze's next user turn input is anything other than "go" or empty/affirmative, Phase 4 dispatch is canceled and flow enters modify/cancel branch (finishing modify sub-flow)
- **`current-ship.json` schema additions** documented:
  - `brief_path: <absolute>` (filled at Phase 2b)
  - `spec_review_iteration: <integer, default 0>` (incremented in Phase 1.6 loop)
  - `project_category: <web|api|cli|plugin|agent|other|null>` (set later by finishing per Task 5; ship.md sets `null` at handoff write)
  - existing fields preserved; Write Protocol (Read-modify-Write, preserve all fields) unchanged
- **Path migration**: every `docs/superpowers/{specs,plans}/` → `docs/ohaze/{specs,plans}/`; `docs/ohaze/briefs/` new path documented

**Acceptance Criteria:**
- [ ] `grep -E "## Phase 1\.5|## Phase 1\.6|## Phase 3\.5" ship.md` matches all 3 new Phases
- [ ] Phase 1 section: "brief approved" terminal state documented; "design approved" removed as terminal phrase
- [ ] Phase 1.5: 4 code-reading categories listed; 5 boundary triggers listed; brief writeback documented
- [ ] Phase 1.6: invokes `Skill(ohaze:spec-to-codex-review)`; documents verdict file path; documents loop max 2 + escalation
- [ ] Phase 2b: writes both brief AND spec; commit message includes both
- [ ] Phase 3.5: default-go + interruptibility documented; summary template embedded; no 'go' wait language remains in Phase 3 wrap-up
- [ ] `current-ship.json` schema in ship.md lists `brief_path`, `spec_review_iteration`, `project_category` as new fields with semantics documented
- [ ] `grep -c "docs/superpowers/" ship.md` returns 0
- [ ] `grep "docs/ohaze/briefs/" ship.md` matches ≥ 1

**TDD Sequence:**
- [ ] Step 1: failing greps
- [ ] Step 2: confirm v2.0 fails (no Phase 1.5/1.6/3.5, has docs/superpowers paths, has 'go' wait)
- [ ] Step 3: rewrite ship.md per contract (this is the biggest file change in the plan; expect ~150 line delta)
- [ ] Step 4: confirm all greps pass
- [ ] Step 5: self-review — walk through the Phase 1 → 1.5 → 1.6 → 2 → 3 → 3.5 → 4 flow end-to-end mentally; ensure hand-offs between Phases are explicit per the `dacf7c6` "don't end turn on hand-off" protocol; ensure `current-ship.json` Write Protocol cross-references stay correct
- [ ] Step 6: commit. Suggested message: `feat(ship): Phase 1.5 spec 自动写 + Phase 1.6 Codex 反审 + Phase 3.5 default-go + 路径 ohaze`

**Cross-Task Dependencies:**
- Consumes: Task 1's `Skill(ohaze:spec-to-codex-review)` invocation surface; Task 2's "brief approved" terminal state; Task 3's plan-summary hand-off
- Provides: `current-ship.json` field set consumed by Tasks 4, 5, 7

---

## Task 7: Refactor `commands/ship-review.md` — ADVERSARIAL display update

**Files:**
- Modify: `plugins/ohaze/commands/ship-review.md`

**Behavior Contract:**
- **Phase 6.5 / Reviewer-提出的-对抗式-发现 section rewrite**:
  - Read `<worktree>/.ohaze/findings-detail.json` (single source of truth, written by codex-executor per Task 4)
  - Filter: only show ADVERSARIAL findings where `user_impact_description != null`
  - Display each shown finding using `user_impact_description` (product language) — NEVER raw `technical_description` / `evidence`
  - Skipped ADVERSARIAL count shown as: `🟢 已 skip 的纯技术细节: <K> 条 → 完整清单: .ohaze/findings-detail.json`
  - User decision options unchanged (fix / accept), still routes into existing finishing 6th menu item
- **Path migration**: every `docs/superpowers/` → `docs/ohaze/`

**Acceptance Criteria:**
- [ ] `grep "findings-detail.json" ship-review.md` matches; references are reads (not writes)
- [ ] `grep "user_impact_description" ship-review.md` matches; logic filters on `!= null`
- [ ] `grep -E "🔴|🟡|🟢" ship-review.md` matches (display template uses emoji buckets)
- [ ] No raw `evidence`/`file:line` fields surface to user in the ADVERSARIAL display path (manual review check)
- [ ] `grep -c "docs/superpowers/" ship-review.md` returns 0

**TDD Sequence:**
- [ ] Step 1: failing greps
- [ ] Step 2: confirm v2.0 fails (raw issues array displayed)
- [ ] Step 3: edit ship-review.md
- [ ] Step 4: confirm greps pass
- [ ] Step 5: self-review
- [ ] Step 6: commit. Suggested message: `feat(ship-review): 6.5 项 ADVERSARIAL 改产品语言展示 + 路径 ohaze`

**Cross-Task Dependencies:**
- Consumes: Task 4's `findings-detail.json` schema and `user_impact_description` field

---

## Task 8: Version bump + four-piece doc sync + .gitignore

**Files:**
- Modify: `plugins/ohaze/.claude-plugin/plugin.json`
- Modify: `CLAUDE.md`
- Modify: `README.md`
- Modify: `ROADMAP.md`
- Modify: `CHANGELOG.md`
- Modify: `.gitignore`

**Behavior Contract:**
- **plugin.json**: `version` field `"2.0.0"` → `"2.1.0"`. No other field changes unless needed for parity.
- **CLAUDE.md**:
  - Update "项目特殊约定" section: describe new Phase 1.5/1.6/3.5 flow at a high level (one sentence each); reference new `spec-to-codex-review` skill; reference path migration `docs/ohaze/`
  - Update "关键文件 / 入口" section: add `spec-to-codex-review` to "核心 skills" list; add `briefs/` to data-contract paths
  - Keep all existing constraints (no nohup, no ScheduleWakeup, `codex exec resume` flag asymmetry) verbatim — these are still load-bearing
- **README.md**:
  - Update overview/architecture section: explain Phase 1.5/1.6/3.5 at the "what user sees" level (haze sees brief, not spec; Codex audits spec; plan auto-progresses)
  - Update version reference if pinned
  - Path references migrated
- **ROADMAP.md**:
  - "## 当前主线" — replace v2.0 release-prep dogfood item with v2.1.0 BDD/TDD restructure status (since v2.0.0 is now functionally released and v2.1 is the active mainline). Move the v2.0 dogfood completion to CHANGELOG.
  - "## Backlog" — remove items folded into v2.1; add any v2.2+ candidates that emerged (e.g., "plan Codex/Claude dry-run audit if observed plan-drift rate exceeds X")
- **CHANGELOG.md**:
  - New `## [2.1.0] - 2026-06-10` block above v2.0.0
  - Sections: `### Added`, `### Changed`, `### Migrated` (path convention)
  - Each entry cites the spec section or commit subject; theme line at top: e.g. "v2.1 主题:把 haze 从 spec/plan/技术 finding 视野中拿掉"
- **.gitignore**: add lines for `.ohaze/spec-review-verdict.json` and `.ohaze/findings-detail.json` (other `.ohaze/` artifacts may already be globbed by `.ohaze/`; confirm coverage and add explicit lines only if needed)

**Acceptance Criteria:**
- [ ] `jq -r .version plugins/ohaze/.claude-plugin/plugin.json` outputs `2.1.0`
- [ ] `grep "Phase 1\.5\|Phase 1\.6\|Phase 3\.5\|spec-to-codex-review" CLAUDE.md` matches each item
- [ ] `grep "docs/ohaze/briefs\|docs/ohaze/specs\|docs/ohaze/plans" CLAUDE.md` matches all three paths
- [ ] `grep "## \[2\.1\.0\]" CHANGELOG.md` matches
- [ ] CHANGELOG v2.1.0 block lists at minimum: BDD-flavored Phase 1; Phase 1.5 auto-spec; Phase 1.6 spec-to-codex-review; Phase 3.5 default-go; investigate_first; 7th security review; user_impact_description; findings-detail.json; path migration
- [ ] ROADMAP: v2.0 dogfood item is no longer in "## 当前主线" (moved to CHANGELOG as completed)
- [ ] `.gitignore` includes either explicit lines for the two new JSON files OR existing `.ohaze/` glob already covers them (verify with `git check-ignore`)
- [ ] No mention of `docs/superpowers/` paths in any of the 5 docs (final cross-cut grep)

**TDD Sequence:**
- [ ] Step 1: greps above + jq version check as failing tests
- [ ] Step 2: confirm v2.0 state fails (version 2.0.0, no Phase 1.5/1.6/3.5 in CLAUDE.md, no v2.1.0 CHANGELOG block, etc.)
- [ ] Step 3: edit all 6 files
- [ ] Step 4: confirm all greps pass + cross-cut "no docs/superpowers/" check
- [ ] Step 5: self-review — sanity-check ROADMAP doesn't lose information (everything moved or kept, nothing dropped silently)
- [ ] Step 6: commit. Suggested message: `chore(release): v2.1.0 — plugin.json + 四件套 + .gitignore`

**Cross-Task Dependencies:**
- Consumes: all prior Tasks (this is the release-prep capstone documenting what 1-7 produced)

---

## Plan-wide invariants

- **No code identifier in haze-facing text**: any user-facing string surfaced through `AskUserQuestion`, plan summary, or finishing menu MUST use product language; any code identifier (file path, function name, line number) belongs in `findings-detail.json` only. This invariant cuts across Tasks 4, 5, 7.
- **Single source of truth — `findings-detail.json`**: Tasks 4, 5, 7 all touch this file. Task 4 writes it (codex-executor Phase 5.3). Tasks 5 and 7 read it. No other writer exists.
- **Path migration is total**: zero `docs/superpowers/` references survive in any file Tasks 2-8 touch. Cross-cut grep at end: `grep -r "docs/superpowers/" plugins/ohaze commands CLAUDE.md README.md ROADMAP.md CHANGELOG.md` returns empty.
- **Schema additions to `current-ship.json` are additive only**: existing field names/semantics stay; new fields default to null where unset; Write Protocol (Read → spread → override → Write) preserves backwards compat.
- **No 'go' gate breaks the orchestration chain**: every Phase hand-off (1 → 1.5 → 1.6 → 2 → 3 → 3.5 → 4) MUST explicitly state "handing back" or "proceeding in same turn" per the `dacf7c6` no-end-of-turn protocol.

---

## Self-Review

**1. Spec coverage**: Walked spec §Phase 1 → §Phase 1.5 → §Phase 1.6 → §Phase 3.5 → §Phase 6 → §Phase 7 → §产品语言翻译 → §涉及文件改动清单. Each maps to:
- §Phase 1 → Task 2
- §Phase 1.5 → Task 6 (Phase 1.5 inside ship.md)
- §Phase 1.6 → Task 1 (new skill) + Task 6 (ship.md call site)
- §Phase 3.5 → Task 3 (writing-plans hand-off) + Task 6 (ship.md default-go)
- §Phase 6 Iron Law → Task 4
- §Phase 7 Security Review → Task 5
- §产品语言翻译 → Task 4 (Phase 5 reviewer) + Task 5 (finishing 6th display) + Task 7 (ship-review 6.5)
- §涉及文件改动清单 → Tasks 1-8 (1-to-1 mapping with file list)
- §数据契约改动 → Task 6 (ship.md schema docs) + Task 5 (project_category write)

**2. Placeholder scan**: No TBD/TODO/"appropriate"/"handle edge cases" found in plan body.

**3. Contract leakage**: No complete function bodies. The XML prompt block in Task 1 is a verbatim contract surface (allowed per spec — embedded prompt is data, not implementation). The `<investigate_first>` block in Task 4 is similarly a contract surface (4 prose lines, not executable). All other contracts are signature-level descriptions.

**4. Contract consistency**: Field names cross-checked:
- `user_impact_description` referenced in Tasks 1, 4, 5, 7 — consistent.
- `findings-detail.json` schema written in Task 4, read in Tasks 5, 7 — consistent.
- `current-ship.json` new fields (`brief_path`, `spec_review_iteration`, `project_category`) introduced in Task 6, consumed in Tasks 4, 5 — consistent.

**5. Acceptance checkability**: Every AC is grep-based or jq-based or visual-walkthrough — all executable as shell commands. No "should work well" / "looks good" softness.

---

## Execution handoff

📋 Plan saved → `docs/ohaze/plans/2026-06-10-bdd-plan-tdd-do.md`, 8 Tasks, areas: new skill (1) + skill refactors (2-5) + ship-flow rewrites (6-7) + release-prep (8). Codex will receive this verbatim — its contracts and acceptance criteria define done.

Standalone invocation note: if this skill was called outside `/ohaze:ship`, next step is `Skill(ohaze:plan-to-codex-prompt)` then `Skill(ohaze:codex-executor)` mode=dispatch. Inside ship flow, control returns to ship.md Phase 4 for that dispatch.
