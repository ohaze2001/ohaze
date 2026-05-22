# ohaze

> 个人 Claude Code 工作流插件：让 superpowers 负责思考、Codex 负责执行、Claude 负责审查与收尾。

## 它是什么

`ohaze` 把多个工具的强项串成一条闭环流水线，**一条 `/ohaze:ship "做什么"` 命令端到端跑完**：

| 阶段 | 谁干 | 来源 |
|---|---|---|
| 1. brainstorming（澄清需求 → 写 spec） | Claude | `superpowers` |
| 2. using-git-worktrees（隔离工作区） | Claude | `superpowers` |
| 3. writing-plans（生成 guidance plan） | Claude | `ohaze`（契约式 fork） |
| 4a. plan → Codex XML prompt | Claude | `ohaze` |
| 4b. 执行整份 plan | Codex | `codex` CLI 二进制 |
| 5a. 主线程补 commit | Claude | `ohaze` |
| 5b. 审查 git diff vs plan | Claude | `ohaze`（general-purpose subagent + 内联审查 prompt） |
| 6. 修复重试（审查不通过，最多 3 次） | Codex | `codex exec resume <session_id>` |
| 7. finishing（收尾菜单 + 收尾链 + 文档收尾） | Claude | `ohaze`（`ohaze:finishing` skill） |

## 前置依赖

### 必装

- **`superpowers` 插件**：`/plugin install superpowers@claude-plugins-official`
  提供 brainstorming / using-git-worktrees。
- **`codex` CLI 二进制**：`npm install -g @openai/codex`，并 `codex login` 完成认证。
  ship 流程直接调 `codex exec`，硬依赖。

> **`codex` 插件不是依赖。** ship 流程从头到尾只用 `codex` CLI 二进制，不经 `codex` 插件、不经 `codex-companion.mjs`。

### 可选

- **`gh` CLI**：`/ohaze:status` 用它拉远端 PR 列表，没装会自动跳过该段输出。

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

改完插件文件后用 `/plugin marketplace update ohaze` 拉新版。

## 命令清单

| 命令 | 作用 |
|---|---|
| `/ohaze:ship "需求"` | 端到端：brainstorm → worktree → plan → Codex 后台派发 |
| `/ohaze:ship-review [--more]` | Codex 跑完后触发：补 commit → 审查（重试上限 3）→ finishing |
| `/ohaze:ship-finish [--skip-review]` | 续跑：从「先不处理」或「自己改」状态恢复，可选再 review，进 finishing |
| `/ohaze:status` | 跨 worktree 工作流总览：哪个在跑、哪个等审查、哪个 stale |

## 使用示例

### 主流程

```text
/ohaze:ship 给 hazeflow 加用户登录页

# Claude 走 brainstorm + worktree + plan，把整份 guidance plan 后台扔给 codex exec
# 并 ScheduleWakeup 自动续到 review

# Codex 跑完后（自动或手动 /ohaze:ship-review）:
# - 主线程帮 Codex 补 commit（约定 commit 权留在主线程）
# - general-purpose subagent 审查 git diff vs plan（含 ADVERSARIAL + DOC-DRIFT）
# - 不通过 → 自动 codex exec resume <session_id> 修复（上限 3 次）
# - 通过 → finishing 菜单
```

### Finishing 菜单

`ohaze:finishing` skill 检测项目类型（`local` / `remote`），给出推荐收尾链，再列 5 项菜单：

```
1. 执行推荐收尾（一键到底）
2. 继续修改
3. 丢弃此次工作
4. 先不处理（worktree 留着，稍后 /ohaze:ship-finish）
5. 自定义收尾方案
```

「继续修改」子流程三选项：

- **a) Codex 续跑**（`codex exec resume <session_id>`，沿用同一 thread，上下文不丢）
- **b) Claude 主线程直接改**（改名、加注释、单行 fix 等小事最适合）
- **c) 我自己改**（退出，去 worktree 手改完跑 `/ohaze:ship-finish` 回来）

改完默认建议再跑一次 review，确认没破，循环回菜单。

### 跨 worktree 总览

```text
/ohaze:status

# 输出跨 worktree 的工作流状态：哪个 Codex 在跑、哪个等审查、
# 哪个 stale（7+ 天没动），以及远端 PR 列表（需 gh）。
```

## 设计决策

- **执行粒度**：整份 plan 一次性给 Codex（端到端）
- **Codex 调用**：直接 `codex exec --sandbox danger-full-access`，后台 `nohup &`；不经 codex 插件
- **commit 处理**：commit 权按约定留在主线程，review 前按 plan 指定 message 统一补
- **审查策略**：派发 `general-purpose` 子 agent 自动审查，审查 prompt（3-PART ADVERSARIAL + DOC-DRIFT）完整内联在 `codex-executor` skill
- **审查重试**：失败送回 Codex `codex exec resume <session_id>`，上限 3 次（modify 循环不计入）
- **resume 边界**：`resume` 仅用于同一 ship 生命周期内；finishing 后的 bug 修复 = 新 fix ship
- **finishing**：`ohaze:finishing` skill 拥有 Phase 7（不调 `superpowers:finishing-a-development-branch`）

## 路线图

> **版本号说明**：V1.x 是历史主题版本叙事，保留不重写。从 1.6.0 起严格按 [SemVer 2.0.0](https://semver.org/lang/zh-CN/) 标。完整变更日志见 [`CHANGELOG.md`](CHANGELOG.md)。

- [x] V1.0：核心 7 阶段闭环
- [x] V1.1：4 个 bug 修复（writing-plans 菜单截断 / Codex bash 权限 / 沙箱 commit 拦截 / worktree 跳过）
- [x] V1.5：`/ohaze:status` + finishing modify 选项 + `/ohaze:ship-finish`
- [x] **1.6.0**：Vault 集成（ohaze 生命周期事件镜像到 `~/Brain`）
- [x] **1.7.0**：Plan 契约化（`ohaze:writing-plans` guidance-form）+ ADVERSARIAL review + sandbox `danger-full-access`
- [x] **1.8.0**：Auto-resume（ScheduleWakeup 自续 ship 生命周期）+ 本地 merge 选项 + real-ship hardening
- [x] **1.9.0**：finish menu 项目类型化 + 文档漂移自动检测 + Codex session 精确 resume + `ohaze:finishing` skill 抽取
- [ ] **2.0.0**：tool-router（按任务复杂度自动路由 Codex / Claude / Gemini / DeepSeek）— 计划中

## License

MIT
