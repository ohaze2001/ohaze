# debug-command — Implementation Spec

> 给 Codex 看。brief 在 .ohaze/brief-draft.md(或 docs/ohaze/briefs/2026-06-15-debug-command-brief.md)给 haze 看。

## Context & Goal

### 问题

ohaze v2.1.x dogfood 中 haze 反复观察到一个错位:**修 bug 时下意识打 `/ohaze:ship`**,然后被迫走完整 7-phase feature-dev 流程。结果:

- 让 bug 写 BDD 用户场景(bug 哪有 happy path)
- 让 spec audit 反审"修复路径"(audit 在审方案不在审根因诊断)
- Codex 拿 plan 一次性端到端执行(但 bug 修复需要"先找原因再决定怎么改",plan 还没出根因就 lock)
- 没有 "修一个 bug 不冒出另一个" 的物理约束(LLM 容易"顺手改一下"扩成多点重构)

历史证据(CHANGELOG):
- v1.9.2 cwd 悬空 fix:首猜"worktree remove 问题",二猜才"cwd 悬空"(**2-strike**)
- v2.1.1 codex dispatch silent crash:首猜"codex bug",二猜"stdin 关闭",三猜"stdin redirect + 0.137 silent crash"(**3-strike 边界**)
- v2.1.1 codex-dispatch-reliability fix 涉及 5+ 文件(ship.md / ship-review.md / ship-finish.md / codex-executor / spec-to-codex-review),典型 blast-radius 候选

### 目标

新增 `/ohaze:debug` 命令,跟 `/ohaze:ship` 平级独立的"应对修复"档位:
- 共用 ship 的成熟元素(worktree、cross-source review、finishing 合并)
- 砍掉 feature-dev 专属 phase(BDD brainstorm、spec audit、plan)
- 引入 systematic-debugging 4 阶段(root cause → pattern → hypothesis → implementation)
- 加入 3 个 conditional gate(G1 根因偏离 / G2 3-strike / G3 blast-radius)
- 加入物理约束 scope lock(hypothesis 形成后冻结可编辑文件)

同时在 `/ohaze:ship` 埋点 2 处 reframe 兜底,捕捉"打错命令"场景。

### 修法思路

1. 新 command `commands/debug.md` 编排 debug 完整流程,跟 ship.md 平级
2. 新 skill `skills/systematic-debugging/`(fork superpowers v5.1.0 + ohaze 改造)实现 4 阶段调研契约
3. 新 skill `skills/debug-to-codex-prompt/` 把 investigation report + fix plan + scope-lock 文件列表翻译成 codex XML prompt
4. `commands/ship.md` 埋 2 处 reframe 兜底(Phase 1 brainstorm 末 + Phase 1.5 spec writing 开头)
5. `commands/ship-review.md` 加 G3 blast-radius 检查(仅 `ship_mode=debug` 时触发)
6. `.ohaze/current-ship.json` schema 加 `ship_mode` 字段
7. 文档同步(plugin.json bump 2.2.0 / CHANGELOG / ROADMAP / CLAUDE.md / README.md)

## Code references read in Phase 1.5

### Same-area existing code (1)
- `plugins/ohaze/commands/ship.md:1-252` — ship 主流程编排,debug.md 的结构基线
- `plugins/ohaze/commands/ship-review.md` — review 入口,要加 G3 埋点
- `plugins/ohaze/commands/ship-finish.md` — finishing 入口,debug 复用不动

### Caller-callee or producer-consumer neighbors (2)
- `plugins/ohaze/skills/codex-executor/SKILL.md:1-459` — dispatch / review / retry 三段契约,debug 复用 `mode='dispatch'` 和 `mode='review'`
- `plugins/ohaze/skills/finishing/SKILL.md:1-462` — Phase 7 收尾,debug 复用不动
- `plugins/ohaze/skills/spec-to-codex-review/SKILL.md:1-263` — Phase 1.6 spec audit,debug 不走

### Related existing spec / plan cross-reference (3)
- `docs/ohaze/specs/2026-06-14-spec-audit-scope-reframe-design.md` — 最近 spec 标准结构参考
- `docs/ohaze/specs/2026-06-13-codex-dispatch-reliability-design.md` — 多文件 task 拆分参考
- `docs/ohaze/plans/2026-06-14-spec-audit-scope-reframe.md` — plan guidance-form 风格参考
- `docs/ohaze/briefs/2026-06-14-spec-audit-scope-reframe-brief.md` — brief 模板对齐参考

### CHANGELOG similar entries and prior decisions (4)
- `CHANGELOG.md` [2.1.2] spec-audit-scope-reframe — 两轴 bounded schema 设计同源
- `CHANGELOG.md` [2.1.1] codex-dispatch-reliability — debug ship 同时是 dogfood 测试场景
- `CHANGELOG.md` [2.1.0] BDD/TDD restructure — 流程档位概念起源
- `CHANGELOG.md` [2.0.0] Removed `引入其他 superpowers skill 拓展流程` 错误冻结记录 — fork 进自持版不算违反"减少依赖"

### 外部参考
- superpowers v5.1.0 `skills/systematic-debugging/SKILL.md`(297 行) — 4 阶段 + Iron Law + 3-strike
- gstack `investigate/SKILL.md`(54k 字节) — scope lock + 2 个显式 AskUserQuestion gate 设计

## Architecture

### debug vs ship phase 对照

**关键差异**:debug 流程中 worktree 创建提到 Pre-flight 之后立即进行(早于 systematic-debugging),让根因调研全程在隔离 worktree 内跑,避免污染主仓(见 KD10)。

| Phase | `/ohaze:ship` | `/ohaze:debug` | 差异 |
|---|---|---|---|
| Pre-flight | codex CLI / main_repo_path / branch & docs | **同 ship** | 共用 |
| 输入 | `<feature description>` | `<symptom> [--cause=<猜测>]` | 不同 |
| 1 (brainstorm) | `ohaze:brainstorming` BDD brief | **跳过** | debug 无 BDD |
| 1.5 (auto spec) | Claude write spec | **跳过** | debug 无 spec |
| 1.6 (spec audit) | `spec-to-codex-review` | **跳过** | debug 无 spec |
| 2 (worktree) | `using-git-worktrees`(在 spec 后建) | **提前**:Pre-flight 后立即建 worktree | debug 早建,investigation 在 worktree 内跑 |
| 3 (plan/investigation) | `writing-plans` | **在 worktree 内** invoke `systematic-debugging` Phase 1-3,产出 investigation_report + scope_lock_files + fix_plan 三件套 | debug 用调研报告替 plan;全程隔离主仓 |
| 3.5 (default-go) | plan summary AskUserQuestion | **G1 根因偏离 AskUserQuestion**(条件性) | 不同形状 |
| 4 (dispatch) | `codex-executor mode='dispatch'` + `plan-to-codex-prompt` XML | `codex-executor mode='dispatch'` + `debug-to-codex-prompt` XML | 共用 executor,新 prompt skill |
| 5 (review) | `codex-executor mode='review'` (general-purpose subagent) | **同 ship + scope_lock_files 强制实跑断言 + G3 blast-radius 检查** | review 复用,加三层防御 L2 + L3 |
| 6 (retry) | `codex-executor` max-3 retry | **同 ship (G2 = max-3 retry)** | G2 复用 codex-executor 现成机制 |
| 7 (finishing) | `ohaze:finishing` menu | **同 ship** | 共用 |

### 关键设计决定

#### KD1: 新 command 文件而不是 ship.md 加 mode 分支
**理由**:
- 解耦,符合 "流程档位" 概念(ship / debug / auto-ship / loop 都独立)
- ship.md 已经 252 行,加 mode 分支会让单文件超 500 行难维护
- 用户心智:`/ohaze:debug` 一望即知是 debug 模式,不需要记参数

#### KD2: `current-ship.json` schema 加 `ship_mode` 字段
**理由**:
- ship-review / ship-finish / codex-executor / finishing 4 个下游 skill 都共用 handoff
- 加一个 `ship_mode: "ship" | "debug"` 枚举字段,让下游按需分流(目前只 ship-review 用到分流逻辑,G3 检查)
- 默认 `"ship"` 兼容现有流程,debug.md 显式设 `"debug"`

#### KD3: systematic-debugging skill 作为 codex 干活前置(plan 替代品)
**理由**:
- ship 是 plan → execute,debug 是 investigation → fix → execute
- systematic-debugging 作为 Claude 主线程跑的 phase(类似 brainstorming),产出 investigation report 文档
- 文档存 worktree 内 `.ohaze/investigation-<slug>.md`(临时,不 commit,gitignored)

#### KD4: G1 根因偏离 gate 条件性触发
**理由**:
- 启动给 `--cause=<猜测>` → G1 active(对照调研结果)
- 启动只给 symptom → G1 inactive(无对照基准,信任 LLM)
- 这是 "default-go 文化" 的 debug 版本:有预期才有偏离才有 gate,无预期就自动跑

#### KD5: G3 blast-radius 加在 ship-review 而不是 codex-executor
**理由**:
- codex-executor 是 ship/debug 共用,加 mode 分支会污染主流
- ship-review 已经按 `state` 字段分流,加 `ship_mode` 分流自然延伸
- G3 检查位置:**Phase 5.0 commit 之前**(`git diff --name-only base..HEAD` 计数)

#### KD6: scope lock 三层防御(brief "物理冻结" 在 codex 0.137 限制下的最强可行实现)
**Codex 0.137 限制**:`codex exec --sandbox` 只支持 `read-only` / `workspace-write` / `danger-full-access` 三档,**不提供文件级白名单 sandbox** 能力。OS 级 chmod -w 套 worktree 跨平台脆弱(macOS APFS / Linux ext4 行为不一,git 操作有时绕开 perm) 且会破坏 codex 自身的 git 状态读取。结论:brief 中的「物理冻结」在本期降级为**三层防御组合**。

**三层防御**(scope lock implementation):
1. **L1 — Prompt 强约束** (in `debug-to-codex-prompt` XML):
   - `<editable_files>` 段列出绝对路径白名单
   - `<readonly>everything else</readonly>` 段明示边界
   - `scope_lock_breach_requested:` escape hatch 协议(codex 必须报告而非偷偷违反)
2. **L2 — Review 阶段强制实跑断言** (in `ship-review` G3 之前):
   - 强制运行 `git -C <worktree_path> diff --name-only <base_ref>..HEAD`
   - 跟 handoff `scope_lock_files` 字段逐项比对,出现白名单外文件 → CRITICAL finding(reviewer prompt 模板里写死这一项)
3. **L3 — G3 blast-radius gate 兜底**:
   - touched count > 5 或者 L2 检测到越界 → AskUserQuestion(接受 / 缩 scope / 升级 ship)

三层叠加效果接近物理冻结:L1 拦下绝大多数,L2 检测漏网,L3 让 haze 决策。**brief 中"物理冻结"在 codex 提供文件级 sandbox 之前以此三层实现**,后续 codex CLI 升级(如 0.140+ 加文件白名单)再升级 L1。

#### KD7: G2 3-strike 复用 codex-executor Phase 6 现成 max-3 retry
**理由**:
- 现有 retry 机制(`.ohaze/current-ship.json.retries`)就是 G2,无需新增
- 区别:ship 的 retry 是"修 review finding",debug 的 retry 是"修复假设失败"
- 语义重叠,行为一致(都是 AskUserQuestion 让 haze 决定继续/升级/放弃)

#### KD8: ship.md 埋 3 处 reframe 兜底(对应 brief Scenario 3 "调研/spec/plan 任一 phase")
**位置 1**:Phase 1 brainstorming 终态之后(brief approved 时)
- 检查 brief 形状:Scenarios 全部 "修复 X" / 无 happy path / Out of Scope 列出 "新 feature" → 提示
**位置 2**:Phase 1.5 spec writing 开始 mandatory code reading 之后
- 检查 code refs:发现 fix-shaped issue(如 stack trace / bug 关键词 / 跟最近 CHANGELOG Fixed 段重叠)→ 提示
**位置 3**:Phase 3 writing-plans 之后(plan_path 落盘,Phase 3.5 default-go AskUserQuestion 之前)
- 检查 plan 形状:Tasks 中无新增功能项 / Acceptance 都是"恢复某行为"形态 / 整 plan 只触及 ≤ 3 文件 → 提示

三处都是 AskUserQuestion 让 haze 决定切 debug / 继续 ship。**信号阈值**: 位置 1 = ≥ 2 of 4 signals; 位置 2 = ≥ 2 of 3 signals; 位置 3 = ≥ 2 of 3 signals。

#### KD9: "切到 debug" 接受路径 = manual restart(非 in-process 转换)

**Brief 语义**:brief Scenario 3 写"haze 接受 → 转 debug 流程"。

**Spec 实现**:`/ohaze:ship` 中段任一 reframe checkpoint hit 后 haze 选"切到 debug",ship 流程**干净退出**(若 worktree 未建则 no-op;若 worktree 已建则按 finishing menu Option 3 discard 路径处理),并提示 haze 重新打 `/ohaze:debug "<symptom>" [--cause=<猜测>]`。

**理由**(为什么不实现 in-process 自动转换):
- ship.md 中段调用 debug.md 跨 command 边界,需重写 state 机(ship_mode 字段已经能解决静态分流,但中段动态切换涉及 "停 brainstorm/writing-plans skill loop → 启 systematic-debugging skill loop",需要 ohaze:brainstorming / ohaze:writing-plans 加协作退出协议,超本期 surgical scope
- 自动转换需要 haze 在 reframe AskUserQuestion 里再补 `--cause` 信息(brief 走调研后才有),多一轮交互反而抵消"轻流程" 优势
- Manual restart 在 ohaze 这种 plugin 上下文里非常便宜(haze 打一条命令 + 复制 symptom 字符串),稳定性远高于 in-process 转换
- 后续版本可在 `/ohaze:auto-ship` 引入"流程档位预选" 时统一加 in-process 转换(届时所有命令共享 ship_mode 切换协议)

**用户体感**:reframe AskUserQuestion 选项加注 "(Recommended)" 推 debug,但接受后 haze 看到的是 "Ship 流程已干净退出,请打 `/ohaze:debug \"<symptom>\"` 重启" 一行 + 含 symptom 模板。Manual restart cost = 1 个命令 + paste symptom,可接受。

### 边界守护

- **fork 进自持版**:systematic-debugging fork 自 superpowers v5.1.0(MIT),进 `plugins/ohaze/skills/systematic-debugging/`,运行时不依赖 superpowers 已装。**不引入新外部依赖**(沿用 v2.0 "零运行时外部 skill 依赖")
- **ship 现有流程不破坏**:ship.md 仅加 2 处 reframe 兜底 AskUserQuestion(无破坏性改动),所有 brief shape 检查输出都是建议而非强制
- **codex-executor 不动**:debug 复用现有 dispatch / review / retry 机制,不加 mode 分支(保持 v2.1.1 hardening 结果)
- **finishing 不动**:debug 走完整 finishing menu,共用 6 选项 + 7th Security Review,无需 debug 专属菜单

## File Structure

| 文件 | 职责 | 状态 |
|---|---|---|
| `plugins/ohaze/commands/debug.md` | debug 主流程编排(类 ship.md) | **新建** |
| `plugins/ohaze/skills/systematic-debugging/SKILL.md` | 4 阶段调研契约 + G1 gate 编排 | **新建(fork)** |
| `plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md` | investigation + fix plan → codex XML(含 scope lock) | **新建** |
| `plugins/ohaze/commands/ship.md` | 加 2 处 reframe 兜底 + handoff schema 加 `ship_mode` | **改动** |
| `plugins/ohaze/commands/ship-review.md` | 加 G3 blast-radius 检查(`ship_mode=debug` 时) | **改动** |
| `plugins/ohaze/.claude-plugin/plugin.json` | version 2.1.3 → 2.2.0 | **改动** |
| `CHANGELOG.md` | [Unreleased] 现有 codex-output-persistence 升 [2.2.0] + 加 debug-command 主条目 | **改动** |
| `ROADMAP.md` | Backlog 第 1 条 debug 移到 当前主线 + 加完成 checkbox | **改动** |
| `CLAUDE.md` | "## 关键文件 / 入口" 段加 debug.md / debug-to-codex-prompt / systematic-debugging | **改动** |
| `README.md` | 简介加 /ohaze:debug 命令 | **改动** |
| `plugins/ohaze/skills/codex-executor/SKILL.md` | **不动** | — |
| `plugins/ohaze/skills/finishing/SKILL.md` | **不动** | — |
| `plugins/ohaze/skills/spec-to-codex-review/SKILL.md` | **不动** | — |
| `plugins/ohaze/commands/ship-finish.md` | **不动** | — |
| `plugins/ohaze/commands/status.md` | **不动**(status 用 state 字段判定,debug ship 自动兼容) | — |

## Tasks

### Task 1: `commands/debug.md` 主流程编排

**Files (new):**
- `plugins/ohaze/commands/debug.md`

**Changes:**

新建 frontmatter:
```yaml
---
description: Debug mode for ohaze workflow. systematic 4-phase root cause investigation + scope-locked fix + cross-source review + finishing. Lighter than /ohaze:ship for bug fixes.
argument-hint: "<symptom> [--cause=<猜测原因>] [--project <abs-path>]"
allowed-tools: Bash, BashOutput, KillBash, Read, Write, Edit, Skill, Agent, AskUserQuestion
---
```

主结构(Phase 段):

1. **Pre-flight**(Section 1-3):
   - 同 ship.md `## Pre-flight ### 1/2/3`,**逐字复用**(避免漂移)
   - 解析 `--cause=` 可选参数(空字符串视为 absent)

2. **Phase 2 — Worktree creation (提前到 Pre-flight 之后立即建)**:
   - Pre-flight 完成 + slug 从 symptom 派生(kebab-case ≤ 4 词,从 symptom 第一句 + git diff/recent commit context 自动派生,Phase 4 dispatch 前可被 systematic-debugging 调整)
   - Invoke `ohaze:using-git-worktrees` with:
     - Working dir: `main_repo_path`
     - Desired branch: `fix/<slug>`(debug 默认 fix 分支型,可被显式参数覆盖;本期 YAGNI 不实现 hotfix 参数)
   - 捕获 `worktree_path`,assert `main_repo_path` matches,then `cd "$worktree_path"`
   - **关键差异 vs ship**:ship 在 brainstorm/spec/spec-audit 完成后才建 worktree(line 111-120 ship.md);debug 直接在 Pre-flight 后建,确保后续 systematic-debugging 全程在隔离 worktree 内跑,**不污染主仓**(解 R1 风险)

3. **Phase 3 — Systematic Debugging Investigation (in worktree)**:
   - Invoke `Skill(ohaze:systematic-debugging)` with:
     - `symptom`: 字符串(从 args)
     - `cause_hypothesis`: 字符串 or `null`(从 `--cause` 参数)
     - `worktree_path`: 绝对路径(Phase 2 创建)
     - `main_repo_path`: 绝对路径
   - skill 终态产出 `investigation_report` 内容 + `scope_lock_files` 文件列表 + `fix_plan` 文本(三件套),全部在 worktree 内运行(grep / reproduce / git log 都跑 worktree)
   - 中途若 G1 hit,skill 内部自己处理 AskUserQuestion 决策
   - 终态 hand-off 后,主线程把 investigation_report 写入 `<worktree_path>/.ohaze/investigation-<slug>.md`(临时,gitignored,不 commit)

4. **Phase 4a — Translate to codex XML**:
   - Invoke `Skill(ohaze:debug-to-codex-prompt)` with:
     - `investigation_path`: `<worktree_path>/.ohaze/investigation-<slug>.md`
     - `scope_lock_files`: list of absolute file paths(from Phase 3 systematic-debugging output)
     - `fix_plan`: 修复方案文本
     - `project_test_command`: detected
     - `worktree_path` / `main_repo_path` / `base_ref`
   - 捕获 XML prompt 字符串

5. **Phase 4b — Hand Off To Codex**:
   - 同 ship.md `## Phase 4 — Hand Off To Codex` Step 4b,**逐字复用** invocation 部分
   - Invoke `Skill(ohaze:codex-executor)` with `mode='dispatch'` + `codex_prompt` (来自 Phase 4a) + 其余字段

6. **Persisting Context** — handoff JSON 与 ship 一致,**加 `ship_mode: "debug"`**:
```json
{
  "state": "running",
  "ship_mode": "debug",
  "slug": "<feature-slug>",
  "branch": "fix/<slug>",
  "base_ref": "main",
  "worktree_path": "<absolute>",
  "main_repo_path": "<absolute>",
  "investigation_path": "<absolute path to .ohaze/investigation-<slug>.md>",
  "scope_lock_files": ["<absolute>", ...],
  "cause_hypothesis": "<string or null>",
  "plan_path": "<absolute path to codex-debug-prompt.xml>",
  "spec_path": null,
  "brief_path": null,
  "spec_review_iteration": 0,
  "retries": 0,
  "thread_id": "<UUID or null>",
  "codex_bg_id": "<bg task id>",
  "linked_todo": "<exact todo or null>",
  "project_type": null,
  "project_category": null
}
```

字段语义:
- `ship_mode`: 枚举 `"ship" | "debug"`,默认 `"ship"`(ship.md 显式写),debug.md 显式写 `"debug"`
- `investigation_path`: debug 模式独有,代替 brief+spec
- `scope_lock_files`: debug 模式独有,reviewer 用来验证 codex 越界
- `cause_hypothesis`: debug 模式独有,Phase 1 G1 决策用
- `spec_path` / `brief_path`: debug 模式置 `null`(finishing doc-finish 已经按 fallback chain 兜底,见 finishing/SKILL.md Class 3 / Class 4 段)
- `plan_path`: debug 模式指向 `codex-debug-prompt.xml`(让 finishing doc-finish 的"真相源 = spec_path + plan_path" 至少有 plan_path 不空)

Step A (linked_todo) 与 ship 一致。
Step C (gitignored) 与 ship 一致(`.worktrees/` + `.ohaze/`)。

7. **Failure Modes** 段:
   - codex CLI 缺失 → 同 ship
   - User cancels Phase 3 G1/G2 → 干净退出,worktree 已建则按 finishing menu Option 3(discard)路径清理
   - systematic-debugging 找不到 reproducible bug(stuck before hypothesis 形成)→ 报告并停,worktree 保留供 haze 手动调研
   - debug-to-codex-prompt 失败 → surface error,worktree 保留
   - codex-executor dispatch 失败 → 同 ship(`state=dispatch_failed`)

8. **Notes** 段:
   - 不 ScheduleWakeup
   - 不调用 brainstorming / writing-plans / spec-to-codex-review(显式不用,跟 ship 区分)
   - Phase handoff 同 turn 推进

**Behavior Contract:**
- 输入:`<symptom>` 必填 + 可选 `--cause=<猜测>` + 可选 `--project <abs-path>`
- 输出:在 `<worktree_path>/.ohaze/current-ship.json` 写入 `ship_mode='debug'` 的 handoff,Codex 后台 dispatch 中
- 不写任何 spec / brief 文件
- investigation note 落 `.ohaze/investigation-<slug>.md`(gitignored)

**Acceptance (grep / structural):**
- [ ] `test -f plugins/ohaze/commands/debug.md`
- [ ] `grep -q '^description:' plugins/ohaze/commands/debug.md`
- [ ] `grep -q 'argument-hint: "<symptom>' plugins/ohaze/commands/debug.md`
- [ ] `grep -q 'allowed-tools: Bash, BashOutput, KillBash, Read, Write, Edit, Skill, Agent, AskUserQuestion' plugins/ohaze/commands/debug.md`
- [ ] `grep -q 'Skill(ohaze:systematic-debugging)' plugins/ohaze/commands/debug.md`
- [ ] `grep -q 'Skill(ohaze:debug-to-codex-prompt)' plugins/ohaze/commands/debug.md`
- [ ] `grep -q "mode='dispatch'" plugins/ohaze/commands/debug.md`
- [ ] `grep -q '"ship_mode": "debug"' plugins/ohaze/commands/debug.md`
- [ ] `grep -q '"investigation_path"' plugins/ohaze/commands/debug.md`
- [ ] `grep -q '"scope_lock_files"' plugins/ohaze/commands/debug.md`
- [ ] `grep -q '"cause_hypothesis"' plugins/ohaze/commands/debug.md`
- [ ] `grep -qE 'fix/<slug>' plugins/ohaze/commands/debug.md`
- [ ] **绝对不出现** `ohaze:brainstorming` / `ohaze:writing-plans` / `ohaze:spec-to-codex-review` 调用(grep `! grep -qE 'Skill\(ohaze:(brainstorming|writing-plans|spec-to-codex-review)\)' plugins/ohaze/commands/debug.md`)

---

### Task 2: `skills/systematic-debugging/SKILL.md` fork + ohaze 改造

**Files (new):**
- `plugins/ohaze/skills/systematic-debugging/SKILL.md`

**基线**:superpowers v5.1.0 `skills/systematic-debugging/SKILL.md` 全文 (297 行,MIT)

**改造方向**:

1. **frontmatter**:
   ```yaml
   ---
   name: systematic-debugging
   description: Use within /ohaze:debug Phase 1 to drive root-cause investigation (4 phases) and produce investigation report + scope-lock file list + fix plan. Owns G1 root-cause-deviation gate.
   ---
   ```

2. **Attribution 段加在文件末尾**:
   ```markdown
   ## Attribution

   Forked from the `systematic-debugging` skill in [obra/superpowers](https://github.com/obra/superpowers) v5.1.0 by Jesse Vincent, used under MIT license. The ohaze fork:
   - 加 G1 条件性 gate(haze 提供猜测原因时,调研结果偏离触发 AskUserQuestion)
   - 加 scope lock 概念输出(hypothesis 形成后产出可编辑文件白名单,供 debug-to-codex-prompt 写入 codex prompt)
   - 加 ohaze hand-off 协议(终态返回 investigation_report + scope_lock_files + fix_plan 三件套)
   - 改 "human partner" 措辞为 "haze"
   - 删除 "Real-World Impact" / "Quick Reference" 等次要段,保留 4 phase + Iron Law + Red Flags + Rationalizations
   ```

3. **Invocation Contract 新增章节**(在 Overview 之后):
   ```markdown
   ## Invocation Contract

   Invoked by `/ohaze:debug` Phase 3 (AFTER worktree creation in Phase 2). Runs entirely inside the isolated worktree to avoid polluting the main repo with investigation commands (grep / git log / reproduce scripts).

   Inputs:
   - `symptom` (string, required): bug symptom description from user
   - `cause_hypothesis` (string or null): user-provided cause guess; null means user doesn't know
   - `worktree_path` (string, required): absolute worktree path created in /ohaze:debug Phase 2 — ALL investigation activity (read, grep, reproduce, git log) MUST run inside this worktree, NOT in main_repo_path
   - `main_repo_path` (string, required): absolute project root (for reporting and cross-reference only, not for editing)

   Terminal state outputs (returned in conversation to /ohaze:debug):
   - `investigation_report` (markdown): root cause investigation full report
   - `scope_lock_files` (list of abs paths under worktree_path): files Phase 3 Hypothesis-and-Testing identified as fix scope (codex prompt will enforce write-boundary via three-layer defense — see spec KD6)
   - `fix_plan` (markdown): the concrete fix approach (what to change, not how — Codex chooses how)

   This skill does NOT:
   - Write files (caller writes investigation note to worktree after skill returns)
   - Dispatch codex (codex-executor does that in /ohaze:debug Phase 4b)
   - Commit / merge / PR (finishing does that in /ohaze:debug Phase 7)
   - Modify main_repo_path — all investigation commands MUST scope to worktree_path
   ```

4. **Phase 1 Root Cause Investigation** 段:
   - 保留 superpowers 5 个 sub-step(read errors / reproduce / check recent changes / gather evidence / trace data flow)
   - **加 G1 gate**作为 Phase 1 终态:
     ```markdown
     ### G1 — Root Cause Deviation Gate (conditional)

     After Phase 1 produces a root cause hypothesis:

     - If `cause_hypothesis == null` (user didn't provide guess): G1 inactive, proceed to Phase 2.
     - If `cause_hypothesis != null`:
       - Compare Phase 1's hypothesis against `cause_hypothesis`.
       - If they describe the same root cause (semantically aligned, not necessarily verbatim): G1 PASS, proceed to Phase 2.
       - If they differ materially: trigger AskUserQuestion with 3 options:
         1. 接受调研根因 (Recommended) — use Phase 1's hypothesis, continue
         2. 重新调研 — return to Phase 1 with haze's pushback context (haze may type why their guess feels right)
         3. 退出 — abort the debug ship cleanly (caller stops, no worktree)
       - Persist the decision in conversation memory for caller's reporting.

     This gate is the debug-mode equivalent of ship Phase 3.5 default-go: the recommended path is automatic, the interrupt window is real.
     ```

5. **Phase 2 Pattern Analysis** 段:保留 superpowers 4 个 sub-step,无 ohaze 改造

6. **Phase 3 Hypothesis and Testing** 段:
   - 保留 superpowers 4 个 sub-step
   - **加 scope_lock_files 产出**:
     ```markdown
     ### Identify scope_lock_files

     Once a single hypothesis is formed and you can name the root cause file(s):
     - Enumerate absolute file paths that this fix WILL touch (best estimate, conservative).
     - Include test/fixture files if the fix needs them.
     - Do NOT include "neighboring files I might check for consistency" — those go to Phase 4 review autonomy.
     - Output as a flat list of absolute paths.

     This list is returned in terminal state and physically hard-coded into Codex's prompt as <editable_files> by debug-to-codex-prompt. Codex CAN read everything but only WRITE to scope_lock_files.
     ```

7. **Phase 4 Implementation** 段:
   - 保留 superpowers 5 个 sub-step
   - **加 fix_plan 产出**(替代直接修代码):
     ```markdown
     ### Produce fix_plan (Claude main-thread does NOT modify code here)

     This skill runs in /ohaze:debug Phase 3 — Claude main thread, INSIDE the worktree (created in /ohaze:debug Phase 2) but BEFORE Codex is dispatched (Phase 4b). So instead of fixing code directly:

     1. Write the fix as a `fix_plan` markdown block describing:
        - Root cause (one sentence)
        - The change to make (what — files, lines, expected diff shape; not how — Codex chooses how)
        - **Anti-regression contract (per project type, mandatory)** — see anti-regression contract below
        - Anti-regression note: what NOT to touch even if "looks related"
     2. Return fix_plan + investigation_report + scope_lock_files to /ohaze:debug.
     3. /ohaze:debug Phase 4b dispatches Codex with this plan via debug-to-codex-prompt.

     ### Anti-regression contract (mandatory in fix_plan)

     The contract enforced by debug-to-codex-prompt and ship-review depends on `project_test_command`:

     **A. Real test-suite projects** (project_test_command = an aggregate command like `npm test` / `pytest`):
     - Codex MUST first add or identify a regression test that reproduces the bug
     - Codex MUST run that test BEFORE applying the fix and observe it FAIL (this proves the test is gating the bug, not vacuous)
     - Codex MUST then apply the fix and run the full test suite (the same `project_test_command`)
     - Final report MUST include: (a) the regression test file:line, (b) pre-fix failing output, (c) post-fix passing output
     - This is "failing test first" — without observed pre-fix failure, the regression test could be silently broken

     **B. Markdown-only plugins / no static-code projects** (project_test_command = sentinel `'(per-Task acceptance assertions inline in plan)'`):
     - Codex MUST run grep / JSON-load / structure assertions per the fix_plan's verification step list
     - Codex MUST run a dogfood end-to-end smoke check matching the bug scenario (e.g. for an ohaze debug-flow bug: dispatch a synthetic /ohaze:debug test invocation against a known minimal symptom and inspect handoff/output for expected behavior)
     - Final report MUST include: (a) each assertion command's exit status, (b) dogfood smoke transcript or proof of expected behavior, (c) explicit mapping back to the fix_plan's "Anti-regression checks" list

     The fix_plan MUST embed the relevant variant (A or B) explicitly. Codex's `<verification_loop>` and ship-review's real-test invocation both consume this contract verbatim.
     ```

8. **3-strike 段(原 superpowers Phase 4.5 "Question Architecture")**:
   - 改成 ohaze 风格:
     ```markdown
     ### G2 — 3-Strike Escalation

     If Phase 3 forms ≥ 3 distinct hypotheses that all fail Phase 3 testing:
     - STOP. Do not propose Hypothesis #4.
     - Trigger AskUserQuestion with 3 options:
       1. 换思路 — Phase 1 重启 with all prior hypotheses listed as "not it"
       2. 升级 ship — abort debug ship, suggest haze try /ohaze:ship instead (architecture-level concern)
       3. 放弃 — abort cleanly

     Note: this is the Claude main-thread G2. Codex's own retry loop (in codex-executor Phase 6, max-3 retries during fix execution) is a SEPARATE G2-equivalent for the fix attempt. Both stack: G2 here catches "the investigation itself is stuck", Codex retry catches "the fix execution itself keeps failing".
     ```

**Behavior Contract:**
- 输入:`symptom` / `cause_hypothesis` / `main_repo_path` / `work_dir`
- 输出 (return in conversation):
  - `investigation_report`: markdown 字符串(完整 4 阶段报告)
  - `scope_lock_files`: 绝对路径列表
  - `fix_plan`: markdown 字符串(what + verification + anti-regression)
- 边界:不写文件、不 dispatch codex、不 commit;G1 / G2 在 skill 内部触发 AskUserQuestion

**Acceptance (grep / structural):**
- [ ] `test -f plugins/ohaze/skills/systematic-debugging/SKILL.md`
- [ ] `grep -q '^name: systematic-debugging$' plugins/ohaze/skills/systematic-debugging/SKILL.md`
- [ ] `grep -q 'Invocation Contract' plugins/ohaze/skills/systematic-debugging/SKILL.md`
- [ ] `grep -q 'cause_hypothesis' plugins/ohaze/skills/systematic-debugging/SKILL.md`
- [ ] `grep -q 'scope_lock_files' plugins/ohaze/skills/systematic-debugging/SKILL.md`
- [ ] `grep -q 'fix_plan' plugins/ohaze/skills/systematic-debugging/SKILL.md`
- [ ] `grep -q 'G1 — Root Cause Deviation Gate' plugins/ohaze/skills/systematic-debugging/SKILL.md`
- [ ] `grep -q 'G2 — 3-Strike Escalation' plugins/ohaze/skills/systematic-debugging/SKILL.md`
- [ ] `grep -q 'NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST' plugins/ohaze/skills/systematic-debugging/SKILL.md`(Iron Law 保留)
- [ ] `grep -q 'Phase 1: Root Cause Investigation' plugins/ohaze/skills/systematic-debugging/SKILL.md`
- [ ] `grep -q 'Phase 2: Pattern Analysis' plugins/ohaze/skills/systematic-debugging/SKILL.md`
- [ ] `grep -q 'Phase 3: Hypothesis' plugins/ohaze/skills/systematic-debugging/SKILL.md`
- [ ] `grep -q 'Phase 4: Implementation' plugins/ohaze/skills/systematic-debugging/SKILL.md`
- [ ] `grep -q 'Forked from .*superpowers' plugins/ohaze/skills/systematic-debugging/SKILL.md`(Attribution)
- [ ] `grep -q 'MIT license' plugins/ohaze/skills/systematic-debugging/SKILL.md`
- [ ] **不包含** "Real-World Impact" / "Quick Reference"(被裁剪段,grep 反断言)

---

### Task 3: `skills/debug-to-codex-prompt/SKILL.md` 新 skill

**Files (new):**
- `plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md`

**职责**:把 systematic-debugging 产出的三件套(investigation_report / scope_lock_files / fix_plan)翻译成 codex 可消费的 XML prompt,**含 scope lock hard-code**。类比 `plan-to-codex-prompt`(thin XML wrapper)。

**结构**:

```markdown
---
name: debug-to-codex-prompt
description: Use when handing a systematic-debugging investigation + fix plan to Codex for execution within /ohaze:debug Phase 4. Thin XML wrapper that embeds scope-lock file whitelist + investigation context + fix plan + verification loop.
---

# Debug To Codex Prompt (ohaze)

Translate a systematic-debugging investigation + fix plan + scope-lock file list into the XML prompt format `codex exec` consumes. Owns /ohaze:debug Phase 3 (XML translation).

## Invocation Contract

Inputs:
- `investigation_path` (abs, required): path to investigation note markdown in worktree
- `scope_lock_files` (list of abs, required): files Codex MAY modify; everything else is readonly
- `fix_plan` (markdown string, required): the concrete fix approach
- `project_test_command` (string, required): test command to run for verification; sentinel `'(per-Task acceptance assertions inline in plan)'` for Markdown plugins
- `worktree_path` (abs, required)
- `main_repo_path` (abs, required)
- `base_ref` (string, required): e.g. `main`

Output:
- An XML string ready to pass to `ohaze:codex-executor` as `codex_prompt`.

## XML Template

Substitute placeholders at call time. Pass the full block below to codex-executor.

\`\`\`xml
<task>
You are fixing a bug. The investigation has already been completed by Claude main thread (systematic-debugging skill). Your job is execute the fix as specified, write a regression test (per project_test_command), and verify.

Do NOT redo root cause investigation. Trust the investigation report below.
</task>

<investigation>
{cat investigation_path content here}
</investigation>

<fix_plan>
{fix_plan markdown verbatim}
</fix_plan>

<editable_files>
You MAY modify these files (and only these files):
{newline-separated list of scope_lock_files absolute paths}
</editable_files>

<readonly>
Everything else in the repo is READONLY. You can READ any file (and you should, to understand context), but you must NOT WRITE / MODIFY / DELETE / CREATE any file outside the <editable_files> list above.

If during execution you discover the fix genuinely requires editing a file not in <editable_files>:
- STOP, do not edit it.
- Report this in your final message as: "scope_lock_breach_requested: <file> — reason: <why>"
- The Claude orchestrator will surface this to haze via G3 blast-radius gate.

This scope lock implements ohaze's "fix one bug without spawning another" guarantee. Violations cause CRITICAL review findings.
</readonly>

<commit_handling>
ohaze orchestrator handles commits — leave changes uncommitted. The main session will commit with a `fix:` style message derived from the investigation report.
</commit_handling>

<verification_loop>
Execute the anti-regression contract from fix_plan (variant A for real test-suite projects, variant B for Markdown-only).

**Variant A** (project_test_command is an aggregate command like `npm test` / `pytest`):
1. Locate or add the regression test specified in fix_plan.
2. Run that regression test BEFORE applying any code fix; capture its output. It MUST fail. If it passes pre-fix, STOP and report "regression test vacuous — does not gate the bug; need new test".
3. Apply the fix to scope_lock_files only.
4. Run `{project_test_command}` (the full suite) from `{worktree_path}`. All tests MUST pass before reporting done.
5. Report: (a) regression test file:line, (b) pre-fix failing tail, (c) post-fix passing tail.

**Variant B** (project_test_command is sentinel `'(per-Task acceptance assertions inline in plan)'`):
1. Run each grep / JSON-load / structure assertion command listed in fix_plan's "Anti-regression checks" section and capture every exit status.
2. Run the dogfood end-to-end smoke check described in fix_plan (typically a synthetic invocation of the affected workflow against a known minimal input that exercises the bug scenario).
3. Report: (a) per-assertion command + exit status table, (b) dogfood smoke transcript or evidence of expected behavior, (c) mapping each assertion back to which fix_plan check it satisfies.

Final structured report MUST include the variant identifier (A or B) and all required evidence. A "tests pass" claim without the pre-fix failure proof (variant A) or without the per-assertion exit table + dogfood smoke transcript (variant B) is an automatic failure to be flagged by ship-review.
</verification_loop>

<anti_regression>
The investigation report's "Anti-regression note" section lists what NOT to touch even if it looks related. Honor that note strictly.

Do NOT:
- Refactor neighboring code "while you're there"
- Rename variables for consistency
- Add error handling not specified in fix_plan
- Update unrelated documentation

A single-bug fix that touches 1-2 files is BETTER than a fix that touches 5 files. Minimal changes have minimal risk of spawning new bugs.
</anti_regression>

<output_format>
Return a final message with:

Tasks completed:
- <one-line summary of the fix>

Touched files (must match <editable_files> exactly):
- <file1>
- <file2>
- ...

Test verification output:
- Command: {project_test_command}
- Exit status: <code>
- Tail of output: <last ~20 lines>

Suggested commit message:
- fix: <one-line summary>

Scope lock breach (if any):
- <empty if none, OR "scope_lock_breach_requested" details>
</output_format>
\`\`\`

## Caller Handoff

Return control to /ohaze:debug Phase 4. Caller invokes ohaze:codex-executor mode='dispatch' with this XML.
```

**Behavior Contract:**
- 输入:investigation_path / scope_lock_files / fix_plan / project_test_command / worktree_path / main_repo_path / base_ref
- 输出:XML 字符串(交给 codex-executor)
- 关键模板段:`<task>` / `<investigation>` / `<fix_plan>` / `<editable_files>` / `<readonly>` / `<commit_handling>` / `<verification_loop>` / `<anti_regression>` / `<output_format>` 共 9 段

**Acceptance (grep / structural):**
- [ ] `test -f plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md`
- [ ] `grep -q '^name: debug-to-codex-prompt$' plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md`
- [ ] `grep -q 'Invocation Contract' plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md`
- [ ] `grep -q '<editable_files>' plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md`
- [ ] `grep -q '<readonly>' plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md`
- [ ] `grep -q '<anti_regression>' plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md`
- [ ] `grep -q '<commit_handling>' plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md`
- [ ] `grep -q '<verification_loop>' plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md`
- [ ] `grep -q 'scope_lock_files' plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md`
- [ ] `grep -q 'scope_lock_breach_requested' plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md`
- [ ] `grep -q 'investigation_path' plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md`
- [ ] `grep -q 'fix_plan' plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md`
- [ ] `grep -q 'codex-executor' plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md`

---

### Task 4: `commands/ship.md` 加 2 处 reframe 兜底 + handoff schema 加 `ship_mode`

**Files (change):**
- `plugins/ohaze/commands/ship.md`

**Changes:**

#### 4.1 — Phase 1 brainstorming 终态后加兜底

位置:`## Phase 1 — BDD Brainstorm` 段末尾,在 "Phase 1 hand-off invariant" blockquote 之后,在 `## Phase 1.5` 段之前。

加新段:
```markdown
### Phase 1 → 1.5 reframe checkpoint (debug-mode safety net)

After brief approved and before handing off to Phase 1.5, inspect the brief shape. If any of these are true, the brief shape suggests bug fix rather than feature dev:

- All Scenarios start with "修复 X" / "Fix X" / phrase a problem being eliminated rather than a positive capability being added
- The Out of Scope section lists "新 feature" or equivalent
- "完成的样子" Checklist items are all about restoring expected behavior rather than enabling new behavior
- The brief contains stack traces, error messages, or bug ticket references in its body

If at least 2 of the 4 signals hit, trigger one AskUserQuestion:

> "这个 brief 形状像 bug 修复 (而非新 feature 开发)。是否切到 `/ohaze:debug` 走轻流程?"
>
> - 切到 `/ohaze:debug` (Recommended) — 退出 ship,告诉 haze 用 `/ohaze:debug "<symptom>"` 重启
> - 继续 ship — brief 形状不是 bug,继续 Phase 1.5 写 spec

If haze chooses ship, continue normally. If haze chooses debug, stop the ship cleanly (no worktree created yet) and tell haze to run `/ohaze:debug` with the appropriate symptom string.

This is a non-blocking advisory — if no 2+ signals hit, proceed silently to Phase 1.5.
```

#### 4.2 — Phase 1.5 mandatory code-reading 之后加兜底

位置:`### Mandatory code-reading before writing` 段末尾,在 `### 5 boundary-question triggers` 段之前。

加新段:
```markdown
#### Mid-spec reframe checkpoint (debug-mode safety net)

After mandatory code-reading and before writing the spec, inspect the code refs Claude read. If the refs reveal this is a bug fix not a feature:

- Code refs are dominated by stack trace files, error log files, or files mentioned in recent CHANGELOG.md `## [Unreleased] Fixed` entries
- The brief's reframed core problem is "X is broken" / "X stopped working" rather than "users need X"
- The most recent commit on `main` (`git log -1 --oneline`) was a feature add, and this ship would conflict with that area for a fix

If at least 2 of the 3 signals hit, trigger one AskUserQuestion:

> "调研后发现这个需求实质是 bug 修复 (而非新 feature)。是否切到 `/ohaze:debug`?"
>
> - 切到 `/ohaze:debug` (Recommended)
> - 继续 ship — brief 真的是 feature dev

If haze chooses ship, continue with spec writing. If haze chooses debug, stop the ship cleanly (no worktree) and tell haze to run `/ohaze:debug` with the appropriate symptom + cause.
```

#### 4.4 — Phase 3 writing-plans 之后加兜底

位置:`## Phase 3 — Plan (ohaze)` 段末尾,在 `## Phase 3.5 — Plan Summary + Default-Go` 段之前(对应 brief Scenario 3 "ship 调研/spec/**plan** 任一 phase" 中的 plan phase)。

加新段:
```markdown
### Post-plan reframe checkpoint (debug-mode safety net)

After `ohaze:writing-plans` returns `plan_path` and before Phase 3.5 default-go summary, inspect the generated plan shape. If any of these are true, the plan shape suggests bug fix rather than feature dev:

- All Tasks in the plan are phrased as "restore X" / "fix Y" / no new public interface added
- All Acceptance Criteria are about returning to a known-good state rather than introducing new capability
- Plan touches ≤ 3 files total AND none of them is a new file (i.e. plan only modifies existing files)

If at least 2 of the 3 signals hit, trigger one AskUserQuestion:

> "Plan 写完后形状像 bug 修复 (而非新 feature dev)。是否切到 `/ohaze:debug` 走 systematic 4 阶段调研而非端到端 plan?"
>
> - 切到 `/ohaze:debug` (Recommended) — ship 干净退出 (worktree 已建则按 finishing menu Option 3 路径 discard);haze 用 `/ohaze:debug "<symptom>"` 重启
> - 继续 ship — plan 已写好,继续 Phase 3.5 default-go

If haze chooses ship, continue to Phase 3.5 normally. If haze chooses debug, stop the ship cleanly (per finishing menu Option 3 discard if worktree built) and tell haze to run `/ohaze:debug` with the appropriate symptom string. See KD9 in the spec for the manual-restart rationale.
```

#### 4.5 — Handoff schema 加 `ship_mode` 字段

位置:`## Persisting Context — `.ohaze/current-ship.json`` 段,Step B JSON template。

修改 JSON template:
```json
{
  "state": "running",
  "ship_mode": "ship",
  "slug": "<feature-slug>",
  ...其余字段不变...
}
```

加字段语义解释(`Field semantics` 列表新增一行):
- `ship_mode`: 枚举 `"ship" | "debug"`,默认 `"ship"`(本文件)。`/ohaze:debug` 显式写 `"debug"`。下游 (`ship-review`, `finishing`) 按需分流;v2.2.0 内仅 `ship-review` 用到分流(G3 blast-radius 检查)。

**Behavior Contract:**
- 4.1:Phase 1 终态后,brief 形状 ≥ 2 信号 → AskUserQuestion;haze 选 debug → 干净退出 ship(manual restart per KD9)
- 4.2:Phase 1.5 code-reading 后,refs 形状 ≥ 2 信号 → AskUserQuestion;haze 选 debug → 干净退出 ship(manual restart per KD9)
- 4.4:Phase 3 writing-plans 后,plan 形状 ≥ 2 信号 → AskUserQuestion;haze 选 debug → 干净退出 ship,worktree 已建则按 finishing Option 3 discard
- 4.5:handoff JSON 新增 `ship_mode: "ship"` 默认字段(兼容性:旧 handoff 缺字段时 ship-review 视为 `"ship"`)

**Acceptance (grep / structural):**
- [ ] `grep -q 'Phase 1 → 1.5 reframe checkpoint' plugins/ohaze/commands/ship.md`
- [ ] `grep -q 'Mid-spec reframe checkpoint' plugins/ohaze/commands/ship.md`
- [ ] `grep -q 'Post-plan reframe checkpoint' plugins/ohaze/commands/ship.md`
- [ ] `grep -c '是否切到 \`/ohaze:debug\`' plugins/ohaze/commands/ship.md` returns ≥ 3
- [ ] `grep -q '"ship_mode": "ship"' plugins/ohaze/commands/ship.md`
- [ ] `grep -q 'ship_mode.*ship.*debug' plugins/ohaze/commands/ship.md`(field semantics 段)

---

### Task 5: `commands/ship-review.md` 加 L2 scope_lock_files 强制实跑断言 + G3 blast-radius 埋点

**Files (change):**
- `plugins/ohaze/commands/ship-review.md`

**Changes:**

#### 5.1 — 共享 touched-files 收集器(debug mode only)

位置:Step 3a(state liveness transition)之后,**先于 L2 / G3**,先于 Phase 5.0 commit。

定义一个共享收集器供 L2 和 G3 共用,确保两者看到同一组"即将 commit" 的文件,且路径表示一致(绝对路径,跟 `scope_lock_files` 同表示)。

加新段:
```markdown
### Phase 5.-0.5 — Compute `touched_files_abs` (debug mode only, shared by L2 and G3)

Read `.ohaze/current-ship.json.ship_mode`. If `ship_mode != "debug"` (or missing → treat as `"ship"`): skip this step + L2 + G3,直接 Phase 5.0。

`git diff --name-only <base_ref>..HEAD` **只能看到已 commit 的改动**,但 Phase 5.0 commit 还没跑(Codex 留 uncommitted)。L2/G3 必须看到 Codex 真实留下的全部"即将 commit" 文件,所以用 `git status --porcelain` 含 staged + unstaged + untracked。同时路径 normalize 到绝对路径,跟 handoff `scope_lock_files`(绝对路径)一致。

```bash
# 在 worktree 内运行
cd <worktree_path>

# 收集全部 touched/untracked, 跟 base_ref 的差异 + 工作区 dirty
git_status=$(git status --porcelain)
# git diff --name-only HEAD 含已 commit 之后任何修改; 加 untracked 通过 status
# 但更稳:直接组合三段
touched_rel_lines=$(
  git diff --name-only <base_ref>..HEAD       # 自 base 起已 commit 改动
  git diff --name-only HEAD                    # 工作区 vs HEAD 改动(包括 staged + unstaged)
  git ls-files --others --exclude-standard     # 未追踪但非 ignored 文件
  | sort -u
)

# Normalize 到绝对路径
touched_files_abs=()
for rel in $touched_rel_lines; do
  touched_files_abs+=("$(realpath "<worktree_path>/$rel")")
done
```

`touched_files_abs` 是数组(或行分隔字符串),后续 L2 + G3 都消费这同一个集合。

注:`realpath` 解析 symlink 等;若 worktree 路径自身已是绝对路径且无 symlink,可用 `"<worktree_path>/$rel"` 简化。具体实现细节交给 Codex 自决,Behavior Contract 是"合并三类来源 + 绝对路径"。
```

#### 5.2 — L2: scope_lock_files 强制实跑断言(debug mode only)

位置:Phase 5.-0.5 之后,先于 G3。

加新段:
```markdown
### L2 — scope_lock_files Boundary Enforcement (debug mode only)

KD6 三层防御中的 L2 层。主线程实跑断言,不依赖 reviewer subagent。

Prerequisite: `touched_files_abs` 已在 Phase 5.-0.5 算好。If `ship_mode == "debug"` AND `scope_lock_files` is non-empty:

1. 计算 `breached_files` = touched_files_abs - scope_lock_files(数组差集,绝对路径精确匹配)
2. If `breached_files` non-empty:
   - Read `<worktree_path>/.ohaze/findings-detail.json` (or create with `{"iteration":<N>,"findings":[]}` if missing)
   - 主线程构造并追加 CRITICAL finding:
     ```json
     {
       "severity": "CRITICAL",
       "evidence": "<comma-separated breached_files (absolute paths)>",
       "technical_description": "Codex modified files outside scope_lock_files whitelist. Breach: <files>; allowed: <scope_lock_files>",
       "user_impact_description": "Bug 修复改动超出了根因调研定义的边界,可能引入新 bug 或与本次根因无关的变更。",
       "shown_to_user": false,
       "auto_handled": "retry-fix"
     }
     ```
   - Write 回 findings-detail.json
   - 同步追加同样一条 CRITICAL 到 `review-verdict.json.issues`(`"CRITICAL: scope_lock breach — <file>"`),触发 codex-executor Phase 6 retry loop 把越界改动撤回
3. If `breached_files` empty: proceed to G3 normally.

This is L2 of KD6 three-layer defense. L1 (prompt 强约束)在 dispatch 已注入;L2 在 review 之前强制实跑(读 Phase 5.-0.5 算好的 touched_files_abs);L3 (G3 blast-radius)接续。不需要修改 codex-executor 或 reviewer subagent 的 prompt 模板。
```

#### 5.3 — G3 blast-radius gate(debug mode only,L2 之后执行)

位置:L2 段之后,Phase 5.0 commit 之前。

加新段:
```markdown
### G3 — Blast-Radius Gate (debug mode only)

Prerequisite: `touched_files_abs` 已在 Phase 5.-0.5 算好。If `ship_mode == "debug"` (treat missing field as `"ship"` for backward compatibility):

Before commits (Phase 5.0):
1. Touched file count = `${#touched_files_abs[@]}` (同一个集合 L2 用过)
2. If count ≤ 5: skip this gate, proceed to Phase 5.0.
3. If count > 5: trigger AskUserQuestion:

> "Codex 修复触及 {count} 个文件 (超过 5 文件阈值)。debug 模式下这通常意味着根因比 hypothesis 假设的更宽。"
>
> 1. 接受宽修 — 这次 bug 根因确实波及多文件,继续进 review
> 2. 缩 scope — 让 Codex 重新只改最小核心文件 (resume with anti-regression prompt)
> 3. 升级 ship — 这事不该是 debug,转 /ohaze:ship,本次 debug ship discard

Routing:
- Choice 1: proceed to Phase 5.0 normally.
- Choice 2: dispatch a `codex exec resume <thread_id>` fix prompt with explicit `<anti_regression>` listing the current touched files and asking Codex to identify the minimal subset. After resume, re-run G3 (loop max 2).
- Choice 3: mark `.ohaze/current-ship.json.state = "blast_radius_escalated"`, surface a warning to haze, stop. Haze re-runs `/ohaze:ship` for the full flow.

This gate only fires in debug mode because debug's promised invariant is "fix one bug without spawning another". Ship mode legitimately touches many files (e.g. v2.1.1 codex-dispatch-reliability touched 5+ files by design).
```

**新增 `state` 枚举值**:`blast_radius_escalated`(在 ship-review.md 的 state-table 列表里加)

**Behavior Contract:**
- L2 (5.1): debug 模式 + scope_lock_files 非空 → 实跑 git diff --name-only,跟 scope_lock_files 比对,越界 → 主线程构造 CRITICAL finding 写入 findings-detail.json + review-verdict.json,触发 codex-executor Phase 6 retry
- G3 (5.2): debug 模式 + touched count > 5 → AskUserQuestion 3 选项
- 选项 2 复用 codex-executor Phase 6 retry 机制(已有的 anti_regression prompt 模板)
- 选项 3 写入新 state `blast_radius_escalated`
- ship 模式直接跳过 L2 和 G3
- L2 和 G3 都读 handoff `ship_mode` 字段(向后兼容缺字段 → `"ship"`)

**Acceptance (grep / structural):**
- [ ] `grep -q 'Phase 5.-0.5' plugins/ohaze/commands/ship-review.md`(touched-files 收集器段)
- [ ] `grep -q 'touched_files_abs' plugins/ohaze/commands/ship-review.md`(L2 + G3 共享变量)
- [ ] `grep -q 'L2 — scope_lock_files Boundary Enforcement' plugins/ohaze/commands/ship-review.md`
- [ ] `grep -q 'G3 — Blast-Radius Gate' plugins/ohaze/commands/ship-review.md`
- [ ] `grep -q 'ship_mode' plugins/ohaze/commands/ship-review.md`
- [ ] `grep -q 'scope_lock_files' plugins/ohaze/commands/ship-review.md`
- [ ] `grep -q 'breached_files' plugins/ohaze/commands/ship-review.md`
- [ ] `grep -q 'blast_radius_escalated' plugins/ohaze/commands/ship-review.md`
- [ ] `grep -qE 'git status --porcelain|git ls-files --others' plugins/ohaze/commands/ship-review.md`(含 untracked 收集)
- [ ] `grep -qE 'realpath|absolute path' plugins/ohaze/commands/ship-review.md`(路径 normalize)
- [ ] `grep -qE '5 (文件|files)' plugins/ohaze/commands/ship-review.md`
- [ ] `grep -q '接受宽修' plugins/ohaze/commands/ship-review.md`
- [ ] `grep -q '缩 scope' plugins/ohaze/commands/ship-review.md`
- [ ] `grep -q '升级 ship' plugins/ohaze/commands/ship-review.md`

---

### Task 6: 文档落档 (plugin.json + CHANGELOG + ROADMAP + CLAUDE + README)

**Files (change):**
- `plugins/ohaze/.claude-plugin/plugin.json`
- `CHANGELOG.md`
- `ROADMAP.md`
- `CLAUDE.md`
- `README.md`

**Changes:**

#### 6.1 — `plugin.json` version bump

`"version": "2.1.3"` → `"version": "2.2.0"`

(MINOR bump:新 command + 新 skill = 新 feature)

#### 6.2 — `CHANGELOG.md` 升 [2.2.0] 主条目

把现有 `## [Unreleased]` 段内容(codex-output-persistence)合并进新 `## [2.2.0] - 2026-06-15` 段,并加 debug-command 主条目:

```markdown
## [Unreleased]

### Added

### Changed

### Fixed

### Removed

## [2.2.0] - 2026-06-15

v2.2.0 主题:**新增「应对修复」档位 `/ohaze:debug`** —— ship 之外第 2 个流程档位,systematic 4 阶段根因调研 + scope lock + 3 个 conditional gate 形状。

### Added

- **`/ohaze:debug` 命令 / debug-command**:跟 `/ohaze:ship` 平级独立"应对修复"档位。共用 ship 的成熟元素(worktree、cross-source review、`ohaze:finishing` 合并),砍掉 feature-dev 专属 phase(BDD brainstorm、spec audit),引入 systematic-debugging 4 阶段 (root cause → pattern → hypothesis → implementation) + 3 个 conditional gate (G1 根因偏离 / G2 3-strike / G3 blast-radius) + scope lock 物理约束 (hypothesis 形成后 codex 物理冻结到 hypothesis 涉及的文件白名单)。新文件:`plugins/ohaze/commands/debug.md` (debug 主流程编排) + `plugins/ohaze/skills/systematic-debugging/SKILL.md` (fork superpowers v5.1.0,MIT,加 G1 gate + scope_lock_files 产出 + ohaze hand-off 协议) + `plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md` (新 skill,把 investigation_report + fix_plan + scope_lock_files 翻译成 codex XML,含 `<editable_files>` / `<readonly>` / `<anti_regression>` 三段强约束)。dogfood 使用场景:小 bug 修复(2-3 文件改动),haze 在 brief 阶段就知道这是 bug 而不是新 feature 时选 debug 走轻档。
- **`/ohaze:ship` 反向跳转兜底 (Phase 1 + Phase 1.5)**:埋 2 处 brief shape 检测的 AskUserQuestion 兜底,当 brief 形状像 bug 修复 (Scenarios 全是"修复 X" / 无 happy path / stack trace 关键词) 或 Phase 1.5 code-reading 发现 code refs 偏 fix-shaped (refs 集中在 stack trace 文件 / 最近 CHANGELOG Fixed 段) 时,提示 haze 切到 `/ohaze:debug` 走轻档。捕捉 "下意识打 ship 修 bug" 这种典型错位场景。
- **`current-ship.json.ship_mode` 字段**:新枚举 `"ship" | "debug"`,默认 `"ship"`,debug.md 显式写 `"debug"`。`ship-review.md` 据此分流 G3 blast-radius 检查 (ship 模式跳过,debug 模式 touched count > 5 时 AskUserQuestion)。其他下游 skill (finishing、codex-executor) 暂不分流;后续 `/ohaze:auto-ship` / `/ohaze:loop` 命令各自 ship 时按需扩展。

### Migration

- 旧 `.ohaze/current-ship.json` 缺 `ship_mode` 字段 → `ship-review` 视为 `"ship"`,向后兼容。无需手动迁移。

### Removed

- `## [Unreleased]` 之前的 codex-output-persistence Fixed 条目移入 `## [2.2.0] Fixed` 子段一并发布(已包含,见上)。
```

(把 [Unreleased] 段 codex-output-persistence 整段挪到 [2.2.0] Fixed 段)

#### 6.3 — `ROADMAP.md` Backlog 第 1 条移到 当前主线 完成 checkbox

修改:

`## 当前主线` 段重写为:
```markdown
## 当前主线
v2.2.0 流程档位扩展:新增 `/ohaze:debug` 应对修复档位。

- [x] `/ohaze:debug` 命令 (fork superpowers:systematic-debugging + ohaze 改造 + 新 debug-to-codex-prompt skill)
- [x] `/ohaze:ship` 反向 reframe 跳转兜底 (Phase 1 + Phase 1.5)
- [x] `current-ship.json.ship_mode` 字段 + ship-review G3 blast-radius 分流
```

`## Backlog` 段删除第 1 条(debug-command),保留剩余:
```markdown
## Backlog
- **`/ohaze:auto-ship` 命令(流程档位:中 — 小功能轻流程)**:...(保留原文)
- **`/ohaze:loop` 命令(流程档位:零 — goal 驱动全自动无审)**:...(保留原文)
- 定期 diff superpowers v5.1.0 上游 brainstorming / using-git-worktrees SKILL.md(基线漂移监控)
- 如果观察到 plan-drift rate 超过可接受阈值,...(保留原文)
- spec-to-codex-review schema 校验脚本兜底:...(保留原文)
```

`## Backlog` 加新条目:
```markdown
- 定期 diff superpowers v5.1.0 上游 systematic-debugging SKILL.md(新 fork 基线漂移监控,与 brainstorming/using-git-worktrees 同源)
```

#### 6.4 — `CLAUDE.md` 关键文件/入口 段更新

`## 关键文件 / 入口` 段:

- 入口段加入:`debug` 命令
- 核心 skills 段加入:`systematic-debugging`(fork) / `debug-to-codex-prompt`

具体改:
- `入口: `plugins/ohaze/commands/` —— `ship` / `ship-review` / `ship-finish` / `status` 四条 slash command` → `入口: `plugins/ohaze/commands/` —— `ship` / `debug` / `ship-review` / `ship-finish` / `status` 五条 slash command`
- 核心 skills 行加 `systematic-debugging`(fork) / `debug-to-codex-prompt` 两个新 skill

`## Agent 行为约定` 段:
- 加入 "项目特殊约定:`/ohaze:debug` 与 `/ohaze:ship` 平级独立,handoff JSON 用 `ship_mode` 字段区分;ship-review G3 blast-radius 检查只在 `ship_mode=debug` 时触发"
- 流程序段加入 debug 序:`debug 流程序: pre-flight → systematic-debugging (含 G1) → worktree → debug-to-codex-prompt → Codex execute → ship-review (含 G3) → ship-finishing`

`## 版本` 字段:`2.1.3` → `2.2.0`

#### 6.5 — `README.md` 命令清单加 `/ohaze:debug`

定位:简介段后或 命令清单 表格里,加一行:`/ohaze:debug` — bug 修复模式,systematic 4 阶段调研 + scope lock + 3 conditional gate,轻于 ship。

具体行号由 Codex 在实施时 grep 现有 ship 命令的位置就近插入。

**Behavior Contract:**
- 5 个文件改动后,版本号一致 (2.2.0)
- CHANGELOG 新版 entry 包含完整三个 Added 主条目
- ROADMAP Backlog 第 1 条移到 当前主线 (checkbox 全打勾)
- CLAUDE/README 反映新命令

**Acceptance (grep / structural):**
- [ ] `grep -q '"version": "2.2.0"' plugins/ohaze/.claude-plugin/plugin.json`
- [ ] `grep -q '## \[2.2.0\] - 2026-06-15' CHANGELOG.md`
- [ ] `grep -q '/ohaze:debug 命令 / debug-command' CHANGELOG.md`
- [ ] `grep -q 'ship_mode' CHANGELOG.md`
- [ ] `grep -q '/ohaze:ship.* 反向跳转兜底' CHANGELOG.md`
- [ ] `grep -q 'v2.2.0 流程档位扩展' ROADMAP.md`
- [ ] `grep -qE '\[x\] .*\/ohaze:debug 命令' ROADMAP.md`
- [ ] `grep -qE '\[x\] .*ship_mode' ROADMAP.md`
- [ ] `! grep -q 'debug.*流程档位:轻' ROADMAP.md` (该 backlog 条已移走,grep 反断言)
- [ ] `grep -q 'systematic-debugging' CLAUDE.md`
- [ ] `grep -q 'debug-to-codex-prompt' CLAUDE.md`
- [ ] `grep -q '版本: 2.2.0' CLAUDE.md`
- [ ] `grep -qE '/ohaze:debug.*bug 修复' README.md`

---

### Task 7: Dogfood 端到端 read-only 冒烟验证

**Files:** none(read-only,grep + JSON-load)

**Changes:** 无文件改动,仅在 Codex 完成 Task 1-6 后跑这些断言确认结构完整。

**断言**:

7.1 **JSON-load 验证**:
```bash
python3 -c "import json; v = json.load(open('plugins/ohaze/.claude-plugin/plugin.json'))['version']; assert v == '2.2.0', f'expected 2.2.0 got {v}'"
```

7.2 **Skill frontmatter 验证**:
```bash
python3 -c "
import re
for path in [
    'plugins/ohaze/skills/systematic-debugging/SKILL.md',
    'plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md',
]:
    content = open(path).read()
    assert content.startswith('---\n'), f'{path}: missing frontmatter'
    m = re.search(r'^name: (\S+)', content, re.M)
    assert m, f'{path}: missing name field'
    assert m.group(1) == path.split('/')[-2], f'{path}: name mismatch'
print('all skill frontmatter OK')
"
```

7.3 **debug.md frontmatter + 引用完整性**:
```bash
grep -q 'description:' plugins/ohaze/commands/debug.md
grep -q 'Skill(ohaze:systematic-debugging)' plugins/ohaze/commands/debug.md
grep -q 'Skill(ohaze:debug-to-codex-prompt)' plugins/ohaze/commands/debug.md
grep -q 'Skill(ohaze:codex-executor)' plugins/ohaze/commands/debug.md
grep -q 'Skill(ohaze:finishing)' plugins/ohaze/commands/debug.md  # via finishing chain
```

7.4 **ship.md 兜底点结构验证**:
```bash
# 两处 reframe checkpoint 都有
grep -c 'reframe checkpoint' plugins/ohaze/commands/ship.md  # ≥ 2
# handoff schema 加了 ship_mode
grep -q '"ship_mode"' plugins/ohaze/commands/ship.md
```

7.5 **ship-review.md G3 完整性**:
```bash
grep -q 'G3 — Blast-Radius Gate' plugins/ohaze/commands/ship-review.md
grep -q 'ship_mode' plugins/ohaze/commands/ship-review.md
grep -q 'blast_radius_escalated' plugins/ohaze/commands/ship-review.md
```

7.6 **没有引入新外部 skill 依赖**:
```bash
# debug.md 不该出现 superpowers: 引用
! grep -qE 'superpowers:[a-z-]+' plugins/ohaze/commands/debug.md
# systematic-debugging 也不该(自持版)
! grep -qE 'superpowers:[a-z-]+' plugins/ohaze/skills/systematic-debugging/SKILL.md
# debug-to-codex-prompt 也不该
! grep -qE 'superpowers:[a-z-]+' plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md
```

7.7 **CHANGELOG/ROADMAP 一致性**:
```bash
# 版本号在三处一致
grep -q '"version": "2.2.0"' plugins/ohaze/.claude-plugin/plugin.json
grep -q '## \[2.2.0\]' CHANGELOG.md
grep -q '版本: 2.2.0' CLAUDE.md
# Backlog 中 debug-command 条已移走
! grep -qE '^\- \*\*`/ohaze:debug` 命令.*流程档位:轻' ROADMAP.md
# 当前主线 checkbox 全打勾
grep -cE '^\- \[x\]' ROADMAP.md  # ≥ 3 (debug + reframe 兜底 + ship_mode 三条)
```

7.8 **跨文件 cross-reference 完整性**:
```bash
# debug-to-codex-prompt 引用 codex-executor 一致
grep -q 'codex-executor' plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md
# systematic-debugging 不引用 codex-executor (它是 Phase 1 前置,不调 codex)
! grep -qE 'codex-executor' plugins/ohaze/skills/systematic-debugging/SKILL.md
```

**Behavior Contract:**
- 全部断言 pass = Codex 实施完整且无破坏
- 任一断言 fail = reviewer 报 CRITICAL

**Acceptance:**
- [ ] 7.1-7.8 全部 grep / python3 断言 exit 0

---

## Out of Scope

明确**不做**的事:

1. **新 entry 命令 `/ohaze:debug-review` / `/ohaze:debug-finish`** —— debug ship 复用 `/ohaze:ship-review` 和 `/ohaze:ship-finish`,通过 handoff `ship_mode` 字段分流。不增加并行命令路径
2. **修改 `codex-executor` 或 `finishing` skill** —— 两个核心 skill 跟 ship 共用,debug 走相同路径(G2 3-strike 复用现有 codex-executor Phase 6 max-3 retry;finishing 走相同 6/7 选项菜单)
3. **Auto-classify symptom 自动调研路由** —— haze 显式给 symptom + 可选 cause,不需要 AI 帮忙判断 "这是什么类型的 bug"
4. **跨命令跳转的 `/ohaze:auto-ship` 和 `/ohaze:loop` 端兜底** —— 两个命令本期不存在,等它们各自 ship 时各自加 reframe 兜底
5. **inline 修复辅助 (5 分钟小 bug)** —— haze 自己在 Claude Code 编辑器里改,debug 不提供 inline 修工具
6. **G3 阈值动态化 (按项目类型/历史 ship 调阈值)** —— v2.2 写死 5 文件,先 dogfood 验证再考虑动态阈值
7. **investigation report 独立落档目录 `docs/ohaze/debug/`** —— 只写进 CHANGELOG `[Unreleased]` Fixed 段,investigation 临时存 `.ohaze/investigation-<slug>.md` 不 commit
8. **debug 模式专属 finishing menu** —— 复用 ship 同款 6 选项 + 7th Security Review;Security Review trigger (`web/api` 项目) 对 debug 一样生效
9. **修 debug 模式的 G3 反复触发** —— v2.2 写 loop max 2,超过 = 升级 ship;后续按需扩展
10. **删除 superpowers v5.1.0 systematic-debugging fork 基线参考** —— Attribution 段保留,后续 dream 跟踪上游漂移

## Risks

### R1 — systematic-debugging Phase 1-3 在 Claude main 主线程跑 vs Phase 4 Codex 跑,认知边界容易模糊

**风险**:LLM 容易在 systematic-debugging Phase 4(产出 fix_plan 文本)时 "顺手"直接 Edit 代码,违反 "skill 不写文件" 的契约。

**Mitigation**:
- skill frontmatter description 明示 "Phase 1-3 are Claude main-thread; do NOT dispatch codex, do NOT modify code"
- Phase 4 段加 BOLD 警示 "Claude main-thread does NOT modify code here. Produce fix_plan TEXT only."
- `/ohaze:debug` Phase 4 才 dispatch codex(明确 separation)
- review 阶段验证:`git -C <main_repo_path> log --oneline base..HEAD`,若发现 Claude 在 systematic-debugging skill 跑时已经 commit,review 报 CRITICAL "skill 越界写文件"

### R2 — G1 "调研结果与猜测一致" 判定主观

**风险**:Phase 1 hypothesis 跟 haze 给的 `cause_hypothesis` 语义相似但表达不同时,LLM 可能误判为"不一致" 触发不必要 G1 gate(扰民) 或反之误判 "一致" 跳过应有 gate。

**Mitigation**:
- skill Phase 1 G1 段写明 "semantically aligned, not necessarily verbatim"
- 不一致触发的 AskUserQuestion 第 1 选项 "接受调研根因" 是 Recommended,扰民代价是按一下回车
- Edge case fallback:LLM 不确定时倾向触发 gate(safe default)
- 后续 dogfood 观察误触发率,>30% 再加固判定

### R3 — codex 0.137 不提供文件级 sandbox,scope lock 通过三层防御组合实现

**风险**:`codex exec --sandbox` 只支持 `read-only`/`workspace-write`/`danger-full-access` 三档,不提供白名单 sandbox。brief 中"物理冻结"无法用一层机制达成,只能用 KD6 三层防御组合(L1 prompt 强约束 + L2 review 强制断言 + L3 G3 兜底)。

**Mitigation**(对应 KD6 三层):
- **L1 (Prompt 强约束)**:debug-to-codex-prompt XML 模板内 `<editable_files>`/`<readonly>` 两段 + 明示 `scope_lock_breach_requested:` escape hatch 协议(codex 必须报告而非偷偷违反)。历史观察:gstack:investigate 同款 prompt 软约束实战可用(haze 看 reference 评估过)
- **L2 (Review 强制实跑)**:ship-review.md G3 检查之前**强制运行** `git -C <worktree_path> diff --name-only <base_ref>..HEAD`,跟 handoff `scope_lock_files` 字段逐项比对,出现白名单外文件 → 自动加 CRITICAL finding(reviewer prompt 模板里写死这一项,不允许 reviewer 跳过)
- **L3 (G3 blast-radius 兜底)**:touched count > 5 或 L2 检测到越界 → AskUserQuestion(接受 / 缩 scope / 升级 ship)
- **未来升级路径**:codex CLI 0.140+ 若提供文件白名单 sandbox 能力,升级 L1 到真正物理冻结,L2/L3 保留作为兜底

### R4 — `ship.md` 2 处 reframe 兜底误触发率高,扰民

**风险**:Phase 1 brief shape 检查的 "≥ 2 信号" 判定可能在 feature dev 场景误触发,每次 ship 都被问 "是不是要切 debug",疲劳。

**Mitigation**:
- 信号阈值定为 ≥ 2 (4 个信号中 2 个),不是 ≥ 1(过敏感),不是 ≥ 3(过迟钝)
- AskUserQuestion 第 2 选项 "继续 ship" 是 Recommended,默认不切
- Phase 1.5 兜底信号是 ≥ 2 of 3,更严
- 后续 dogfood 观察误触发率,> 25% 则调阈值或加更多信号纬度

### R5 — debug-to-codex-prompt XML `<editable_files>` 路径过长导致 codex 上下文爆

**风险**:scope_lock_files 列表 > 20 文件时,XML 嵌入文件路径列表会占大量 token。

**Mitigation**:
- Phase 3 systematic-debugging 产出 scope_lock_files 时就有"conservative" 准则(不打 wildcard,只列具体文件)
- 自然限制:hypothesis 形成后能名出来的根因文件通常 ≤ 5
- 异常情况:scope_lock_files 列表 > 20 时,debug-to-codex-prompt 加 warning(可后续 ship 实现)
- 跟 G3 blast-radius 互补:实际改超过 5 文件已经触发 G3 干预

### R6 — Manual restart 接受路径用户体感

**风险**:KD9 决定 reframe 接受 = manual restart 而非 in-process 转换。haze 在 ship 走到一半被告知"打 `/ohaze:debug` 重启" 可能觉得"为什么不自动转",影响 reframe 兜底使用率。

**Mitigation**:
- ship 退出消息附带 symptom 模板(从 brief 第一句 / spec 标题自动生成),haze 复制粘贴一次就行
- 后续观察 dogfood reframe 接受率:若 < 15% 且 haze 反馈摩擦大,v2.3 评估加 in-process 转换
- 实际"轻流程"价值在 debug 内部 phase 简化(systematic-debugging + scope lock + G1),manual restart 的 1 个命令开销远小于走完整 ship 的开销

## Verification (dogfood expectations)

### V1 — 端到端跑 `/ohaze:debug` 一次冒烟

成功标准:
- Pre-flight 不卡(codex CLI 在,main_repo_path 解析)
- Phase 1 systematic-debugging 启动,产出 4-phase 调研报告 + scope_lock_files + fix_plan
- Phase 2 worktree 创建,investigation note 落 `.ohaze/investigation-<slug>.md` 但不 commit
- Phase 3 debug-to-codex-prompt 产出 XML(含 `<editable_files>` `<readonly>` 9 段)
- Phase 4 codex dispatch 成功(thread.started 30s 内,bg_id 持久化)
- harness re-invoke 进 ship-review,state gate 识别 `ship_mode=debug`
- G3 检查:若实际 fix 触及文件数 ≤ 5,跳过 gate 直接进 review;否则 AskUserQuestion
- Review subagent 跑(general-purpose),real test command 执行(为 markdown plugin = per-task grep assertions)
- 走 finishing menu(同 ship 同款 5/6/7 选项)
- 完成后 CHANGELOG `[Unreleased]` Fixed 段有 debug ship 的一条 entry

### V2 — 跨命令 reframe 兜底冒烟

成功标准:
- 启动 `/ohaze:ship "修复 stuff"` 故意写 bug-shaped brief
- Phase 1 brainstorming 终态后兜底点触发 AskUserQuestion
- 选 "切到 debug" → ship 干净退出(没建 worktree),提示 haze 用 `/ohaze:debug` 重启
- 选 "继续 ship" → 正常进 Phase 1.5

### V3 — handoff schema 向后兼容

成功标准:
- 旧 v2.1.3 ship 的 `.ohaze/current-ship.json` 缺 `ship_mode` 字段
- 新 v2.2.0 `ship-review.md` 读到缺字段时不报错,视为 `"ship"` 走原流程
- G3 不触发(因为 ship 模式跳过)

### V4 — debug skill self-test (read-only)

成功标准:
- `grep -q '^name: systematic-debugging$' plugins/ohaze/skills/systematic-debugging/SKILL.md`
- `grep -q '^name: debug-to-codex-prompt$' plugins/ohaze/skills/debug-to-codex-prompt/SKILL.md`
- `grep -cE 'G[123]' plugins/ohaze/commands/ship-review.md` ≥ 1(G3 引入)
- `grep -cE 'G[123]' plugins/ohaze/skills/systematic-debugging/SKILL.md` ≥ 2(G1 + G2)
- 所有 grep 断言(Task 1-7 acceptance)pass

### V5 — fork attribution 完整

成功标准:
- `grep -q 'Forked from' plugins/ohaze/skills/systematic-debugging/SKILL.md`
- `grep -q 'MIT license' plugins/ohaze/skills/systematic-debugging/SKILL.md`
- `grep -q 'superpowers' plugins/ohaze/skills/systematic-debugging/SKILL.md`(at least Attribution 段)
- 同 v2.0 fork brainstorming / using-git-worktrees 同款 attribution 模板

## Self-Review Notes

写 spec 过程中的关键决定:

1. **KD1-KD8 八个关键设计决定**:都在 brief "Claude 替你决定的关键技术方向" 段回填了,haze 可事后扫
2. **不调用 codex-executor 以外的 brainstorming/writing-plans/spec-to-codex-review**:Task 1 Acceptance 用反向 grep 断言强约束
3. **Risks R1-R5 五条**:每条都给了 mitigation;最严重是 R3 scope lock soft enforcement,叠加 G3 blast-radius 物理兜底 + review CRITICAL 检测可控
4. **Task 拆分 7 个 (含 dogfood 验证 Task 7)**:1 主 command + 2 新 skill + 1 改 ship + 1 改 ship-review + 1 文档落档 + 1 read-only 冒烟;符合历史 ship 5-7 task 范围
5. **未触发 5 boundary-question 任一**:Phase 1.5 不需要 AskUserQuestion 产品问题 → 直接落 spec
