# ohaze
> 我自己的 Claude Code 工作流插件：superpowers 上游 brainstorm/plan + Codex 中段执行 + Claude 审查 + ohaze 自己的 5 选项 finishing

> README: [./README.md](./README.md)
> ROADMAP: [./ROADMAP.md](./ROADMAP.md)
> CHANGELOG: [./CHANGELOG.md](./CHANGELOG.md)
> VAULT-CONTEXT: [./VAULT-CONTEXT.md](./VAULT-CONTEXT.md)

## 项目类型
- 类型: 发行产品（Claude Code plugin，会被 `/plugin install` 安装消费）
- 集群归属: 集群 3 hazeflow（个人 AI 工作流系统）
- 状态: active
- 版本: 1.9.1（`plugins/ohaze/.claude-plugin/plugin.json`）

## Agent 行为约定
- 继承全局 [`~/CLAUDE.md`](~/CLAUDE.md) 4 编码原则（先想再写 / 极简优先 / 外科手术式改动 / 目标驱动）
- 项目特殊约定:
  - 整份 plan 一次性给 Codex 端到端执行，不逐 Task 派发
  - commit 权保留在主线程：Codex 不自己 commit，review 前由主线程按 plan message 统一补
  - 审查用 `general-purpose` subagent（superpowers 不提供 code-reviewer）
  - resume 只在同一 ship 生命周期内（review retry / modify）；finishing 后的 bug 修复 = 新 fix ship
- 分支策略: 由 `/ohaze:ship` 自动判断类型（feat/fix/hotfix）+ 起分支名；遵循全局 git 分支 4 规则

## 关键文件 / 入口
- 入口: `plugins/ohaze/commands/` —— `ship` / `ship-review` / `ship-finish` / `status` 四条 slash command
- 配置: `.claude-plugin/marketplace.json`（marketplace 元信息）+ `plugins/ohaze/.claude-plugin/plugin.json`（plugin 元信息 + 版本号）
- 核心 skills: `plugins/ohaze/skills/` —— `plan-to-codex-prompt` / `codex-executor` / `finishing` / `writing-plans`
- 测试: 无自动化测试套件（Markdown plugin），靠沙箱实测 ship 流程验证
- 部署: 本地 `/plugin marketplace add <path>` 或远程 `muling-dev/ohaze`；详见 README `## 安装 / 部署`

## 集成点
- 上游依赖: `superpowers` 插件（brainstorming / using-git-worktrees / writing-plans）；`codex` CLI 二进制（`@openai/codex`，ship 直调 `codex exec`，硬依赖）
- 下游消费: 被装入任意项目驱动其 feature ship；通过 `hooks/hooks.json` + `adapters/vault-adapter.sh` 把 ship 生命周期事件镜像到 `~/Brain`
- 数据契约: `.ohaze/current-ship.json`（ship handoff，跨 session/command 续跑）；`~/Brain/20_Projects/<proj>/`（vault 镜像）；可选 `gh` CLI（`/ohaze:status` 拉远端 PR）
