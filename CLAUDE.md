# ohaze
> 我自己的 Claude Code 工作流插件：superpowers 上下游 + Codex 中段执行 + Claude 审查

## 基本信息
- 路径：~/Project/ohaze/
- 状态：active
- Tech：Markdown skills/commands（Claude Code plugin 格式），无构建依赖
- 仓库：github.com/muling-dev/ohaze（待推送）
- 本地安装：软链 `~/Project/ohaze` → `~/.claude/plugins/ohaze`

## 关键文件
仓库本身是一个 Claude Code marketplace。布局：

| 文件 | 作用 |
|------|------|
| .claude-plugin/marketplace.json | marketplace 元信息（声明本仓库内有哪些 plugin） |
| plugins/ohaze/.claude-plugin/plugin.json | plugin 元信息 |
| plugins/ohaze/commands/ship.md | `/ohaze:ship` 主入口：编排 brainstorm→worktree→plan→Codex 后台派发 |
| plugins/ohaze/commands/ship-review.md | `/ohaze:ship-review` Codex 完成后审查循环 + 5 选项 finishing 菜单 (含"继续修改") |
| plugins/ohaze/commands/ship-finish.md | `/ohaze:ship-finish` 从 paused/self-edit 状态恢复，可选再 review，进 finishing |
| plugins/ohaze/commands/status.md | `/ohaze:status` 跨 worktree 工作流总览 |
| plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md | plan.md → Codex XML prompt 翻译规则（含 commit_handling: 不要 commit）|
| plugins/ohaze/skills/codex-executor/SKILL.md | 调 codex:codex-rescue + Phase 5.0 主线程补 commit + 审查重试循环 |

## 设计决策（V1）
- **执行粒度**：整份 plan 一次性给 Codex（端到端）
- **Codex 模式**：默认 `--background --write`
- **审查策略**：Codex 完成后 `superpowers:code-reviewer` 子 agent 自动审查
- **审查重试**：失败送回 Codex `--resume`，上限 3 次
- **上下游**：1-3 阶段 + 7 阶段全部用 superpowers 原生 skill，不动

## 阶段归属
| 阶段 | 执行方 | 来源 |
|---|---|---|
| 1 brainstorming | Claude | superpowers |
| 2 using-git-worktrees | Claude | superpowers |
| 3 writing-plans | Claude | superpowers |
| 4 plan→prompt | Claude | ohaze |
| 4 执行 | Codex | codex 插件 |
| 5 审查 | Claude | ohaze + superpowers:code-reviewer |
| 6 修复重试 | Codex | codex 插件 --resume |
| 7 finishing | Claude | superpowers |

## 常用命令
- 本地安装（开发期，无需推 GitHub）：在 Claude Code 内
  - `/plugin marketplace add /Users/apple/Project/ohaze`
  - `/plugin install ohaze@ohaze`
- 远程安装（推 GitHub 后）：
  - `/plugin marketplace add muling-dev/ohaze`
  - `/plugin install ohaze@ohaze`
- 改完 plugin 文件后：`/plugin marketplace update ohaze`（拉新版）
- 推 GitHub：`gh repo create muling-dev/ohaze --public --source=. --push`

## 外部依赖
- `superpowers` plugin（必须已安装）：提供 brainstorming / writing-plans / using-git-worktrees / code-reviewer / finishing-a-development-branch
- `codex` plugin（必须已安装）：提供 codex:codex-rescue subagent + /codex:status /codex:result

## 当前目标
- [x] V1 骨架（5 个核心文件）
- [ ] 在一个真实小项目上跑通 `/ohaze:ship` 全流程
- [ ] 推 GitHub
- [ ] V2：Obsidian 同步
- [ ] V3：tool-router（按任务复杂度路由 Codex / Claude / Gemini）
