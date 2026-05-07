# ohaze
> 我自己的 Claude Code 工作流插件：superpowers 上下游 + Codex 中段执行 + Claude 审查

## 基本信息
- 路径：~/Project/ohaze/
- 状态：active
- Tech：Markdown skills/commands（Claude Code plugin 格式），无构建依赖
- 仓库：github.com/muling-dev/ohaze（待推送）
- 本地安装：软链 `~/Project/ohaze` → `~/.claude/plugins/ohaze`

## 关键文件
| 文件 | 作用 |
|------|------|
| .claude-plugin/plugin.json | 插件元信息 |
| commands/ship.md | `/ohaze:ship` 主入口：编排 brainstorm→plan→Codex→review→finishing |
| commands/ship-review.md | `/ohaze:ship-review` 续跑：Codex 完成后触发审查循环+finishing |
| skills/plan-to-codex-prompt/SKILL.md | plan.md → Codex XML prompt 翻译规则 |
| skills/codex-executor/SKILL.md | 调 codex:codex-rescue + 审查重试循环 |

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
- 本地安装：`ln -sf ~/Project/ohaze ~/.claude/plugins/ohaze`
- 重载：在 Claude Code 内 `/plugin reload`
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
