# Changelog

本项目所有显著变更都记录在本文件。

格式遵循 [Keep a Changelog 1.1.0](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [SemVer 2.0.0](https://semver.org/lang/zh-CN/)。

> **历史叙事说明**：`V1.0 / V1.1 / V1.5` 是项目早期的主题版本叙事，保留不重写。从 **1.6.0** 起严格按 SemVer 标。

---

## [Unreleased]

### Added

### Changed

### Fixed
- **Codex dispatch reliability hardening / codex-dispatch-reliability**：修复 Bug 2（`codex exec --json` 配合 stdin redirect 偶发 silent crash，导致 thread.started 永不到来、后台任务或前台 sync 卡住）和 Bug 3（`spec-to-codex-review` Phase 1.6 dispatch mode 规约不一致，旧 SKILL:49 写成禁止 background，放大 stdin crash 伤害面）。本次修法包含 5 点：① 顶层 `codex exec` 改为 prompt-as-arg，并用 `< /dev/null` 关闭 stdin；② Phase 6 retry 的 `codex exec resume` 因 codex 0.137 不接受 PROMPT arg，保留 stdin redirect 但新增 30s `thread.started` liveness check、KillBash、同 prompt 重试 1 次；③ finishing 6th-option + modify 2a 保持必要 foreground sync + tee，同时补 stdin silent crash NOTE 和 Ctrl-C / 重选菜单救场步骤；④ `codex-executor` 新增 Dispatch Mode Vocabulary anchor，统一区分 harness background、禁止的 OS-level background、以及仅 finishing 例外的 foreground sync；⑤ `spec-to-codex-review` 反转旧 SKILL:49 语义，明确要求 `Bash(run_in_background: true)` harness background，并用 TaskOutput 完成协议兜底。spec audit 历史一并落档：iter 1 修 4，iter 2 修 3，iter 3 最小 fix #1 后 accept。
- **brainstorming → ship Phase 2 hand-off 卡死（dogfood 实测）**：`brainstorming/SKILL.md` 终止协议写 "Then STOP"，LLM 把它当对话默认意（end of turn = 等用户），在 "Design approved" 之后停下来不进 Phase 2a，要 haze 戳「卡住了？」才回神。根因是 ohaze fork 把上游 brainstorming 的「自己钻进下一个 skill」改成「declare approved + hand back to caller」时，hand-off 的「立即返回 + 同 turn 继续」语义没有显式协议化。修复：`brainstorming/SKILL.md` 终止段加「return-from-subroutine signal, NOT end-of-turn signal」明文 + `commands/ship.md` Phase 1 末尾加 Phase 1→2 hand-off invariant。
- **Phase 1 brief approval gate 缺失（2026-06-13 dogfood 观察 — main agent 偶发自动 declare brief approved 直接进 Phase 1.5，跳过 haze 拍板）**：`brainstorming/SKILL.md` 整段假设 `brief approved` 是一个状态，但全文从未定义触发条件——既没说 haze 必须显式说同意词，也没禁止 main agent 自己 declare。结果 main agent 偶尔判断「brief template 填完了」就直接 hand-off。修复：① `brainstorming/SKILL.md` 新增「Brief Approval Gate (BLOCKING)」段（位于「Approval And Self-Review」前），明确 explicit assent 触发词白名单、明确 forbidden self-declaration、明确 fail-safe（找不到 haze explicit assent 消息 = NOT in terminal state） ② SKILL.md「Approval And Self-Review」第一句加「explicitly」修饰 ③ SKILL.md「Terminal State」段加 fail-safe 提醒 ④ `commands/ship.md` Phase 1 在 hand-off invariant 之前加独立「Phase 1 BLOCKING gate」blockquote，强调 gate 是 haze 信号不是 main agent 判断、gate 是 BLOCKING vs hand-off 是 NON-BLOCKING 两者独立。

### Removed

### Planned
- **未来某版** — tool-router（按任务复杂度自动路由 Codex / Claude / Gemini / DeepSeek，从 v1.x Planned 顺延，待 v2 稳定后重启评估）

### Backlog

---

## [2.1.0] - 2026-06-10

v2.1 主题:把 haze 从 spec/plan/技术 finding 视野中拿掉。

### Added
- **BDD-flavored Phase 1**（spec §Phase 1；`feat(brainstorming): BDD-flavored Phase 1`）：brainstorming 改成 pain / reframe / user / visible outcome / out-of-scope / capability / scope 4-modes，终态为 brief approved。
- **Phase 1.5 auto-spec**（spec §Phase 1.5；`feat(ship): Phase 1.5 spec 自动写`）：Claude mandatory code-reading 后自动从 brief 写 spec，并把关键技术方向回填 brief。
- **Phase 1.6 `spec-to-codex-review`**（spec §Phase 1.6；`feat(spec-to-codex-review): 新 skill 封装 Codex 反向审 spec XML prompt`）：Codex 用 fresh `codex exec` 异源审 spec，输出 `.ohaze/spec-review-verdict.json`。
- **Phase 3.5 default-go**（spec §Phase 3.5；`feat(ship): Phase 3.5 default-go`）：plan 只给一行摘要，默认继续进 Codex 实现，保留打断能力。
- **Phase 7 Security Review**（spec §Phase 7；`feat(finishing): 7th 安全审查`）：web/API 或外部输入场景可选 OWASP Top 10 + STRIDE 审查，confidence ≥ 8 且必须有 concrete exploit scenario。

### Changed
- **Phase 6 retry prompt 加 `<investigate_first>`**（spec §Phase 6；`feat(codex-executor): investigate_first`）：Codex retry 改代码前必须先写根因诊断，和主线程 stuck-detection 叠加。
- **Reviewer finding schema 增加 `user_impact_description`**（spec §审查输出产品语言翻译机制；`feat(codex-executor): user_impact`）：CRITICAL/IMPORTANT 仍自动修，ADVERSARIAL 只展示产品语言影响，纯技术细节默认 skip。
- **`.ohaze/findings-detail.json` 持久化**（spec §持久化；`feat(codex-executor): findings-detail.json`）：保存 evidence / technical_description / user_impact_description / shown_to_user / auto_handled，供 finishing 与 ship-review 读取。
- **ROADMAP 当前主线切换到 v2.1.0**：v2.0 dogfood / release-prep completion 从 active roadmap 移到 changelog 历史，当前主线只追踪 BDD/TDD restructure。
- **Phase 3.5 真正的可打断窗口**（reviewer ADVERSARIAL；`fix(ship): Phase 3.5 真正的可打断窗口`）：原 design 同 turn dispatch 让"可打断"成空话；改为 plan 摘要后 2-option `AskUserQuestion`（go / 打断，Recommended go），单 keystroke 保留 vibe coding 的同时让打断窗口真实存在。

### Migrated
- **Path convention**（spec §涉及文件改动清单；`chore(release): v2.1.0`）：新产物路径统一迁移到 `docs/ohaze/{briefs,specs,plans}`。

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
- **`codex exec resume` 错误带 `--sandbox`**：原 `codex-executor` 第 280 行残留 v1 实现 bug，v2 全面修复（含 retry / modify 2a / 第 6 项 ADVERSARIAL 修复）
- **资源浪费的 ScheduleWakeup 二次唤醒**：v1 完成后未取消 ScheduleWakeup 仍到点执行（haze 提报）；v2 不设兜底唤醒，幂等状态门吃掉任何重入，从源头杜绝

#### Release-prep fixes（两轮 `/code-review high` → 19 findings 全修，未 tag/release 前折叠进本块）

**第一轮（10 findings, F1–F10）**
- **F1 状态门死锁**：`ship-review.md` 缺 `state=running → codex_done` 的 liveness 检测转换，harness re-invoke 后会无限循环卡 `running`。补 Step 3a「liveness-detect-and-transition」契约（含 race-window tiebreaker）
- **F2/F3/F4 resume 命令体 + 前台 fallback**：`codex exec resume` 残留 `--cd`（codex 0.137 不支持）、`codex_bg_id` 未持久化、`run_in_background:false` 路径无前台执行入口。统一去 `--cd`、Read-modify-Write 落 bg_id、补 foreground tee 落 `codex_report_source`
- **F5 `/exit` 安全承诺**：`ship.md` 错误声称「保存进度后可 `/exit`」，但 stdin 关闭后 codex 子进程会被 SIGHUP。删该虚假承诺
- **F6 `allowed-tools` 缺 `BashOutput`**：`ship.md` / `ship-review.md` / `ship-finish.md` / `status.md` 四个 command frontmatter 都未声明 `BashOutput`，运行时会被拒
- **F7 modify 子流程编号**：原文里 `5a/5b/5c` 错位（实际是 modify 子项，不是 Phase 5），全仓改 `2a/2b/2c`
- **F8 `linked_todo` 落点**：原写进 CHANGELOG/CLAUDE.md，违反全局四件套契约。改写进 `ROADMAP.md ## 当前主线`
- **F9 doc-finish 真相源 fallback**：`finishing` 找不到主真相源（spec / plan）时无 fallback，会卡死。补「按 git diff 推断」兜底路径
- **F10 `codex-executor` Inputs 段缺 `spec_path` / `mode`**：契约级遗漏，调用方传了但 skill 文档没声明。补全 Inputs 表 + 分支契约

**第二轮（9 findings, R1–R9）**
- **R1 callers 未显式传 `mode=`**：`ship.md` / `ship-review.md` / `ship-finish.md` 三个 caller invoke `codex-executor` 时未显式传 `mode`，缺省 fallback 会把 review 当作 dispatch 重跑 codex。三处全部补 `mode='dispatch'` / `mode='review'`
- **R2 foreground `codex_bg_id` 失效路径**：前台 codex 跑完后 `codex_bg_id` 还指向已结束的 task，`finishing` / `codex-executor` 后续步骤 `BashOutput` 会拉空。改读 `codex_report_source` 文件兜底
- **R3 `BashOutput` OOM 风险**：codex `--json` 流多小时跑可达 5-20MB，无 `filter` 会爆 context。所有 `BashOutput` 调用强制带 `filter='"type":"(message|error)"|panic|fatal|unhandled'`
- **R4 残留 `--cd`**：codex-executor 文档某处仍写 `codex exec resume --cd`，删除
- **R5 Class 1 `linked_todo` no-match**：doc-finish Class 1 用 grep 找不到 `linked_todo` 时静默跳过，应 WARNING 提示「ROADMAP 条目缺失或已被人工删除」
- **R6 `current-ship.json` Write 协议**：多个并发写点未约定「Read full → preserve all fields → Write with overrides」，存在覆盖 race。`ship.md` 加 `## Write Protocol` 章节，所有写点引用
- **R7 race-window tiebreaker**：F1 修的 liveness 转换缺 codex「emit-final-then-exit」窗口处理（最终 `message` 已 emit 但进程未 exit），补 sleep 2s + 重查的 tiebreaker 分支
- **R8 `codex_done` 双写**：状态门和 codex-executor Phase 5.0 都会写 `codex_done`，幂等但语义混乱。统一在 `ship-review.md` Step 3a 写一次
- **R9 menu 2a 漏改**：F7 重命名时 `finishing` 第 2a 项 modify 子流程文档某处遗漏，补改

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
