# ohaze Roadmap

> 进度记录 (Forward-Looking). 历史已发布看 CHANGELOG.md.
> Agent 行为指导看 CLAUDE.md. 项目自描述看 README.md.

## 当前主线
v2.2.0 流程档位扩展：debug 修复档位 + ship 反向 reframe + `ship_mode` 下游分流。

## Backlog
- **`/ohaze:auto-ship` 命令（流程档位：中 — 小功能轻流程）**：介于 ship 和 debug 之间，跳过 BDD brainstorm + spec audit 的重 phase，brief→plan→execute→review 一条线；fork `superpowers:test-driven-development` 红绿节奏进自持版作为"必须有失败过的测试"边界。等 `/ohaze:debug` 跑通后边界更清楚再开
- **`/ohaze:loop` 命令（流程档位：零 — goal 驱动全自动无审）**：fork `superpowers:subagent-driven-development` 两阶段自动 review（spec→quality）+ `superpowers:dispatching-parallel-agents` 并行调度进自持版；prompt 驱动而非文档驱动，终态自动合并；最激进档位，等前两个有 dogfood 经验做安全网后再开
- 定期 diff superpowers v5.1.0 上游 brainstorming / using-git-worktrees SKILL.md（基线漂移监控）
- 定期 diff superpowers v5.1.0 上游 systematic-debugging/SKILL.md（debug fork 基线漂移监控）
- 如果观察到 plan-drift rate 超过可接受阈值，再加 plan Codex/Claude dry-run audit；当前 v2.1 先依赖 spec audit + implementation review 双闸。
- spec-to-codex-review schema 校验脚本兜底：机械验「COVERAGE-* finding 的 `brief_anchor` 字符串在 brief 文件中能 grep 到对应内容」+「ALT-DECISION finding 的 `better_alternative` 三子字段全非空」。本 ship (v2.1.2 spec-audit-scope-reframe) Risk R3 提出，作为后续 ship 候选。优先级 = 中（dogfood 跑 3-5 ship 后再评估必要性）
- **CHANGELOG v2.1.2 段回测预言修正 (doc-drift 小补丁)**：v2.1.2 段写「回测：codex-dispatch-reliability ship 9 个 finding 100% 属 B/C/D 维度 → 修后假想 iter 1 PASS」过于乐观。v2.2.0 debug-command ship dogfood 实测 iter 1 4 finding + iter 2 2 finding 触发 max loop，但 6/6 finding 都在新两轴 bounded 维度内（无越权前置），说明 v2.1.2 的真实目标是「防越审越深」而非「iter 1 PASS」。把回测预言改成更窄目标，避免误读。下次 ship 顺便修
- **Phase 1.5 spec quality self-check (跨 ship 工艺改进)**：v2.2.0 debug-command dogfood 暴露 Phase 1.5 写 spec 容易漏 brief 真实点 (本次漏了 6 个: cross-command reframe 不完整 / scope lock 没写物理 / worktree 顺序错 / regression test 无 pre-fix 失败 / touched-files 用 commit 后 diff / KD8 只埋 2 处)。所有 6 个都被 audit 抓到，但本应 Phase 1.5 自己写好。候选: spec writing 阶段加 "对每条 brief checkbox 写一条 spec mapping" 的 self-check checklist，或者在 spec 模板里嵌入 brief↔spec 对照表。优先级 = 中 (dogfood 3-5 ship 后看是否高频复现再评估具体落地)
- **历史 v2.1.1 / v2.1.2 / v2.1.3 缺 tag 补打 (contract drift, hygiene)**：`git tag -l 'v2.*'` 显示只有 v2.0.0 / v2.1.0 / v2.2.0，三个 patch release 缺 annotated tag，违反全局 CLAUDE.md「发行产品 = 完整 SemVer + tag + CHANGELOG」契约。补打方式: 对每个 CHANGELOG 已有的 [2.1.x] 段找到对应 release commit，打 `git tag -a v2.1.x -m "..."` + `git push origin v2.1.x`。优先级 = 低 (纯 hygiene，不阻塞功能；可作为下次小 ship 顺便补)
- **（中优先 · 2026-06-17 同源）debug-to-codex-prompt 同款禁令**：同上 — `skills/debug-to-codex-prompt/SKILL.md` 加红线，debug fix 期间禁止 Codex 写 CHANGELOG（统一由 finishing/doc-finish 收口）
- **（中优先 · 2026-06-17 同源）codex-executor drift detection 扩展**：`skills/codex-executor/SKILL.md:279` 当前 drift 仅检测 CLAUDE.md/README.md/ROADMAP 描述失真，建议扩展规则：CLAUDE.md 任一 bullet > 150 chars 视为 drift 报 doc-finish；README 占位段 `{{...}}` 未填实视为 drift。这样过长内容 / 占位泄漏会被自动捕获进 doc-finish 修复

## Bug
- **（中优先 · 2026-06-16 vault fix/dream-test-state-leak debug dogfood 暴露）`/ohaze:debug` 模式产出全英文，与用户偏好语言冲突**——`ohaze:systematic-debugging` skill 跑出来的 investigation_report / scope_lock_files / fix_plan 章节标题全是英文（"Phase 1: Root Cause Investigation" / "Pattern Analysis" / "Hypothesis" / "Implementation" / "Root cause" / "The change" / "Anti-regression contract" / "Anti-regression note" / "Variant A/B"），即便用户全局 CLAUDE.md 指定「Always respond in chinese」也跟随英文模板输出。**根因**：skill SKILL.md 自身 prompt 模板用英文写章节骨架 + 强约束 schema 字段名（`investigation_report` / `scope_lock_files` / `fix_plan`）→ LLM 跟着模板字面格式输出英文。**约束**：terminal artifact 名（`investigation_report` / `scope_lock_files` / `fix_plan`）是机械字段，下游 `ohaze:debug-to-codex-prompt` 按名消费，**不能改成中文**。**修向 3 选 1**：① skill 模板内加 i18n 指令——`investigation_report` / `scope_lock_files` / `fix_plan` 三个 top-level artifact 名保留英文（机械字段），但其下的章节标题（Phase 1-4 / Root cause / The change / Anti-regression contract / Anti-regression note）跟随用户语言偏好用中文写；② 加 zh 别名映射表（"Phase 1: Root Cause Investigation" ↔ "Phase 1: 根因调研"）放进模板；③ 最低限度在 SKILL.md 头加 "skill 产出的人类可读章节（标题、解释段）应跟随会话语言偏好；机械 schema 字段名（artifact 名 / G1·G2·gate 名 / Variant A/B 等）保持英文"。**同类影响范围**：可能其他 ohaze skill（`ohaze:brainstorming` / `ohaze:writing-plans` / `ohaze:spec-to-codex-review` / `ohaze:codex-executor` / `ohaze:debug-to-codex-prompt` / `ohaze:finishing`）也有同样模板英文问题，本 bug 修时应一并 audit。**优先级中**：不阻塞功能、debug 修复结果照常落地，但中文用户读 debug 产出割裂、影响 dogfood 体验
- **（dogfood backlog 记账）** 本 bug 是 vault dream-test-state-leak debug 跑 `Skill(ohaze:systematic-debugging)` 时暴露；修后用 vault 下一次 debug 跑回归看产出是否中文化

## 长期目标
- v2.x 稳定后，重新设计「事件外露、消费方自取」式 vault 接口（非 hook 耦合），让外部观察方按需消费 ohaze ship 事件而不耦合 ohaze 自身

## In-flight
- (无)

## Cancelled / Frozen
- 审查强度分级（按改动规模调深度）—— v2 YAGNI
- 引入其他 superpowers skill 拓展流程 —— 违「减少依赖」原则
- vault 重连接口预留 —— 先剥干净再说
