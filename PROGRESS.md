# ohaze 进度

## 2026-05-07
- 完成：V1 设计锁定（5 决策点全部按推荐组合确定）
  - Codex 端到端执行
  - 审查自动触发
  - 审查重试上限 3 次
  - 默认 `--background`
  - 整体 review（非逐 Task）
- 完成：项目骨架搭建（CLAUDE.md / PROGRESS.md / 目录结构）
- 完成：5 个核心文件全部到位（plugin.json / 2 commands / 2 skills）
- 修正：发现 Claude Code 不识别 `~/.claude/plugins/<name>/` 直接路径，必须经 marketplace
  → 重构为 marketplace+plugin 布局：仓库根放 `.claude-plugin/marketplace.json`，
     plugin 实体在 `plugins/ohaze/`
- 待处理：本地 marketplace 安装测试 → 真实项目跑通 `/ohaze:ship` → 推 GitHub

## 2026-05-08

### V1 沙箱实测 — 端到端跑通

测试任务：`/ohaze:ship 加一个 subtract 函数到 src/math.js，并配上测试`
（沙箱：`~/Project/ohaze-sandbox/`，session log：`docs/session-log-2026-05-08.md`）

**结果**：
- 流程跑通：brainstorm → writing-plans → codex 派发 → result → 自动续跑 → review → finishing
- 审查 VERDICT: PASS，0 retries
- 产物质量：spec / plan / code / tests 全部高质量，TDD 节奏到位
- Codex 总耗时 1m45s

### 发现的 4 个 V1 bug + 已落地修复

**Bug 1：writing-plans 自带"两选项"菜单截断流程**（commit `99c1ee0`）
- 现象：plan 写完后 superpowers 让用户选 1/2，绕过 ohaze Phase 4
- 修法：ship.md Phase 3 加 CRITICAL override，明确禁止显示该菜单

**Bug 2：codex-rescue subagent 缺 Bash 权限静默失败**（commit `2a12806`）
- 现象：subagent 没有 interactive permission UI，settings.json 里没 `Bash(node:*)` 时直接派不出去
- 修法：codex-executor skill 加 Path B fallback，subagent 失败自动回落到主线程直接调 codex-companion.mjs

**Bug 3：Codex 沙箱拦 `.git/` 写入**（V1.1）
- 现象：Codex `workspace-write` 模式特意禁止 `.git/` 写入（产品安全设计，非 bug）
- 现象延伸：Codex 写完代码+测试后，`git add` 报 `Operation not permitted`，commit step 全部失败
- 修法：
  - plan-to-codex-prompt 加 `<commit_handling>` 块，明示告知 Codex 不要 commit
  - codex-executor 加 Phase 5.0：review 之前由主线程统一 commit
  - `<output_report>` 调整：Codex 报告"intended commit messages"列表

**Bug 4：worktree 阶段被 brainstorming 跳过**（V1.1）
- 现象：brainstorming 的 terminal state 是直接调 writing-plans，绕过 using-git-worktrees
- 后果：实测中 Codex 直接在 main 上写代码，没建独立 feature branch
- 修法：ship.md Phase 1 加 CRITICAL override，明确禁止 brainstorming 直跳；Phase 2 标记 mandatory

### V1.1 状态
- 4 个 bug 全部修完，待新 session 重测
- 推 GitHub 暂缓，等 V1.1 重测通过

### V1.5 同期落地（一起测）

讨论完 worktree 用途和 finishing 缺"继续修改"选项后，把以下功能并入 V1.5：

**新增 `/ohaze:status` 命令**（`commands/status.md`）
- 跨 worktree 工作流总览：每个 worktree 的分支、git 状态、ohaze handoff、Codex job 状态、stale 检测
- 远端 PR 状态（用 gh 拉，可选）
- 只读，不会自动清理

**finishing 菜单加第 5 个选项 "继续修改"**（`commands/ship-review.md`）
- 4 个原选项保留（push / PR / keep / discard），第 5 个进 modify 子流程
- 子流程 3 选 1：a) Codex `--resume` 续跑，b) Claude 主线程直接 Edit，c) 退出让用户自己改后回 `/ohaze:ship-finish`
- 改完默认建议再跑一次 review，循环回 finishing 菜单

**新增 `/ohaze:ship-finish` 命令**（`commands/ship-finish.md`）
- 从"保持现状"或"自己改"状态续跑
- 检测未提交改动 → 帮 commit
- 可选再 review (默认 yes)
- 进同款 5 选项 finishing 菜单

**架构决策**：finishing 菜单从 superpowers 收回，由 ohaze 自己实现 5 个选项。这避免了菜单嵌套和"继续修改"在外部 skill 里改不进去的问题。

V1.5 与 V1.1 一起重测，OK 后推 GitHub。

### V1.5 沙盒重测（multiply 函数）

测试任务：`/ohaze:ship 加一个 multiply 函数到 src/math.js，并配上测试`
（详见 `~/Project/ohaze-sandbox/docs/2026-05-08-session-multiply.md`）

**结果：完美通过，零 bug**
- V1.1 4 个 bug 全部修复确认（worktree 真建了、Codex 不再尝试 commit、主线程接 commit、writing-plans 不再卡菜单）
- V1.5 3 个新功能全部 work（status 冷启/中场都对、finishing 5 选项菜单、modify 子流程跑了 2 轮 jsdoc 都成）
- Codex 执行时间 1m1s，比 V1 (1m45s) 提速 40%（不再浪费时间尝试被沙箱拦的 commit）
- ship-finish 被调了 2 次，从 state=kept 都正确恢复

### bash 权限问题最终解决

V1.5 沙盒测试再次出现 codex-rescue subagent bash 权限被拒（走 Path B fallback）。
根因：`~/.claude/settings.json` 的 `permissions.allow` 没有 `Bash(node:*)` 模式。
subagent 没有交互式权限弹框，必须预先放行。

**修复**：在用户 `~/.claude/settings.json` 加 `Bash(node:*)`，下次新 session 起 subagent 直接走 Path A。
**附带改进**：commit `56d7534` — ship.md 强化 `mkdir -p .ohaze` 必须在 Write 之前的指令。

### 推 GitHub 完成

`gh repo create muling-dev/ohaze --public --push` ✅

仓库：https://github.com/muling-dev/ohaze

提交历史（自下而上）：
- `3b23d5e` feat: initial ohaze plugin scaffold
- `7c44c8d` refactor: convert to marketplace+plugin layout
- `99c1ee0` fix(ship): override superpowers:writing-plans built-in handoff prompt
- `2a12806` fix(codex-executor): add direct-Bash fallback when subagent lacks permissions
- `7b2ca33` fix(V1.1): address Codex sandbox commit block + worktree skip
- `81c89b5` feat(V1.5): /ohaze:status + finishing menu modify option + /ohaze:ship-finish
- `56d7534` fix(ship): force mkdir -p .ohaze before Write tool
- `a5de483` docs: update README and CLAUDE.md to reflect V1.5 reality

任何机器现在可装：
```text
/plugin marketplace add muling-dev/ohaze
/plugin install ohaze@ohaze
```

## 2026-05-12
- 完成：vault-adapter.sh 实现（E1/E2/E4/E_pause/E5 全部跑通）
- 完成：ship.md 加 Vault Context 读取步骤（brainstorm 前静默加载项目状态）
- 完成：~/.claude/settings.json 注册全局 hooks（PostToolUse Write + PreToolUse Bash）
- 架构：hooks 代码强约束，LLM 不参与写入决策；adapter 脚本在 ohaze 插件目录
- 待处理：推送更新到 GitHub remote（muling-dev/ohaze）
- 完成：A — ship-review.md 加 Vault Context 读取 + codex-executor review prompt 注入 <vault_context>
- 完成：B — E5 时同步更新 vault README.md（ohaze 完成记录区块 + last_active frontmatter）
- 完成：C — ship-finish.md 加 Vault Context 读取（discussions log + progress.md）
- 待处理：推送更新到 GitHub remote

## 2026-05-15
- 完成：vault-adapter.sh — _handle_verdict（review-verdict.json → discussions 追加审查结论）
- 完成：vault-adapter.sh — _handle_result（ship-result.json → sync state 存储 finishing 选择）
- 完成：vault-adapter.sh — handle_pre_bash E5 全面升级
  - ship_result 读取并注入 decisions ADR（action / branch / PR URL 字段）
  - README marker 修正：ohaze-shipped → shipped-features，section 名 → ## 完成记录
  - ship 真正完成（push/pr/discard）时自动更新源项目 CLAUDE.md 的 - [ ] → - [x]
- 完成：codex-executor/SKILL.md — Phase 5.3：review 后写 review-verdict.json 触发 hook
- 完成：ship-review.md — Options 1/2/4 在 terminal action 前写 ship-result.json
- 完成：ship-finish.md — 明确 ship-result.json 写入时机说明

---

## 2026-05-18 — 版本号规范化（混合 SemVer）

历史的 `V1.0 / V1.1 / V1.5` 主题版本叙事保留；从此之后所有版本号严格按 [SemVer 2.0.0](https://semver.org/lang/zh-CN/) 走。规则录入全局 `~/CLAUDE.md`，所有项目通用。

把 2026-05-12 至 2026-05-18 这 18 个未版本化 commits 归类如下：

---

## 1.6.0 — Vault 集成（2026-05-12 → 2026-05-15）

**主题**：把 ohaze 生命周期事件镜像到 `~/Brain`，让每次 ship 都自动留下 discussions / decisions / progress / README 同步。

### Added
- `adapters/vault-adapter.sh`：736 行的事件路由 + E1/E2/E4/E_pause/E5 完整 lifecycle handlers（`0d1d5f1`）
- `hooks/hooks.json`：PostToolUse Write + PreToolUse Bash 注册在**插件内**，脱离 `~/.claude/settings.json` 全局依赖（`e927dbd`）
- ship.md / ship-review.md / ship-finish.md：brainstorm 与 review 前静默加载 vault context（`4946d86`）
- `_handle_verdict` / `_handle_result`：把 review-verdict.json 与 ship-result.json 同步到 vault（`40b9de0`）
- E5 写 `decisions/<feature>.md` ADR：含 action / branch / PR URL / commits 数量 / 审查重试次数（`40b9de0`）
- E5 同步源项目 CLAUDE.md：用户在 ship.md Step A 选定的 linked_todo 用 Python 字面 replace 打勾（`02802f4`）
- ship.md：brainstorm 阶段读 related 项目 README（cross-project 知识图谱边）（`e166036`）

### Fixed
- 4 个 V2 ship-result chain blocking bug（`f2f08ce`）
- 删除 last_active sed 死代码：vault README 用 `updated` 字段不是 `last_active`（`2f27913`）

### Architecture
- Hook 代码强约束、LLM 不参与写入决策；E5 用 `sync_state.e5_completed` 去重防止双触发

---

## 1.7.0 — Plan 契约化 + Sandbox 升级（2026-05-15 → 2026-05-16）

**主题**：把 Codex 从"打字员"升回"实现者"；review 加设计挑战维度；绕过 codex-companion 的 workspace-write 锁死。

### Added
- `skills/writing-plans/SKILL.md`（305 行）：fork 自 `superpowers:writing-plans`，改为 **guidance-form**（contract + acceptance，不是 prescriptive code）（`defa9a0`）
- "Reading the Spec" 章节：spec→plan 时如何把执行代码转写成契约描述，附转换对照表（`520ad82`）
- ADVERSARIAL review 维度：reviewer subagent 三部分（契约合规 / 代码质量 / 对抗式设计挑战），ADVERSARIAL 仅 advisory 不阻塞 ship（`18dca08`）
- codex-executor 改走 `codex exec --sandbox danger-full-access`，直接派发不经 codex-companion；ship 流程已 brainstorm/plan/review 三重 gate（`535b68c`）

### Changed
- `plan-to-codex-prompt` 改成薄包装：原来要 distill prescriptive code 现在直接 verbatim 嵌入 guidance plan（`64d9994`）

---

## 1.8.0 — Real-ship hardening + Auto-resume（2026-05-16 → 2026-05-18）

**主题**：第一批真实项目跑出来的 bug 收尾；ScheduleWakeup 自续 ship 生命周期，用户不再手动接 Phase 5。

### Added
- `/ohaze:ship` 派发 Codex 后 `ScheduleWakeup(600s, "/ohaze:ship-review")`：自动接 review；review pre-flight 检查 codex pid，还在跑则再 schedule（`794f19f`）
- Finishing 菜单第 6 选项已存在；新增 **Option 1 本地 merge**：`git merge --ff-only`，纯本地仓不开 PR 也能完成 ship（`daba82c`）

### Fixed
- `vault-adapter.sh` 3 个 real-ship blocking bug（`f508cd3`）
- ship.md `.ohaze/` 路径修正 + 明确强制用 Write 工具（不能 heredoc，否则 PostToolUse hook 不触发）（`9bdeeb8`）
- finishing Option 1：merge 前预算 commits 列表注入 `ship_result.commits`，避免 ff-merge 后 worktree `base..HEAD` 空导致 vault decisions 记 "Commits 数量=0"（`b679ee3`）

---

## 待发布动作（pending）

- [ ] `plugin.json` version：`0.1.0` → `1.8.0`
- [ ] `README.md` 路线图：V2 → 1.6/1.7/1.8 全部交付，V3 改 2.0.0 (tool-router) 作为下一目标
- [ ] `CLAUDE.md` 当前目标段：同步到 1.8.0
- [ ] 新建 `CHANGELOG.md`（Keep a Changelog 格式）
- [ ] `git push origin main`（本地 18 commits ahead）
- [ ] `git tag v1.6.0 / v1.7.0 / v1.8.0` 打回历史标签
