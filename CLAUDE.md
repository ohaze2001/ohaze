# ohaze
> 个人 Claude Code 工作流插件：Claude 主线程编排 + Codex 异源执行 + Claude 异源审查 + 自包含收尾。v2.1.0 起引入 BDD brief、Codex spec audit、default-go plan summary。

> README: [./README.md](./README.md)
> ROADMAP: [./ROADMAP.md](./ROADMAP.md)
> CHANGELOG: [./CHANGELOG.md](./CHANGELOG.md)

## 项目类型
- 类型: 发行产品（Claude Code plugin，会被 `/plugin install` 安装消费）
- 集群归属: 集群 3 hazeflow（个人 AI 工作流系统）
- 状态: active
- 版本: 2.2.0（`plugins/ohaze/.claude-plugin/plugin.json`）

## Agent 行为约定
- 继承全局 [`~/CLAUDE.md`](~/CLAUDE.md) 4 编码原则（先想再写 / 极简优先 / 外科手术式改动 / 目标驱动）
- 项目特殊约定:
  - Phase 1 只聊 BDD brief；Phase 1.5 由 Claude 自动写 spec，Phase 1.6 用 `spec-to-codex-review` 做 Codex 异源审 spec
  - 整份 plan 一次性给 Codex 端到端执行，不逐 Task 派发
  - Phase 3.5 会先给 plan 一句话摘要，再 default-go 进 Codex 实现，除非 haze 打断
  - commit 权保留在主线程：Codex 不自己 commit，review 前由主线程按 plan suggested message 统一补
  - 审查用 `general-purpose` subagent（异源对抗写死，禁改 codex 自审）；审查必须实跑 `project_test_command`（verification-before-completion）
  - `spec-to-codex-review` 是新核心 skill：输入 brief/spec/code refs/project type/main repo，输出 spec-review verdict JSON
  - `codex exec resume <thread_id>` **不带 `--sandbox`**（codex 0.137 拒绝；sandbox 继承自初始 dispatch）
  - 后台派发用 `Bash(run_in_background: true)`，**不用 nohup / no ScheduleWakeup**；harness re-invoke 是主触发，幂等状态门是唯一防御
  - 顶层 `codex exec` dispatch 用 prompt-as-arg + `< /dev/null` 关 stdin（codex 0.137 stdin redirect silent crash mitigation）；resume 路径因 codex 0.137 不接受 PROMPT arg 保留 stdin redirect + 30s `thread.started` liveness check + KillBash 兜底；二次失败转 `state=dispatch_failed`（清 codex_bg_id）防 dangling running state
  - Dispatch mode 术语 anchor 在 `codex-executor/SKILL.md` 顶层 Dispatch Mode Vocabulary 段：harness background（允许）/ OS-level background（禁止）/ foreground sync（仅 finishing 6th-option + modify 2a 架构例外）；其他 SKILL cross-ref 不再各自定义
  - resume 只在同一 ship 生命周期内（review retry / modify / finishing 第 6 项 ADVERSARIAL 修复）；finishing 后的 bug 修复 = 新 fix ship
  - `/ohaze:debug` 独立于 `/ohaze:ship`：debug 写 `ship_mode: "debug"` handoff 字段供下游分流；`ship-review` 的 G3 blast-radius gate 只在 debug mode 触发
  - doc-finish 是四件套 (CLAUDE.md/README.md/ROADMAP.md/CHANGELOG.md/manifest) 写入唯一收口；Codex 实施期间禁直接写四件套 (即便 plan Task 错列)，由 plan-to-codex-prompt 双闸拦截 + writing-plans 红线源头预防
- 流程序: brainstorm（brief only）→ spec → Codex spec audit → worktree + brief/spec → plan → default-go → Codex
- debug 流程序: pre-flight → worktree → systematic-debugging (含 G1) → debug-to-codex-prompt → Codex execute → ship-review (含 L2 + G3) → ship-finishing
- 分支策略: 由 `/ohaze:ship` 自动判断类型（feat/fix/hotfix）+ 起分支名（slug = feature 描述）；遵循全局 git 分支 4 规则
- 显式项目路径: ship 用 `--project <abs-path>` 锁定目标项目，不靠 `pwd` detect（harness 会重置 cwd）

## 关键文件 / 入口
- 入口: `plugins/ohaze/commands/` —— `ship` / `debug` / `ship-review` / `ship-finish` / `status` 五条 slash command
- 配置: `.claude-plugin/marketplace.json`（marketplace 元信息）+ `plugins/ohaze/.claude-plugin/plugin.json`（plugin 元信息 + 版本号）
- 核心 skills: `plugins/ohaze/skills/` —— `brainstorming`（fork） / `systematic-debugging`（fork） / `debug-to-codex-prompt` / `spec-to-codex-review` / `using-git-worktrees`（fork，含 teardown） / `writing-plans`（fork） / `plan-to-codex-prompt` / `codex-executor` / `finishing`（7 项菜单 + neat 路由内化）
- 数据契约: `.ohaze/current-ship.json`（ship handoff，权威 schema 在 `commands/ship.md`）+ `.ohaze/review-verdict.json`（审查结论 + ADVERSARIAL/doc_drift）+ `.ohaze/findings-detail.json`（产品语言展示单一真相源）
- 产物路径: `docs/ohaze/briefs/` / `docs/ohaze/specs/` / `docs/ohaze/plans/`
- 测试: 无自动化测试套件（Markdown plugin），靠 grep/test/JSON-load 结构断言 + dogfood 端到端冒烟验证
- 部署: 本地 `/plugin marketplace add <path>` 或远程 `muling-dev/ohaze`；详见 README `## 安装 / 部署`

## 集成点
- 硬依赖: `codex` CLI 二进制（`@openai/codex`，版本基线 0.137，ship 直调 `codex exec` / `codex exec resume`）
- Fork 基线: `superpowers` v5.1.0（brainstorming + using-git-worktrees + writing-plans 子集，MIT，已 fork 进 `plugins/ohaze/skills/`，运行时不依赖 superpowers 已装）
- 可选: `gh` CLI（`/ohaze:status` 拉远端 PR）
- 下游消费: 被装入任意项目驱动其 feature ship；自身不向外部系统镜像（v2.1.0 起 vault 镜像已剥离）
