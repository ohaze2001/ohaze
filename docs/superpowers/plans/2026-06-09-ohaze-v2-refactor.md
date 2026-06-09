# ohaze v2.0.0 重构 — Guidance Plan

> **For Codex (the executor):** Each Task below specifies WHAT must be true at completion, not HOW to write it line by line. You have autonomy over internal naming, control flow, helper extraction, and algorithm choice. You do NOT have autonomy over public interfaces, file paths in Files lists, acceptance criteria, or cross-Task invariants. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 ohaze 从依赖 superpowers 运行时 + vault 镜像耦合的脆弱三命令链，重构为零运行时外部 skill 依赖、自包含、流程更稳的 v2.0.0 ship 工作流。

**Architecture:** ohaze 是 Claude Code plugin（纯 Markdown skills/commands，AI 顶层编排）。本次重构把它真正用到的 superpowers skill（brainstorming + using-git-worktrees）fork 进自身 `skills/`、整层剥离 vault 镜像（删 hooks + adapter）、内化四件套文档契约（md-init 完备性检查 + neat 落点路由）、修掉 nohup/ScheduleWakeup 幽灵唤醒与 cwd 悬空等已知坑。控制流改为事件驱动：主 agent 用 `Bash(run_in_background)` 派 codex exec，进程退出后 harness 自动 re-invoke，经幂等状态门进 review。设计真相源 = `docs/superpowers/specs/2026-06-09-ohaze-v2-refactor-design.md`（每个 Task 标注对应 spec 章节）。

**Tech Stack:** Claude Code plugin（Markdown commands + skills + `.claude-plugin/plugin.json`）；`codex` CLI 0.137（`codex exec` / `codex exec resume`，`--json` 事件流）；Claude Code harness 能力（`Bash(run_in_background)` + 完成 re-invoke、`BashOutput`、`Agent`、`AskUserQuestion`）。无自动化测试套件 —— 验证靠结构断言（grep / 文件存在性 / JSON 字段）+ 末尾 dogfood 端到端冒烟。

---

## 验证模型（贯穿所有 Task）

这是 Markdown plugin，没有 unit test runner。每个 Task 的 Acceptance 用三类**可检查**断言：

1. **存在性断言**：`test -f` / `test ! -f`（文件被 fork/删除）。
2. **内容断言**：`grep -q <pattern> <file>` 命中或 `! grep -q` 不命中（某约束被写入 / 某过期内容被移除）。
3. **结构断言**：JSON 字段集合、skill frontmatter `name` 匹配目录名。

整体行为正确性由 plan 末尾「集成验证（dogfood）」的端到端 throwaway ship 兜底。每个 Task 的 TDD Sequence 适配为：先写下预期断言（grep/test 命令）→ 改文件 → 跑断言确认通过。

---

## File Structure（重构后 `plugins/ohaze/`）

| 路径 | 动作 | 责任 |
|---|---|---|
| `commands/ship.md` | 重写 | Pre-flight（codex 检查 + 分支安全 + md-init 完备性 + 显式项目路径）→ Phase 1 brainstorm → Phase 2 worktree+写 spec → Phase 3 plan → Phase 4 派 codex（run_in_background）；定义 `current-ship.json` 权威 schema |
| `commands/ship-review.md` | 改造 | 幂等状态门重入 + review 循环 + ADVERSARIAL 提示 + 交 finishing |
| `commands/ship-finish.md` | 改造 | 状态门重入（kept/self-edit-pending）+ 可选 re-review + 交 finishing |
| `commands/status.md` | 改造 | 只读跨 worktree 状态，改读 `state` + `codex_bg_id` |
| `skills/brainstorming/SKILL.md` | 新建（fork） | 文本澄清 → 设计获批（终止于此，不写 spec、不 invoke writing-plans）|
| `skills/using-git-worktrees/SKILL.md` | 新建（fork） | 建 worktree（环境检测）+ teardown（删前 cd 回主仓）|
| `skills/codex-executor/SKILL.md` | 改造 | 派 codex（run_in_background, thread_id 捕获）+ 异源审查（实跑）+ retry（卡住升级, resume 去 sandbox）|
| `skills/finishing/SKILL.md` | 改造 | 6 项菜单（+修复对抗审查）+ doc-finish（内化 neat）+ 收尾链（删 ship-result.json, remove-worktree cd 回主仓）|
| `skills/plan-to-codex-prompt/SKILL.md` | 微调 | 去 vault-adapter 引用 |
| `skills/writing-plans/` | 不动 | 已 fork |
| `.claude-plugin/plugin.json` | 改 | version 2.0.0 + 去 superpowers |
| `hooks/hooks.json` | **删** | vault 剥离 |
| `adapters/vault-adapter.sh` | **删** | vault 剥离 |
| 根 `VAULT-CONTEXT.md` | **删** | vault 剥离 |
| 根 `README.md` / `CLAUDE.md` / `ROADMAP.md` / `CHANGELOG.md` | 改 | 文档对齐（去 vault/五件套，修死链，记 v2.0.0）|

---

### Task 1: vault 剥离 — 删除耦合文件

> Spec §6 / §9。无依赖，先清理，后续 Task 不再引用这些文件。

**Files:**
- Delete: `plugins/ohaze/hooks/hooks.json`
- Delete: `plugins/ohaze/adapters/vault-adapter.sh`
- Delete: `VAULT-CONTEXT.md`（仓库根）

**Behavior Contract:**
- 三个文件从工作树移除。`hooks/` 与 `adapters/` 目录若移除后为空，一并删除空目录。
- 删除后仓库内**不得有任何存活代码路径**仍引用 `vault-adapter.sh` 或 `hooks.json`（这些引用会在 Task 4/6/7/8/9 各自的改造中消除；本 Task 只负责删文件，不负责改引用）。
- `VAULT-CONTEXT.md` 当前工作树有一处未提交的无关 dream 改动 —— 删除即可，无需保留。

**Acceptance Criteria:**
- [ ] `test ! -f plugins/ohaze/hooks/hooks.json`
- [ ] `test ! -f plugins/ohaze/adapters/vault-adapter.sh`
- [ ] `test ! -f VAULT-CONTEXT.md`
- [ ] `git status --short` 显示这三个文件为 deleted（`D`）

**TDD Sequence:**
- [ ] Step 1: 写下三条 `test ! -f` 断言，先跑确认当前为 false（文件还在）
- [ ] Step 2: 删除三个文件（及可能的空目录）
- [ ] Step 3: 跑三条断言确认全部通过
- [ ] Step 4: Commit。Suggested message: `refactor(vault): 删除 hooks/adapter/VAULT-CONTEXT 剥离 vault 镜像`

**Cross-Task Dependencies:**
- Provides: 删除后的干净基线给 Task 4/6/7/8/9（它们移除对这些文件的引用）。

---

### Task 2: fork using-git-worktrees 进 skills/

> Spec §1 / §9。fork 源 = `~/.claude/plugins/cache/claude-plugins-official/superpowers/5.1.0/skills/using-git-worktrees/SKILL.md`（锁 v5.1.0 形态）。

**Files:**
- Create: `plugins/ohaze/skills/using-git-worktrees/SKILL.md`

**Behavior Contract:**
- frontmatter `name: using-git-worktrees`（与目录名一致），`description` 去掉任何 superpowers 字样。
- 保留源的核心：**Step 0 环境检测**（`GIT_DIR != GIT_COMMON` 且非 submodule → 已在 worktree 内，跳过创建）、native-tool 优先、git fallback、目录优先级、`.gitignore` 忽略校验、clean baseline。
- **新增 teardown 章节**「Removing a worktree safely」：删除 worktree 前必须先 `cd "$main_repo_path"`（回主仓），再 `git worktree remove`，再 `git branch -D`。teardown 章节是 finishing `remove-worktree` 步骤的契约来源（Task 9 引用它）。说明根因：在 worktree 内删自身会让 session cwd 悬空，导致后续任意 hook `posix_spawn ENOENT`（CC 上游 #50960）。
- **MIT 署名**：保留 attribution（Jesse Vincent, MIT, https://github.com/obra/superpowers）。
- 锁基线说明：注明「fork 自 superpowers v5.1.0；定期 diff 上游 SKILL.md」一句兜底。

**Acceptance Criteria:**
- [ ] `test -f plugins/ohaze/skills/using-git-worktrees/SKILL.md`
- [ ] `grep -q 'name: using-git-worktrees' SKILL.md` 且 frontmatter name 与目录名一致
- [ ] `grep -q 'cd "\?\$main_repo_path' SKILL.md`（teardown 含删前 cd 回主仓）
- [ ] `grep -qi 'MIT' SKILL.md`（attribution 存在）
- [ ] `! grep -qi 'superpowers:using-git-worktrees' SKILL.md`（无对上游 skill 的运行时调用引用）

**TDD Sequence:**
- [ ] Step 1: 读 fork 源全文，列出要保留 / 要新增（teardown）/ 要去除（superpowers 自指）的清单作为断言
- [ ] Step 2: 写 fork 文件，植入 teardown 章节 + attribution + 锁基线说明
- [ ] Step 3: 跑 Acceptance grep 断言确认通过
- [ ] Step 4: Commit。Suggested message: `feat(skills): fork using-git-worktrees 自持 + teardown cd 回主仓`

**Cross-Task Dependencies:**
- Provides: teardown 契约给 Task 9（finishing remove-worktree）；建 worktree 契约给 Task 6（ship Phase 2 调用）。

---

### Task 3: fork brainstorming 进 skills/（砍 companion，终止于设计获批）

> Spec §1 / §2。fork 源 = `~/.claude/plugins/cache/claude-plugins-official/superpowers/5.1.0/skills/brainstorming/SKILL.md`。

**Files:**
- Create: `plugins/ohaze/skills/brainstorming/SKILL.md`

**Behavior Contract:**
- frontmatter `name: brainstorming`，`description` 去 superpowers 字样、保留「设计前必用」语义。
- 保留核心：HARD-GATE（获批前不进实现）、探索 context、一次一问、提 2-3 方案、分段呈现设计、获批。
- **砍掉 visual companion**：移除 Checklist 第 2 项（Offer visual companion）、Process Flow 图中 visual 节点、整个 `## Visual Companion` 章节、对 `visual-companion.md` 与 `scripts/` 的所有引用。**不 fork** `scripts/`、`visual-companion.md`、`frame-template.html`。
- **改终止状态（关键，配合 §2 流程序）**：fork 版**终止于「设计获批」** —— 移除源 Checklist 第 6 项「Write design doc + commit」与第 9 项「invoke writing-plans」的执行语义。理由：v2 流程序是 Phase 1 brainstorm（主仓纯对话、**不落任何文件**）→ Phase 2 建 worktree → 在 worktree 内写 spec。写 spec 与后续编排由 `ship.md` 负责，不在本 skill 内。fork 版产出 = **获批的设计内容（在对话中确定，供 ship Phase 2 落成 spec 文件）**。
- spec 自审清单（placeholder / 一致性 / scope / 歧义）作为「设计获批前」的口头检查保留，但「写文件」动作不在本 skill。
- 保留 `spec-document-reviewer-prompt.md`？**不 fork**（写 spec 落到 ship Phase 2，self-review 内联即可）。
- **MIT 署名**：保留 attribution（Jesse Vincent, MIT）。

**Acceptance Criteria:**
- [ ] `test -f plugins/ohaze/skills/brainstorming/SKILL.md`
- [ ] `grep -q 'name: brainstorming' SKILL.md`
- [ ] `! grep -qi 'visual companion\|visual-companion\|frame-template\|start-server' SKILL.md`（companion 已砍净）
- [ ] `! test -d plugins/ohaze/skills/brainstorming/scripts`（未 fork scripts）
- [ ] 内容断言：SKILL.md 明确声明「终止于设计获批，不写 spec、不 invoke writing-plans」（grep 命中该语义关键句，如 `不写 spec` 或 `终止于`/`获批`）
- [ ] `grep -qi 'MIT' SKILL.md`（attribution）

**TDD Sequence:**
- [ ] Step 1: 读 fork 源，标出 companion 相关段（删）与终止状态段（改）
- [ ] Step 2: 写 fork 文件，砍 companion、改终止状态、加 attribution
- [ ] Step 3: 跑 Acceptance grep/test 断言
- [ ] Step 4: Commit。Suggested message: `feat(skills): fork brainstorming 砍 companion + 终止于设计获批`

**Cross-Task Dependencies:**
- Provides: 「brainstorm 终止于获批、不落档」契约给 Task 6（ship Phase 1/2 编排：Phase 2 才写 spec）。

---

### Task 4: codex-executor 改造（后台换血 + 异源审查 + retry 升级）

> Spec §3 / §4 / §8 / §10。最大改动面。定义 `thread_id` / `codex_bg_id` 捕获契约与 review-verdict 消费契约。

**Files:**
- Modify: `plugins/ohaze/skills/codex-executor/SKILL.md`

**Behavior Contract:**

*Phase 4 — dispatch（去 nohup）:*
- 派发改为纯 `Bash(run_in_background: true)` 跑 `codex exec --sandbox danger-full-access --cd <worktree_path> --json`，prompt 由 stdin 传入。**禁止 `nohup`、`&`、`> log 2>&1`、`echo $! > pid_file`**（去掉 pid_file/log_file 机制）。
- **thread_id 捕获**：解析 `--json` 输出的**首个** `{"type":"thread.started","thread_id":"<UUID>"}` 事件，取 `thread_id`（字段名就是 `thread_id`，非 session_id）。
- **codex_bg_id 捕获**：记录 `Bash(run_in_background)` 返回的 background task id（取代旧 pid_file/log_file），后续用 `BashOutput` 读输出。
- 两者写回 `.ohaze/current-ship.json`（schema 见 Task 6）。**去掉** `codex_job_id` / `codex_run_id` / `codex_pid_file` / `codex_log_file` / `codex_session_id` / `codex_thread_resume` 字段与对 vault-adapter back-compat 的描述。
- prompt 文件仍用 Write 工具写（避免 shell 转义），但**不再以「触发 hook」为理由**（vault 已剥离）。
- 不再 `ScheduleWakeup` —— 派发后 turn 结束让出，harness 完成即 re-invoke（见 §10）。「What this skill does NOT do」更新：去掉 superpowers 引用与 ScheduleWakeup 轮询描述。

*Phase 5 — review（异源 + 实跑，去 vault）:*
- Phase 5.0 commit 权在主线程：保留（codex 不自 commit）。report 来源改为**从 `--json` message 事件提取**（用 `BashOutput` 读 background 输出末尾的 message 事件），**不依赖 `-o/--output-last-message`**（`--json` 下不产出文件）。
- Phase 5.2 审查 subagent = `Agent(subagent_type="general-purpose")`（继承 Opus，异源对抗写死；禁改 codex 自审 / `codex exec review`）。
- **审查者上下文 = plan + spec + `git diff <base_ref>...HEAD` + codex report（Tasks/Touched files/Notable choices）**。**删除 `<vault_context>` 注入**与对 `~/Brain/.../decisions/` 的读取。
- **实跑验证写进审查 prompt**：审查者必须实跑 `project_test_command` + 关键验证，用真实输出下 verdict，不只读 diff（内化 verification-before-completion）。
- Phase 5.3 写 `review-verdict.json`：schema 见 Task 6。**删除「必须用 Write 工具触发 vault hook」硬约束**与 `_handle_verdict` 描述（用 Write 仍可，但理由改为「结构化、避免转义」）。verdict 含 `issues[]`（CRITICAL/IMPORTANT/ADVERSARIAL 保留前缀，跳过 NIT）+ `doc_drift[]`。
- review prompt 四部分（Contract / Quality / DOC-DRIFT / ADVERSARIAL）保留；DOC-DRIFT 与 ADVERSARIAL 均 advisory 不 gate；FAIL 当且仅当存在 CRITICAL/IMPORTANT。

*Phase 6 — retry（≤3，卡住升级，resume 去 sandbox）:*
- FAIL 且 retry<3：组结构化 fix prompt（每条 issue 带 `file:line` + 违反的契约/验收 + 期望状态 *what* 非 *how*；**ADVERSARIAL 不下发** codex）。
- 派 `codex exec resume <thread_id>`，**命令不带 `--sandbox`**（resume 不支持该参数，继承初始 session 配置）；带 `--cd <worktree_path> --json` 等必要 opts。读 `thread_id`（非 codex_session_id）。
- **防震荡**：第 N 轮 fix prompt 附「前几轮改了什么 + 为何仍 FAIL」。
- **卡住升级（新增，内化 systematic-debugging）**：连续 FAIL 同一类 issue 时，先诊断「plan 问题 vs Codex 执行问题」—— 指向 plan 则回退修 plan、不盲目 resume 到第 3 次；指向执行则继续 resume 或考虑 Claude 介入。
- retry==3 仍 FAIL：停，给用户 3 选项（继续 / 手动 / 接受现状进 finishing），不自动越过 3。
- thread_id 缺失的 fallback：打印 WARNING 后才用 `codex exec resume --last`；exact resume 找不到旧 thread 则 fresh `codex exec` 带「原任务+fix delta」。

**Acceptance Criteria:**
- [ ] `! grep -q 'nohup' codex-executor/SKILL.md`（去 nohup）
- [ ] `! grep -q 'pid_file\|log_file\|codex_session_id\|codex_run_id\|codex_job_id' codex-executor/SKILL.md`（旧字段清净）
- [ ] `grep -q 'run_in_background' SKILL.md` 且 `grep -q 'thread.started' SKILL.md` 且 `grep -q 'thread_id' SKILL.md`
- [ ] `grep -q 'codex_bg_id' SKILL.md`
- [ ] resume 命令段：`grep -q 'codex exec resume' SKILL.md` 且该段**不含** `--sandbox`（结构断言：resume 代码块内无 `--sandbox`）
- [ ] `! grep -q 'vault_context\|vault-adapter\|_handle_verdict\|PostToolUse' SKILL.md`（vault 注入/hook 清净）
- [ ] `grep -qi '实跑\|run.*project_test_command\|verification-before-completion' SKILL.md`（实跑验证写入）
- [ ] `grep -qi '卡住升级\|systematic-debugging\|plan 问题 vs' SKILL.md`（retry 升级写入）
- [ ] `grep -q 'general-purpose' SKILL.md`（异源审查保留）
- [ ] thread_id 缺失 fallback 契约存在（spec §8 点名）：`grep -qi 'resume --last' SKILL.md` 且 `grep -qi 'WARNING' SKILL.md`

**TDD Sequence:**
- [ ] Step 1: 写下上述 grep 断言（含「应消失」与「应出现」两类），跑确认当前状态（旧字段还在）
- [ ] Step 2: 改 Phase 4（run_in_background + thread_id/codex_bg_id 捕获，去 nohup/pid/log）
- [ ] Step 3: 改 Phase 5（去 vault_context、report 从 --json、实跑验证、解除 Write 硬约束）
- [ ] Step 4: 改 Phase 6（resume 去 sandbox、thread_id、卡住升级）+ 清理 NOT-do/failure 段的 superpowers/ScheduleWakeup 引用
- [ ] Step 5: 跑全部 Acceptance 断言
- [ ] Step 6: Commit。Suggested message: `refactor(codex-executor): run_in_background + thread_id + resume 去 sandbox + 异源实跑审查`

**Cross-Task Dependencies:**
- Depends on: Task 1（vault 文件已删）。
- Provides: `thread_id`/`codex_bg_id` 捕获契约给 Task 6/7/10；`review-verdict.json`（含 ADVERSARIAL/doc_drift）给 Task 9（finishing 第 6 项 + doc-finish）；review 模式接口给 Task 7/8。

---

### Task 5: plan-to-codex-prompt 去 vault 引用

> Spec §6。改动最小。

**Files:**
- Modify: `plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md`

**Behavior Contract:**
- `<commit_handling>` 段移除「integrates the commits into the vault-adapter discussions log」对 vault-adapter 的引用，改为中性表述（一致 commit message 风格 + 按文件重叠 split per-Task）。
- 其余 XML 契约（completeness / verification_loop / autonomy / grounding / action_safety / output_report）**不动**。

**Acceptance Criteria:**
- [ ] `! grep -q 'vault-adapter\|vault' plan-to-codex-prompt/SKILL.md`
- [ ] `grep -q '<output_report>' SKILL.md`（其余契约结构未损）

**TDD Sequence:**
- [ ] Step 1: grep 定位 vault-adapter 引用行
- [ ] Step 2: 中性化该行表述
- [ ] Step 3: 跑断言确认 vault 清净 + 契约结构完整
- [ ] Step 4: Commit。Suggested message: `refactor(plan-to-codex-prompt): 去 vault-adapter 引用`

**Cross-Task Dependencies:** 无（独立小改）。

---

### Task 6: ship.md 重写（流程序 + 显式路径 + md-init + run_in_background + current-ship.json 权威 schema）

> Spec §2 / §3 / §5 / §7 / §决策汇总。定义 `current-ship.json` 权威 schema。

**Files:**
- Modify: `plugins/ohaze/commands/ship.md`

**Behavior Contract:**

*Pre-flight:*
- 检查 `codex` CLI（硬依赖，缺则停并提示安装）。**去掉**对 superpowers brainstorming 路径的检查（已 fork）。
- **分支安全**：核对当前分支 == 目标 / 工作区是否干净；不符按全局规约报风险。
- **四件套完备性（内化 md-init）**：在主仓内检测 CLAUDE/README/ROADMAP/CHANGELOG 是否齐，缺则按项目类型补（发行产品全铺 / 工作流仅 CLAUDE），齐则跳过；**仅缺失时触发**（避免打断自动流）。逻辑内化，**不调** hazeflow `/md-init`。
- **显式项目路径参数**锁定目标项目，**不靠 `pwd`/`git rev-parse` detect**（harness 会重置 cwd，dogfood 实证）。
- **删除整个 `## Vault Context` 段**（pre-brainstorm vault read + related 跨项目读）。

*Phase 1 — Brainstorm:*
- 调 `ohaze:brainstorming`（fork，Task 3），主仓内纯对话澄清，**不落任何文件**，终止于设计获批。

*Phase 2 — Worktree + 写 spec（流程序核心）:*
- 调 `ohaze:using-git-worktrees`（fork，Task 2）建 worktree + `cd` 进去。**分支名 = feature 描述（`$ARGUMENTS`）slug**（brainstorm 前即可定），不从 spec 文件名 derive。
- worktree 建好后，把 Phase 1 获批的设计**写成 spec 文件**（`docs/superpowers/specs/<date>-<slug>-design.md`，slug 同分支）并**在 worktree 内 commit**。main 全程不被碰。

*Phase 3 — Plan:* 调 `ohaze:writing-plans`（已 fork），捕获 plan 绝对路径，等用户 'go'。去掉对 superpowers 的负向声明措辞（保留「为何 contract-form」说明即可，不必反复点名 superpowers）。

*Phase 4 — Codex dispatch:*
- 调 `ohaze:plan-to-codex-prompt`（XML）→ 调 `ohaze:codex-executor`（Task 4）派发。
- **去掉 `## Auto-resume` 整段的 `ScheduleWakeup`**（A 方案）：派发后报告 + turn 结束让出，harness 完成即 re-invoke 进 `/ohaze:ship-review`（经状态门）。报告文案去掉 `tail -f log` / `ps pid`，改为「Codex 在后台跑，完成会自动接 review」。`allowed-tools` 去掉 `ScheduleWakeup`。

*current-ship.json 权威 schema（本 Task 定义，全工作流引用）:*
```json
{
  "state": "running",
  "slug": "<feature-slug>",
  "branch": "feat/<slug>",
  "base_ref": "main",
  "worktree_path": "<abs>",
  "main_repo_path": "<abs>",
  "spec_path": "<abs>",
  "plan_path": "<abs>",
  "retries": 0,
  "thread_id": "<codex UUID or null>",
  "codex_bg_id": "<run_in_background task id>",
  "linked_todo": "<exact todo text or null>",
  "project_type": null
}
```
- `state` 枚举：`running` | `codex_done` | `review_fail` | `kept` | `self-edit-pending` | `done` | `discarded`。
- 写 handoff 仍先 `mkdir -p .ohaze` 再 Write（目录不自动建）；但**去掉「必须用 Write 触发 hook」的理由表述**（vault 已剥离，heredoc 亦可，Write 仅为结构化）。`.ohaze/` 加入 `.gitignore`。
- 保留 Step A「linked_todo」交互（doc-finish tick 用）。

**Acceptance Criteria:**
- [ ] `! grep -q 'Vault Context\|~/Brain\|PROJ_DIR\|related' ship.md`（vault 段清净）
- [ ] `! grep -q 'ScheduleWakeup' ship.md` 且 frontmatter `allowed-tools` 不含 ScheduleWakeup
- [ ] `grep -q 'ohaze:brainstorming' ship.md` 且 `grep -q 'ohaze:using-git-worktrees' ship.md`（指向 fork，非 superpowers:）
- [ ] `! grep -q 'superpowers:brainstorming\|superpowers:using-git-worktrees' ship.md`
- [ ] 流程序断言：Phase 1（brainstorm）在 Phase 2（worktree）之前，且写 spec 描述出现在 worktree 建立**之后**（结构断言：spec commit 段落位于 worktree 段落之后）
- [ ] `grep -q 'run_in_background' ship.md`（或经 codex-executor）且 `grep -q 'main_repo_path' ship.md` 且 `grep -q 'thread_id' ship.md`
- [ ] `! grep -q 'codex_pid_file\|codex_log_file\|codex_session_id\|started_at\|codex_run_id\|codex_job_id' ship.md`（旧字段清净）
- [ ] `grep -qi 'md-init\|四件套.*完备\|完备.*四件套' ship.md`（完备性检查内化）
- [ ] `grep -qi '显式.*路径\|不靠 pwd\|不靠.*detect' ship.md`（显式路径参数）

**TDD Sequence:**
- [ ] Step 1: 写下「应消失」（vault/ScheduleWakeup/旧字段/superpowers:）与「应出现」（fork 调用/新字段/md-init/显式路径/流程序）grep 断言
- [ ] Step 2: 删 Vault Context 段 + Auto-resume(ScheduleWakeup) 段
- [ ] Step 3: 改 Pre-flight（codex 检查 + 分支安全 + md-init + 显式路径）
- [ ] Step 4: 改 Phase 1/2（fork 调用 + 流程序 + worktree 内写 spec）+ Phase 4（run_in_background）
- [ ] Step 5: 落定 current-ship.json 权威 schema + 去 hook 理由
- [ ] Step 6: 跑全部断言；Commit。Suggested message: `refactor(ship): 流程序 brainstorm→worktree→spec + 显式路径 + run_in_background + schema 精简`

**Cross-Task Dependencies:**
- Depends on: Task 2（worktree fork）、Task 3（brainstorm fork）、Task 4（codex-executor 接口）。
- Provides: `current-ship.json` 权威 schema（state 机 + 字段集）给 Task 7/8/9/10。

---

### Task 7: ship-review.md 改造（幂等状态门）

> Spec §3 / §10。核心新增 = 幂等状态门，替掉 pid 检查 + ScheduleWakeup 重排。

**Files:**
- Modify: `plugins/ohaze/commands/ship-review.md`

**Behavior Contract:**
- **Pre-flight 幂等状态门**：第一步读 `.ohaze/current-ship.json.state`，按下表动作（这是防幽灵唤醒唯一防线）：

  | state | 动作 |
  |---|---|
  | 不存在 / `done` / `discarded` | 静默 no-op 早退 |
  | `running` | 不动，等 harness re-invoke |
  | `codex_done` | 跑 review |
  | `review_fail` | 进 retry |
  | `kept` / `self-edit-pending` | 提示 `/ohaze:ship-finish` 恢复 |

- **去掉** `codex_pid_file` + `kill -0` 存活检查与 `ScheduleWakeup` 重排逻辑；「是否完成」由 `state` + 必要时 `BashOutput` 读 `codex_bg_id` 判断。`allowed-tools` 去掉 ScheduleWakeup。
- **删除整个 `## Vault Context` 段**（不再注入 vault decisions 给审查）。
- Phase 5-6 调 `ohaze:codex-executor` review 模式，传 `plan_path`/`base_ref`/`worktree_path`/`spec_path`；retry 用 `thread_id`（非 codex_session_id）。
- Phase 6.5 ADVERSARIAL 提示：保留「展示 ADVERSARIAL findings 不加评论」，但指引文案改为指向 **finishing 菜单新增的「修复对抗审查后收尾」第 6 项**（不再说 option 5）。
- Phase 7 传 finishing 上下文：用 `thread_id` 替 `codex_session_id`；`review_verdict_path` 保留。
- Notes/Failure 段：去 superpowers 引用、`5-option` → `6-option`、resume 示例去 `--sandbox`。

**Acceptance Criteria:**
- [ ] `grep -qi '状态门\|current-ship.json.*state\|state.*no-op\|幂等' ship-review.md` 且含 state 表（grep `codex_done` 与 `discarded` 同现）
- [ ] `! grep -q 'ScheduleWakeup\|kill -0\|codex_pid_file' ship-review.md` 且 allowed-tools 无 ScheduleWakeup
- [ ] `! grep -q 'Vault Context\|vault_context\|~/Brain' ship-review.md`
- [ ] `! grep -q 'codex_session_id' ship-review.md` 且 `grep -q 'thread_id' ship-review.md`
- [ ] ADVERSARIAL 指向第 6 项（正向断言）：`grep -q '修复对抗审查' ship-review.md`（不用 `! grep 'option 5'` —— ship-review 可能在非 ADVERSARIAL 上下文合法引用菜单第 5 项「自定义收尾」，会误伤）
- [ ] resume 相关示例不含 `--sandbox`

**TDD Sequence:**
- [ ] Step 1: 写「应消失/应出现」断言
- [ ] Step 2: 加幂等状态门、删 pid/ScheduleWakeup、删 Vault Context
- [ ] Step 3: 改 session_id→thread_id、ADVERSARIAL 指向第 6 项、菜单计数 6
- [ ] Step 4: 跑断言；Commit。Suggested message: `refactor(ship-review): 幂等状态门 + 去 vault/ScheduleWakeup + thread_id`

**Cross-Task Dependencies:**
- Depends on: Task 6（state 机/schema）、Task 4（codex-executor review 接口 + thread_id）、Task 9（finishing 第 6 项）。

---

### Task 8: ship-finish.md 改造（状态门重入 + 去 vault）

> Spec §3 / §6。

**Files:**
- Modify: `plugins/ohaze/commands/ship-finish.md`

**Behavior Contract:**
- Pre-flight 过**幂等状态门**：`kept` / `self-edit-pending` → 正常恢复 finishing；`done` / `discarded` / 不存在 → no-op 提示已 finish。
- **删除整个 `## Vault Context` 段**（discussions/progress 读取）。
- 句柄字段 `codex_session_id` → `thread_id`（Pre-flight parse 与 Phase 7 传参）。
- Step 1（检测未提交改动 / self-edit commit）+ Step 2（可选 re-review，调 codex-executor）保留；re-review 的 resume 不带 `--sandbox`。
- Step 2.5 ADVERSARIAL 提示：保留，文案指向第 6 项。
- `allowed-tools` 去掉 ScheduleWakeup。Notes 去 superpowers 引用。

**Acceptance Criteria:**
- [ ] `! grep -q 'Vault Context\|~/Brain\|discussions\|progress.md' ship-finish.md`
- [ ] `grep -qi '状态门\|state.*kept\|self-edit-pending' ship-finish.md`
- [ ] `! grep -q 'codex_session_id' ship-finish.md` 且 `grep -q 'thread_id' ship-finish.md`
- [ ] `! grep -q 'ScheduleWakeup' ship-finish.md`（含 allowed-tools）

**TDD Sequence:**
- [ ] Step 1: 写断言
- [ ] Step 2: 加状态门、删 Vault Context、session_id→thread_id、去 ScheduleWakeup
- [ ] Step 3: 跑断言；Commit。Suggested message: `refactor(ship-finish): 状态门重入 + 去 vault + thread_id`

**Cross-Task Dependencies:**
- Depends on: Task 6（state 机）、Task 9（finishing）、Task 4（thread_id）。

---

### Task 9: finishing 改造（6 项菜单 + doc-finish 内化 neat + 收尾链去 vault）

> Spec §4 / §5 / §6 / §7 / §9。

**Files:**
- Modify: `plugins/ohaze/skills/finishing/SKILL.md`

**Behavior Contract:**

*菜单 5 → 6 项:*
- 现有 5 项不变：1 执行推荐收尾 / 2 继续修改 / 3 丢弃 / 4 先不处理（state=kept）/ 5 自定义收尾。
- **新增第 6 项「修复对抗审查后收尾」**，**仅当本次 `review-verdict.json` 含 ADVERSARIAL findings 时出现**（无则菜单仍是 5 项）。行为：读 `review-verdict.json` 的 ADVERSARIAL 条目 → `AskUserQuestion` 让用户勾选要修的 → 组 fix prompt → `codex exec resume <thread_id>`（**不带 `--sandbox`**）修 → 跑 `ohaze:codex-executor` Phase 5.0 commit → 询问是否复验（复验不计 retry，因用户发起）→ 修完回菜单或继续收尾链。
- 全文 `five-option` / 「五选项」/ option 计数引用同步为 6（含 modify 子流程 line「five-option finishing menu」、prefs 写回的 option 编号说明）。
- 注：`AskUserQuestion` 单问最多 4 选项的展示约束 —— 6 项菜单沿用现有呈现方式（现状已用 5 项，按现有实现扩到 6；若用分组/多问，保持与现状一致的呈现风格）。

*doc-finish 内化 neat 完整路由:*
- 现有「CHANGELOG `[Unreleased]` + bump manifest version + tick linked_todo + drift 修复（读 review-verdict.doc_drift）」**升级补齐 neat 落点路由**：
  - 待办 / 新想法 → `ROADMAP.md` `## Backlog`
  - 发现的 bug → `ROADMAP.md` `## Bug`
  - 架构 / 约定变更 → `README.md`（人读）+ `CLAUDE.md`（约束）
  - 命令变更 → `README.md`
- **真相源 = spec + plan + Codex report + git diff**（ship 场景 Codex 干活不在对话里，**不套 neat「对话为真相源」**）。
- **边界：止于四件套，绝不碰 vault 决策层**（不向 vault 决策目录写入 —— 措辞避开字面 token，防与 acceptance 自我误伤）。
- 仍合成一个 patch preview，给用户 Accept all / Skip all / Select hunks。

*收尾链去 vault:*
- **删除「Terminal Result Files」整个 `ship-result.json` 机制**（spec §7：删 ship-result.json + .vault-sync-state.json）。终止动作（merge/push/pr/discard）直接：`rm <worktree>/.ohaze/current-ship.json` → teardown worktree。不再写 ship-result.json、不依赖 Write 触发 hook、去掉 A4「hook 需 worktree/handoff 存活」表述。
- `merge` 步骤：**去掉为 vault-adapter 预计算 `PRE_MERGE_COMMITS`/`PRE_MERGE_COUNT` 的逻辑与理由**（spec §9：ff-merge commits=0 坑随 vault 剥离消失）；`--ff-only` 主路径 + ff 失败的 merge-commit/退出二选一保留。
- **`remove-worktree` 删前 `cd "$main_repo_path"` 保留**（spec §9，1.9.2 已修，别回退）；引用 Task 2 fork 的 teardown 契约。

*modify 子流程:*
- 5a Codex 续跑：resume 用 `thread_id`、**命令去 `--sandbox`**；其余保留。menu 计数说明同步 6。

**Acceptance Criteria:**
- [ ] `grep -qi '修复对抗审查\|对抗审查后收尾\|第 6' finishing/SKILL.md`（第 6 项存在）且其触发条件为「有 ADVERSARIAL」（grep `ADVERSARIAL` 与 第6项 同段）
- [ ] `! grep -q 'ship-result.json\|.vault-sync-state\|PRE_MERGE_COMMITS\|PostToolUse' SKILL.md`（vault 收尾机制清净）
- [ ] `! grep -qi 'five-option\|五选项' SKILL.md`（菜单计数已更新）
- [ ] `grep -q 'cd "\?\$main_repo_path' SKILL.md`（remove-worktree cd 回主仓保留）
- [ ] doc-finish 含 neat 路由：`grep -q 'ROADMAP' SKILL.md` 且 `grep -qi 'Backlog' SKILL.md` 且 `grep -qi 'Bug' SKILL.md`
- [ ] 边界声明存在（正向）：`grep -qi '止于四件套\|不碰 vault 决策' SKILL.md`（不用 `! grep 'decisions/'` —— 避免边界解释句自我误伤）
- [ ] modify 5a resume 不含 `--sandbox`；`! grep -q 'codex_session_id' SKILL.md` 且 `grep -q 'thread_id' SKILL.md`

**TDD Sequence:**
- [ ] Step 1: 写「应消失」（ship-result/PRE_MERGE/five-option/session_id/--sandbox）与「应出现」（第6项/neat 路由/cd 主仓/thread_id）断言
- [ ] Step 2: 菜单加第 6 项（conditional）+ 全文计数同步 6
- [ ] Step 3: doc-finish 补 neat 路由 + 边界声明
- [ ] Step 4: 删 ship-result.json 机制 + merge 去 vault 预计算（保留 cd 主仓）
- [ ] Step 5: modify 5a thread_id + 去 sandbox
- [ ] Step 6: 跑断言；Commit。Suggested message: `refactor(finishing): 6 项菜单(+修复对抗审查) + doc-finish 内化 neat + 收尾去 vault`

**Cross-Task Dependencies:**
- Depends on: Task 4（review-verdict ADVERSARIAL/doc_drift + thread_id）、Task 2（teardown 契约）、Task 6（schema）。
- Provides: 第 6 项「修复对抗审查」给 Task 7/8（ADVERSARIAL 提示指向它）。

---

### Task 10: status.md 改造（改读 state + codex_bg_id）

> Spec §7。只读命令，不改副作用。

**Files:**
- Modify: `plugins/ohaze/commands/status.md`

**Behavior Contract:**
- Step 3.2 解析的 handoff 字段改为新 schema：`plan_path` / `retries` / `state` / `codex_bg_id` / `branch` / `slug`；**去掉** `started_at` / `codex_job_id` / `codex_pid_file` / `codex_log_file` / `codex_run_id`。
- Step 3.3 Codex job state：**用 `state` 字段直接判定**（`running`/`codex_done`/`review_fail`/...），不再 `kill -0 pid` + tail log。若需更细活跃度可经 `BashOutput` 读 `codex_bg_id`，但主判据是 `state`。
- Status icon mapping 的「下一步」列去掉 `tail -f <codex_log_file>`，改为状态语义（如 `等审查 → /ohaze:ship-review`）。
- 保留只读语义、worktree 枚举、远端 PR（gh）section。

**Acceptance Criteria:**
- [ ] `! grep -q 'codex_pid_file\|codex_log_file\|kill -0\|codex_job_id\|started_at' status.md`
- [ ] `grep -q 'state' status.md` 且 `grep -q 'codex_bg_id' status.md`
- [ ] `grep -q 'read-only\|只读' status.md`（只读语义保留）

**TDD Sequence:**
- [ ] Step 1: 写断言
- [ ] Step 2: 改字段解析 + state 判定 + icon 下一步文案
- [ ] Step 3: 跑断言；Commit。Suggested message: `refactor(status): 改读 state + codex_bg_id`

**Cross-Task Dependencies:**
- Depends on: Task 6（schema）。

---

### Task 11: plugin.json 版本 + 去 superpowers

> Spec §决策汇总（版本 v2.0.0 + 文档维护）。

**Files:**
- Modify: `plugins/ohaze/.claude-plugin/plugin.json`

**Behavior Contract:**
- `version`: `1.9.2` → `2.0.0`。
- `description`: 去 superpowers 字样，改为自包含描述（如「Personal Claude Code workflow: self-contained brainstorm/plan + Codex execute + Claude adversarial review + finishing」）。
- `keywords`: 移除 `"superpowers"`（保留 workflow/codex/tdd/orchestration）。
- JSON 合法、其余字段（name/author/homepage/repository/license）不动。

**Acceptance Criteria:**
- [ ] `grep -q '"version": "2.0.0"' plugin.json`
- [ ] `! grep -qi 'superpowers' plugin.json`
- [ ] `python3 -c 'import json;json.load(open("plugins/ohaze/.claude-plugin/plugin.json"))'` 无错（JSON 合法）

**TDD Sequence:**
- [ ] Step 1: 写三条断言
- [ ] Step 2: 改 version/description/keywords
- [ ] Step 3: 跑断言（含 JSON 解析）；Commit。Suggested message: `chore(plugin): bump 2.0.0 + 去 superpowers`

**Cross-Task Dependencies:** 无。

---

### Task 12: 文档对齐（四件套：去 vault/五件套 + 修死链 + 记 v2.0.0）

> Spec §6 / §决策汇总（文档维护）。**纠正 spec §6 笔误**：死链实际在**根 `README.md:152`**（非 `plugins/ohaze/README.md`，后者仅 5 行）。

**Files:**
- Modify: `README.md`（根，157 行）
- Modify: `CLAUDE.md`（根，项目级）
- Modify: `ROADMAP.md`（根）
- Modify: `CHANGELOG.md`（根）

**Behavior Contract:**

*README.md:*
- **修死链**：`README.md:152` 行 `5 件套规约真本见 ~/Project/vault-system/docs/5-piece-set-schema.md` —— 删除该死链子句（文件已不存在）。
- 去 vault 镜像描述：`## 相关项目 / 文档` 中 `hazeflow / vault（~/Brain）：ohaze ship 生命周期事件的镜像目标` 改为剥离后表述（或删除该 bullet）。
- superpowers 引用（11 处）：改为「fork 自 superpowers v5.1.0（brainstorming/using-git-worktrees/writing-plans），现自持，零运行时依赖」的口径，不再表述为运行时上游依赖。
- 去「五件套」措辞，统一「四件套」。

*CLAUDE.md（根项目级）:*
- 删 frontmatter 区 `> VAULT-CONTEXT: [./VAULT-CONTEXT.md]` 链接行（文件已删）。
- 集成点段：去 `hooks/hooks.json` + `adapters/vault-adapter.sh` 镜像到 `~/Brain` 的「下游消费」描述；数据契约去 `~/Brain/20_Projects/<proj>/（vault 镜像）`。
- 上游依赖：superpowers 从「运行时依赖」改为「已 fork 自持」；版本号 `1.9.2` → `2.0.0`。

*ROADMAP.md:* 去 2 处 vault 关联表述（当前主线/长期目标若提 vault 镜像则更新为「vault 后续以解耦方式重连」）。

*CHANGELOG.md（铁律：朝过去，保留历史）:*
- **保留**现有 15 处 vault 历史条目（已发生的变更，不可删）。
- **新增** `## [2.0.0] - 2026-06-09` 块，记本次：superpowers 全解耦（fork 子集）/ vault 流程层剥离（删 hooks+adapter+VAULT-CONTEXT）/ 流程序 brainstorm→worktree→spec / run_in_background 替 nohup + 不设 ScheduleWakeup / codex resume 去 sandbox / finishing 6 项菜单 / 四件套文档内化。配一句话主题。
- 与 plugin.json version 一致（2.0.0）。

**Acceptance Criteria:**
- [ ] `! grep -q '5-piece-set-schema\|vault-system/docs' README.md`（死链修掉）
- [ ] `! grep -q '五件套\|5 件套' README.md CLAUDE.md ROADMAP.md`（统一四件套）
- [ ] `! grep -q 'VAULT-CONTEXT' CLAUDE.md`（链接删除）
- [ ] `! grep -q 'vault-adapter\|hooks/hooks.json' CLAUDE.md`（集成点去镜像）
- [ ] `grep -q '## \[2.0.0\]' CHANGELOG.md` 且 `grep -q '2.0.0' CLAUDE.md`（版本一致）
- [ ] CHANGELOG 历史块仍在：`grep -c '## \[' CHANGELOG.md` 数量 ≥ 改前（只增不减）

**TDD Sequence:**
- [ ] Step 1: 写「应消失」（死链/五件套/VAULT-CONTEXT/vault-adapter）与「应出现」（[2.0.0]/四件套口径）断言
- [ ] Step 2: 改 README（死链/vault/superpowers 口径）
- [ ] Step 3: 改 CLAUDE.md（VAULT-CONTEXT 链接/集成点/版本）+ ROADMAP
- [ ] Step 4: CHANGELOG 加 [2.0.0] 块（保留历史）
- [ ] Step 5: 跑断言；Commit。Suggested message: `docs: 四件套对齐 v2.0.0 — 去 vault/五件套 + 修死链 + CHANGELOG 2.0.0`

**Cross-Task Dependencies:**
- Depends on: Task 1（VAULT-CONTEXT 已删）、Task 11（version 2.0.0 对齐）。

---

## 集成验证（dogfood — 非 Task，收尾手动冒烟）

12 个 Task 完成后，在真实 ohaze 仓库跑一次 throwaway ship 端到端冒烟（spec §验证已部分预证），确认链路通：

- [ ] `/ohaze:ship "<一个 throwaway 小需求>"`（显式目标路径）→ Phase 1 brainstorm（不落档）→ Phase 2 建 worktree + worktree 内写 spec（main 干净）→ Phase 3 plan → Phase 4 `run_in_background` 派 codex（无 nohup）。
- [ ] codex 进程退出 → **harness 自动 re-invoke**（无需 ScheduleWakeup）→ 过幂等状态门 → 异源 review（实跑测试）。
- [ ] 构造一次 FAIL → `codex exec resume <thread_id>`（**确认命令无 `--sandbox`、不报错**）→ 复验 PASS。
- [ ] finishing 菜单：无 ADVERSARIAL 时 5 项；有 ADVERSARIAL 时出现第 6 项「修复对抗审查后收尾」。
- [ ] discard 收尾：删 worktree 前 cwd 已 `cd` 回主仓（删除后无 `posix_spawn ENOENT` hook 报错）。
- [ ] 全程 `~/Brain` 无写入、无 hook 触发（vault 已剥离）。

**幽灵唤醒回归检查**：ship 完成后**确认没有遗留的 ScheduleWakeup/cron 在到点二次唤醒**（A 方案不设兜底，根除痛点）。

---

## 备注（交接给执行者）

- 这是 Markdown plugin，**无代码测试**；Acceptance 的 grep/test 断言是主要验收手段，行为正确性靠末尾 dogfood。
- fork 源锁 **superpowers v5.1.0**（`~/.claude/plugins/cache/claude-plugins-official/superpowers/5.1.0/skills/`）。
- 跨 Task 不变量：`current-ship.json` schema 以 **Task 6** 为权威；`thread_id`/`codex_bg_id` 捕获契约以 **Task 4** 为权威；teardown（删前 cd 回主仓）以 **Task 2** 为权威。后续 Task 引用这些，字段名/状态值必须一致。
- commit 权按 ohaze 约定保留在主线程（Codex 不自 commit）；本 plan 每 Task 的「Commit」步由 orchestrator 统一补。
```
