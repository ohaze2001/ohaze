# ohaze
> 我自己的 Claude Code 工作流插件：superpowers 上游 brainstorm/plan + Codex 中段执行 + Claude 主线程补 commit + Claude 审查 + ohaze 自己的 5 选项 finishing

## 基本信息
- 路径：~/Project/ohaze/
- 状态：active
- Tech：Markdown skills/commands（Claude Code plugin 格式），无构建依赖
- 仓库：github.com/muling-dev/ohaze
- 本地安装：`/plugin marketplace add /Users/apple/Project/ohaze` → `/plugin install ohaze@ohaze`
- 远程安装：`/plugin marketplace add muling-dev/ohaze` → `/plugin install ohaze@ohaze`

## 关键文件
仓库本身是一个 Claude Code single-plugin marketplace。布局：

| 文件 | 作用 |
|------|------|
| .claude-plugin/marketplace.json | marketplace 元信息（声明本仓库内有哪些 plugin） |
| plugins/ohaze/.claude-plugin/plugin.json | plugin 元信息 |
| plugins/ohaze/commands/ship.md | `/ohaze:ship` 主入口：brainstorm→worktree→plan→Codex 后台派发 |
| plugins/ohaze/commands/ship-review.md | `/ohaze:ship-review` 补 commit + 审查循环 + 5 选项 finishing 菜单（含"继续修改"） |
| plugins/ohaze/commands/ship-finish.md | `/ohaze:ship-finish` 从 paused/self-edit 状态恢复，可选再 review，进 finishing |
| plugins/ohaze/commands/status.md | `/ohaze:status` 跨 worktree 工作流总览（含 stale 检测、远端 PR） |
| plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md | plan.md → Codex XML prompt（含 commit_handling: 不要 commit）|
| plugins/ohaze/skills/codex-executor/SKILL.md | 调 codex:codex-rescue（Path A）+ 直接 Bash fallback（Path B）+ Phase 5.0 补 commit + 审查重试循环 + modify 子流程 |

## 设计决策
- **执行粒度**：整份 plan 一次性给 Codex（端到端）
- **Codex 模式**：默认 `--background --write`
- **commit 处理**：Codex 沙箱拦 `.git/`，主线程在 review 前按 plan 指定 message 统一补
- **审查策略**：Codex 完成后 `superpowers:code-reviewer` 子 agent 自动审查
- **审查重试**：失败送回 Codex `--resume`，上限 3 次（modify 循环不计入）
- **finishing**：ohaze 自己实现 5 选项（不调 superpowers:finishing-a-development-branch）
- **modify 循环**：选 5 后子菜单 a/b/c（Codex --resume / Claude inline / 自己改）

## 阶段归属
| 阶段 | 执行方 | 来源 |
|---|---|---|
| 1 brainstorming | Claude | superpowers |
| 2 using-git-worktrees | Claude | superpowers |
| 3 writing-plans | Claude | superpowers |
| 4a plan→prompt | Claude | ohaze (plan-to-codex-prompt skill) |
| 4b 执行 | Codex | codex 插件 |
| 5a 补 commit | Claude | ohaze (codex-executor Phase 5.0) |
| 5b 审查 | Claude | ohaze + superpowers:code-reviewer |
| 6 修复重试 | Codex | codex 插件 --resume |
| 7 finishing | Claude | **ohaze（5 选项菜单）** |

## 前置要求

### 必装插件
- `superpowers@claude-plugins-official`
- `codex@openai-codex`

### 必加权限（关键）
`~/.claude/settings.json` 的 `permissions.allow` 必须含 `"Bash(node:*)"`，否则 codex-rescue subagent 派发会失败（兜底走 Path B 也能跑，但慢）。

## 常用命令
- 本地安装（开发期，无需推 GitHub）：`/plugin marketplace add /Users/apple/Project/ohaze` → `/plugin install ohaze@ohaze`
- 远程安装：`/plugin marketplace add muling-dev/ohaze` → `/plugin install ohaze@ohaze`
- 改完 plugin 文件后：`/plugin marketplace update ohaze`（拉新版）
- 推 GitHub：`gh repo create muling-dev/ohaze --public --source=. --push`

## 外部依赖
- `superpowers` plugin：brainstorming / writing-plans / using-git-worktrees / code-reviewer
- `codex` plugin：codex:codex-rescue subagent + /codex:status /codex:result + scripts/codex-companion.mjs
- 可选 `gh`：让 `/ohaze:status` 能拉远端 PR 列表

## 当前目标
- [x] V1 骨架（5 个核心文件）
- [x] V1 沙盒实测（subtract 函数）→ 发现 4 个 bug
- [x] V1.1 修复（writing-plans 菜单 / bash fallback / 沙箱 commit / worktree 跳过）
- [x] V1.5 新功能（status / finishing modify / ship-finish）
- [x] V1.5 沙盒实测（multiply 函数 + jsdoc 双轮 modify）→ 全绿，0 retries
- [x] 推 GitHub
- [ ] V2：Obsidian 同步（spec/plan/progress 镜像到 vault）
- [ ] V3：tool-router（按任务复杂度路由 Codex / Claude / Gemini / DeepSeek）
