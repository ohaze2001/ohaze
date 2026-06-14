# ohaze Roadmap

> 进度记录 (Forward-Looking). 历史已发布看 CHANGELOG.md.
> Agent 行为指导看 CLAUDE.md. 项目自描述看 README.md.

## 当前主线
v2.1.0 BDD/TDD restructure：haze 只 approve brief，Claude 自动写 spec，Codex 反审 spec，plan 默认推进，review finding 转产品语言。

- [x] Phase 1 BDD-flavored brainstorming：7 forcing hints + feature brief + 4-mode scope reflection
- [x] Phase 1.5 Claude auto-spec：mandatory code-reading + 5 类边界单点问 + brief 技术方向回填
- [x] Phase 1.6 `spec-to-codex-review`：Codex 异源审 spec，max-2 loop
- [x] Phase 3.5 plan summary + default-go：不再让 haze 读完整 plan 才能继续
- [x] Phase 6 `<investigate_first>`：retry 前先根因诊断
- [x] Phase 7 conditional Security Review + ADVERSARIAL 产品语言展示
- [x] 路径迁移到 `docs/ohaze/{briefs,specs,plans}`

## Backlog
- 定期 diff superpowers v5.1.0 上游 brainstorming / using-git-worktrees SKILL.md（基线漂移监控）
- 如果观察到 plan-drift rate 超过可接受阈值，再加 plan Codex/Claude dry-run audit；当前 v2.1 先依赖 spec audit + implementation review 双闸。
- spec-to-codex-review schema 校验脚本兜底：机械验「COVERAGE-* finding 的 `brief_anchor` 字符串在 brief 文件中能 grep 到对应内容」+「ALT-DECISION finding 的 `better_alternative` 三子字段全非空」。本 ship (v2.1.2 spec-audit-scope-reframe) Risk R3 提出，作为后续 ship 候选。优先级 = 中（dogfood 跑 3-5 ship 后再评估必要性）

## Bug
## 长期目标
- v2.x 稳定后，重新设计「事件外露、消费方自取」式 vault 接口（非 hook 耦合），让外部观察方按需消费 ohaze ship 事件而不耦合 ohaze 自身

## In-flight
- (无)

## Cancelled / Frozen
- 审查强度分级（按改动规模调深度）—— v2 YAGNI
- 引入其他 superpowers skill 拓展流程 —— 违「减少依赖」原则
- vault 重连接口预留 —— 先剥干净再说
