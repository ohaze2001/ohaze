# ohaze Roadmap

> 进度记录 (Forward-Looking). 历史已发布看 CHANGELOG.md.
> Agent 行为指导看 CLAUDE.md. 项目自描述看 README.md.

## 当前主线
v2.2.2 PATCH 累积中（spec audit single-pass + debug gate i18n + 4 条 backlog hygiene 收口）。

## Backlog
- **`/ohaze:auto-ship` 命令（流程档位：中 — 小功能轻流程）**：介于 ship 和 debug 之间，跳过 BDD brainstorm + spec audit 的重 phase，brief→plan→execute→review 一条线；fork `superpowers:test-driven-development` 红绿节奏进自持版作为"必须有失败过的测试"边界。等 `/ohaze:debug` 跑通后边界更清楚再开
- **`/ohaze:loop` 命令（流程档位：零 — goal 驱动全自动无审）**：fork `superpowers:subagent-driven-development` 两阶段自动 review（spec→quality）+ `superpowers:dispatching-parallel-agents` 并行调度进自持版；prompt 驱动而非文档驱动，终态自动合并；最激进档位，等前两个有 dogfood 经验做安全网后再开
- 低：碰到 superpowers / claude-plugins-official 新 release 时人工扫一眼**新概念 / 新 skill 类型**（不 diff 既有 SKILL 文本），评估是否反向揭示 ohaze 还没意识到的需求。触发线索 = 看到上游 release 公告。背景：2026-06 评估 v5.1→v6.0.3，三个 fork 净有效 drift = 1 个 typo，结论 ohaze 已是「借骨架的独立 plugin」，跟 patch 无价值，只跟范式
- 如果观察到 plan-drift rate 超过可接受阈值，再加 plan Codex/Claude dry-run audit；当前 v2.1 先依赖 spec audit + implementation review 双闸。
- spec-to-codex-review schema 校验脚本兜底：机械验「COVERAGE-* finding 的 `brief_anchor` 字符串在 brief 文件中能 grep 到对应内容」+「ALT-DECISION finding 的 `better_alternative` 三子字段全非空」。本 ship (v2.1.2 spec-audit-scope-reframe) Risk R3 提出，作为后续 ship 候选。优先级 = 中（spec-audit-single-pass 落地后 dogfood 3 次再评估必要性）

## Bug
- (无)

## 长期目标
- v2.x 稳定后，重新设计「事件外露、消费方自取」式 vault 接口（非 hook 耦合），让外部观察方按需消费 ohaze ship 事件而不耦合 ohaze 自身

## In-flight
- (无)

## Cancelled / Frozen
- 审查强度分级（按改动规模调深度）—— v2 YAGNI
- 引入其他 superpowers skill 拓展流程 —— 违「减少依赖」原则
- vault 重连接口预留 —— 先剥干净再说
- Phase 1.5 spec quality self-check —— 同源 LLM 盲点（spec-audit-single-pass 决策中同款思路被否，源头质量靠 brainstorm 阶段 haze 审 brief 保证）
