# ohaze

> 个人 Claude Code 工作流插件：让 superpowers 负责思考、Codex 负责执行、Claude 负责审查。

## 它是什么

`ohaze` 把三个工具的强项串成一条闭环流水线，**一条 `/ohaze:ship "做什么"` 命令端到端跑完**：

| 阶段 | 谁干 | 来源 |
|---|---|---|
| 1. brainstorming（澄清需求 → 写 spec） | Claude | `superpowers` |
| 2. using-git-worktrees（隔离工作区） | Claude | `superpowers` |
| 3. writing-plans（生成 TDD 实现计划） | Claude | `superpowers` |
| 4a. plan → Codex XML prompt | Claude | `ohaze` |
| 4b. 执行整份 plan | Codex | `codex` 插件 |
| 5. 主线程补 commit（沙箱拦了 `.git/`） | Claude | `ohaze` |
| 5. 审查 git diff vs plan | Claude | `ohaze` + `superpowers:code-reviewer` |
| 6. 修复（如审查不通过，最多 3 次） | Codex `--resume` | `codex` 插件 |
| 7. finishing（5 选项菜单，含"继续修改"） | Claude | `ohaze` |

## 前置依赖

### 1. 必装的两个插件

```text
/plugin install superpowers@claude-plugins-official
/plugin install codex@openai-codex
```

### 2. 必加的一条权限（关键）

ohaze 需要从 subagent 内调 `codex-companion.mjs`，subagent 没有交互式权限弹框，所以必须**预先**在 `~/.claude/settings.json` 的 `permissions.allow` 加：

```json
"Bash(node:*)"
```

不加这条插件还是能跑（有 fallback），但每次都走"主线程代为派发"的兜底路径，慢且不优雅。

### 3. 可选：`gh` 命令行

`/ohaze:status` 会用 `gh` 拉远端 PR 列表，没装也能跑（自动跳过该段输出）。

## 安装

ohaze 是一个 single-plugin marketplace（仓库根即 marketplace）。

**从 GitHub 安装（推荐）**

```text
/plugin marketplace add muling-dev/ohaze
/plugin install ohaze@ohaze
```

**本地路径安装（开发期）**

```text
/plugin marketplace add /Users/apple/Project/ohaze
/plugin install ohaze@ohaze
```

安装后 4 个命令立即可用。

## 命令清单

| 命令 | 作用 |
|---|---|
| `/ohaze:ship "需求"` | 端到端：brainstorm → worktree → plan → Codex 后台派发 |
| `/ohaze:ship-review [--more]` | Codex 跑完后触发：补 commit → 审查（重试上限 3）→ 5 选项 finishing |
| `/ohaze:ship-finish [--skip-review]` | 续跑：从"保持现状"或"自己改"状态恢复，可选再 review，进 finishing |
| `/ohaze:status` | 跨 worktree 工作流总览：哪个在跑、哪个等审查、哪个 stale |

## 使用示例

### 主流程

```text
/ohaze:ship 给 hazeflow 加用户登录页

# Claude 走 brainstorm + worktree + plan，把整份 plan 后台扔给 Codex
# 提示用 /codex:status 看进度

/ohaze:ship-review

# Codex 跑完后:
# - 主线程帮 Codex 补 commit (沙箱拦了 .git/)
# - superpowers:code-reviewer 审查 git diff vs plan
# - 不通过 → 自动 codex --resume 修复 (上限 3 次)
# - 通过 → 5 选项 finishing 菜单
```

### Finishing 菜单

```
1. 推送到远端
2. 创建 Pull Request
3. 保持现状 (稍后处理)
4. 丢弃此次工作
5. 继续修改 (小改动)   ← 不需要走完整 ship 的小调整
```

选 5 后子菜单：

- **a) Codex 续跑**（`--resume`，沿用同一 Codex thread，上下文不丢）
- **b) Claude 主线程直接改**（改名、加注释、单行 fix 等小事最适合）
- **c) 我自己改**（退出，去 worktree 手改完跑 `/ohaze:ship-finish` 回来）

改完默认建议再跑一次 review，确认没破，循环回菜单。

### 跨 worktree 总览

```text
/ohaze:status

# 输出示例：
# 项目: myproject (~/Project/myproject)
#
# 📍 主目录    main      ✅ 干净
# 🔧 worktrees:
#   feat+login        分支:worktree-feat+login    🟡 Codex 跑中 (task-xxx, 4m)
#   fix+auth-bug      分支:worktree-fix+auth      🟢 等审查
#   experiment+cache  分支:worktree-experiment+cache  🟡 stale (7+ 天)
# 📊 远端 PRs (gh): #42 feat: payment integration
```

> ℹ️ worktree 路径和分支命名由 superpowers 决定（当前版本用 `.claude/worktrees/feat+<name>` 和 `worktree-feat+<name>`）。

## 设计决策（V1.5）

- **执行粒度**：整份 plan 一次性给 Codex（端到端）
- **Codex 模式**：默认 `--background --write`
- **commit 处理**：Codex 沙箱拦 `.git/`，由主线程在 review 前用 plan 指定的 commit message 统一补
- **审查策略**：Codex 完成后 `superpowers:code-reviewer` 子 agent 自动审查
- **审查重试**：失败送回 Codex `--resume`，上限 3 次
- **finishing**：ohaze 自己实现 5 选项菜单（不调 superpowers:finishing-a-development-branch），多出"继续修改"分支
- **modify 循环**：用户主动触发，不计入 3 次审查重试

## 工作原理

1. `/ohaze:ship` 顺序调超级 powers 的 brainstorming → using-git-worktrees → writing-plans
2. plan 生成后，`ohaze:plan-to-codex-prompt` skill 把 plan.md 包成 Codex 能理解的结构化 XML（含完整 plan 内容 + completeness/verification/grounding/safety 契约）
3. `ohaze:codex-executor` skill 派 `codex:codex-rescue` subagent（Path A）或直接 Bash 调 codex-companion（Path B fallback）
4. Codex 后台跑，写代码 + 跑测试，但不 commit（沙箱限制）
5. `/ohaze:ship-review` 触发后，主线程先按 plan 指定的 message 补 commit，再派 reviewer subagent
6. PASS → 进 5 选项菜单；FAIL → `codex:rescue --resume` 把 issues 送回去修
7. 选 modify → 进子流程；选其他 → push/PR/keep/discard

详细见 [`plugins/ohaze/`](plugins/ohaze/) 下的 commands 和 skills。

## 路线图

> **版本号说明**：V1.x 是历史主题版本叙事，保留不重写。从 1.6.0 起严格按 [SemVer 2.0.0](https://semver.org/lang/zh-CN/) 标。完整变更日志见 [`CHANGELOG.md`](CHANGELOG.md)。

- [x] V1.0：核心 7 阶段闭环
- [x] V1.1：4 个 bug 修复（writing-plans 菜单截断 / Codex bash 权限 / 沙箱 commit 拦截 / worktree 跳过）
- [x] V1.5：`/ohaze:status` + finishing modify 选项 + `/ohaze:ship-finish`
- [x] **1.6.0**：Vault 集成（ohaze 生命周期事件镜像到 `~/Brain`，含 discussions / decisions / progress / README 同步 + linked-todo 精确打勾）
- [x] **1.7.0**：Plan 契约化（`ohaze:writing-plans` guidance-form）+ ADVERSARIAL review + sandbox `danger-full-access`
- [x] **1.8.0**：Auto-resume（ScheduleWakeup 自续 ship 生命周期）+ 本地 merge 选项 + real-ship hardening
- [ ] **2.0.0**：tool-router（按任务复杂度自动路由 Codex / Claude / Gemini / DeepSeek）— 计划中

## License

MIT
