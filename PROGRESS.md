# ohaze 进度

## 2026-05-07
- 完成：V1 设计锁定（5 决策点全部按推荐组合确定）
  - Codex 端到端执行
  - 审查自动触发
  - 审查重试上限 3 次
  - 默认 `--background`
  - 整体 review（非逐 Task）
- 完成：项目骨架搭建（CLAUDE.md / PROGRESS.md / 目录结构）
- 完成：5 个核心文件全部到位（plugin.json / 2 commands / 2 skills）
- 修正：发现 Claude Code 不识别 `~/.claude/plugins/<name>/` 直接路径，必须经 marketplace
  → 重构为 marketplace+plugin 布局：仓库根放 `.claude-plugin/marketplace.json`，
     plugin 实体在 `plugins/ohaze/`
- 待处理：本地 marketplace 安装测试 → 真实项目跑通 `/ohaze:ship` → 推 GitHub

## 2026-05-08

### V1 沙箱实测 — 端到端跑通

测试任务：`/ohaze:ship 加一个 subtract 函数到 src/math.js，并配上测试`
（沙箱：`~/Project/ohaze-sandbox/`，session log：`docs/session-log-2026-05-08.md`）

**结果**：
- 流程跑通：brainstorm → writing-plans → codex 派发 → result → 自动续跑 → review → finishing
- 审查 VERDICT: PASS，0 retries
- 产物质量：spec / plan / code / tests 全部高质量，TDD 节奏到位
- Codex 总耗时 1m45s

### 发现的 4 个 V1 bug + 已落地修复

**Bug 1：writing-plans 自带"两选项"菜单截断流程**（commit `99c1ee0`）
- 现象：plan 写完后 superpowers 让用户选 1/2，绕过 ohaze Phase 4
- 修法：ship.md Phase 3 加 CRITICAL override，明确禁止显示该菜单

**Bug 2：codex-rescue subagent 缺 Bash 权限静默失败**（commit `2a12806`）
- 现象：subagent 没有 interactive permission UI，settings.json 里没 `Bash(node:*)` 时直接派不出去
- 修法：codex-executor skill 加 Path B fallback，subagent 失败自动回落到主线程直接调 codex-companion.mjs

**Bug 3：Codex 沙箱拦 `.git/` 写入**（V1.1）
- 现象：Codex `workspace-write` 模式特意禁止 `.git/` 写入（产品安全设计，非 bug）
- 现象延伸：Codex 写完代码+测试后，`git add` 报 `Operation not permitted`，commit step 全部失败
- 修法：
  - plan-to-codex-prompt 加 `<commit_handling>` 块，明示告知 Codex 不要 commit
  - codex-executor 加 Phase 5.0：review 之前由主线程统一 commit
  - `<output_report>` 调整：Codex 报告"intended commit messages"列表

**Bug 4：worktree 阶段被 brainstorming 跳过**（V1.1）
- 现象：brainstorming 的 terminal state 是直接调 writing-plans，绕过 using-git-worktrees
- 后果：实测中 Codex 直接在 main 上写代码，没建独立 feature branch
- 修法：ship.md Phase 1 加 CRITICAL override，明确禁止 brainstorming 直跳；Phase 2 标记 mandatory

### V1.1 状态
- 4 个 bug 全部修完，待新 session 重测
- 推 GitHub 暂缓，等 V1.1 重测通过

### V1.5 同期落地（一起测）

讨论完 worktree 用途和 finishing 缺"继续修改"选项后，把以下功能并入 V1.5：

**新增 `/ohaze:status` 命令**（`commands/status.md`）
- 跨 worktree 工作流总览：每个 worktree 的分支、git 状态、ohaze handoff、Codex job 状态、stale 检测
- 远端 PR 状态（用 gh 拉，可选）
- 只读，不会自动清理

**finishing 菜单加第 5 个选项 "继续修改"**（`commands/ship-review.md`）
- 4 个原选项保留（push / PR / keep / discard），第 5 个进 modify 子流程
- 子流程 3 选 1：a) Codex `--resume` 续跑，b) Claude 主线程直接 Edit，c) 退出让用户自己改后回 `/ohaze:ship-finish`
- 改完默认建议再跑一次 review，循环回 finishing 菜单

**新增 `/ohaze:ship-finish` 命令**（`commands/ship-finish.md`）
- 从"保持现状"或"自己改"状态续跑
- 检测未提交改动 → 帮 commit
- 可选再 review (默认 yes)
- 进同款 5 选项 finishing 菜单

**架构决策**：finishing 菜单从 superpowers 收回，由 ohaze 自己实现 5 个选项。这避免了菜单嵌套和"继续修改"在外部 skill 里改不进去的问题。

V1.5 与 V1.1 一起重测，OK 后推 GitHub。
