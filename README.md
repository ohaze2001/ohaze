# ohaze

> 个人 Claude Code 工作流插件：Claude 主线程编排 + Codex 异源执行 + Claude 异源审查 + 自包含收尾。**v2.1.0 起把 haze 视野收敛到 brief / 产品影响 / 收尾决策。**

## 安装 / 部署

ohaze 是一个 single-plugin marketplace（仓库根即 marketplace）。

### 前置依赖

**必装**

- **`codex` CLI 二进制**：`npm install -g @openai/codex`，并 `codex login` 完成认证。
  ship 流程直接调 `codex exec` / `codex exec resume`，硬依赖。

> **`codex` 插件不是依赖。** ship 流程从头到尾只用 `codex` CLI 二进制，不经 `codex` 插件、不经 `codex-companion.mjs`。
>
> **`superpowers` 插件也不再是依赖。** v2.0.0 起 ohaze 自持 `brainstorming` / `using-git-worktrees` / `writing-plans` 三个 skill（fork 自 superpowers v5.1.0，MIT），运行时不要求 superpowers 已装。

**可选**

- **`gh` CLI**：`/ohaze:status` 用它拉远端 PR 列表，没装会自动跳过该段输出。

### 安装方式

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

## 架构

`ohaze` 把多个工具的强项串成一条闭环流水线，**一条 `/ohaze:ship "做什么"` 命令端到端跑完**。v2.1 流程序：BDD brainstorm → brief approved → Claude 自动写 spec → Codex 异源审 spec → worktree 写 brief/spec → plan → Phase 3.5 摘要 + default-go → Codex → 异源审查 → 7 项 finishing 菜单。

用户看到的是 feature brief 和产品语言的风险描述，不需要读 spec / plan 的实现细节。Phase 1.5 自动把 brief 转成 spec；Phase 1.6 用 `spec-to-codex-review` 让 Codex 在实现前审 spec；Phase 3.5 只给 plan 一句话摘要，然后默认进入 Codex 实现，仍可被 haze 打断。

| 阶段 | 谁干 | 来源 |
|---|---|---|
| 1. brainstorming（BDD/needs-side，终止于 brief approved） | Claude | `ohaze`（fork 自 superpowers v5.1.0，砍 visual companion） |
| 1.5. brief → spec（mandatory code-reading + 关键边界单点问） | Claude | `/ohaze:ship` Phase 1.5 |
| 1.6. Codex 异源审 spec | Codex | `spec-to-codex-review` skill |
| 2a. using-git-worktrees（建 worktree + 安全 teardown） | Claude | `ohaze`（fork 自 superpowers v5.1.0 + 新增 teardown cd 主仓） |
| 2b. 在 worktree 内写 brief + spec 并 commit | Claude | `ohaze`（`/ohaze:ship` Phase 2b） |
| 3. writing-plans（生成 guidance plan） | Claude | `ohaze`（契约式 fork） |
| 3.5. plan 摘要 + default-go | Claude | `/ohaze:ship` Phase 3.5 |
| 4a. plan → Codex XML prompt | Claude | `ohaze`（`plan-to-codex-prompt` skill） |
| 4b. 执行整份 plan | Codex | `codex` CLI 二进制（`Bash(run_in_background)`，无 nohup） |
| 5a. 主线程补 commit | Claude | `ohaze`（`codex-executor` Phase 5.0） |
| 5b. 异源审查 git diff vs plan + **实跑测试** | Claude | `ohaze`（`general-purpose` subagent + 内联 4 部审查 prompt） |
| 6. 修复重试（审查不通过，最多 3 次，含「卡住升级」诊断） | Codex | `codex exec resume <thread_id>`（无 `--sandbox`） |
| 7. finishing（6 项菜单 + conditional Security Review + 收尾链 + 文档收尾） | Claude | `ohaze`（`finishing` skill） |

### 控制流

- **后台 + harness 自动唤醒**：Phase 4b `Bash(run_in_background)` 派 codex exec，主 agent turn 立即结束让出；Codex 进程退出后 **harness 自动 re-invoke 主 agent** 进 `/ohaze:ship-review`。
- **幂等状态门防幽灵唤醒**：`/ohaze:ship-review` 第一步读 `.ohaze/current-ship.json.state`，按 7 状态查表（`done`/`discarded` → 静默 no-op 吃掉幽灵唤醒）。
- **不设 ScheduleWakeup**：v2 A 方案 —— harness re-invoke 是唯一主触发，状态门是唯一防御。

### 设计决策（v2.1.0）

- **零运行时外部 skill 依赖**：brainstorming / using-git-worktrees / writing-plans 全部自持（fork 子集，非整仓）。锁基线 superpowers v5.1.0，定期 diff 上游。
- **流程序 brief → spec audit → worktree brief/spec**：haze 只 approve brief；Claude 自动写 spec，Codex 审 spec；建 worktree 后在 worktree 内写 `docs/ohaze/briefs/` + `docs/ohaze/specs/` 并 commit。
- **plan default-go**：`docs/ohaze/plans/` 产物只摘要给 haze，默认进入 Codex 实现，仍允许用户打断。
- **显式项目路径参数**：`/ohaze:ship "..." --project <abs-path>` 锁定目标项目，不靠 `pwd` detect（harness 会重置 cwd）。
- **Codex 调用**：初始 `codex exec --sandbox danger-full-access --cd <worktree> --json` 经 `Bash(run_in_background:true)` 派发，**无 nohup / no &**。
- **thread_id 捕获**：解析 `--json` 首事件 `{"type":"thread.started","thread_id":"<UUID>"}`；与 `~/.codex/sessions/.../rollout-*-<UUID>.jsonl` 一致。
- **resume 不带 `--sandbox`**：`codex exec resume <thread_id>` 不重复传 sandbox（codex 0.137 拒绝），sandbox 继承自初始 dispatch。
- **commit 处理**：Codex 不自 commit；主线程按 plan suggested message 统一补，可按文件重叠 split per-Task。
- **异源对抗审查**：审查 subagent = `general-purpose`（继承 Opus），刻意异于 Codex。审查 prompt 含 PART 2.5 **实跑验证**（必须真跑 `project_test_command` 并量化输出）+ PART 4 ADVERSARIAL（设计层挑战，不 gate）。
- **审查重试**：失败送 `codex exec resume <thread_id>` 修复，上限 3 次（含「卡住升级」诊断 —— 同类 issue 反复出现时识别 plan 问题 vs 执行问题，不盲烧 retry）。
- **resume 边界**：`resume` 仅用于同一 ship 生命周期（review retry / modify / 第 6 项 ADVERSARIAL 修复）；finishing 后的 bug 修复 = 新 fix ship。
- **finishing**：`ohaze:finishing` skill 拥有 Phase 7 —— 项目类型检测（local/remote）+ project_category + 6 项菜单 + conditional Security Review + 收尾链 + doc-finish 内化 neat 路由。
- **产品语言 finding 展示**：`findings-detail.json` 保存技术细节；haze 只看到 `user_impact_description`。

## 常用命令

| 命令 | 作用 |
|---|---|
| `/ohaze:ship "需求" [--project <abs-path>]` | 端到端：BDD brief → auto-spec → Codex spec audit → worktree+brief/spec → plan summary → Codex 后台派发 |
| `/ohaze:debug "症状" [--cause=<猜测原因>] [--project <abs-path>]` | bug fix mode：systematic 4-phase investigation + scope lock + 3 conditional gates，比 ship 更轻 |
| `/ohaze:ship-review [--more]` | Codex 跑完 harness 自动唤醒落到这里（也可手动）：状态门 → 审查（重试上限 3）→ finishing |
| `/ohaze:ship-finish [--skip-review]` | 续跑：从 `kept` / `self-edit-pending` 状态恢复，可选再 review，进 finishing |
| `/ohaze:status` | 跨 worktree 工作流总览：state-first 判定，哪个在跑 / 等审查 / stale |

开发期常用：

- 改完插件文件：`/plugin marketplace update ohaze`（拉新版）
- 推 GitHub：`gh repo create muling-dev/ohaze --public --source=. --push`

## 使用

### 主流程

```text
/ohaze:ship "给 hazeflow 加用户登录页" --project /Users/apple/Project/hazeflow

# Claude 走 BDD brainstorm（brief approved）→ auto spec → Codex spec audit → 建 worktree → 写 brief/spec + commit → plan summary
# 把整份 guidance plan 经 Bash(run_in_background) 扔给 codex exec
# Codex 进程退出后 harness 自动 re-invoke 主 agent 进 /ohaze:ship-review

# /ohaze:ship-review:
# - 过状态门: codex_done → 跑 review
# - 主线程帮 Codex 补 commit (commit 权留在主线程)
# - general-purpose 异源 subagent 审查 git diff vs plan (实跑 project_test_command, 含 ADVERSARIAL + DOC-DRIFT)
# - 不通过 → codex exec resume <thread_id> 修复 (无 --sandbox), 上限 3 次, 含卡住升级诊断
# - 通过 → 6 项 finishing 菜单
```

### Finishing 菜单

`ohaze:finishing` skill 检测项目类型（`local` / `remote`）和 `project_category`，给出推荐收尾链，再列菜单（5 或 6 项；Security Review 作为第 7 项在 web/API 或外部输入场景出现）：

```
1. 执行推荐收尾（一键到底）
2. 继续修改
3. 丢弃此次工作
4. 先不处理（worktree 留着，稍后 /ohaze:ship-finish）
5. 自定义收尾方案
6. 修复对抗审查后收尾  ← 仅当本次有 ADVERSARIAL findings 时出现
7. 安全审查（可选，适用于 web/API 项目）← 条件触发
```

「继续修改」子流程三选项：

- **a) Codex 续跑**（`codex exec resume <thread_id>` 无 `--sandbox`，沿用同一 thread 上下文不丢，经 `Bash(run_in_background)` 等 harness 唤醒）
- **b) Claude 主线程直接改**（改名、加注释、单行 fix 等小事最适合）
- **c) 我自己改**（退出，去 worktree 手改完跑 `/ohaze:ship-finish` 回来 —— state 设 `self-edit-pending`）

改完默认建议再跑一次 review，确认没破，循环回菜单。

「修复对抗审查后收尾」（第 6 项）：多选要修的 ADVERSARIAL items → 组 fix prompt → `codex exec resume` 修 → 询问复验 → 再走收尾链。复验不计入 3 次 retry cap（用户发起）。

### 跨 worktree 总览

```text
/ohaze:status

# 输出跨 worktree 的工作流状态: state-first 判定 (running / codex_done /
# review_fail / kept / self-edit-pending / done / discarded), 远端 PR 列表 (需 gh).
# 只读, 不修改任何 worktree 状态.
```

## 历史

已发布版本主题 / 进度路线见 [ROADMAP.md](./ROADMAP.md)。
完整 SemVer changelog 见 [CHANGELOG.md](./CHANGELOG.md)。

## 相关项目 / 文档

- **`superpowers`**（`claude-plugins-official`）：brainstorming / using-git-worktrees / writing-plans 上游来源；v2.0.0 起 ohaze fork 子集自持，运行时不依赖。
- **`codex` CLI**（`@openai/codex`）：中段执行引擎（版本基线 0.137）。
- **`docs/ohaze/briefs/` / `docs/ohaze/specs/` / `docs/ohaze/plans/`**：本仓库内的 brief / spec / plan 产物。

## License

MIT
