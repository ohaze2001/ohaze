# ohaze Roadmap

> 进度记录 (Forward-Looking). 历史已发布看 CHANGELOG.md.
> Agent 行为指导看 CLAUDE.md. 项目自描述看 README.md.

## 当前主线
v2.0.0 重构：零运行时外部 skill 依赖 + vault 流程层剥离 + 修核心坑（nohup/ScheduleWakeup 幽灵唤醒、cwd 悬空、resume sandbox）。

- [x] superpowers 全解耦（fork 子集 brainstorming + using-git-worktrees + writing-plans）
- [x] vault 剥离（删 hooks/adapter/VAULT-CONTEXT）
- [x] codex 后台换血（run_in_background 替 nohup；harness re-invoke 替 ScheduleWakeup；幂等状态门）
- [x] codex exec resume 去 `--sandbox`（codex 0.137 实测修复）
- [x] 流程序 brainstorm → worktree → spec（main 干净）
- [x] 显式项目路径参数（`--project`）
- [x] finishing 6 项菜单（第 6 项「修复对抗审查后收尾」conditional）+ doc-finish 内化 neat 路由
- [x] 异源审查强化（实跑 project_test_command + 卡住升级诊断）
- [x] 四件套文档对齐 + 修死链

## Backlog
- 集成验证 dogfood（v2 装机后端到端跑一个 throwaway ship 冒烟验证）
- 定期 diff superpowers v5.1.0 上游 brainstorming / using-git-worktrees SKILL.md（基线漂移监控）
- 持久化 Codex 输出（`codex-executor` Phase 4 `tee` `--json` 到 `<worktree>/.ohaze/codex-output.jsonl`），使 doc-finish 真相源跨 session 可用，消除 F9 的 fallback 降级

## Bug
- （v2.0.0 发版前清空；后续发现登记于此）

## 长期目标
- v2.x 稳定后，重新设计「事件外露、消费方自取」式 vault 接口（非 hook 耦合），让外部观察方按需消费 ohaze ship 事件而不耦合 ohaze 自身

## In-flight
- (无)

## Cancelled / Frozen
- 审查强度分级（按改动规模调深度）—— v2 YAGNI
- 引入其他 superpowers skill 拓展流程 —— 违「减少依赖」原则
- vault 重连接口预留 —— 先剥干净再说
