# ohaze v2.0.0 重构设计

> Spec 日期: 2026-06-09 · 状态: 待 haze review → writing-plans
> 类型: 发行产品（Claude Code plugin）· break 级重构 → v2.0.0

## 一句话目标

**ohaze 独立成一个自包含的 ship 流程，零运行时外部 skill 依赖** —— fork 自持它真正用到的、内化它需要的、修掉已知坑、剥离 vault 镜像、对齐四件套文档约束。

## 背景与驱动

- **核心矛盾：链路碎/易断** —— `ship` / `ship-review` / `ship-finish` 三命令 + `nohup codex &` + `ScheduleWakeup(600s)` 轮询 + `current-ship.json` handoff，跨 session 接力链复杂、易断、有幽灵唤醒 bug。
- **superpowers 解耦** —— ohaze 久未更新；调研（2026-06-08）显示 superpowers 近 1 个多月已无能力级 commit（停在 v5.1.0），解耦窗口安全。haze 决定彻底解耦。
- **文档对齐债** —— 现行全局约束是**四件套**（CLAUDE/README/ROADMAP/CHANGELOG），但 ohaze 残留过期的"五件套/VAULT-CONTEXT"（`vault-system/docs/5-piece-set-schema.md` 已删，README:152 死链）。
- **vault 剥离** —— vault 镜像是 ohaze 对 `~/Brain` 的外部耦合，先剥离让 ohaze 独立，后续再用解耦方式重连。

## 起因与调研依据（过程留档）

**完整动机（haze 2026-06-08 提出）**：① 主线 = **优化链路**（三命令 + `ScheduleWakeup` 轮询 + handoff 碎而易断，有幽灵唤醒 bug）；② superpowers 久未对齐；③ **Codex 干对抗必须保留**；④ 一批细节优化（开工查项目状态、收尾文档对齐、worktree/cwd）；⑤ 对齐现行文档约束。

**superpowers 解耦调研（2026-06-08）**：
- 频率：历史周更偏日更，近 1 个多月骤降月更级、**零能力 commit**，停在 v5.1.0。
- **反直觉洞察**：ohaze 的"落差"不是没跟上 superpowers，而是 **superpowers 在 5.0→5.1 重写了 worktree/brainstorm 契约、ohaze 仍按旧契约调** —— 这才是真正的对齐债。
- 真依赖盘点：运行时**只真依赖 2 个** skill（`brainstorming` + `using-git-worktrees`）；`writing-plans` 早已 fork、finishing/审查早已自持。
- 窗口判断：解耦踏空风险**中但不紧急**（上游能力迭代已停 5 周）= 安全窗口。

**方案选择**：备选 A 激进收敛(单命令) / B 精准解耦(只解 worktree、保 brainstorming) / C 最小手术；haze 定 **彻底解耦（brainstorming + worktree 全自持）**，但 **fork 子集非整仓**（14 个 skill 只用 2–3 个，整仓是死重）。

**md-init/neat 内化的本质**：二者是「四件套契约」的可执行化身（md-init 立契约、neat 守契约），目的是让四件套成为**人 + agent 共同消费的可信结构化真相源** —— 故内化其逻辑、止于四件套、不碰 vault 层 `decisions/`。

## 总纲决策汇总

| 维度 | 定稿决策 |
|---|---|
| superpowers | 全解耦，**fork 子集**（brainstorming 砍 companion + using-git-worktrees），零运行时外部 skill 依赖 |
| 执行引擎 | Codex 保留，**异源对抗**（Codex 写 / Opus 审，刻意异模型异厂）|
| 后台机制 | `run_in_background`（**无 nohup**），完成即 harness re-invoke |
| 防幽灵唤醒 | **review 幂等状态门**；ScheduleWakeup 降级为长 fallback（dogfood 已验证 re-invoke 可靠，可不设）|
| 流程序 | **先 worktree 再 brainstorm/spec**，分支名从 feature 描述 slug，spec 落 feat 分支，main 全程干净 |
| 项目定位 | ship 加**显式项目路径参数**，不靠 pwd（harness 会重置 cwd，dogfood 实证）|
| 文档内化 | 内化 md-init（开工四件套完备性检查）+ neat（收尾完整落点路由），**止于四件套，不碰 decisions/** |
| vault | **流程层剥离**（删 hooks + adapter + ship-result.json + .vault-sync-state.json），`.ohaze/*.json` 保留为 ship 自身状态，不预留重连接口（YAGNI）|
| 审查 | 异源 + **实跑验证**（不只读 diff）+ retry **卡住升级**；DOC-DRIFT(发现)/doc-finish(修复) 分工 |
| 编排 | **CLI + harness（dogfood 验证）**：主 agent `Bash(run_in_background)` 调 codex exec + 薄 markdown 编排；**不用 codex SDK**（要 Node orchestrator，会架空 Claude 异源 review）；骨架至多包小 shell 助手 |
| 文档维护 | **四件套对齐**（删 VAULT-CONTEXT.md + 修 README:152 死链）|
| 版本 | **v2.0.0** |

## 目标架构

### 主流程（Phase 1/2 已对调）

```
/ohaze:ship "需求"
│
├─ Pre-flight  检查 codex CLI(硬依赖) + 分支安全(当前分支==目标?工作区干净?)
│              + 四件套完备性(内化 md-init,缺则按类型补,齐则跳过;在主仓内做)
│              ※ 目标项目用显式路径参数锁定，不靠 pwd（harness 重置 cwd）
├─ Phase 1  建 worktree + cd 进去   ← 自持 using-git-worktrees(fork)，分支名 = feature 描述 slug
├─ Phase 2  brainstorm + 写 spec + commit  ← 自持 brainstorming(fork,砍 companion)，spec 落 feat 分支
├─ Phase 3  writing-plans → guidance plan   ← 已自持
├─ Phase 4  plan→XML + run_in_background 跑 codex exec(无 nohup) → 捕获 thread_id
│           ⟳ harness 完成即 re-invoke ── 经「幂等状态门」──┐
├─ Phase 5  补 commit → 审查(异源对抗 + 实跑验证) → verdict ←┘
│              ├ PASS → Phase 7
│              └ FAIL → Phase 6
├─ Phase 6  retry(卡住升级, ≤3)：codex exec resume <thread_id> → 修完回 Phase 5
└─ Phase 7  finishing: 状态门菜单 + doc-finish(内化 neat 完整路由) + 收尾链(删 worktree 前 cd 回主仓)
```

### 模块结构（`plugins/ohaze/`）

| 目录 | 重构后 |
|---|---|
| `commands/` | `ship` / `ship-review`(**幂等重入口**) / `ship-finish` / `status` |
| `skills/` | **+brainstorming(fork砍companion)** **+using-git-worktrees(fork)** / writing-plans(已fork) / plan-to-codex-prompt / codex-executor / finishing |
| `hooks/` `adapters/` | **整个移除**（vault 剥离）|
| `.ohaze/*.json` | 保留为 ship 自身状态，状态机精简（不再被 adapter 字段绑死）|

## 设计细节

### 1. superpowers 全解耦（fork 子集）

- **fork `brainstorming`** 进 `skills/`：**砍掉 visual companion**（web server，自动流用不上），只留「文本澄清 → 设计 → 写 spec」核心。改 spec 落档时机为 worktree-aware（不在 main commit）。
- **fork `using-git-worktrees`** 进 `skills/`：带上 v5.1.0 的环境检测（已在 worktree 内则跳过）+ cwd 安全；内建「删 worktree 前 cd 回主仓」。
- **`writing-plans`** 已 fork（`ohaze:writing-plans`），保留 + **确认 MIT 署名**（法律义务）。
- **清理**：plugin.json description/keywords 去 superpowers；移除各处 "Do NOT invoke superpowers:X" 负向声明；ship.md Phase 1/2 调用点改指 ohaze 自持 skill。
- **锁基线 + 检查点**：锁 superpowers v5.1.0 形态；留一个「定期 diff 上游 brainstorming/using-git-worktrees SKILL.md」的兜底说明。

### 2. 流程重排（worktree-first）

- **分支名 = ship feature 描述（`$ARGUMENTS`）slug**，不再从 spec 文件名 derive → worktree 可最先建。例：`给登录页加双因子` → `feat/2fa-login`。
- spec 文件名复用同一 slug（`<date>-<slug>-design.md`），**在 worktree 内 commit**。
- main 全程不被碰，并行多 ship 互不污染，`merge --ff-only` 不再因 main 被 spec 污染而失败。

### 3. Codex 后台换血 + 幂等状态门

- **Phase 4**：纯 `Bash(run_in_background:true)` 跑 `codex exec --sandbox danger-full-access --cd <worktree> --json`，**不加 nohup/&**。harness 追踪 codex 进程，完成即 re-invoke 主循环（dogfood 已验证）。放弃「/exit 后 codex 还活」韧性（haze 确认）。
- **幂等状态门**：`current-ship.json` 的 `state`，所有 review 入口（re-invoke / 手动 ship-review / wakeup）第一步读它：

  | state | 动作 |
  |---|---|
  | 不存在 / `done` / `discarded` | 静默 no-op 早退（幽灵唤醒在此被吃掉）|
  | `running` | 不动，等 re-invoke |
  | `codex_done` | 跑 review |
  | `review_fail` | 进 retry |
  | `kept` / `self-edit-pending` | 提示 `ship-finish` 恢复 |

- **ScheduleWakeup**：不再做 600s 轮询。主触发 = re-invoke。可选长 fallback（1200s+）同样过状态门；dogfood 已验证 re-invoke 可靠，**可完全不设**。

### 4. 审查增强（codex-executor）

- **异源对抗写死**：审查 subagent = `general-purpose`（继承 Opus），刻意异于 Codex；spec 禁止改成 Codex 自审，也不用 `codex exec review`（同源）。
- **实跑验证**：审查必须实跑 project test command + 关键验证，用真实输出下 verdict，不只读 diff（内化 verification-before-completion）。
- **retry 卡住升级**：连续 FAIL 同一类 issue → 先诊断「plan 问题 vs Codex 问题」（内化 systematic-debugging），不盲目 resume 到第 3 次；指向 plan 则回退修 plan，指向执行考虑 Claude 介入。
- **DOC-DRIFT / doc-finish 分工**：审查 PART3 只「发现」描述失真（advisory，写 review-verdict.json），doc-finish 统一「路由归位 + 修复」，不重复检测。

### 5. 文档契约内化（四件套）

- **Pre-flight 内化 md-init**：检测四件套是否齐，缺则按项目类型补（发行产品全铺 / 工作流仅 CLAUDE），齐则跳过；**仅缺失时触发**（md-init 会问类型、打断自动流）。逻辑内化，不调 hazeflow skill。
- **doc-finish 内化 neat 完整路由**：现有「CHANGELOG `[Unreleased]` + bump 版本 + tick linked_todo + drift 修复」升级补齐：待办→ROADMAP Backlog、bug→ROADMAP Bug、架构→README+CLAUDE、命令→README。真相源 = spec+plan+Codex report+git diff（ship 场景 Codex 干活不在对话里，不套 neat 的"对话为真相源"）。
- **边界**：内化止于四件套，**绝不碰 `decisions/`**（vault 层，本次剥离）。

### 6. vault 剥离

- **删** `hooks/hooks.json` + `adapters/vault-adapter.sh`。
- **保留** `.ohaze/current-ship.json`（续跑核心）+ `review-verdict.json`（审查结论）作为 ship 自身状态；解除「为触发 hook 必须用 Write 工具」硬约束。
- **删** `VAULT-CONTEXT.md` + 修 `plugins/ohaze/README.md:152` 死链；README/CLAUDE 去 vault 镜像 / 数据契约 / 五件套描述。
- **不预留**重连接口；未来再设计「事件外露、消费方自取」式接口。

### 7. 数据契约（vault 剥离后 `.ohaze/*.json`）

vault 剥离后这些文件不再触发 hook，角色回归「ship 自身状态」，大幅精简：

**`current-ship.json`（保留 — ship 续跑 + 状态门核心）**
- `state`：`running`|`codex_done`|`review_fail`|`kept`|`self-edit-pending`|`done`|`discarded`
- `slug` / `branch` / `base_ref` / `worktree_path` / `main_repo_path` / `spec_path` / `plan_path`
- `retries`（计数）
- **`thread_id`**（codex exec 的 `--json` `thread.started.thread_id`，用于 `codex exec resume`）/ `codex_bg_id`（run_in_background 任务 ID，**取代旧 pid_file/log_file**）
- `linked_todo`（doc-finish tick 用）/ `project_type`（finishing 检测后写回）
- **删**：`codex_session_id`(旧名,统一为 `thread_id`) / `codex_run_id` / `codex_job_id` / `codex_pid_file` / `codex_log_file` / `started_at` 等 vault/pid 专用字段

**`review-verdict.json`（保留 — 消费方转 ship 内部）**：`iteration` / `verdict`(PASS|FAIL) / `issues`[] / `doc_drift`[]。retry 读 issues、doc-finish 读 doc_drift；不再触发 hook、无需强制 Write 工具。

**`ship-result.json` + `.vault-sync-state.json`（删除）**：纯 vault hook 触发器/缓存，剥离后 finishing 主线程直接收尾，无需写文件触发。

### 8. 审查闭环 codex 命令契约 + 上下文传递

> 命令契约据 **codex-cli 0.137.0 实测**厘定（本机 PATH codex = 0.137.0；dogfood 日志一度因工具层误报显示 0.50.0，已校正 —— 行为结论本就是 0.137.0 的）。
>
> **集成方式 = CLI exec + run_in_background（dogfood 验证），不用 codex SDK**：codex 0.137 虽有官方 SDK `@openai/codex-sdk`(TS)，但它是给 **Node orchestrator** 用的，而 ohaze 的 orchestrator 是 **Claude 主 agent** —— 用 SDK 会架空 Claude 异源 review（详见 §11）。故 codex 侧走下方 CLI 命令契约。resume 坑（对 `codex exec resume` 同样适用）：超长靠自动 compaction（旧细节摘要丢失）、跨目录 resume 需 `--all`、`--ephemeral` 不能 resume、反复启动有幽灵 token([#19996](https://github.com/openai/codex/issues/19996))。

**codex 命令契约：**
- 执行 `codex exec [opts] < prompt`；恢复 `codex exec resume <thread_id> [opts] < fix_prompt`（**exec 子命令**，区别于顶层交互 `codex resume`）。
- **session 捕获**：`--json` 首事件即 `{"type":"thread.started","thread_id":"<UUID>"}` —— 字段名是 **`thread_id`**（非 session_id），与 `~/.codex/sessions/.../rollout-*-<UUID>.jsonl` 文件名一致。捕获 = 解析 `--json` 首个 `thread.started` 事件。
- **拿 report**：从 `--json` 末尾的 message 事件提取。**实测：`-o/--output-last-message` 在 `--json` 下不产出文件，不依赖它**。
- **不用 `--ephemeral`**（要持久化 session 才能 resume）；codex exec **必须在真实 git 项目目录**跑（`/tmp` 下 exit 1）。

**双向上下文：**
- **codex → 审查者**：把 codex 的结构化 report（Tasks/Touched files/Notable choices）喂审查 subagent，理解意图、避免把自主选择误判为 bug。审查者上下文 = plan + spec + git diff + report。
- **审查者 → codex**：结构化反馈包，每条 issue 带 ①`file:line` ②违反的契约/验收标准（引 plan）③期望状态（*what* 非 *how*）。ADVERSARIAL 不下发给 codex（交 haze）。
- **连续性**：`codex exec resume <thread_id>` 同 thread。**防震荡**：第 N 轮 fix prompt 附「前几轮改了什么 + 为何仍 FAIL」。

### 9. 已知坑修复（防回退）

- **cwd 悬空**（1.9.2 已修，根因 CC 上游 #50960）：删 worktree 前 `cd "$main_repo_path"` —— 内建到 fork 的 using-git-worktrees + finishing 的 remove-worktree，别回退（dogfood 已复测有效）。
- vault 相关坑（路径死链、ff-merge commits=0）随 vault 剥离自然消失。

### 10. 控制流与控制权交接（review-fix 反复循环）

**核心：控制权在「主 agent」与「后台 codex」间来回，靠 harness 的 `run_in_background` 完成通知交接 —— 事件驱动，非轮询**（dogfood 已验证）。

```
主 agent (Claude 主线程)
  │ Bash(run_in_background) 启 codex exec → turn 立即结束    ← ① 让出（不阻塞）
  ▼
后台 codex 独立进程跑 → 进程退出
  ▼
harness 注入 <task-notification completed> → 自动 re-invoke   ← ② 控制权交回主 agent
  ▼
主 agent 唤醒 → 先过「幂等状态门」(读 current-ship.json.state)
  │ 派 general-purpose subagent 异源 review（同步等 verdict）
  ├ PASS → Phase 7 finishing
  └ FAIL → 结构化 fix prompt → codex exec resume <thread_id> + run_in_background  ← ① 再让出
       ▼  循环（retries+1，≤3；连续同类 FAIL → 卡住升级诊断）
```

- **① 主→codex（让出）**：`Bash(run_in_background:true)` 启动后 turn 立即结束，主 agent 不阻塞。
- **② codex→主（收回）**：codex 进程退出，harness 自动 re-invoke 主 agent。
- **谁在哪侧**：只有 **codex 执行/修改在后台**（需 ② 交接）；**review 全程在主 agent 侧**（同步派 subagent、始终在场）。交接机制是 **Claude Code harness 运行时能力（借用，ohaze 不自写）**；ohaze 只负责「让出」+「收回后做什么」（状态门→review→resume）。

### 11. 编排策略：AI 编排 vs shell 固化

- **现状**：流程几乎全交主 agent 读 markdown 指令执行；shell 仅 `vault-adapter.sh`（本次剥离）+ 零散 Bash，**无总控脚本**；控制权交接借 harness。
- **脆弱根源**：确定性步骤也交 AI 即兴 → 易跑偏（dogfood 实证：误入 /tmp、误判 cwd）。
- **plugin 范式硬约束**：AI 必然是顶层编排者，shell 不能「当老板」反调 AI（那需 SDK/headless）。故不可能「全 shell 控制」，但**可让 AI 编排变薄、确定性骨架下沉**。

| 环节 | 归属 | 理由 |
|---|---|---|
| brainstorm / **review 判断** / verdict / 组织 fix prompt / 卡住诊断 | **AI（必须）** | 需智能，异源审是灵魂 |
| 建/删 worktree、cd 管理、codex dispatch、session 捕获、状态机读写、retry 计数、跑测试 | **可固化为薄 shell** | 纯确定性，AI 即兴只会出错 |
| 控制权交接 | **harness（借用）** | dogfood 已验证 |

**决策（联网核实后定，2026-06-09）**：**不自写重 shell，也不用 codex SDK**。关键认知：ohaze 的 orchestrator 是 **Claude 主 agent**（非 Node 进程），而 `@openai/codex-sdk` 是给 Node orchestrator 用的；用 SDK = 把编排+codex 调用搬进 Node 脚本，**架空 Claude 异源 review**（ohaze 灵魂），与 §10 控制流冲突 → **不采用 SDK**。
- **正解 = CLI + harness（dogfood 已验证）**：主 agent 几条 `Bash(run_in_background)` 调 `codex exec`/`exec resume`，harness 管控制权交接，编排是**薄 markdown 指令** —— 本就不重，无需重 shell。确定性骨架（thread_id 捕获、状态机读写）至多包小 shell 助手，可选。
- `codex exec review` 同源自审、与异源对抗冲突，不采用。
- `codex mcp-server` 仅当未来想让 Claude Code 当 MCP host 同步调 codex 时备选（MCP 同步阻塞，不如 run_in_background 异步，当前不取）。
> ⚠️ 版本前提：统一到 codex 0.137（本机 PATH 已是）；§8 命令契约即 0.137 实测。

## 验证（dogfood 实测，2026-06-09）

已在真实 ohaze 项目端到端实跑一个 throwaway accordion ship（worktree→codex→review→discard），结论：

- ✅ **B1 成立（最关键）**：纯 `run_in_background` **完成即 harness 自动 re-invoke**，无需 nohup+ScheduleWakeup 轮询（两次后台任务均自动唤醒主 agent）。
- ✅ **session 捕获**：`--json` 首事件 `thread.started.thread_id`，与 `rollout-*.jsonl` 文件名 UUID 一致；字段名 **`thread_id`**。
- ✅ **cwd 悬空修复有效**：删 worktree 前 `cd` 回主仓（实测删除前 cwd 确在 worktree 内）。
- ✅ **异源 review + codex 不自 commit**：codex 做出 accordion、测试 4/4 全过、未自行 commit（符合约定）。
- ⚠️ **实测修正点（已并入上文）**：① `-o` 在 `--json` 下不产出 → report 从 `--json` message 事件提取（见 §8）；② codex exec 在 `/tmp` exit 1 → 必须真实 git 目录（见 §8）；③ ship 靠 pwd 但 harness 重置 cwd → 加显式项目路径参数（见决策汇总/架构）。

待补实测（非阻塞）：codex per-Task `verification_loop` 遵守度、retry 卡住升级、多轮 resume 上下文累积。（codex SDK/MCP 已联网核实，结论见 §11：不采用 SDK，走 CLI+harness。）

## 不做（YAGNI）

- 审查强度分级（按改动规模调深度）—— 增复杂度、收益低。
- 引入其他 superpowers skill 拓展流程 —— 违「减少依赖」；有价值的理念已内化进 prompt 文字。
- vault 重连接口预留 —— 先剥干净，未来再设计。
