# Changelog

本项目所有显著变更都记录在本文件。

格式遵循 [Keep a Changelog 1.1.0](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [SemVer 2.0.0](https://semver.org/lang/zh-CN/)。

> **历史叙事说明**：`V1.0 / V1.1 / V1.5` 是项目早期的主题版本叙事，保留不重写。从 **1.6.0** 起严格按 SemVer 标。

---

## [Unreleased]

待规划：**2.0.0** — tool-router（按任务复杂度自动路由 Codex / Claude / Gemini / DeepSeek）。

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

[Unreleased]: https://github.com/muling-dev/ohaze/compare/v1.8.0...HEAD
[1.8.0]: https://github.com/muling-dev/ohaze/releases/tag/v1.8.0
[1.7.0]: https://github.com/muling-dev/ohaze/releases/tag/v1.7.0
[1.6.0]: https://github.com/muling-dev/ohaze/releases/tag/v1.6.0
