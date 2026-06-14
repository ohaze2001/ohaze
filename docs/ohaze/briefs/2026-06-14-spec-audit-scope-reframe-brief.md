# spec-audit-scope-reframe — Feature Brief
> 给 haze 看。spec 在 docs/ohaze/specs/... 给 Codex 看,你不用看。

## 这是干嘛的
修 ROADMAP backlog 高优先元问题「spec audit 越审越深」的根因 — 不是加更多审查层（GAN discriminator / 自反思 / harness）治症状，而是把 audit 的任务范围本身收窄到「spec 是不是覆盖了 brief 的功能 + 这个实现方法是不是最好的」两件事，删掉 implementer 实施阶段才需要追的 B/C/D 三维度（措辞模糊 / 细节缺漏 / 与现有代码冲突），让 audit 在结构上不可能越审越深。

## 给谁用
- `/ohaze:ship` Phase 1.6 spec audit 流程的最终用户（haze 收 review verdict 看结果）
- Claude 主线程（按 verdict 路由 fix-in-spec / ask-haze）
- Codex auditor（按新 2 维度 prompt 产 finding，不再开 B/C/D 新维度）
- 下游 implementer（撞 B/C/D 问题不再卡审查阶段，走现有 `<missing_context_gating>` 反馈通道在实施阶段解决）

## 用户场景 (Scenarios)

### Scenario 1: 小修复 ship spec audit iter 1 直接 PASS
- Given haze 提了个外科手术式小修复 ship（如 README 错别字 / 文案 typo）
- When Claude 写完 spec 调 spec-to-codex-review，codex 按新 2 维度 prompt 跑
- Then 因 spec 完全覆盖 brief、无更优 alt → iter 1 verdict = PASS、issues = []，不再被旧 5 维度 prompt 莫名挑「这个变量名能更清楚」「文案错别字修法是否会破坏 git blame」这种 implementer 视角问题

### Scenario 2: spec 漏了 brief 一条 checklist → 触发 COVERAGE-GAP
- Given brief 写了「完成的样子」5 条 checklist，spec 漏掉第 3 条
- When codex 跑 audit
- Then 产 1 个 COVERAGE-GAP finding，evidence 引用 spec file:line、brief_anchor 引用 brief checklist 第 3 条 verbatim，severity = CRITICAL/IMPORTANT，routing = fix-in-spec
- And Claude 主线程读 verdict → 自动 edit spec 补回第 3 条覆盖 → 重跑 audit → PASS

### Scenario 3: spec 选了次优实现方法 → 触发 ALT-DECISION
- Given brief 要的功能 spec 用了方案 X，但客观存在方案 Y 在某个可量化维度（简洁 / 安全 / 成本 / UX）显著更好
- When codex 跑 audit
- Then 产 1 个 ALT-DECISION finding，better_alternative 子对象明确写「当前用 X，建议改 Y，量化对比是 …」，severity = IMPORTANT/NICE-TO-HAVE，routing = fix-in-spec（除非 X vs Y 是 brief 范围决策才 ask-haze）
- And 「我会用别的方法」但说不出具体 better alt + 量化对比 → codex 不报这条

### Scenario 4: implementer 实施时撞模糊措辞 → 走现有反馈通道（**不是** audit 阶段的事）
- Given audit PASS、ship 进 Codex 实现阶段、Codex 撞到 spec 某句措辞有 2 种解读
- When Codex 实施
- Then Codex 走现有 `plan-to-codex-prompt:85` `<missing_context_gating>`：标 ambiguity、跳过该 Task、final report 报 concerns，主线程或 Phase 5 cross-source review 处理
- And 这条不在 audit 阶段被发现也不要求 audit 提前发现 — 这是 audit 范围之外的设计决定

## "完成的样子" Checklist
- [ ] spec-to-codex-review SKILL audit prompt 改：删 B AMBIGUITY / C MISSING / D CONFLICTS 三个 dimension 段
- [ ] A 维度改名 "Functional Coverage" + 强制每个 finding cite brief 具体 line（机械锚点）
- [ ] E 维度改名 "Implementation Quality" + 强制带具体 better alternative + 可量化对比（无 alt 不报）
- [ ] category enum 缩为 3 值 {COVERAGE-GAP, COVERAGE-DRIFT, ALT-DECISION}，旧值 AMBIGUITY/MISSING/CONFLICT/DRIFT 全删
- [ ] SKILL 加 `<scope_boundary>` 段明示 implementer 实施阶段问题走 `<missing_context_gating>` + Phase 5 cross-source review，不在此 audit
- [ ] dogfood 验证：本 ship Phase 1.6 撞「ok」+ 上一个 ship 9 个 finding 100% 是 B/C/D 类（修后假想 iter 1 PASS）

## 不做什么 (Out of Scope)
- 不加 brief judge 前置 / cross-source firewall 前置（会引入新维度 = 本 ship 自己掉进越审越深 trap 的元元元 trap）
- 不调闸门超参（max iter / confidence gate / NICE-TO-HAVE 阈值都不动）
- 不改 codex-executor / finishing / plan-to-codex-prompt / brainstorming / using-git-worktrees
- 不改 ship.md / ship-review.md / ship-finish.md（verdict routing 逻辑保持，PASS/NEEDS-CLARIFICATION/fix-in-spec/ask-haze/max-2 loop 不变）
- 不引入 plan-judge / spec audit retry refine prompt / self-reflection layer 等新审查 primitive
- 不重写已发布的 v2.1.x spec-to-codex-review skill 接口（输入/输出 JSON schema 兼容，只动 prompt 内容 + enum 收紧 + 加 2 字段）

## Scope 决策
- **模式**: Hold Scope
- **理由**: 上一个 ship (codex-dispatch-reliability) 的死亡阴影还在 — 任何 Expansion 都增加本 ship 自己被自己旧 SKILL 审进越审越深 trap 的概率。Hold Scope 是反 trap 的最小集。

## Claude 替你决定的关键技术方向 (Phase 1.5 后回填,事后扫一眼)
- category enum 严格 3 值 {COVERAGE-GAP, COVERAGE-DRIFT, ALT-DECISION}：A 维度拆 GAP（spec 漏 brief）+ DRIFT（spec 加 brief 没要的）两类，E 维度独占 ALT-DECISION
- A 维度 brief_anchor 字段宽松模式：cite 不出 brief 具体 line → 降级 NICE-TO-HAVE 不阻塞 PASS，避免 codex 蒙混强报
- E 维度 better_alternative 严格模式：必填 `{current_approach, proposed_alternative, quantified_tradeoff}` 三子字段，缺一不报
- 不动 plan-to-codex-prompt `<missing_context_gating>` 段（implementer 反馈通道已存在）
- 不动 codex-executor Phase 5 cross-source review（scope drift 兜底 firewall 已存在，是 audit 之外的二道闸）
