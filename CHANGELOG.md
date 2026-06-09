# Changelog

本项目所有显著变更都记录在本文件。

格式遵循 [Keep a Changelog 1.1.0](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [SemVer 2.0.0](https://semver.org/lang/zh-CN/)。

> **历史叙事说明**：`V1.0 / V1.1 / V1.5` 是项目早期的主题版本叙事，保留不重写。从 **1.6.0** 起严格按 SemVer 标。

---

## [Unreleased]

### Added

### Changed

### Fixed

### Removed

### Planned
- **2.1.0** — 集成验证 dogfood + 上游 fork 基线漂移监控（详见 ROADMAP.md Backlog）
- **未来某版** — tool-router（按任务复杂度自动路由 Codex / Claude / Gemini / DeepSeek，从 v1.x Planned 顺延，待 v2 稳定后重启评估）

### Backlog

---

## [2.0.0] — 2026-06-09

**主题**：零运行时外部 skill 依赖 + vault 流程层剥离 + 修核心控制流坑（nohup/ScheduleWakeup 幽灵唤醒、resume sandbox、cwd 悬空）。**break 级重构**。

### Added
- **fork brainstorming**（自 superpowers v5.1.0，MIT）进 `plugins/ohaze/skills/brainstorming/`：砍 visual companion，改终止状态为「设计获批」（不写 spec、不 invoke writing-plans）
- **fork using-git-worktrees**（自 superpowers v5.1.0，MIT）进 `plugins/ohaze/skills/using-git-worktrees/`：保留 Step 0/1/3/4 + 新增「Removing a Worktree Safely」teardown 章节（删前必 `cd "$main_repo_path"`） + `main_repo_path` 捕获契约
- **codex-executor 实跑验证（PART 2.5）**：审查者必须真跑 `project_test_command` 并量化输出（内化 verification-before-completion）
- **codex-executor retry 卡住升级**：连续 FAIL 同类 issue 时识别 plan 问题 vs 执行问题，不盲烧 retry（内化 systematic-debugging）；fix prompt 加 `<anti_regression>` 块防震荡
- **finishing 第 6 项「修复对抗审查后收尾」**：仅当 review-verdict.json.issues 含 ADVERSARIAL 时出现，给设计层风险结构化修复入口
- **doc-finish 内化 neat 完整路由（4 class）**：CHANGELOG/version/linked_todo + drift 修复 + 待办→ROADMAP Backlog/Bug + 架构→README+CLAUDE
- **幂等状态门**：`/ohaze:ship-review` 与 `/ohaze:ship-finish` 第一步读 `.ohaze/current-ship.json.state` 查 7 状态表，是 v2 唯一的防幽灵唤醒/重入手段
- **显式项目路径参数** `--project <abs-path>` 锁定目标项目（不靠 `pwd` detect，harness 会重置 cwd）
- **Pre-flight 四件套完备性检查**（内化 md-init）：缺则按项目类型补，齐则跳过

### Changed
- **流程序调整**：brainstorm（主仓内文本对话，不落档）→ 建 worktree → 在 worktree 内写 spec 并 commit。main 全程干净，并行多 ship 不互相污染 ff-merge
- **codex dispatch 改 `Bash(run_in_background:true)`**：去 `nohup` / `&` / `> log 2>&1` / `pid_file`；harness 自动 re-invoke 替代 ScheduleWakeup 轮询
- **codex exec resume 命令去 `--sandbox`**：codex 0.137 不支持，sandbox 继承自初始 dispatch（修旧实现 bug）
- **handoff schema 精简**：新增 `state` / `thread_id` / `codex_bg_id` / `main_repo_path` / `slug`；删 `codex_session_id` / `codex_run_id` / `codex_job_id` / `codex_pid_file` / `codex_log_file` / `codex_thread_resume` / `started_at`
- **异源审查写死**：审查 subagent 必须 `general-purpose`（继承 Opus），刻意异于 Codex；禁改 codex 自审 / `codex exec review`
- **status 命令 state-first 判定**：用 handoff `state` 字段查表，不再 `kill -0 pid` / `ps -p`
- **finishing 菜单 5 → 6 项**（第 6 项 conditional）
- **plugin.json**：version 1.9.2 → 2.0.0；description 改自包含口径；keywords 移除 superpowers，新增 adversarial-review

### Fixed
- **`codex exec resume` 错误带 `--sandbox`**：原 `codex-executor` 第 280 行残留 v1 实现 bug，v2 全面修复（含 retry / modify 5a / 第 6 项 ADVERSARIAL 修复）
- **资源浪费的 ScheduleWakeup 二次唤醒**：v1 完成后未取消 ScheduleWakeup 仍到点执行（haze 提报）；v2 不设兜底唤醒，幂等状态门吃掉任何重入，从源头杜绝

### Removed
- **vault 镜像流程层耦合**：
  - 删 `plugins/ohaze/hooks/hooks.json`
  - 删 `plugins/ohaze/adapters/vault-adapter.sh`（836 行）
  - 删根 `VAULT-CONTEXT.md`
- **删 ScheduleWakeup 整套机制**（A 方案）：`ship.md` Auto-resume 段、`ship-review.md` 重排逻辑、相关 `allowed-tools` 字段
- **删 `ship-result.json` + `.vault-sync-state.json` 机制**：纯 vault hook 触发器，剥离后 finishing 主线程直接收尾
- **删「必须用 Write 触发 vault hook」硬约束**：仍可用 Write（结构化、防转义），但理由不再是 hook
- **删 `## Vault Context` 段**（`ship.md` / `ship-review.md` / `ship-finish.md` 各一段，pre-brainstorm/review/finish 的 `~/Brain` decisions/discussions 注入）
- **删 `merge` 步骤的 `PRE_MERGE_COMMITS` / `PRE_MERGE_COUNT` 预计算**：vault-adapter `commits=0` 工件随 vault 剥离消失
- **运行时不再依赖 superpowers 插件已装**（仍可用作 fork 基线参考）

### Migration
- 升级到 v2 后，旧 `.ohaze/current-ship.json` 含 v1 字段（`codex_pid_file` 等）的 handoff 会被 `/ohaze:status` 标为「legacy v1 handoff detected」并跳过 v1 字段；建议旧 ship 完成后再升级，或手动清掉残留 handoff
- 若同时装了 `superpowers` 插件，v2 ohaze 仍正常工作，但 ship 流程不再调用 `superpowers:*` —— 全部走 `ohaze:*` 自持版

---

## [1.9.2] — 2026-05-29

**主题**：修复 finishing 删 worktree 后 session cwd 悬空导致 hook 调用失败。

### Fixed
- `finishing/SKILL.md` `remove-worktree`：删 worktree 前先 `cd "$main_repo_path"` 把 session cwd 收回主仓。此前 `ship.md` Phase 2 / `ship-finish.md` 会 `cd` 进 worktree，finishing 用 `git -C "$main_repo_path" worktree remove` 删除时 shell 仍站在 worktree 内 → cwd 指向已删目录 → 之后任意 hook（`UserPromptSubmit` / `Stop` / `SessionEnd`）从死 cwd spawn，Claude Code 报 `posix_spawn '/bin/sh' ENOENT` / `getcwd: cannot access parent directories` 错误。spawn 在 hook 脚本执行前就失败，hook 侧无法兜底，唯一修复点是不让 cwd 留在待删 worktree 内。discard 分支同样先 cd 再 `git worktree remove --force`（这两天 vault refactor 高密度连续 ship 时高概率复现，根因实为 Claude Code hook spawn 前不校验 cwd 的上游 bug [#50960](https://github.com/anthropics/claude-code/issues/50960)，ohaze 侧通过收回 cwd 规避触发）

---

## [1.9.1] — 2026-05-22

**主题**：codex 插件彻底弃用 + 修正 1.9.0 里错误的 finishing 菜单改动 + vault-adapter 死链修复。

### Fixed
- `vault-adapter.sh`：decisions/discussions 文档的 Spec/Plan 路径记的是 worktree 内路径，`worktree remove` 后变死链 —— E5 finish 时按 `ship_action` 转主仓路径（merge/push/pr 转、discard 标注「未落主仓」），新增 `to_main_repo_path` helper；同步重写 discussions「## 启动」段的死链
- 撤回 1.9.0 里把 `ohaze:finishing` 菜单从 `AskUserQuestion` 改成纯文字的改动（基于「`AskUserQuestion` 限 4 项」的错误假设——实测可渲染 5+ 项），恢复 `AskUserQuestion` 5 项菜单

### Changed
- `vault-adapter.sh` `pre-bash`：PreToolUse 对每条 Bash 都触发，先对原始 stdin 做廉价 `grep -q current-ship` 预过滤再走 python 解析；`=== event ===` 日志延后到命中真信号后才写，消除日志刷屏
- `codex` 插件完全弃用：`ship.md` Pre-flight 不再检查 / 要求安装 codex 插件（改为检查 `codex` CLI 二进制）；`status.md` 删除 `codex-companion.mjs` back-compat fallback；`codex-executor` 删除 codex-rescue 段、binary 缺失改提示装 CLI；`CLAUDE.md` / `README.md` 清除 codex 插件作为依赖的描述

---

## [1.9.0] — 2026-05-22

**主题**：finish menu 项目类型化 + 文档漂移自动检测 + Codex session 精确 resume。

### Added
- `ohaze:finishing` skill：抽出 Phase 7 finishing，统一 finishing menu、收尾链执行、文档收尾、modify 子流程
- Finish menu 项目类型推荐链：`local` 默认 doc-finish → commit → merge → remove-worktree；`remote` 默认 doc-finish → commit → merge → push → remove-worktree，并支持偏好回写
- Reviewer `DOC-DRIFT` 检测：发现目标项目 `CLAUDE.md` 描述性 section 漂移，写入 `review-verdict.json` 的 `doc_drift`

### Changed
- `/ohaze:ship-review` 与 `/ohaze:ship-finish` 改为 invoke `ohaze:finishing`，不再维护内联 finishing 菜单副本
- `/ohaze:ship` handoff 增加 `codex_session_id` 与 `project_type` 字段
- Resume 边界文档化：finishing 后发现 bug 要开新的 fix ship，不 resume 旧 session

### Fixed
- Codex retry/modify 从全局 `resume --last` 改为 session-id 精确 resume，修复并行 ship 下可能串会话的问题
- 审查 subagent 派发类型从不存在的 `superpowers:code-reviewer` 改为 `general-purpose`（superpowers 不提供 code-reviewer subagent，旧代码每次靠 fallback 蒙混）
- `ohaze:finishing` 菜单从 `AskUserQuestion`（限 4 项，5 项菜单溢出）改为纯文字编号菜单

---

## [1.8.0] — 2026-05-18

**主题**：Auto-resume + Real-ship hardening — 不需要用户手动接 Phase 5；finishing 支持纯本地仓。

### Added
- `/ohaze:ship` 派发 Codex 后 `ScheduleWakeup(600s, "/ohaze:ship-review")` 自动接 review；review pre-flight 检查 codex pid，还在跑则再 schedule（`794f19f`）
- Finishing 菜单 Option 1 — 本地 merge（`git merge --ff-only`），纯本地仓不开 PR 也能完成 ship（`daba82c`）

### Fixed
- `vault-adapter.sh` 3 个 real-ship blocking bug（`f508cd3`）
- ship.md / ship-review.md / ship-finish.md：`.ohaze/` 路径修正 + 明确强制用 `Write` 工具（heredoc 不触发 PostToolUse hook）（`9bdeeb8`）
- Finishing Option 1：merge 前预算 commits 列表注入 `ship_result.commits`，避免 ff-merge 后 worktree `base..HEAD` 空导致 vault decisions 记 "Commits 数量=0"（`b679ee3`）

---

## [1.7.0] — 2026-05-16

**主题**：Plan 契约化 + Sandbox 升级 — 让 Codex 重新有实现自治权；review 加设计挑战维度；绕过 codex-companion 的 workspace-write 锁死。

### Added
- `skills/writing-plans/SKILL.md`：fork 自 `superpowers:writing-plans`，改为 **guidance-form**（contract + acceptance，不是 prescriptive code），305 行（`defa9a0`）
- "Reading the Spec" 章节：spec→plan 时如何把执行代码转写成契约描述，附转换对照表（`520ad82`）
- ADVERSARIAL review 维度：reviewer subagent 三部分（契约合规 / 代码质量 / 对抗式设计挑战），ADVERSARIAL 仅 advisory 不阻塞 ship（`18dca08`）
- codex-executor 改走 `codex exec --sandbox danger-full-access`，直接派发不经 codex-companion；ship 流程已 brainstorm/plan/review 三重 gate（`535b68c`）

### Changed
- `plan-to-codex-prompt` 改成薄包装：原来要 distill prescriptive code 现在直接 verbatim 嵌入 guidance plan（`64d9994`）

---

## [1.6.0] — 2026-05-15

**主题**：Vault 集成 — 把 ohaze 生命周期事件镜像到 `~/Brain`，让每次 ship 都自动留下 discussions / decisions / progress / README 同步。

### Added
- `adapters/vault-adapter.sh`：736 行的事件路由 + E1/E2/E4/E_pause/E5 完整 lifecycle handlers（`0d1d5f1`）
- `hooks/hooks.json`：PostToolUse Write + PreToolUse Bash 注册在**插件内**，脱离 `~/.claude/settings.json` 全局依赖（`e927dbd`）
- ship.md / ship-review.md / ship-finish.md：brainstorm 与 review 前静默加载 vault context（`4946d86`）
- `_handle_verdict` / `_handle_result`：把 review-verdict.json 与 ship-result.json 同步到 vault（`40b9de0`）
- E5 写 `decisions/<feature>.md` ADR：action / branch / PR URL / commits 数量 / 审查重试次数（`40b9de0`）
- E5 同步源项目 CLAUDE.md：用户在 ship.md Step A 选定的 `linked_todo` 用 Python 字面 replace 打勾（`02802f4`）
- ship.md：brainstorm 阶段读 related 项目 README（cross-project 知识图谱边）（`e166036`）

### Fixed
- 4 个 V2 ship-result chain blocking bug（`f2f08ce`）
- 删除 last_active sed 死代码：vault README 用 `updated` 字段不是 `last_active`（`2f27913`）

---

## [V1.5] — 2026-05-08（历史主题版本）

**主题**：观测 + Finishing 子流程。

### Added
- `/ohaze:status` 命令：跨 worktree 工作流总览（running / 等审查 / stale / 远端 PR），143 行（`81c89b5`）
- Finishing 菜单第 5 选项"继续修改"：子菜单 a) Codex `--resume` b) Claude 主线程 c) 用户自改后 `/ohaze:ship-finish`（`81c89b5`）
- `/ohaze:ship-finish` 命令：从 paused / self-edit 状态恢复，可选 re-review，进同款 finishing 菜单（`81c89b5`）

### Fixed
- ship.md：force `mkdir -p .ohaze` before Write tool to avoid first-write failure（`56d7534`）

---

## [V1.1] — 2026-05-08（历史主题版本）

**主题**：V1 沙箱实测发现的 4 个 bug 全部修复。

### Fixed
- writing-plans 自带菜单截断 ship 流程：Phase 3 加 CRITICAL override（`99c1ee0`）
- codex-rescue subagent 缺 Bash 权限静默失败：codex-executor 加 Path B fallback 直接调 codex-companion（`2a12806`）
- Codex 沙箱拦 `.git/` 写入：plan-to-codex-prompt 加 `<commit_handling>` 块明确告知不要 commit；codex-executor 加 Phase 5.0 主线程统一 commit（`7b2ca33`）
- Worktree 阶段被 brainstorming 跳过：ship.md Phase 1 加 CRITICAL override 禁止 brainstorming 直跳；Phase 2 标记 mandatory（`7b2ca33`）

---

## [V1.0] — 2026-05-07（历史主题版本）

**主题**：核心 7 阶段闭环。

### Added
- Marketplace + plugin 布局：`.claude-plugin/marketplace.json` + `plugins/ohaze/`（`7c44c8d`）
- 4 个 commands：`ship` / `ship-review`（V1 含 4 选项 finishing）
- 2 个 skills：`plan-to-codex-prompt` / `codex-executor`
- 5 个核心决策：Codex 端到端 / 审查自动触发 / 审查重试上限 3 次 / 默认 `--background` / 整体 review
- 初始 scaffold（`3b23d5e`）

---

[Unreleased]: https://github.com/muling-dev/ohaze/compare/v1.9.0...HEAD
[1.9.0]: https://github.com/muling-dev/ohaze/releases/tag/v1.9.0
[1.8.0]: https://github.com/muling-dev/ohaze/releases/tag/v1.8.0
[1.7.0]: https://github.com/muling-dev/ohaze/releases/tag/v1.7.0
[1.6.0]: https://github.com/muling-dev/ohaze/releases/tag/v1.6.0
