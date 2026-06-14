# spec-audit-scope-reframe — Implementation Spec
> 给 Codex 看。brief 在 .ohaze/brief-draft.md 给 haze 看。

## Context & Goal

ROADMAP backlog 高优先元问题「spec audit 越审越深」根因 = `plugins/ohaze/skills/spec-to-codex-review/SKILL.md` 的 5 维度 audit prompt 把 implementer 实施阶段的活越权前置到 audit 阶段，B/C/D 三维度（措辞模糊 / 细节缺漏 / 与现有代码冲突）天然无底洞 → codex 每 iter 都从干净 implementer 视角找新维度问题 → spec 一路膨胀，scope drift 风险高。

历史数据点：
- 2026-06-11 dream-review-stability ship 撞第 1 次（iter1 修 5 → iter2 找 5 个全新维度）
- 2026-06-14 codex-dispatch-reliability ship 撞第 2 次（iter1 修 4 → iter2 修 3 新维度 → iter3 又 3 个新维度 → 累计 9 个 finding 全部 B/C/D 类、0 个 A/E 类；scope drift 引入 Task 1.4 Background completion protocol + TaskOutput cite + spec-audit-handoff orphan handoff → Phase 5 cross-source reviewer 当场识别 scope drift → review FAIL → 主线程 revert Task 1.4）

修法：把 audit 的 task 范围本身缩到「spec 覆盖 brief 功能 + 是否最佳实现」2 维度，删 B/C/D 全部。配机械锚点字段（A 强制 cite brief line / E 强制带具体 alt + 可量化对比）防止 A/E 内部 drift。

## Code references read in Phase 1.5

### Same-area existing code
- `plugins/ohaze/skills/spec-to-codex-review/SKILL.md:53-76` — Prompt Template `<task>` + `<inputs>` 段（待改引导词）
- `plugins/ohaze/skills/spec-to-codex-review/SKILL.md:77-119` — `<review_dimensions>` 5 维度 A/B/C/D/E 全文（待删 B/C/D、改 A/E）
- `plugins/ohaze/skills/spec-to-codex-review/SKILL.md:121-147` — `<constraints>` 段含 category enum（待改）
- `plugins/ohaze/skills/spec-to-codex-review/SKILL.md:149-172` — `<output_format>` JSON schema（待加 brief_anchor + better_alternative）
- `plugins/ohaze/skills/spec-to-codex-review/SKILL.md:175-189` — Output Validation 段（待同步 enum + 新字段）
- `plugins/ohaze/skills/spec-to-codex-review/SKILL.md:191-216` — Malformed JSON Fallback stub verdict（待同步 enum 之一）

### Caller-callee neighbors（不动，cross-ref only）
- `plugins/ohaze/commands/ship.md` Phase 1.6 — verdict routing (PASS / NEEDS-CLARIFICATION / fix-in-spec / ask-haze / max-2 loop)，不动
- `plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md:85` — `<missing_context_gating>` implementer 反馈通道，不动（新 SKILL `<scope_boundary>` 段会 cross-ref 它）
- `plugins/ohaze/skills/codex-executor/SKILL.md` Phase 5 — cross-source review scope drift firewall，不动（新 SKILL `<scope_boundary>` 段会 cross-ref）

### Related existing spec/plan
- `docs/ohaze/specs/2026-06-13-codex-dispatch-reliability-design.md` Post-implementation Revert Addendum — 上 ship 越审越深 trap 真实数据点链
- `docs/ohaze/specs/2026-06-09-bdd-plan-tdd-do-design.md` — v2.1 spec audit 引入设计真相源（5 维度 prompt 出处）

### CHANGELOG similar entries and prior decisions
- v2.1.1 codex-dispatch-reliability hardening 条目 — 现场 dogfood 越审越深 + revert 完整链路
- v2.1.0 Phase 1.6 spec-to-codex-review 引入条目 — 5 维度 prompt 当前 baseline 来源

## Architecture

### 修前 vs 修后 prompt 任务结构

| 段落 | 修前 | 修后 |
|---|---|---|
| `<task>` 引导词 | "find spec issues that WILL block at execution time: ambiguity / missing constraints / contradictions / scope drift" | "audit along EXACTLY TWO axes only: (1) does spec cover brief, (2) is there a concretely better implementation alternative" |
| `<review_dimensions>` | 5 维度 A/B/C/D/E | 2 维度 A "Functional Coverage" + B "Implementation Quality"（原 E 改名上提） |
| 新增 `<scope_boundary>` | — | 明示 B/C/D 类问题 OUT OF SCOPE，cross-ref `<missing_context_gating>` + Phase 5 cross-source review |
| `<constraints>` category enum | `{AMBIGUITY, MISSING, CONFLICT, DRIFT, ALT-DECISION}` (5 值) | `{COVERAGE-GAP, COVERAGE-DRIFT, ALT-DECISION}` (3 值，enum 闭合不允许扩) |
| `<output_format>` schema | 含 evidence/problem/user_impact_description/suggestion/confidence | 加 `brief_anchor` 字段（COVERAGE-* 必填、ALT-DECISION 可选）+ `better_alternative` 子对象（ALT-DECISION 必填 3 子字段、COVERAGE-* 为 null） |
| Output Validation 段 | enum 校验旧 5 值 | enum 校验新 3 值 + 新增字段一致性规则 |
| Malformed JSON Fallback stub | category=MISSING | category=COVERAGE-GAP（最贴近「无法判断 spec 覆盖度」的语义） |

### 关键设计决定

- **A 维度命名 "Functional Coverage"**：直接对应 brief「这是干嘛的」+「完成的样子」Checklist 双向校验语义
- **B 维度命名 "Implementation Quality"**：直接对应 brief「这个实现方法是不是最好的」语义
- **DRIFT 拆 2 类**：原 5 维度的 DRIFT 是 A 维度内部 scope creep/cut，新拆 COVERAGE-GAP（spec 漏 brief 某项）+ COVERAGE-DRIFT（spec 加 brief 没要的 / 实现 out-of-scope）；两类都属 A 维度
- **brief_anchor 字段宽松模式**：A 维度 finding 应 cite brief 具体 line，但若 codex 实在 cite 不出（罕见边界）→ 降级 severity = NICE-TO-HAVE 不阻塞 PASS，避免 codex 卡死硬蒙
- **better_alternative 字段严格模式**：B 维度 finding 必填 `{current_approach, proposed_alternative, quantified_tradeoff}` 三子字段，缺一项即不报（绝不允许「我会用别的方法」空喊）
- **JSON schema 兼容性**：保持顶层结构（verdict / summary / issues 数组）+ issue 必填字段（id/category/severity/routing/evidence/problem/user_impact_description/suggestion/confidence）；只加 2 个新字段 brief_anchor + better_alternative。下游 ship.md verdict routing 不需要改

### 边界守护

- **不改 SKILL.md「Invocation Contract」/「Codex Invocation Contract」/「Output Validation」框架结构**，只改 prompt 文本 + enum + 新增 2 字段
- **不改 caller-callee 接口**：ship.md Phase 1.6 不动；下游消费 verdict 的 routing 逻辑兼容
- **不改 implementer 反馈通道**：`plan-to-codex-prompt:85` `<missing_context_gating>` 不动
- **不改 cross-source review firewall**：`codex-executor` Phase 5 不动

## Tasks

### Task 1: spec-to-codex-review/SKILL.md prompt 5→2 维度改写

**Files:**
- Modify: `plugins/ohaze/skills/spec-to-codex-review/SKILL.md`

**Changes:**

1.1 改 `<task>` 段（line 56-66）引导词从「find ambiguity/missing/contradictions/drift」改为「audit along EXACTLY TWO axes only」+ 明示 implementer 视角问题 OUT OF SCOPE 走 `<missing_context_gating>` + Phase 5 cross-source review。

1.2 删除 `<review_dimensions>` 段原 B/C/D 三段（原 line 87-115 区间，含 B AMBIGUITY / C MISSING DETAILS / D CONFLICTS WITH EXISTING CODE 三大段及子项）。

1.3 保留并重写 A 段（原 line 80-86 「BRIEF ↔ SPEC ALIGNMENT」）：
- 命名 "FUNCTIONAL COVERAGE (brief ↔ spec, both directions)"
- 增加 4 个具体检查项：每个 brief 完成的样子 checklist 是否被 spec 覆盖（漏=COVERAGE-GAP）/ 每个 brief Scenario 是否实现可达（漏=COVERAGE-GAP）/ 每个 brief Out of Scope 是否被误实现（误=COVERAGE-DRIFT）/ spec 是否加了 brief 没要的新章节/Task/行为（加=COVERAGE-DRIFT）
- 强制规则：每个 A 维度 finding 必须 cite brief 具体 line（写进 brief_anchor 字段）。Cite 不出 → severity 降级 NICE-TO-HAVE 不阻塞。

1.4 保留并重写 E 段（原 line 116-119 「TECHNICAL DECISION CHALLENGE」），重新编号为 B：
- 命名 "IMPLEMENTATION QUALITY (concrete alternative challenge)"
- 强制规则：每个 finding 必填 better_alternative 子对象，含 `{current_approach, proposed_alternative, quantified_tradeoff}`。"Better" 定义可量化的至少一项：simpler（代码量 / 文件触达）/ safer（失败模式数 / 爆炸半径）/ cheaper（LLM 调用 / 存储 / 时延）/ better UX（brief scenario 影响）。
- "I would have done it differently" 无 alternative + 无量化对比 → 不报

1.5 在 `<review_dimensions>` 段之后新增 `<scope_boundary>` 段，明示三类问题 OUT OF SCOPE：
- 措辞模糊（ambiguity in wording）→ implementer 走 `<missing_context_gating>`
- 缺细节（missing low-level details）→ implementer 走 `<missing_context_gating>`
- 与现有代码冲突（conflicts with existing code）→ implementer 执行时 git grep
- 段末写明：「DO NOT report them here even if you notice them. They are handled by other quality gates downstream. Reporting them here causes 'audit 越审越深' — the meta-problem this audit is intentionally designed to avoid.」

1.6 改 `<constraints>` 段（line 121-147）category enum：
- 旧「Each issue must be tagged with one of: {AMBIGUITY, MISSING, CONFLICT, DRIFT, ALT-DECISION}」→ 新 3 值闭合 enum：
  - COVERAGE-GAP: A-dimension finding，spec 漏 brief 覆盖。brief_anchor REQUIRED
  - COVERAGE-DRIFT: A-dimension finding，spec 加 brief 没要 / 实现 out-of-scope。brief_anchor REQUIRED
  - ALT-DECISION: B-dimension finding，spec 有具体更好 alt。better_alternative REQUIRED
- 加一条「enum is closed; new categories not allowed」明示不允许 codex 扩展

1.7 改 `<output_format>` 段（line 149-172）JSON schema：
- 加 `brief_anchor` 字段 `"<brief :line ref + verbatim quote ...; REQUIRED for COVERAGE-* categories, optional for ALT-DECISION>"`
- 加 `better_alternative` 子对象 `{current_approach, proposed_alternative, quantified_tradeoff}` 或 null
- enum 更新：`"category": "COVERAGE-GAP" | "COVERAGE-DRIFT" | "ALT-DECISION"`
- 加字段一致性规则：COVERAGE-* MUST 非空 brief_anchor（否则降 NICE-TO-HAVE）；ALT-DECISION MUST 非空 better_alternative 全 3 子字段（否则不报）；ALT-DECISION 的 brief_anchor 可 null；COVERAGE-* 的 better_alternative 必须 null

1.8 同步 Output Validation 段（line 175-189）：enum 校验改新 3 值；新增「issue.category=COVERAGE-* → issue.brief_anchor non-null（否则 normalize 为 NICE-TO-HAVE）」+「issue.category=ALT-DECISION → issue.better_alternative non-null 含 3 子字段（否则 issue 整条丢弃 + 警告）」+「例外：fallback stub `id=codex-output-unparseable` 跳过两条降级规则（severity 保持 IMPORTANT、issue 不丢弃），因这是 review 系统故障预设 stub 不是真实 codex finding」

1.9 同步 Malformed JSON Fallback stub verdict（line 191-213）改完整 stub 与新 schema 一致 — 不只改 category，还要明确补 `brief_anchor` 和 `better_alternative` 两个新字段，避免与 Task 1.7 schema 矛盾：

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

字段说明：fallback stub 的 `brief_anchor` 是 review-system fault 特殊文字标记（不指向真实 brief line），属预设的 schema 例外白名单 — Task 1.8 Output Validation 规则「COVERAGE-* 缺 brief_anchor 时降 NICE-TO-HAVE」**不适用**于此 stub（fallback severity = IMPORTANT 保持，confidence = 10）；`better_alternative` 因 category 非 ALT-DECISION 按 schema 强制 null。Task 1.8 Validation 需明示这一例外（fallback stub id = `codex-output-unparseable` 时跳过降级规则）。

**Behavior Contract:**

- 输入：brief_path / spec_path / code_refs / project_type / main_repo_path（不变）
- 输出：`<work_dir>/.ohaze/spec-review-verdict.json` 顶层 schema 不变（verdict / summary / issues 数组）
- issue 内部 schema：必填字段 +2 新字段（brief_anchor / better_alternative）+ category enum 缩为 3 值
- caller-callee 接口：`ship.md` Phase 1.6 verdict routing 逻辑不变（PASS / NEEDS-CLARIFICATION / fix-in-spec / ask-haze / max-2 loop）

**Acceptance (grep / structural):**

- `! grep -E '^B\) AMBIGUITY' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` （B 段已删）
- `! grep -E '^C\) MISSING' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` （C 段已删）
- `! grep -E '^D\) CONFLICTS' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` （D 段已删）
- `grep -q 'FUNCTIONAL COVERAGE' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` （A 段命名）
- `grep -q 'IMPLEMENTATION QUALITY' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` （B 段命名）
- `grep -q '<scope_boundary>' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` （新增段）
- `grep -q 'missing_context_gating' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` （cross-ref 已存在通道）
- `grep -q 'cross-source review' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` （cross-ref Phase 5）
- `grep -q 'COVERAGE-GAP' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` （新 enum 值 1）
- `grep -q 'COVERAGE-DRIFT' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` （新 enum 值 2）
- `grep -q 'ALT-DECISION' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` （新 enum 值 3 保留）
- `! (grep -E '\b(AMBIGUITY|MISSING|CONFLICT)\b|(^|[^-])\bDRIFT\b' plugins/ohaze/skills/spec-to-codex-review/SKILL.md | grep -v -E '(越审越深|missing_context_gating|conflicts with existing)' | grep -q .)` （旧 enum 4 值全删；用 `grep -E` 保留行上下文不裁词，`(^|[^-])\bDRIFT\b` 用前导非 `-` 字符排除 `COVERAGE-DRIFT` 复合词；`-v` 过滤允许中文叙述 / scope_boundary 段内 implementer 视角英文描述；末段 `grep -q .` 测过滤后有无残留行 — 无残留 → grep -q . exit 1 → 外层 `!` 反转 = PASS（注意不能用 `head -1`，因 `head` 即便无输入也 exit 0 → `!` 反转始终 fail）；`<scope_boundary>` 段叙述用小写 "ambiguity / missing / conflicts" 避免大小写敏感匹配）
- `grep -q 'brief_anchor' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` （新字段 1）
- `grep -q 'better_alternative' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` （新字段 2）
- `grep -q 'current_approach' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` （better_alternative 子字段 1）
- `grep -q 'proposed_alternative' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` （子字段 2）
- `grep -q 'quantified_tradeoff' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` （子字段 3）
- `grep -q 'EXACTLY TWO axes' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` （`<task>` 段新引导词）
- `grep -q 'Walk through these 2 dimensions' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` （`<review_dimensions>` 段新开头）
- `! grep -q 'Walk through these 5 dimensions' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` （旧 5 维度文案已删）

### Task 2: 文档落档（manifest + CHANGELOG + ROADMAP）

**Files:**
- Modify: `plugins/ohaze/.claude-plugin/plugin.json`（manifest 版本号 bump）
- Modify: `CHANGELOG.md`
- Modify: `ROADMAP.md`

**Changes:**

2.1 `plugins/ohaze/.claude-plugin/plugin.json` 的 `version` 字段从 `"2.1.1"` bump 到 `"2.1.2"`（PATCH，因属 bug fix 类元问题修复，无 API breaking、无新 user-facing 功能）

2.2 `CHANGELOG.md` `[Unreleased]` 块的 `### Fixed`（如无则新建）追加条目：

```markdown
- **spec audit 「越审越深」元问题修复 / spec-audit-scope-reframe**：缩 spec-to-codex-review SKILL audit prompt 任务范围 — 删 B AMBIGUITY + C MISSING + D CONFLICTS 三个 dimension 段（这三个维度都是 implementer 实施阶段越权前置，天然无底洞），保留 A 改名 Functional Coverage + 原 E 改名 Implementation Quality 上提为 B 两个 bounded 维度。配机械锚点：A finding 必填 brief_anchor（cite brief checklist/scenario/out-of-scope line，cite 不出降 NICE-TO-HAVE 不阻塞），B finding 必填 better_alternative 子对象（current_approach + proposed_alternative + quantified_tradeoff，缺一不报）。Category enum 缩为 {COVERAGE-GAP, COVERAGE-DRIFT, ALT-DECISION} 3 值，旧 5 值 AMBIGUITY/MISSING/CONFLICT/DRIFT/ALT-DECISION 中前 4 个全删。新增 `<scope_boundary>` 段明示 implementer 视角问题走现有 `<missing_context_gating>` + Phase 5 cross-source review，audit 阶段不抓。回测：codex-dispatch-reliability ship 9 个 finding 100% 属 B/C/D 维度 → 修后假想 iter 1 PASS。
```

2.3 `ROADMAP.md` `## Backlog` 段移除「spec audit「越审越深」元问题（高优）」整条目（含描述 / 候选方案 / 数据点子项）。如条目编号有「4.」前缀，把后续条目编号顺移（如原 5. → 4.）保持顺序连续。

**Behavior Contract:**

- manifest 版本号字段、CHANGELOG `[Unreleased]` 条目、ROADMAP backlog 三处同步
- 全局四件套契约（CLAUDE.md）：本 ship 属「已完成未发版」→ 落 CHANGELOG `[Unreleased]`；Backlog 移除属朝未来视图清理；manifest 版本号 bump 备 finishing 阶段统一打 tag

**Acceptance:**

- `grep -q '"version": "2.1.2"' plugins/ohaze/.claude-plugin/plugin.json` （manifest 已 bump）
- `! grep -q '"version": "2.1.1"' plugins/ohaze/.claude-plugin/plugin.json` （旧版本号已替换）
- `grep -q 'spec-audit-scope-reframe' CHANGELOG.md` （Fixed 条目已加 — slug 锚点）
- `grep -q '越审越深' CHANGELOG.md` （Fixed 条目中文描述）
- `! grep -E 'spec audit ["「]越审越深["」]|收敛阈值|每次 iter 都找到新维度 issue' ROADMAP.md` （Backlog 条目已删；3 个 alt regex 任一 match 即报错，对应当前 ROADMAP.md:21 实际行内三处独立锚点：`spec audit "越审越深"` 字面 / 「没有收敛阈值」/「codex 每次 iter 都找到新维度 issue」。仅校 ROADMAP.md 不会与 CHANGELOG 本 ship 加的 Fixed 条目「越审越深」描述冲突）

### Task 3: Dogfood 端到端 grep 冒烟验证

**Files:**
- 无（read-only verification）

**Behavior Contract:**

- 跑全 Task 1 + Task 2 acceptance grep 命令一遍，全部 PASS
- 跑额外 sanity grep：旧 5 维度文案、旧 enum 残留、旧 verdict 路由是否仍能兼容
- Final report 列出 touched files + 关键 grep 摘要

**Acceptance:**

- Task 1 全部 acceptance grep PASS
- Task 2 全部 acceptance grep PASS
- 额外 sanity：`grep -c '^### ' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` 数值与修前一致或减少（SKILL 结构未被破坏，只缩 prompt 内容）
- 额外 sanity：`grep -q 'Skill(ohaze:spec-to-codex-review)' plugins/ohaze/commands/ship.md` （ship.md 调用接口未变）

## Out of Scope (与 brief 一致严格执行)

- 不加 brief judge / cross-source firewall 前置（会引入新维度 = 本 ship 自己掉进越审越深 trap 的元元元 trap）
- 不调闸门超参（max iter / confidence gate / NICE-TO-HAVE 阈值都不动）
- 不改 codex-executor / finishing / plan-to-codex-prompt / brainstorming / using-git-worktrees
- 不改 ship.md / ship-review.md / ship-finish.md（verdict routing 逻辑保持，PASS/NEEDS-CLARIFICATION/fix-in-spec/ask-haze/max-2 loop 不变）
- 不引入 plan-judge / spec audit retry refine prompt / self-reflection layer 等新审查 primitive
- 不重写 SKILL.md「Invocation Contract」/「Codex Invocation Contract」框架；只改 prompt 文本 + enum + 新增 2 字段 + 同步 Validation/Fallback

## Risks

- **R1 codex 不严格遵循新 prompt**：可能仍以新 category 报但 finding 内容是旧 B/C/D 类。Mitigation: `<scope_boundary>` 段措辞够强 + 强制写「DO NOT report them here even if you notice them」+ dogfood 验证。若 dogfood 仍出现 B/C/D 类 finding，下次 ship 再加 schema 校验脚本机械拒绝。
- **R2 dogfood 自指风险**：本 ship 自己跑 Phase 1.6 时还是用未修的旧 5 维度 SKILL → 仍可能撞 B/C/D 维度 finding。Mitigation: brief 极小、spec 极小、改动 100% surgical（只动 1 个 SKILL 文件 + 3 个落档文件），scope drift 空间小。若撞了，主线程按 brief Out of Scope 严格 fix-in-spec 不让 scope drift。如果 routing 提示 ask-haze 而问题确实属 B/C/D 类（无关 audit 任务范围 reframe 本身）→ 主线程降级当作 fix-in-spec 不实际改 spec、直接 ack 跳过。
- **R3 A 维度 brief_anchor 字段 codex 蒙混填假 line**：codex 可能为强报 finding 而 cite 不存在的 brief line。Mitigation: dogfood 验证 + 后续 ship 候选加 schema 校验「brief_anchor 字符串需在 brief 文件中找到对应内容」机械校验；本 ship 不做（极简）。
- **R4 旧 enum grep 假阳性**：旧 5 值字符串 AMBIGUITY/MISSING/CONFLICT 可能作为英语单词出现在 `<scope_boundary>` 段叙述 implementer 视角问题时 → grep 误报「未删干净」。Mitigation: acceptance 校验已写过滤逻辑（允许 COVERAGE-DRIFT 复合词 / 中文叙述 / scope_boundary 段内 implementer 视角问题英文描述）；如仍误报，主线程手动确认上下文判定。

## Verification (dogfood expectations)

- **本 ship Phase 1.6 spec audit**（用旧 5 维度 SKILL 跑本 spec）：期望 iter 1 或 iter 2 PASS。若 codex 报 B/C/D 维度 finding 但实质 OK → 按 brief Out of Scope 严格 fix-in-spec（不实质改 spec、ack 跳过；或写一行注释「按本 ship 设计本应在新 SKILL 下不报，临时旧 SKILL 兼容跳过」）。
- **本 ship Phase 5 cross-source review**：期望 PASS（无 scope drift，因 brief↔spec 100% 1:1 对应 Task 1/2/3、Out of Scope 严格守，无 over-implementation）。
- **修法生效后回测（手动 / 文档化即可，不机械跑）**：取上 ship `docs/ohaze/specs/2026-06-13-codex-dispatch-reliability-design.md` 跑同样 audit，预期 9 个 finding 全部对应新 enum 均无可触发，iter 1 PASS。
