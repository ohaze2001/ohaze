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
- 持久化 Codex 输出（`codex-executor` Phase 4 `tee` `--json` 到 `<worktree>/.ohaze/codex-output.jsonl`），使 doc-finish 真相源跨 session 可用，消除 F9 的 fallback 降级
- 如果观察到 plan-drift rate 超过可接受阈值，再加 plan Codex/Claude dry-run audit；当前 v2.1 先依赖 spec audit + implementation review 双闸。
- **（高优先 · 多次观察到的元问题）spec audit "越审越深" — codex 每次 iter 都找到新维度 issue，没有收敛阈值**：haze 实战观察（已 2026-06-11 dream-review-stability ship 命中第 2 次）：iter1 fix 5 issue 后 iter2 找到 5 个全新 issue（不是同问题残留），iter2 修完跑 iter3 大概率仍找到新维度 issue（implementer perspective 永远能挖更细）。**根因**：spec audit prompt 让 codex 从 implementer 视角找 "WILL block at execution time" 的问题，但没定 "spec 够好就停" 的阈值——每次都从干净视角审就永远能挖出"更深 1 层"的问题。**症状**：5 dimension review 在第 N iter 仍能列 issue，spec 不收敛、max=2 loop 触发率高、haze 频繁被弹三选项（accept/revise/drop）。**实施候选**：① spec audit prompt 加 "已 iter ≥ 2 时只报 iter1 同维度残留，不开新维度" ② 加 iteration-aware confidence gate（iter2 conf ≥ 9 才报，iter3 conf = 10 才报）③ 改 max=2 → max=3，但默认 PASS 含 NICE-TO-HAVE 条目（不阻塞 ship）④ codex prompt 加 "spec 已经达到 implementer 能开工的最小集即可，不追求穷尽" 哲学声明。需要先收集 3-5 ship 的 iter pattern 数据再定方案。**优先级 = 高**：直接影响 /ohaze:ship 用户体验和 spec phase 效率

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
