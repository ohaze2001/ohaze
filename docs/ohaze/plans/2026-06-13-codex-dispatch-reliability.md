# codex-dispatch-reliability — Guidance Plan

> **For Codex (the executor):** Each Task below specifies WHAT must be true at completion, not HOW to write it line by line. You have autonomy over internal naming, control flow, helper extraction, and algorithm choice. You do NOT have autonomy over public interfaces, file paths in Files lists, acceptance criteria, or cross-Task invariants. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修 ohaze plugin 内 5 个 codex CLI 调用点偶发卡死（Bug 2 stdin redirect silent crash + Bug 3 dispatch mode 行为不一致），把规约术语澄清 + 调用模板换 prompt-as-arg + < /dev/null + Phase 6 resume 路径加 liveness check 兜底。

**Architecture:** 三层修法。① 调用模板层：顶层 codex exec 改 prompt-as-arg + 关 stdin 彻底消除 stdin redirect crash；resume 路径无法改命令形式，加 30s thread.started liveness check + kill-retry 1 次兜底。② 术语规约层：codex-executor SKILL 新增「Dispatch Mode Vocabulary」段定义 harness background / OS-level background / foreground sync 三类术语 anchor，其他 SKILL cross-reference 不再各自定义，消除「Do NOT run in background」歧义。③ 文档落档层：ROADMAP 移除已修 Bug 2+3 条目；CHANGELOG [Unreleased] Fixed 新增 codex-dispatch-reliability 条目。

**Tech Stack:** Claude Code plugin（Markdown commands + skills + `.claude-plugin/plugin.json`）；codex CLI 0.137（`codex exec` / `codex exec resume`，`--json` 事件流）；Claude Code harness 能力（`Bash(run_in_background)` + 完成 re-invoke、`BashOutput`、`TaskOutput`、`KillBash`、`Agent`、`AskUserQuestion`）。无自动化测试套件 — 验证靠 grep / 文件存在性 / JSON 字段结构断言 + 末尾 dogfood 端到端冒烟。

---

## Verification Model（贯穿所有 Task）

ohaze 是 Markdown plugin，无 unit test runner。Acceptance 用三类**可检查**断言（CLAUDE.md 自报模型）：

1. **存在性断言**：`test -f <path>`（文件存在）
2. **内容断言**：`grep -q '<pattern>' <file>` 命中 / `! grep -q` 不命中
3. **结构断言**：JSON 字段集合、Markdown frontmatter `name` 匹配目录名

TDD Sequence 本地化为「写失败 grep 断言 → 跑确认失败 → 编辑 SKILL/command 让 grep 命中 → 跑确认通过」节奏。

最末 Task（Task 7 dogfood 验证）跑端到端冒烟：手动验证下次 `/ohaze:ship` 调用走的 codex 模板与本 plan 修法一致。

---

## Task 1: spec-to-codex-review/SKILL.md 改造（Bug 2 + Bug 3 主战场）

**Files:**
- Modify: `plugins/ohaze/skills/spec-to-codex-review/SKILL.md`

**Behavior Contract:**
- **Codex Invocation Contract 命令模板**（当前 line 30-49 段）从 `codex exec ... < <prompt_file>` 改成 `codex exec ... "$(cat <prompt_file>)" < /dev/null` 模式：prompt 作为 top-level CLI argument 传入，stdin 显式 redirect 到 /dev/null 关闭
- **line 49 旧歧义规约「Do NOT run in background. Phase 1.6 is synchronous」反转**为术语澄清版本：明确禁止 nohup / OS-level detachment / ScheduleWakeup pattern；明确要求 `Bash(run_in_background: true)` harness background；cross-reference codex-executor SKILL 的 Dispatch Mode Vocabulary anchor
- **新增「Background completion protocol」段**（替换原 SKILL.md:175-185「Output Validation」的 sync 模型假设）。完整协议含 6 步：① 30s dispatch liveness check via `BashOutput(codex_bg_id) filter='thread.started'` → 失败 KillBash + 重 dispatch 1 次 → 二次失败写 codex-output-unparseable stub verdict ② 通过 `TaskOutput(task_id, block=true, timeout=300000)` 阻塞等 codex 完成（harness-native primitive，dogfood-verified 2026-06-13 in this ship's spec audit iter 2/3）③ codex 完成后 `BashOutput(codex_bg_id) filter='"type":"message"'` 抽 final JSON ④ JSON 验证通过 → 写 verdict ⑤ JSON malformed → 走 SKILL.md:187-212 fallback 重试 1 次 ⑥ 返回 caller
- **defensive fallback**：TaskOutput 拒绝或超时时，写临时 handoff `<work_dir>/.ohaze/spec-audit-handoff.json` (字段：`state=spec_audit_running, codex_bg_id, brief_path, spec_path`) + 结束当前 turn + 由 harness re-invoke 接续 — 仅 defensive 路径，dogfood 证明 happy path 可靠

**Acceptance Criteria:**
- [ ] `grep -q '"\$(cat' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` 命中（命令模板用 prompt-as-arg）
- [ ] `grep -q '< /dev/null' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` 命中
- [ ] `! grep -q 'Do NOT run in background' plugins/ohaze/skills/spec-to-codex-review/SKILL.md`（旧歧义规约删除）
- [ ] `grep -q 'TaskOutput' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` 命中
- [ ] `grep -q 'thread.started' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` 命中（liveness check）
- [ ] `grep -q 'spec-audit-handoff' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` 命中（defensive fallback handoff）
- [ ] `grep -q 'Dispatch Mode Vocabulary' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` 命中（cross-ref Task 2 anchor）
- [ ] Interface conformance：Invocation Contract 入参字段不变（brief_path / spec_path / code_refs / project_type / main_repo_path）；side effect 仍为写 `<work_dir>/.ohaze/spec-review-verdict.json`

**TDD Sequence:**
- [ ] Step 1: 写 grep 失败断言（按 Acceptance 列表）
- [ ] Step 2: 跑断言确认 0 命中（修改前 SKILL 仍是旧版）
- [ ] Step 3: 编辑 SKILL.md — 改 Codex Invocation Contract 命令模板 + 替换 line 49 + 新增 Background completion protocol 段
- [ ] Step 4: 跑断言确认全部命中
- [ ] Step 5: 自审 — 「background」「stdin」「synchronous」相关每条行文是否还有歧义
- [ ] Step 6: 暂不 commit（orchestrator 统一 commit per `<commit_handling>`）；suggested message: `fix(spec-to-codex-review): prompt-as-arg + dispatch mode 术语澄清 + background completion protocol`

**Cross-Task Dependencies:**
- 依赖 Task 2 提供 codex-executor SKILL 「Dispatch Mode Vocabulary」段（用于 cross-reference）
- 提供 spec-to-codex-review 新协议供 Task 4 ship.md Phase 1.6 段 cross-reference

---

## Task 2: codex-executor/SKILL.md 改造（Dispatch Mode Vocabulary anchor + Phase 4 + Phase 6）

**Files:**
- Modify: `plugins/ohaze/skills/codex-executor/SKILL.md`

**Behavior Contract:**
- **新增「Dispatch Mode Vocabulary」段**（建议放在 Phase 4 段之前，line 36 之上）作为术语中央 anchor，定义三类术语：
  - **harness background**（允许且必须，除架构反例）：`Bash(run_in_background: true)` — Bash 子进程由 harness 管，main agent 仍拥有任务 id 可 `BashOutput(<id>)` claim 输出；codex 完成后 harness 自动 re-invoke main agent
  - **OS-level background**（禁止）：`nohup codex exec ... &` / `codex exec ... > log 2>&1 &` / `echo $! > pid_file` 等让 codex 脱离 session 在 OS 层 detach 的模式 + 配套 `ScheduleWakeup` 回神，v1 老路径
  - **foreground sync**（仅允许架构反例：finishing 6th-option + modify 2a）：`Bash(...)` 不设 `run_in_background: true`，main agent 阻塞等 codex 返回 — 理由是 finishing skill 必须在前台保持 alive 跨 commit / re-review / finish chain mini-loop
- **Phase 4 Step 2 命令模板**（line 54-61）改 prompt-as-arg + `< /dev/null`：`codex exec ... "$(cat <prompt_file>)" < /dev/null`，dispatch via `Bash(run_in_background: true)`
- **Phase 4 Step 2 Strict rules**（line 63-67）补两条：① stdin MUST be closed via `< /dev/null`（解释 codex 0.137 stdin crash）② dispatch via Bash(run_in_background:true)（cross-ref Dispatch Mode Vocabulary）
- **新增 Phase 4 Step 2.5「Dispatch liveness check」**（在 Step 2 与 Step 3 之间）：dispatch 后立即 BashOutput(codex_bg_id) filter='thread.started' 30s bounded 检查。无 thread.started → KillBash + 重 dispatch 1 次（同 prompt 文件）+ 同样 30s 检查。二次失败 → surface verbatim 警告，**不写 handoff**（避免 dangling running state）。通过 → 进 Step 3 capture thread_id + Step 4 persist
- **Phase 6 retry 命令模板**（line 367-371）保留 `codex exec resume <thread_id> --json < <prompt_file>`（resume 不接受 PROMPT arg 是 codex 0.137 限制） + 在命令后追加 liveness check 段，结构同 Phase 4 Step 2.5：30s thread.started 检查 → 失败 KillBash + 重 dispatch 1 次（同 thread_id 同 prompt 文件） + 同样 30s 检查；二次失败 surface 警告：`WARNING: codex resume dispatch failed liveness check twice; codex 0.137 stdin crash. Suggest /ohaze:ship-review --more or manual resume.` 不自动 retry 超过 1 次
- **改全局 no-poll invariant**（line 99 + line 403-404）：明确「Don't poll **asynchronously for completion**」+ 加例外条款「The ONLY bounded synchronous poll allowed is the 30s dispatch-liveness check immediately after dispatch (Phase 4 initial + Phase 6 retry + spec-to-codex-review Phase 1.6) to detect codex 0.137 stdin silent crash; this is a transport-layer crash detector, not a completion poll」
- **改 SKILL line 65「No nohup, no trailing &」段**：cross-reference Dispatch Mode Vocabulary 而非各自定义

**Acceptance Criteria:**
- [ ] `grep -q 'Dispatch Mode Vocabulary' plugins/ohaze/skills/codex-executor/SKILL.md` 命中（顶层 anchor 段存在）
- [ ] `grep -c 'harness background' plugins/ohaze/skills/codex-executor/SKILL.md` ≥ 2（Vocabulary + 其他段引用）
- [ ] `grep -c 'OS-level background' plugins/ohaze/skills/codex-executor/SKILL.md` ≥ 1
- [ ] `grep -c 'foreground sync' plugins/ohaze/skills/codex-executor/SKILL.md` ≥ 1
- [ ] `grep -q '"\$(cat' plugins/ohaze/skills/codex-executor/SKILL.md` 命中（Phase 4 命令模板 prompt-as-arg）
- [ ] `grep -q '< /dev/null' plugins/ohaze/skills/codex-executor/SKILL.md` 命中
- [ ] `grep -c 'liveness check' plugins/ohaze/skills/codex-executor/SKILL.md` ≥ 2（Phase 4 Step 2.5 + Phase 6 retry + global no-poll invariant 例外说明）
- [ ] `grep -q 'KillBash' plugins/ohaze/skills/codex-executor/SKILL.md` 命中（liveness check kill 步骤）
- [ ] `grep -q 'transport-layer crash detector\|transport-level crash detector' plugins/ohaze/skills/codex-executor/SKILL.md` 命中
- [ ] Interface conformance：Phase 4 dispatch input/output 不变（codex_prompt / worktree_path / project_test_command），新增 codex_bg_id liveness check 不变 dispatch 公共接口

**TDD Sequence:**
- [ ] Step 1: 写 grep 失败断言
- [ ] Step 2: 确认 0 命中
- [ ] Step 3: 编辑 SKILL.md — 新增 Dispatch Mode Vocabulary 段 + 改 Phase 4 Step 2 命令模板 + 加 Step 2.5 + 改 Phase 6 retry + 改 line 99/403-404 invariant + 改 line 65 cross-ref
- [ ] Step 4: 跑断言确认全部通过
- [ ] Step 5: 自审 Phase 4 / Phase 6 dispatch 流程是否一致（命令模板 + liveness check + KillBash + 重试上限）
- [ ] Step 6: orchestrator 统一 commit；suggested message: `fix(codex-executor): Dispatch Mode Vocabulary + Phase 4 命令模板 + Phase 4/6 liveness check + no-poll invariant 例外`

**Cross-Task Dependencies:**
- 提供 Dispatch Mode Vocabulary anchor 供 Task 1 + 3 + 4 cross-reference
- 与 Task 1 (spec-to-codex-review) 协调：spec-to-codex-review 的 Background completion protocol 与 codex-executor 的 Phase 4 Step 2.5 共用同一种 liveness check 形态（30s thread.started bounded check + KillBash + 重 dispatch 1 次）

---

## Task 3: finishing/SKILL.md 改造（6th-option + modify 2a 文档兜底）

**Files:**
- Modify: `plugins/ohaze/skills/finishing/SKILL.md`

**Behavior Contract:**
- **6th-option mini-loop 命令块后**（当前 line 149-154 命令块后）追加 NOTE 段：解释「codex exec resume 不接受 PROMPT arg → 必须 stdin redirect → 这是 codex 0.137 stdin crash 风险面 → 因为 finishing skill 架构必须 foreground sync 跨 mini-loop → 撞 crash 时主线程阻塞」+ 用户救场步骤：`tail -f <output-file>` 检查 30s 内是否 0 bytes → ctrl-c kill → 回 finishing menu 重选第 6 项（idempotent）→ 重试通常成功
- **modify 2a 命令块后**（当前 line 400-413 命令块后）追加 NOTE 段：同 6th-option，但场景文字改为「修改 spec/plan 后重跑 codex」
- **Failure modes 段**（line 454 附近）新增 "Foreground codex resume hits stdin silent crash" 条目：症状 + recovery 步骤 + cross-ref per-section NOTE
- 架构约束保留：6th-option + modify 2a 仍走 foreground sync + tee（架构必要，不是失误）。cross-ref Dispatch Mode Vocabulary 中「foreground sync」类别

**Acceptance Criteria:**
- [ ] `grep -c 'stdin silent crash' plugins/ohaze/skills/finishing/SKILL.md` ≥ 2（6th-option NOTE + modify 2a NOTE + Failure modes 条目）
- [ ] `grep -c 'Ctrl-C\|ctrl-c' plugins/ohaze/skills/finishing/SKILL.md` ≥ 2（救场步骤）
- [ ] `grep -c 'codex 0.137' plugins/ohaze/skills/finishing/SKILL.md` ≥ 2
- [ ] `grep -q 'foreground sync\|Dispatch Mode Vocabulary' plugins/ohaze/skills/finishing/SKILL.md` 命中（cross-ref Task 2 anchor）
- [ ] Interface conformance：6th-option + modify 2a 公共 contract 不变（command shape / tee 文件路径 / 后续 Phase 5.0 commit handoff）

**TDD Sequence:**
- [ ] Step 1: 写 grep 失败断言
- [ ] Step 2: 确认 0 命中
- [ ] Step 3: 编辑 SKILL.md — 6th-option + modify 2a 命令块后追加 NOTE + Failure modes 新增条目 + cross-ref Dispatch Mode Vocabulary
- [ ] Step 4: 跑断言确认通过
- [ ] Step 5: 自审 NOTE 用语是否给到 「30s 检查 tee 文件 0 bytes」「ctrl-c」「回 menu 重选」三个可执行救场动作
- [ ] Step 6: orchestrator 统一 commit；suggested message: `fix(finishing): 6th-option + modify 2a 加 codex stdin crash 用户救场 NOTE`

**Cross-Task Dependencies:**
- 依赖 Task 2 提供 Dispatch Mode Vocabulary anchor（用于 cross-reference foreground sync 类别）

---

## Task 4: ship.md / ship-review.md / ship-finish.md frontmatter 补 KillBash + TaskOutput

**Files:**
- Modify: `plugins/ohaze/commands/ship.md`
- Modify: `plugins/ohaze/commands/ship-review.md`
- Modify: `plugins/ohaze/commands/ship-finish.md`

**Behavior Contract:**
- **三个命令的 frontmatter allowed-tools** 加 `KillBash, TaskOutput`（运行时工具授权前置）
  - 当前三个命令都是 `allowed-tools: Bash, BashOutput, Read, Write, Edit, Skill, Agent, AskUserQuestion`
  - 改为 `allowed-tools: Bash, BashOutput, KillBash, TaskOutput, Read, Write, Edit, Skill, Agent, AskUserQuestion`
- **ship.md Phase 4 段**（line 163-189）补一行 cross-reference codex-executor Dispatch Mode Vocabulary（Task 2 anchor），不改 phase 主体结构
- **ship-review.md / ship-finish.md**：现有「v2 control flow = `run_in_background` + harness re-invoke + idempotent state gate」措辞保留正确；补 cross-reference 链到 codex-executor Dispatch Mode Vocabulary anchor

**Acceptance Criteria:**
- [ ] `grep -q '^allowed-tools:.*KillBash' plugins/ohaze/commands/ship.md` 命中
- [ ] `grep -q '^allowed-tools:.*KillBash' plugins/ohaze/commands/ship-review.md` 命中
- [ ] `grep -q '^allowed-tools:.*KillBash' plugins/ohaze/commands/ship-finish.md` 命中
- [ ] `grep -q '^allowed-tools:.*TaskOutput' plugins/ohaze/commands/ship.md` 命中
- [ ] `grep -q '^allowed-tools:.*TaskOutput' plugins/ohaze/commands/ship-review.md` 命中
- [ ] `grep -q '^allowed-tools:.*TaskOutput' plugins/ohaze/commands/ship-finish.md` 命中
- [ ] `grep -c 'Dispatch Mode Vocabulary' plugins/ohaze/commands/ plugins/ohaze/skills/` ≥ 4（Task 2 定义 + Task 1 / Task 3 / Task 4 / Task 5 cross-ref 中至少 4 个文件命中）
- [ ] frontmatter 其他字段（description / argument-hint）不变
- [ ] Interface conformance：三个 command argument-hint 和 description 不变

**TDD Sequence:**
- [ ] Step 1: 写 grep 失败断言
- [ ] Step 2: 确认 0 命中（修改前 frontmatter 仍是旧版）
- [ ] Step 3: 编辑三个 command frontmatter 加 `KillBash, TaskOutput` + ship.md Phase 4 段补 cross-ref + ship-review.md / ship-finish.md 补 cross-ref
- [ ] Step 4: 跑断言确认通过
- [ ] Step 5: 自审 frontmatter YAML 语法是否还合规
- [ ] Step 6: orchestrator 统一 commit；suggested message: `fix(commands): frontmatter 补 KillBash + TaskOutput allowed-tools + cross-ref Dispatch Mode Vocabulary`

**Cross-Task Dependencies:**
- 依赖 Task 2 提供 Dispatch Mode Vocabulary anchor
- 依赖 Task 1 + Task 2 + Task 3 实施完成（KillBash + TaskOutput 是给 Phase 1.6 / Phase 4 / Phase 6 retry 用的，frontmatter 补全保证运行时调用不被 deny）

---

## Task 5: plan-to-codex-prompt/SKILL.md 同步去 pipe 描述

**Files:**
- Modify: `plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md`

**Behavior Contract:**
- **line 8 description 段**：「piped into codex exec」改为新模式描述 — 「passed as the top-level prompt argument to codex exec by ohaze:codex-executor (prompt 写到文件用作 structural safety，codex-executor cats the file content into the CLI argument 并 closes stdin with `< /dev/null`)」
- **line 26 Output contract 段**：「ready to be written to a prompt file and piped into codex exec」改为 — 「ready to be written to a prompt file. ohaze:codex-executor then passes the file content as the top-level codex exec prompt argument while closing stdin (`< /dev/null`)」
- **line 113 Notes 段**：「pipes it into codex exec」改为 — 「passes the file content as the top-level prompt argument to codex exec ... running in the background (`Bash(run_in_background: true)`), with stdin redirected to /dev/null to avoid codex 0.137 stdin silent crash. See codex-executor Phase 4 Step 2 for the exact dispatch command.」

**Acceptance Criteria:**
- [ ] `! grep -qE 'pipe[ds]?\s+into|pipes?\s+it\s+into' plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md`（所有 "piped/pipes into" 措辞清理完毕）
- [ ] `grep -c 'top-level prompt argument' plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md` ≥ 2
- [ ] `grep -q '< /dev/null' plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md` 命中
- [ ] `grep -q 'codex 0.137' plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md` 命中（引用解释为何不 pipe）
- [ ] Interface conformance：output contract 入参字段不变（plan_path / project_test_command）；output 仍为 XML prompt string，prompt 内部结构（task / completeness_contract / commit_handling / verification_loop 等）不变

**TDD Sequence:**
- [ ] Step 1: 写 grep 失败断言
- [ ] Step 2: 确认 0 命中（旧措辞「piped into codex exec」仍存在）
- [ ] Step 3: 编辑 SKILL.md — 改 line 8 + line 26 + line 113 三处措辞
- [ ] Step 4: 跑断言确认通过
- [ ] Step 5: 自审是否有其他段落仍说 pipe（grep 整文件 "pipe" 关键词）
- [ ] Step 6: orchestrator 统一 commit；suggested message: `fix(plan-to-codex-prompt): 描述去 pipe + 改为 top-level prompt argument`

**Cross-Task Dependencies:**
- 与 Task 2 codex-executor Phase 4 命令模板一致（plan-to-codex-prompt 生成的 prompt 由 codex-executor 用 prompt-as-arg + < /dev/null 模式 dispatch，两者契合）

---

## Task 6: ROADMAP / CHANGELOG 落档（worktree 内）

**Files:**
- Modify: `ROADMAP.md`
- Modify: `CHANGELOG.md`

**Behavior Contract:**
- **ROADMAP `## Bug` 段** 移除两条已修条目：
  - 原「codex exec --json + stdin redirect 偶发 silent crash 卡死」+ 配套「影响的 skill 命令模板」「修法落地」「实战预案文档」子项 → 全部移除（本 ship 已修）
  - 「spec-to-codex-review Phase 1.6 dispatch mode 行为不一致」→ 移除（本 ship 已修）
  - 保留 ROADMAP 其他段（当前主线 / Backlog / 长期目标 / In-flight / Cancelled）原样
- **CHANGELOG `## [Unreleased]` `### Fixed` 段** 新增条目（用产品语言描述本 ship 修法 5 点 + spec audit iter 历史）。文字应包含：「Codex dispatch reliability hardening」+ Bug 2 + Bug 3 简述 + 修法 5 点（顶层 codex prompt-as-arg / Phase 6 retry liveness / 6th-option + modify 2a NOTE / Dispatch Mode Vocabulary anchor / SKILL:49 反转）+ spec audit iter 历史（iter 1 修 4 / iter 2 修 3 / iter 3 最小 fix #1 + accept）

**Acceptance Criteria:**
- [ ] `! grep -q 'codex exec --json' ROADMAP.md` 在 `## Bug` 段（旧 Bug 2 条目移除）
- [ ] `! grep -q 'dispatch mode 行为不一致\|dispatch mode 不一致' ROADMAP.md` 在 `## Bug` 段（旧 Bug 3 条目移除）
- [ ] `grep -q 'Codex dispatch reliability hardening\|codex-dispatch-reliability' CHANGELOG.md` 命中 `[Unreleased] ### Fixed` 段
- [ ] CHANGELOG `[Unreleased] ### Fixed` 段新增条目长度 ≥ 200 字（保证摘要充分）
- [ ] ROADMAP 其他段（当前主线 / Backlog / 长期目标）行数不变（用 wc -l + 段头 grep 验证）

**TDD Sequence:**
- [ ] Step 1: 写 grep 失败断言（"Bug 2 + Bug 3 字符串在 ROADMAP 里" + "本 ship 条目不在 CHANGELOG"）
- [ ] Step 2: 确认 ROADMAP 段命中、CHANGELOG 段不命中（修改前状态）
- [ ] Step 3: 编辑 ROADMAP `## Bug` 段移除两条 + 编辑 CHANGELOG `## [Unreleased] ### Fixed` 段新增条目
- [ ] Step 4: 跑断言确认 ROADMAP 段不命中 + CHANGELOG 段命中
- [ ] Step 5: 自审 ROADMAP 其他段（Backlog / 当前主线）是否完整保留
- [ ] Step 6: orchestrator 统一 commit；suggested message: `docs(roadmap+changelog): 落档 codex-dispatch-reliability — 移除已修 Bug 2+3 + Unreleased Fixed 新增条目`

**Cross-Task Dependencies:**
- 依赖 Task 1-5 实施完成（已修才能落档为「Fixed」）

---

## Task 7: Dogfood 端到端冒烟（手动验证）

**Files:**
- Read-only verification（不修改任何文件）

**Behavior Contract:**
- 跑端到端 grep 全 acceptance（汇总 Task 1-6 全部 acceptance criteria 跑一遍）
- 检查全局 grep `nohup\|ScheduleWakeup` 在 plugin 内每条引用是否明确属于「OS-level background (forbidden)」或在合理上下文（如 codex-executor Strict rules 段标禁止用）
- 检查全局 grep `background` 是否每条引用都能从上下文判断属于 harness background / OS-level background / foreground sync 三类之一（无歧义）

**Acceptance Criteria:**
- [ ] Task 1-6 acceptance 全部通过（汇总报告）
- [ ] 全 plugin grep `nohup` 每条都在禁止规约或注释中
- [ ] 全 plugin grep `background` 每条都可追溯到 Dispatch Mode Vocabulary 三类之一
- [ ] 报告：Touched files 列表 + 关键 grep 结果摘要

**TDD Sequence:**
- [ ] Step 1: 跑 Task 1-6 全部 acceptance grep 一遍
- [ ] Step 2: 跑全局 `nohup\|background\|ScheduleWakeup` grep 检查歧义
- [ ] Step 3: 报告（无新代码改动；validation only）
- [ ] Step 4: 不 commit（无文件变化）；orchestrator 在最终汇总报告中包含 Task 7 结果

**Cross-Task Dependencies:**
- 依赖 Task 1-6 全部实施完成

---

## 控制流与 dogfood verification

- 本次 ship 自己跑 Phase 1.6 spec audit 时 codex 应走 `Bash(run_in_background: true)` 模式（已验证 — iter 1/2/3 三次 audit 都走 background 跑通）
- 本次 ship Phase 4 codex initial dispatch 应跑 prompt-as-arg + `< /dev/null` 命令模式（这是 Codex 实施 Task 2 后的目标状态；本次 ship 的 Phase 4 dispatch 走的是**修改前的** codex-executor SKILL，所以会用 stdin redirect，撞 stdin crash 概率非零）
- 如果本次 ship Phase 4 期间撞到 codex stdin crash：Codex 实施失败 → 我们走 review fail 路径 → Phase 6 retry 用 background mode，可触发自实施的 liveness check（如果 Task 2 已完成）

## Notes for Codex implementer

- 所有 grep 断言以 worktree root 为 cwd 跑（即 `/Users/apple/Project/ohaze/.worktrees/codex-dispatch-reliability/`）
- 不要创建新的 SKILL 或 command 文件（只 Modify 现有的）
- 不要修改 `.claude-plugin/plugin.json` 或 `plugin.json` 中版本号（这次是 Unreleased 状态，发版交后续 ship 处理）
- 6 个 Task 之间可以并行执行（除明确 cross-task dep）；Task 2 应优先完成（其他 Task cross-ref Dispatch Mode Vocabulary）
- Task 7 dogfood 验证最后跑一次（汇总所有 acceptance）
