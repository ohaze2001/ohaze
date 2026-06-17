# doc-finish 收口契约加固 — Feature Brief

> 给 haze 看。spec 在 docs/ohaze/specs/... 给 Codex 看，你不用看。

## 这是干嘛的

让 ohaze 的 doc-finish 链路 (收口阶段写四件套) 强制遵守全局四件套契约 (`~/CLAUDE.md` § 单条目体量上限 + 「CHANGELOG 朝过去 / ROADMAP 朝未来」铁律)，防止下游项目 (vault / 其他用 ohaze 的项目) 在 ship 过程中产出膨胀文档 / 僵尸条目 / 旁路绕过 preview。

## 给谁用

- **直接消费者**：所有用 `/ohaze:ship` 或 `/ohaze:debug` 的项目 (ohaze 自己 / vault / 未来加入的项目)
- **间接受益方**：四件套的人类读者 (haze 自己以及 future contributor) — CHANGELOG 短可读、ROADMAP 不留勾痕、改动对得起契约
- **直接触发**：ohaze ship 流程 Phase 7 finishing 阶段 (doc-finish step) + Phase 4 codex dispatch (plan-to-codex prompt 双闸)

## 用户场景 (Scenarios)

### Scenario 1: 短 CHANGELOG entry (happy path)
- **Given** 一次 ship 跑完，Codex 实施 + review pass，进入 doc-finish 步骤
- **When** doc-finish 写 CHANGELOG `[Unreleased]` 段
- **Then** 新 bullet 一行 ≤ 200 字符 + 末尾 commit hash + 可选 spec/plan path，视角是「消费者看到的变化」(例：「修 finishing/SKILL.md doc-finish 类 1 加 CHANGELOG 篇幅+视角约束 (引用 versioning.md) — 防 entry 膨胀」)，不内嵌 sub-ship 编号 / reviewer finding / fixture / hash 列表 / 反思段

### Scenario 2: ROADMAP 不留勾痕
- **Given** ship 启动时 `linked_todo` 指向 `## 当前主线` 一条 `- [ ] xxx`
- **When** doc-finish 处理 ROADMAP
- **Then** CHANGELOG 已写入这条 todo 的归宿后，doc-finish 把 `## 当前主线` 里那一整行删除 (不留 `- [x]`，不留 `~~划掉~~`)；ROADMAP 段落如果空了就只保留主题句

### Scenario 3: plan 错列四件套，Codex 跳过
- **Given** writing-plans 写出来的 plan Task 4 误把 `Modify: CHANGELOG.md` 列进 Files
- **When** Codex 执行该 plan
- **Then** Codex 跳过 CHANGELOG 改动，在最终 `<output_report>` 的 "Tasks with concerns" 标注「plan Task 4 越权列了 CHANGELOG.md，已跳过留 doc-finish 处理」，CHANGELOG 写入留给 doc-finish 收口

### Scenario 4: 边界 — linked_todo 找不到 (cross-version)
- **Given** `linked_todo` 非 null，但精确文本在 `## 当前主线` 找不到 (老版本 handoff / 用户手改了 ROADMAP)
- **When** doc-finish 处理 ROADMAP
- **Then** emit 一条 WARNING + 跳过删行 (现有行为，保留不动)，其他 doc-finish step 继续

### Scenario 5: ohaze 自身先对齐 (hygiene)
- **Given** 本次 ship 同时改了 ohaze CLAUDE.md / ROADMAP 自己
- **When** ship 完成
- **Then** ohaze CLAUDE.md `## Agent 行为约定` 段新增一行说明 doc-finish 唯一收口契约；ohaze ROADMAP `## 当前主线` v2.2.0 段历史 3 行 `- [x]` 勾痕清掉；ROADMAP `## Backlog` 删问题 10/11/12 三条 (这三条已被 CHANGELOG bullet 替代)

## "完成的样子" Checklist

- [ ] **能** doc-finish Class 1 写 CHANGELOG 时遵守 ≤ 200 字符 + 消费者视角 + 禁内嵌清单 (引用 `~/Project/hazeflow/_shared/versioning.md ## CHANGELOG 写作风格` 而非本地复述)
- [ ] **能** doc-finish Class 1 把 `linked_todo` 行从 ROADMAP `## 当前主线` 整行删除 (默认行为，非选项)
- [ ] **能** writing-plans 在 Task Structure 段明示「四件套禁列 Task 交付物」红线
- [ ] **能** plan-to-codex-prompt 在 `<grounding_rules>` 和 `<action_safety>` 双闸禁 Codex 写四件套 (即便 plan 错列也跳过)
- [ ] **能** ohaze 自己 CLAUDE.md / ROADMAP 立即对齐新契约 (CLAUDE.md 加一行明示契约 / ROADMAP 清勾痕 / Backlog 删三条)
- [ ] **能** v2.2.0 → v2.2.1 同步 manifest (`plugins/ohaze/.claude-plugin/plugin.json`) + CHANGELOG `## [Unreleased]` → `## [2.2.1]` 段
- [ ] **不能** 触碰非本主题的 skill (debug-to-codex-prompt / codex-executor / brainstorming / ship-review / systematic-debugging) — out of scope
- [ ] **不能** 复述 versioning.md 内容到 finishing/SKILL.md (双份维护漂移风险) — 只引用
- [ ] **失败时能** doc-finish 任何 step 失败立即停 chain (不变，现有 chain execution contract)

## 不做什么 (Out of Scope)

- debug-to-codex-prompt 同款禁令 (问题 13, 单独 ship)
- codex-executor drift detection 扩展 (问题 14, 单独 ship)
- ohaze:debug 英文产出 bug (单独 ship)
- 历史 v2.1.1/v2.1.2/v2.1.3 缺 tag 补打 (单独 ship)
- Phase 1.5 spec quality self-check (跨 ship 工艺改进, 单独 ship)
- 本 ship 自己的 finishing **不强制** dog-food 新规则 (时序悖论：worktree SKILL.md 未 merge 时 main thread invoke 还是旧版)，haze 手动监督 + 模拟新规则；真 dog-food 在下次自然 ship 自动发生
- 历史 CHANGELOG entry (v2.1.1 / v2.1.2 等) 重写到 ≤ 200 字符 — 不动已发版段，新约束只管未来 entry

## Scope 决策

- **模式**: **Hold Scope (保持 6 项原子单元)**
- **理由**: 6 项需求里前 3 项 (doc-finish 加约束 / writing-plans 红线 / plan-to-codex 双闸) 是契约本体加固；后 3 项 (ohaze CLAUDE 加一行 / ROADMAP 清勾痕 / Backlog 删三条) 是 ohaze 自身对齐 — 如果只做前 3 项，ohaze 自己变成「制定规则但自己不遵守」的反例，失去 dogfood 起点；如果只做后 3 项，新契约没法落地。6 项是一个原子单元，拆开就破。**不算 Expansion** (没扩到无关功能，例如没顺手修 codex-executor 或 debug-to-codex)；**不算 Reduction** (砍任何一项都破整体)。

## Claude 替你决定的关键技术方向 (Phase 1.5 后回填，事后扫一眼)

- **finishing Class 1 CHANGELOG 约束 = 引用 versioning.md 而非本地复述**：避免 finishing/SKILL.md 和 versioning.md 双份维护漂移；versioning.md 是真相源，本 skill 指向 + 列 3-4 条最 actionable 硬约束
- **finishing Class 1 tick → prune = 默认行为不留 option**：vault dogfood 已证「留 `- [x]` 默认 = 累积僵尸」，prune 改成强制默认；如未来发现 edge case 再补 escape hatch
- **writing-plans 红线落点 = Task Structure 段顶 callout + No Placeholders 段补充**：双重提醒（Task 写作时第一眼看到 + 收尾 self-review 时再被扫到），减少漏写概率
- **plan-to-codex-prompt 双闸 = `<grounding_rules>` 软提示 + `<action_safety>` 硬禁令**：grounding_rules 告诉 Codex 怎么 graceful 处理（跳过 + 标注），action_safety 是绝对禁令（never modify）；双闸冗余有意为之
- **ohaze 自身对齐顺手做 (不拆 Ship 2)**：理由是「制定规则的人自己违反规则」即时反例风险大，hygiene 不延迟
