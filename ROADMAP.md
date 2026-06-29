# ohaze Roadmap

> 进度记录 (Forward-Looking). 历史已发布看 CHANGELOG.md.
> Agent 行为指导看 CLAUDE.md. 项目自描述看 README.md.

## 当前主线
v2.2.2 PATCH 累积中（debug gate i18n + 4 条 backlog hygiene 收口）。

## Backlog
- **`/ohaze:auto-ship` 命令（流程档位：中 — 小功能轻流程）**：介于 ship 和 debug 之间，跳过 BDD brainstorm + spec audit 的重 phase，brief→plan→execute→review 一条线；fork `superpowers:test-driven-development` 红绿节奏进自持版作为"必须有失败过的测试"边界。等 `/ohaze:debug` 跑通后边界更清楚再开
- **`/ohaze:loop` 命令（流程档位：零 — goal 驱动全自动无审）**：fork `superpowers:subagent-driven-development` 两阶段自动 review（spec→quality）+ `superpowers:dispatching-parallel-agents` 并行调度进自持版；prompt 驱动而非文档驱动，终态自动合并；最激进档位，等前两个有 dogfood 经验做安全网后再开
- 定期 diff superpowers v5.1.0 上游 brainstorming / using-git-worktrees SKILL.md（基线漂移监控）
- 定期 diff superpowers v5.1.0 上游 systematic-debugging/SKILL.md（debug fork 基线漂移监控）
- 如果观察到 plan-drift rate 超过可接受阈值，再加 plan Codex/Claude dry-run audit；当前 v2.1 先依赖 spec audit + implementation review 双闸。
- spec-to-codex-review schema 校验脚本兜底：机械验「COVERAGE-* finding 的 `brief_anchor` 字符串在 brief 文件中能 grep 到对应内容」+「ALT-DECISION finding 的 `better_alternative` 三子字段全非空」。本 ship (v2.1.2 spec-audit-scope-reframe) Risk R3 提出，作为后续 ship 候选。优先级 = 中（dogfood 跑 3-5 ship 后再评估必要性）
- **Phase 1.5 spec quality self-check (跨 ship 工艺改进)**：v2.2.0 debug-command dogfood 暴露 Phase 1.5 写 spec 容易漏 brief 真实点 (本次漏了 6 个: cross-command reframe 不完整 / scope lock 没写物理 / worktree 顺序错 / regression test 无 pre-fix 失败 / touched-files 用 commit 后 diff / KD8 只埋 2 处)。所有 6 个都被 audit 抓到，但本应 Phase 1.5 自己写好。候选: spec writing 阶段加 "对每条 brief checkbox 写一条 spec mapping" 的 self-check checklist，或者在 spec 模板里嵌入 brief↔spec 对照表。优先级 = 中 (dogfood 3-5 ship 后看是否高频复现再评估具体落地)

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
