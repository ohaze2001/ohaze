# spec-audit-scope-reframe — Guidance Plan

> **For Codex (the executor):** Each Task below specifies WHAT must be true at completion, not HOW to write it line by line. You have autonomy over internal naming, control flow, helper extraction, and exact prose phrasing. You do NOT have autonomy over the file paths in Files lists, the contract surface listed in Behavior Contract, acceptance criteria, or cross-Task invariants. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 缩 `plugins/ohaze/skills/spec-to-codex-review/SKILL.md` audit prompt 任务范围从 5 维度（A/B/C/D/E）改 2 维度（A Functional Coverage + B Implementation Quality），删 B AMBIGUITY / C MISSING DETAILS / D CONFLICTS WITH EXISTING CODE 三段，配机械锚点字段（brief_anchor + better_alternative）防内部 drift，从根因上修「越审越深」元问题。

**Architecture:** 不加新审查层（GAN discriminator / 自反思 / harness），而是重新定义 audit 的 task scope。B/C/D 三维度本质是 implementer 实施阶段的活越权前置 → 天然无底洞 → codex 每 iter 都从新视角开新维度。删掉它们后，audit 在结构上不可能越审越深；implementer 撞 B/C/D 类问题走现有 `<missing_context_gating>` + Phase 5 cross-source review 兜底（不动）。Category enum 闭合为 3 值 {COVERAGE-GAP, COVERAGE-DRIFT, ALT-DECISION}，schema 加 brief_anchor + better_alternative 字段强制 finding 带具体锚点 / 替代方案。

**Tech Stack:** Markdown 文档 + JSON schema 描述 + grep / file existence acceptance（无 unit test runner，per CLAUDE.md「ohaze 是 Markdown plugin，靠 grep/test/JSON-load 结构断言 + dogfood 端到端冒烟验证」）。

**Spec reference:** `docs/ohaze/specs/2026-06-14-spec-audit-scope-reframe-design.md` — 所有详细 Task 子步骤 (1.1-1.9 / 2.1-2.3) 和 acceptance grep 命令在 spec 内为单一真相源，本 plan 不复制。

**Pre-flight context:** Phase 1.6 dogfood spec audit 跑了 3 iter 全 NEEDS-CLARIFICATION（活生生越审越深 trap 证据），haze 在 iter 3 选 "accept current spec as-is 进 Phase 2"。Iter 3 仍剩 1 个 IMPORTANT/MISSING finding (`post-validation-verdict-stale` — Task 1.7+1.8 normalize 后未说重算 top-level verdict)。**Codex 在 Task 1 实施时应该一并修这个 invariant 漏洞**（详见 Task 1 末尾的 Implementer Note）。Phase 5 cross-source review 是兜底。

---

## File Structure

| File | Responsibility |
|---|---|
| `plugins/ohaze/skills/spec-to-codex-review/SKILL.md` | 唯一被实质修改的源文件 — audit prompt + constraints + output_format schema + Output Validation + Malformed JSON Fallback stub |
| `plugins/ohaze/.claude-plugin/plugin.json` | manifest version bump 2.1.1 → 2.1.2 |
| `CHANGELOG.md` | `[Unreleased] ### Fixed` 加本 ship 完整描述 |
| `ROADMAP.md` | `## Backlog` 删「越审越深」高优条目 |

不动文件（明确边界）：

- `plugins/ohaze/skills/codex-executor/SKILL.md` (Phase 5 cross-source review 是 audit 之外的二道闸，保留)
- `plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md` (`<missing_context_gating>` implementer 反馈通道保留)
- `plugins/ohaze/skills/finishing/SKILL.md` / `plugins/ohaze/skills/brainstorming/SKILL.md` / `plugins/ohaze/skills/using-git-worktrees/SKILL.md` / `plugins/ohaze/skills/writing-plans/SKILL.md`
- `plugins/ohaze/commands/ship.md` / `ship-review.md` / `ship-finish.md` / `status.md` (Phase 1.6 verdict routing 保持兼容)

---

## Task 1: spec-to-codex-review/SKILL.md prompt 5→2 维度改写

**Files:**
- Modify: `plugins/ohaze/skills/spec-to-codex-review/SKILL.md`

**Behavior Contract:**

- **External interface (unchanged contract surface):**
  - Skill invocation 参数: `brief_path`, `spec_path`, `code_refs`, `project_type`, `main_repo_path` — 全保留
  - Output 文件位置: `<work_dir>/.ohaze/spec-review-verdict.json` — 不变
  - JSON 顶层 schema: `{verdict, summary, issues[]}` — 不变
  - Verdict enum: `"PASS" | "NEEDS-CLARIFICATION"` — 不变
  - Issue 必填字段: `id, category, severity, routing, evidence, problem, user_impact_description, suggestion, confidence` — 不变
  - Severity enum: `"CRITICAL" | "IMPORTANT" | "NICE-TO-HAVE"` — 不变
  - Routing enum: `"fix-in-spec" | "ask-haze"` — 不变
  - Confidence range: integer 7-10 — 不变

- **New / changed contract surface:**
  - `<task>` 段引导词必须含字面字符串 "EXACTLY TWO axes"
  - `<review_dimensions>` 段必须开头含 "Walk through these 2 dimensions"
  - `<review_dimensions>` 段只剩 2 个子段，命名必须含字面 "FUNCTIONAL COVERAGE" + "IMPLEMENTATION QUALITY"
  - 新增 `<scope_boundary>` 段（在 `<review_dimensions>` 之后），明示 implementer-stage 三类问题 OUT OF SCOPE，必须 cross-ref `missing_context_gating` + `cross-source review` 两个字面字符串
  - Category enum 缩为闭合 3 值: `"COVERAGE-GAP" | "COVERAGE-DRIFT" | "ALT-DECISION"`
  - Issue schema 新增字段 `brief_anchor` (string | null) + `better_alternative` (object | null with sub-fields `current_approach`, `proposed_alternative`, `quantified_tradeoff`)
  - Output Validation 段新增 4 条规则：(a) category enum 校验改新 3 值；(b) COVERAGE-* 缺非空 brief_anchor → normalize severity 为 NICE-TO-HAVE；(c) ALT-DECISION 缺完整 better_alternative 3 子字段 → 整条 issue 丢弃 + 警告；(d) **所有 normalize 跑完后必须重算 top-level verdict**：`PASS` iff zero CRITICAL/IMPORTANT remaining；fallback stub 为例外保持 `NEEDS-CLARIFICATION`
  - 例外 fallback stub `id=codex-output-unparseable` 跳过 (b)/(c) 降级规则
  - Malformed JSON Fallback stub 改完整内容：category 改 `COVERAGE-GAP`，加 `brief_anchor` 设特殊文字标记（如 `"<fallback exception: review system fault, no specific brief line applicable>"`），`better_alternative` 设 `null`

- **Old artifacts that MUST be removed:**
  - Review dimensions 子段 B `AMBIGUITY (2-interpretation test)` 整段
  - Review dimensions 子段 C `MISSING DETAILS (implementer "卡住" test)` 整段
  - Review dimensions 子段 D `CONFLICTS WITH EXISTING CODE` 整段
  - Constraints 段旧 5 值 enum 中前 4 个字面值 `AMBIGUITY`, `MISSING`, `CONFLICT`, `DRIFT`（保留 `ALT-DECISION`）
  - `Walk through these 5 dimensions in order. Do not skip any.` 字面字符串

- **Invariants:**
  - 改完后 `Skill(ohaze:spec-to-codex-review)` 调用接口与 ship.md Phase 1.6 verdict routing 完全兼容（PASS / NEEDS-CLARIFICATION / fix-in-spec / ask-haze / max-2 loop 不变）
  - SKILL.md 顶层段结构（`## Invocation Contract` / `## Codex Invocation Contract` / `## Prompt Template` / `## Output Validation` / `## Malformed JSON Fallback` / `## Caller Handoff`）保留，只改内容不动框架

**Acceptance Criteria:**

引用 spec `## Tasks → Task 1 → Acceptance (grep / structural)` 完整 grep 清单作为单一真相源（spec line ~141-160 区间共 ~20 条 grep 命令）。Codex 必须逐条跑过、全 PASS。其中关键示例（不全 — 完整以 spec 为准）：

- [ ] `! grep -E '^B\) AMBIGUITY' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` （B 段已删）
- [ ] `! grep -E '^C\) MISSING' plugins/ohaze/skills/spec-to-codex-review/SKILL.md`
- [ ] `! grep -E '^D\) CONFLICTS' plugins/ohaze/skills/spec-to-codex-review/SKILL.md`
- [ ] `grep -q 'FUNCTIONAL COVERAGE' plugins/ohaze/skills/spec-to-codex-review/SKILL.md`
- [ ] `grep -q 'IMPLEMENTATION QUALITY' plugins/ohaze/skills/spec-to-codex-review/SKILL.md`
- [ ] `grep -q '<scope_boundary>' plugins/ohaze/skills/spec-to-codex-review/SKILL.md`
- [ ] `grep -q 'missing_context_gating' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` (scope_boundary cross-ref)
- [ ] `grep -q 'cross-source review' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` (scope_boundary cross-ref)
- [ ] `grep -q 'COVERAGE-GAP' plugins/ohaze/skills/spec-to-codex-review/SKILL.md`
- [ ] `grep -q 'COVERAGE-DRIFT' plugins/ohaze/skills/spec-to-codex-review/SKILL.md`
- [ ] `grep -q 'ALT-DECISION' plugins/ohaze/skills/spec-to-codex-review/SKILL.md`
- [ ] `! (grep -E '\b(AMBIGUITY|MISSING|CONFLICT)\b|(^|[^-])\bDRIFT\b' plugins/ohaze/skills/spec-to-codex-review/SKILL.md | grep -v -E '(越审越深|missing_context_gating|conflicts with existing)' | grep -q .)` （旧 enum 4 值无残留；用 grep -E 保上下文、grep -q . 测有无残留）
- [ ] `grep -q 'brief_anchor' plugins/ohaze/skills/spec-to-codex-review/SKILL.md`
- [ ] `grep -q 'better_alternative' plugins/ohaze/skills/spec-to-codex-review/SKILL.md`
- [ ] `grep -q 'current_approach' plugins/ohaze/skills/spec-to-codex-review/SKILL.md`
- [ ] `grep -q 'proposed_alternative' plugins/ohaze/skills/spec-to-codex-review/SKILL.md`
- [ ] `grep -q 'quantified_tradeoff' plugins/ohaze/skills/spec-to-codex-review/SKILL.md`
- [ ] `grep -q 'EXACTLY TWO axes' plugins/ohaze/skills/spec-to-codex-review/SKILL.md`
- [ ] `grep -q 'Walk through these 2 dimensions' plugins/ohaze/skills/spec-to-codex-review/SKILL.md`
- [ ] `! grep -q 'Walk through these 5 dimensions' plugins/ohaze/skills/spec-to-codex-review/SKILL.md`
- [ ] **Spec 之外的 invariant 重算规则**: `grep -E 'recompute|重算' plugins/ohaze/skills/spec-to-codex-review/SKILL.md | grep -i 'verdict' | grep -q .` (Output Validation 段含 verdict 重算规则 — Codex 在 Task 1.8 落地)
- [ ] Caller invariant: `grep -q 'Skill(ohaze:spec-to-codex-review)' plugins/ohaze/commands/ship.md` (ship.md 调用接口未变)
- [ ] Structural sanity: `grep -c '^## ' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` ≥ 6 (SKILL 顶层段未被破坏 — Invocation Contract / Codex Invocation Contract / Prompt Template / Output Validation / Malformed JSON Fallback / Caller Handoff)

**TDD Sequence:**

- [ ] Step 1: Read 当前 `plugins/ohaze/skills/spec-to-codex-review/SKILL.md:30-220` 全量 — 锁定 baseline
- [ ] Step 2: Edit SKILL.md `<task>` 段（spec Task 1.1） — 引导词改 EXACTLY TWO axes
- [ ] Step 3: Edit SKILL.md `<review_dimensions>` 段（spec Task 1.2-1.4）— 删 B/C/D，改 A→FUNCTIONAL COVERAGE，原 E 改名 IMPLEMENTATION QUALITY 上提为 B
- [ ] Step 4: Edit SKILL.md 加 `<scope_boundary>` 段（spec Task 1.5）— cross-ref missing_context_gating + cross-source review
- [ ] Step 5: Edit SKILL.md `<constraints>` 段（spec Task 1.6）— category enum 缩 3 值闭合
- [ ] Step 6: Edit SKILL.md `<output_format>` JSON schema 段（spec Task 1.7）— 加 brief_anchor + better_alternative + 字段一致性规则
- [ ] Step 7: Edit SKILL.md Output Validation 段（spec Task 1.8）— 加 enum + brief_anchor + better_alternative 校验 + **iter 3 finding 的 verdict 重算规则** + fallback stub 例外
- [ ] Step 8: Edit SKILL.md Malformed JSON Fallback stub（spec Task 1.9）— 改完整 stub 与新 schema 一致
- [ ] Step 9: 跑全部 Acceptance Criteria grep 命令，全 PASS
- [ ] Step 10: 不提交 — orchestrator 统一 commit per Task

**Cross-Task Dependencies:**
- Provides: 改后的 SKILL prompt 给 Task 3 dogfood 验证用
- Nothing 依赖 Task 1 内部细节，因为 schema 顶层兼容

**Implementer Note (重要 — iter 3 finding 落地):**

Phase 1.6 spec audit iter 3 发现 spec 写了 normalize 规则但漏说 verdict 重算。Codex 在 Step 7 落地 Output Validation 段时**必须**加这条规则：「after all issue normalize / drop rules run, recompute top-level `verdict` from final `issues[]`: `verdict='PASS'` iff zero CRITICAL/IMPORTANT items remain; otherwise `verdict='NEEDS-CLARIFICATION'`. Exception: malformed JSON fallback stub (`id=codex-output-unparseable`) keeps `NEEDS-CLARIFICATION` regardless of computed value.」spec 已在 1.9 Implementer Note 隐含此点，Codex 在 1.8 显式落到 SKILL.md。

---

## Task 2: 文档落档（manifest + CHANGELOG + ROADMAP）

**Files:**
- Modify: `plugins/ohaze/.claude-plugin/plugin.json`
- Modify: `CHANGELOG.md`
- Modify: `ROADMAP.md`

**Behavior Contract:**

- **manifest:** `plugins/ohaze/.claude-plugin/plugin.json` 字段 `version` 从 `"2.1.1"` 改 `"2.1.2"`（PATCH bump，bug fix 类元问题修复，无 API breaking、无新 user-facing 功能）
- **CHANGELOG:** `CHANGELOG.md` 找到 `[Unreleased]` 块（如无则在最顶部新建），在 `### Fixed` 子段（如无则新建）追加一条本 ship 完整描述（详见 spec Task 2.2 提供的完整 Markdown 块）。条目必须含字面字符串 `spec-audit-scope-reframe` + `越审越深` + `COVERAGE-GAP` + `ALT-DECISION` 用于回查
- **ROADMAP:** `ROADMAP.md` `## Backlog` 段删除「越审越深」高优先元问题整条目（line 21 在本 worktree HEAD 时刻；条目核心标识词「spec audit "越审越深"」+ 「没有收敛阈值」+「codex 每次 iter 都找到新维度 issue」）。如条目编号有「4.」前缀，后续条目编号顺移（如原 5. → 4.）保持顺序连续

- **Invariants:**
  - CHANGELOG `[Unreleased]` 落「已完成未发版」(全局 CLAUDE.md 信息落点路由) — 不动其他版本块
  - ROADMAP `## 当前主线` / `## Bug` / `## 长期目标` 段不动
  - 三个文件之间字面 `2.1.2` 字符串保持一致（manifest 改了，CHANGELOG 暂只进 `[Unreleased]`，finishing 阶段统一打 tag 时同步 `[2.1.2]` 块）

**Acceptance Criteria:**

引用 spec `## Tasks → Task 2 → Acceptance` 作为真相源。关键 grep：

- [ ] `grep -q '"version": "2.1.2"' plugins/ohaze/.claude-plugin/plugin.json` (manifest 已 bump)
- [ ] `! grep -q '"version": "2.1.1"' plugins/ohaze/.claude-plugin/plugin.json` (旧版本号已替换)
- [ ] `grep -q 'spec-audit-scope-reframe' CHANGELOG.md` (Fixed 条目已加 slug 锚点)
- [ ] `grep -q '越审越深' CHANGELOG.md` (中文描述)
- [ ] `grep -q 'COVERAGE-GAP' CHANGELOG.md` (新 enum 提及)
- [ ] `! grep -E 'spec audit ["「]越审越深["」]|收敛阈值|每次 iter 都找到新维度 issue' ROADMAP.md` (Backlog 条目已删 — 3 alt regex 任一 match 即报错；仅校 ROADMAP 不与 CHANGELOG 冲突)
- [ ] `grep -q '## Backlog' ROADMAP.md` (Backlog 段本身保留)
- [ ] `grep -q '## 当前主线' ROADMAP.md` (其他段保留)

**TDD Sequence:**

- [ ] Step 1: Read `plugins/ohaze/.claude-plugin/plugin.json` — 改 `version` 字段
- [ ] Step 2: Read `CHANGELOG.md` 顶部 — 定位 `[Unreleased]` 块（如无新建）+ `### Fixed`（如无新建）
- [ ] Step 3: Edit CHANGELOG 加完整条目
- [ ] Step 4: Read `ROADMAP.md` 定位 Backlog 段 + 「越审越深」条目
- [ ] Step 5: Edit ROADMAP 删整条
- [ ] Step 6: 跑全部 Acceptance Criteria grep 命令，全 PASS
- [ ] Step 7: 不提交 — orchestrator 统一 commit

**Cross-Task Dependencies:**
- Depends on: Task 1（CHANGELOG 描述实际生效的 SKILL 改动；版本号 bump 反映 Task 1 完成）
- Provides: CHANGELOG/ROADMAP 状态给 Task 3 dogfood 验证

---

## Task 3: Dogfood 端到端 grep 冒烟验证

**Files:**
- 无（read-only verification）

**Behavior Contract:**

- 全跑 Task 1 + Task 2 acceptance grep 命令一遍，全部 PASS
- 跑额外 sanity grep：
  - SKILL.md 顶层段结构未坏（`grep -c '^## '` ≥ 6）
  - ship.md 调用接口未变（`grep -q 'Skill(ohaze:spec-to-codex-review)' plugins/ohaze/commands/ship.md`）
  - 不动文件清单全未变（`git diff --name-only` 只出现 4 个允许文件 + `docs/ohaze/{briefs,specs,plans}/2026-06-14-spec-audit-scope-reframe-*` 三个新 docs 文件）
- Final report 列出 touched files + 关键 grep 摘要 + 任何遗留 NICE-TO-HAVE 备注

**Acceptance Criteria:**

- [ ] Task 1 全部 acceptance grep PASS（≥ 22 条）
- [ ] Task 2 全部 acceptance grep PASS（≥ 8 条）
- [ ] `git diff --name-only HEAD~1 HEAD` 输出文件只在白名单：`plugins/ohaze/skills/spec-to-codex-review/SKILL.md` / `plugins/ohaze/.claude-plugin/plugin.json` / `CHANGELOG.md` / `ROADMAP.md`（外加 docs/ 三个新文件已在 Phase 2 commit 不在本 commit 内）
- [ ] `grep -c '^### ' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` 数值与修前差 ≤ 2（SKILL 结构未被破坏）

**TDD Sequence:**

- [ ] Step 1: 跑 Task 1 全部 acceptance grep
- [ ] Step 2: 跑 Task 2 全部 acceptance grep
- [ ] Step 3: 跑额外 sanity grep
- [ ] Step 4: 写 final report

**Cross-Task Dependencies:**
- Depends on: Task 1 + Task 2 都已完成（read-only verification）

---

## Out of Scope (与 brief/spec 一致严格执行)

- 不加 brief judge / cross-source firewall 前置
- 不调闸门超参（max iter / confidence gate / NICE-TO-HAVE 阈值）
- 不改 codex-executor / finishing / plan-to-codex-prompt / brainstorming / using-git-worktrees
- 不改 ship.md / ship-review.md / ship-finish.md
- 不引入 plan-judge / spec audit retry refine prompt / self-reflection layer 等新审查 primitive
- 不重写 SKILL.md「Invocation Contract」/「Codex Invocation Contract」框架；只改 prompt 文本 + enum + 新增 2 字段 + 同步 Validation/Fallback

---

## Self-Review Notes

- ✅ Spec coverage: 3 Tasks 对应 spec 3 Tasks（1 SKILL + 2 文档 + 3 dogfood），spec Task 1.1-1.9 全部对应 Task 1 TDD Step 2-8（每 step 一对一），iter 3 finding 在 Implementer Note 单独点名
- ✅ No placeholders — 所有 acceptance 都是具体 grep 命令
- ✅ Contract leakage check — Task 1.7 spec 的 JSON schema sample 块属 "JSON config sample" 允许类型，不是 implementation；其他无 forbidden code block
- ✅ Contract consistency — 字面字符串 EXACTLY TWO axes / Walk through these 2 dimensions / FUNCTIONAL COVERAGE / IMPLEMENTATION QUALITY / scope_boundary / COVERAGE-GAP / COVERAGE-DRIFT / ALT-DECISION 跨 Task 一致
- ✅ Acceptance checkability — 全 grep / file existence，可机械跑
