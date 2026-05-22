# Finish Menu 重构 + 文档漂移自动修 + Codex Session 精确化 — Guidance Plan

> **For Codex (the executor):** Each Task below specifies WHAT must be true at completion, not HOW to write it line by line. You have autonomy over internal naming, control flow, helper extraction, and algorithm choice. You do NOT have autonomy over public interfaces, file paths in Files lists, acceptance criteria, or cross-Task invariants. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 ohaze ship 流程的 finishing 阶段认得项目类型并给一键推荐收尾、自动检测设计文档漂移、并修复并行 ship 下 Codex resume 接错会话的 bug。

**Architecture:** finishing 逻辑从 `ship-review.md` / `ship-finish.md` 两份近重复拷贝抽成单一 `ohaze:finishing` skill（消除当前及未来的菜单漂移）；reviewer 增加非阻塞的文档漂移检测 PART；Codex resume 从全局 `--last` 改为按 ship 启动时捕获的 session id 精确恢复。

**Tech Stack:** Claude Code 插件 —— Markdown skills（`SKILL.md`）+ commands（`commands/*.md`）。无构建、无运行时、无测试框架。

**验收方式（本项目特殊）:** ohaze 无可执行测试。每个 Task 的 Acceptance 用「文件存在性 / `grep` 模式命中 / 关键 section 存在 / JSON 字段存在」作为可机读判据。下文 TDD Sequence 适配为「判据先行 → 改文件 → `grep` 验证」——先把 Acceptance 的 grep 判据列清楚，再改文件，最后逐条 grep 确认。

---

## File Structure

| 文件 | 责任 | 本次 |
|---|---|---|
| `plugins/ohaze/skills/finishing/SKILL.md` | Phase 7 finishing 全部逻辑 | **新建** |
| `plugins/ohaze/commands/ship-review.md` | review/retry 循环 + 接入 finishing | 改：移除内联 finishing，改 invoke |
| `plugins/ohaze/commands/ship-finish.md` | 从暂停态恢复 + 接入 finishing | 改：移除内联 finishing，改 invoke |
| `plugins/ohaze/skills/codex-executor/SKILL.md` | Codex 派发 + review + retry/modify | 改：resume 用 session id + DOC-DRIFT PART + resume 边界 |
| `plugins/ohaze/commands/ship.md` | ship 主入口 | 改：Phase 4 捕获 codex_session_id + handoff 字段 |
| `plugins/ohaze/CLAUDE.md` | 项目说明 | 改：关键文件表 / 设计决策 / 阶段归属 / 版本 |
| `CHANGELOG.md` | 变更日志 | 改：新增 `[1.9.0]` |
| `plugins/ohaze/.claude-plugin/plugin.json` | plugin manifest | 改：`version` → `1.9.0` |

---

## Task 1: 新建 `ohaze:finishing` skill

**Files:**
- Create: `plugins/ohaze/skills/finishing/SKILL.md`

**迁移来源（必读）:** 现有 `plugins/ohaze/commands/ship-review.md` 的「Phase 7 — Finishing Menu」整段与「Modify Sub-Flow」整段。其中所有时序契约、失败处理、vault hook 注意事项**必须原样保留**，本 Task 只做「菜单形态 + 项目类型检测 + 文档收尾」三项改造。

**Behavior Contract:**

- **Skill 标识**：`name: finishing`；description 说明它 owns ohaze 工作流 Phase 7（finishing 菜单 + 收尾链执行 + 文档收尾 + modify 子流程），由 `ship-review.md` / `ship-finish.md` invoke。
- **输入**（从 caller 上下文 / handoff `current-ship.json` 取）：`worktree_path`、`base_ref`、`branch`、`plan_path`、`spec_path`、`retries`、`linked_todo`、`codex_session_id`、worktree 内 `.ohaze/review-verdict.json` 路径。
- **职责 1 — 项目类型检测（A6）**：基于**主仓**（非 worktree）执行 `git remote`；无输出 → `local`，有输出 → `remote`。把结果写回 `current-ship.json` 的 `project_type` 字段。
- **职责 2 — 偏好文件（A5）**：读 `~/.ohaze/finish-prefs.json`，取对应 `project_type` 的推荐链。文件不存在 / 条目缺失 / JSON 损坏 → 用内置默认链，且不阻塞（损坏时提示一句）。内置默认链：
  - `local`：`["doc-finish", "commit", "merge", "remove-worktree"]`
  - `remote`：`["doc-finish", "commit", "merge", "push", "remove-worktree"]`
- **职责 3 — 菜单**：先打印检测到的 `project_type` + 推荐链全文（让用户看清「选 1 会发生什么」），再用 `AskUserQuestion` 给 5 项菜单：
  1. 执行推荐收尾（一键到底）
  2. 继续修改
  3. 丢弃此次工作
  4. 先不处理（worktree 留着，稍后 `/ohaze:ship-finish`）
  5. 自定义收尾方案
- **职责 4 — 收尾链步骤化执行（A3）**：推荐链是一个有序步骤列表，步骤取值域 `doc-finish` / `commit` / `merge` / `push` / `pr` / `remove-worktree` / `keep-worktree`。执行契约：
  - 逐步顺序执行，每步执行后检查成功判据（git 命令退出码 / 预期状态）。
  - **任一步失败立即中止**：不执行后续步骤，把失败步骤名 + 错误原文报给用户，回到菜单。
  - 硬约束：`merge` 成功但 `push` 失败时，**禁止**继续执行 `remove-worktree`——worktree 与分支必须保留以便重试 push。
  - 失败中止后 `current-ship.json` 保持可恢复状态。
- **职责 5 — 文档收尾步骤（A2，即链中的 `doc-finish`，排在 `commit` 之前）**：统一处理两类文档改动——
  - (a) 进度可机读契约：向 `CHANGELOG.md` 追加 `[Unreleased]`/版本条目、bump manifest `version`、勾选项目 `CLAUDE.md`「当前目标」中 `linked_todo` 对应的 `- [ ]`。
  - (b) 漂移修复：读 `review-verdict.json` 的 `doc_drift` 数组，生成项目 `CLAUDE.md` 描述性 section 的同步 patch。
  - 两类合并为一份 patch 预览呈现给用户，用户可「全部接受 / 全部跳过 / 逐条挑」，确认后应用。
  - 无任何文档改动时静默跳过该步。
  - 文档改动由链的 `commit` 步骤提交为独立 `docs:` commit（代码改动已在 review 前由 codex-executor Phase 5.0 提交）。
- **职责 6 — modify 子流程（菜单项 2「继续修改」）**：保留现有三分支 5a（Codex 续跑）/ 5b（Claude 主线程直接改）/ 5c（我自己改，退出等 `/ohaze:ship-finish`）。其中 **5a 用 `codex exec resume <codex_session_id>`**（不用 `--last`；`codex_session_id` 缺失时降级 `--last` 并显著告警）。modify 子流程结束后 loop back 回本菜单。
- **职责 7 — terminal 动作的收尾文件与时序（A4）**：每个 terminal 动作（merge / push / pr / discard）执行后，按**严格顺序**：① 用 **Write 工具**（非 bash heredoc）写 `<worktree>/.ohaze/ship-result.json` ② `rm` `current-ship.json` handoff ③ 删 worktree。删 worktree 必须最后。`ship-result.json` 的 `action` 取值与字段 schema 沿用现有 `ship-review.md` Phase 7 中各 option 的定义（`merge`/`push`/`pr`/`discard`），不变更。
- **职责 8 — 偏好回写**：用户选 1（接受推荐）或选 5（自定义）后，把最终执行的链回写 `~/.ohaze/finish-prefs.json` 对应 `project_type` 条目。
- **职责 9 — 自定义收尾（A7 基础版）**：菜单项 5 不做自由文本解析；给用户上述步骤取值域作为「积木」按序勾选组合成链，再走职责 4 的执行契约。
- **菜单项 4「先不处理」**：把 `current-ship.json` 的 `state` 设为 `kept`，告知用户 worktree 路径与 `/ohaze:ship-finish` 恢复方式，不做任何破坏性操作。
- **错误边界**：偏好文件读写、vault context 读取均 best-effort，失败不阻塞 finishing 主流程。`merge` 的 `--ff-only` 失败（base 在 ship 期间前进）须沿用 ship-review.md 现有处理（询问 merge commit / 退出）。

**Acceptance Criteria:**
- [ ] 文件 `plugins/ohaze/skills/finishing/SKILL.md` 存在，frontmatter 含 `name: finishing`
- [ ] `grep` 命中项目类型检测两类：`local` 与 `remote`
- [ ] `grep` 命中偏好文件路径 `~/.ohaze/finish-prefs.json`（或 `finish-prefs.json`）
- [ ] `grep` 命中 5 项菜单全部条目文字（执行推荐收尾 / 继续修改 / 丢弃 / 先不处理 / 自定义收尾）
- [ ] `grep` 命中失败即停契约关键句，且含「merge 成功 push 失败禁止删 worktree」的明确表述
- [ ] `grep` 命中 `doc-finish` 文档收尾步骤，且文中说明它排在 `commit` 之前、合并处理进度契约 + 漂移修
- [ ] `grep` 命中 A4 时序：`ship-result.json` 用 Write 工具 → `rm` handoff → 删 worktree
- [ ] `grep` 命中 modify 三分支 5a/5b/5c，且 5a 用 `resume <` 形式（不是 `resume --last`）
- [ ] Manual check：通读 SKILL.md，ship-review.md Phase 7 中的所有时序/失败处理契约均有对应保留

**TDD Sequence:**
- [ ] Step 1: 把上面 Acceptance 的每条 grep 判据列成本 Task 的验收清单
- [ ] Step 2: 阅读 ship-review.md 的 Phase 7 + Modify Sub-Flow，确认要迁移保留的契约清单
- [ ] Step 3: 编写 `finishing/SKILL.md`，满足 Behavior Contract 全部职责
- [ ] Step 4: 逐条跑 Acceptance 的 grep 判据，确认全部命中
- [ ] Step 5: 通读一遍，确认无遗漏的现有契约
- [ ] Step 6: Commit。建议信息：`feat(finishing): 抽出 ohaze:finishing skill — 项目类型推荐链 + 文档收尾`

**Cross-Task Dependencies:**
- Provides `ohaze:finishing` skill for Task 2（两个 command invoke 它）
- Consumes `codex_session_id`（Task 4 写入 handoff）、`review-verdict.json` 的 `doc_drift`（Task 3 写入）

---

## Task 2: ship-review.md / ship-finish.md 接入 `ohaze:finishing`

**Files:**
- Modify: `plugins/ohaze/commands/ship-review.md`
- Modify: `plugins/ohaze/commands/ship-finish.md`

**Behavior Contract:**
- **`ship-review.md`**：删除「Phase 7 — Finishing Menu」整段、「Modify Sub-Flow」整段，以及 Cleanup / Final Summary 中只属于 finishing 的内容。在原 Phase 7 位置改为 invoke `ohaze:finishing` skill，向其传递所需上下文（`worktree_path`、`base_ref`、`branch`、`plan_path`、`spec_path`、`retries`、`linked_todo`、`codex_session_id`、`review-verdict.json` 路径）。
  - **保留不动**：Pre-flight、Vault Context、Phase 5-6 review/retry 循环、Phase 6.5「Surface ADVERSARIAL findings」。
- **`ship-finish.md`**：删除「Step 3 — Finishing Menu」的内联 6 项菜单文本与 Cleanup 中的 finishing 细节，改为 invoke `ohaze:finishing`。
  - **保留不动**：Pre-flight、Vault Context、Step 1（检测未提交改动）、Step 2（可选 re-review）、Step 2.5（ADVERSARIAL surfacing）。
- 两个 command 完成后均**不再含 finishing 菜单正文**（菜单文字只存在于 `finishing/SKILL.md`）。

**Acceptance Criteria:**
- [ ] `grep` 确认 `ship-review.md` 与 `ship-finish.md` 均含 invoke `ohaze:finishing` 的语句
- [ ] `grep` 确认 `ship-review.md` 不再含旧菜单文本「合并回主分支」「创建 Pull Request」等内联选项行
- [ ] `grep` 确认 `ship-finish.md` 不再含内联 6 项菜单文本
- [ ] `grep` 确认 `ship-review.md` 仍保留 Phase 5 / Phase 6 / Phase 6.5 章节
- [ ] `grep` 确认 `ship-finish.md` 仍保留 Step 1 / Step 2 / Step 2.5
- [ ] Interface conformance：两处 invoke 传递的上下文字段与 Task 1 finishing skill 的「输入」列表一致

**TDD Sequence:**
- [ ] Step 1: 列出两个文件要删除的段落与要保留的段落清单
- [ ] Step 2: 改 `ship-review.md`——移除 finishing，插入 invoke
- [ ] Step 3: 改 `ship-finish.md`——移除 finishing，插入 invoke
- [ ] Step 4: 跑 Acceptance 的 grep 判据
- [ ] Step 5: Commit。建议信息：`refactor(commands): ship-review/ship-finish 改为 invoke ohaze:finishing`

**Cross-Task Dependencies:**
- Depends on Task 1 的 `ohaze:finishing` skill 存在

---

## Task 3: codex-executor 改造 — session-id resume + DOC-DRIFT + resume 边界

**Files:**
- Modify: `plugins/ohaze/skills/codex-executor/SKILL.md`

**Behavior Contract:**

- **改动 (a) — R1 精确 resume**：Phase 6 retry 循环、以及 modify 子流程涉及 Codex 续跑处的 `codex exec resume --last`，改为 `codex exec resume <codex_session_id>`。`codex_session_id` 从 `current-ship.json` 读取。
  - 兜底：`codex_session_id` 为空 / 缺失时，降级回 `resume --last`，并在 Codex 日志中显著写入告警（含「session id 缺失，并行 ship 下 resume 可能不精确」之意）。不静默降级。
- **改动 (b) — R2 文档漂移检测 PART**：在 Phase 5 的 reviewer prompt 模板中新增一个 PART，命名 `DOC-DRIFT`，与现有 `ADVERSARIAL` PART 同级。该 PART 指示 reviewer：
  - 检测本次 `git diff` 是否让**目标项目** `CLAUDE.md` 的描述性 section 失真，描述性 section 限定为 `关键文件` / `设计决策` / `阶段归属` / `前置要求` / `外部依赖` 五个。
  - **不检测** `当前目标` checkbox 区（进度由文档收尾的进度契约处理）。
  - 产出 doc-drift 清单（每条形如 `<section>: <失真描述>`）。
  - 明确声明：DOC-DRIFT 发现 **不进 PASS/FAIL gate**（advisory，与 ADVERSARIAL 同性质）。
- **改动 (b) 续 — verdict schema**：`review-verdict.json` 的 schema 增加字段 `doc_drift`（字符串数组；无漂移为 `[]`）。Phase 5.3「写 review-verdict.json」的说明同步更新，把 `doc_drift` 纳入写入内容，并保持「用 Write 工具写」的现有要求。
- **改动 (c) — R8 resume 边界**：在 SKILL.md 中（retry / modify 说明附近的合适位置）写明 resume 边界规则：
  - `resume` 仅用于**同一个 ship 生命周期内**（review retry / modify）。
  - ship 走完 finishing 后出现的 bug = **新的 fix ship**（新 worktree / 新 plan / 新 codex session），不 resume 旧 session。
  - 原功能的 plan / vault decisions / 相关 commit 作为**显式参考材料**喂给新 ship 的 prompt，而非依赖 codex session memory。

**Acceptance Criteria:**
- [ ] `grep` 确认 codex-executor/SKILL.md 的 retry / modify 路径不再含 `resume --last`（兜底分支除外，且兜底处含告警文本）
- [ ] `grep` 命中 `resume <` 形式（按 session id 恢复）
- [ ] `grep` 命中 reviewer prompt 中的 `DOC-DRIFT`，且附近含「不进 PASS/FAIL」「不检测 当前目标」表述
- [ ] `grep` 命中 `review-verdict.json` 说明中的 `doc_drift` 字段
- [ ] `grep` 命中 resume 边界说明（含「新 fix ship」「不 resume 旧 session」之意）
- [ ] Interface conformance：`doc_drift` 字段名与 Task 1 finishing skill 读取的字段名一致

**TDD Sequence:**
- [ ] Step 1: 列出三处改动各自的 grep 验收判据
- [ ] Step 2: 改动 (a) resume 改 session id + 兜底
- [ ] Step 3: 改动 (b) 加 DOC-DRIFT PART + verdict schema 加 `doc_drift`
- [ ] Step 4: 改动 (c) 写 resume 边界说明
- [ ] Step 5: 跑 Acceptance grep 判据
- [ ] Step 6: Commit。建议信息：`feat(codex-executor): session-id 精确 resume + DOC-DRIFT 检测 + resume 边界`

**Cross-Task Dependencies:**
- Consumes `codex_session_id`（Task 4 写入 `current-ship.json`）
- Provides `review-verdict.json` 的 `doc_drift` 字段（Task 1 finishing skill 消费）

---

## Task 4: ship.md 改造 — 捕获 codex_session_id + handoff 字段

**Files:**
- Modify: `plugins/ohaze/commands/ship.md`

**Behavior Contract:**
- Phase 4 派发 `codex exec` 之后，捕获本次 Codex session id（UUID 形式）。**捕获方式由实现自行决定**（从 `codex exec` 启动输出解析、或查 codex 的 session 记录目录），plan 不规定具体手段；契约是最终能拿到一个可用于 `codex exec resume <id>` 的标识，或确定其不可得。
- handoff 文件 `current-ship.json` 的 schema 增加两个字段：
  - `codex_session_id`：string 或 `null`。Phase 4 捕获成功则填 UUID，失败填 `null`。
  - `project_type`：string，初始值 `null`（由 `ohaze:finishing` 在 finishing 阶段检测后回填，见 Task 1 职责 1）。
- 兜底：session id 捕获失败时 `codex_session_id` 置 `null`，在派发日志/handoff 流程中标注一句，不阻塞 ship 继续。
- handoff schema 的文档（ship.md 中展示 `current-ship.json` 结构的 JSON 块）须更新，包含这两个新字段。

**Acceptance Criteria:**
- [ ] `grep` 命中 ship.md Phase 4 捕获 `codex_session_id` 的说明
- [ ] `grep` 确认 ship.md 中 `current-ship.json` 的 JSON schema 块含 `codex_session_id` 与 `project_type` 两字段
- [ ] `grep` 命中 session id 捕获失败的兜底说明
- [ ] Interface conformance：`codex_session_id` 字段名与 Task 1 / Task 3 读取处一致

**TDD Sequence:**
- [ ] Step 1: 列出 grep 验收判据
- [ ] Step 2: 改 ship.md Phase 4——加捕获逻辑说明 + 兜底
- [ ] Step 3: 更新 ship.md 中 `current-ship.json` schema JSON 块
- [ ] Step 4: 跑 Acceptance grep 判据
- [ ] Step 5: Commit。建议信息：`feat(ship): Phase 4 捕获 codex_session_id 进 handoff`

**Cross-Task Dependencies:**
- Provides `codex_session_id` / `project_type` 字段于 `current-ship.json`，给 Task 1（finishing）与 Task 3（codex-executor）消费

---

## Task 5: 文档与版本收尾

**Files:**
- Modify: `plugins/ohaze/CLAUDE.md`
- Modify: `CHANGELOG.md`
- Modify: `plugins/ohaze/.claude-plugin/plugin.json`

**Behavior Contract:**
- **`plugins/ohaze/CLAUDE.md`**：
  - 「关键文件」表：新增一行 `plugins/ohaze/skills/finishing/SKILL.md`（作用：Phase 7 finishing —— 项目类型推荐链 + 文档收尾 + modify 子流程）；更新 `ship-review.md` / `ship-finish.md` 行的描述（finishing 已抽出，改为 invoke `ohaze:finishing`）；`codex-executor` 行描述补「DOC-DRIFT 检测」。
  - 「设计决策」：新增「resume 边界」条目（与 Task 3 改动 c 一致的摘要）；新增 / 更新「finishing」条目为新形态（项目类型检测 → 推荐收尾链 → 一键执行，菜单 5 项）。
  - 「阶段归属」表：第 7 行 finishing 的「来源」更新为 `ohaze（finishing skill）`；第 6 行修复重试的 `codex exec resume --last` 更新为 `resume <session_id>`。
  - 「版本号」段「当前版本」更新为 `1.9.0`。
  - 「当前目标」：新增一行 `- [x] **1.9.0**：finish menu 项目类型化 + 文档漂移自动检测 + Codex session 精确 resume + finishing skill 抽取`。
- **`CHANGELOG.md`**：新增 `## [1.9.0] — 2026-05-22` 小节，遵循 Keep a Changelog 格式。含一句话主题「finish menu 项目类型化 + 文档漂移自动检测 + Codex session 精确 resume」，并在 `Added` / `Changed` / `Fixed` 下分列：finishing skill 抽取、项目类型推荐链、DOC-DRIFT 检测、session-id 精确 resume（修复并行 ship 串会话 bug）、resume 边界文档化。
- **`plugins/ohaze/.claude-plugin/plugin.json`**：`version` 字段改为 `1.9.0`。

**Acceptance Criteria:**
- [ ] `grep` 确认 `1.9.0` 同时出现在 `CHANGELOG.md`、`plugin.json`、`CLAUDE.md`「当前版本」三处
- [ ] `grep` 确认 `CLAUDE.md` 关键文件表含 `finishing/SKILL.md` 行
- [ ] `grep` 确认 `CLAUDE.md` 设计决策含「resume 边界」条目
- [ ] `grep` 确认 `CHANGELOG.md` 含 `[1.9.0]` 小节标题
- [ ] `grep` 确认 `CLAUDE.md`「当前目标」含 `- [x] **1.9.0**` 行
- [ ] Manual check：`CLAUDE.md` 阶段归属表第 7 行 finishing 来源已更新

**TDD Sequence:**
- [ ] Step 1: 列出三个文件各自的 grep 验收判据
- [ ] Step 2: 改 `plugin.json` version
- [ ] Step 3: 改 `CHANGELOG.md` 新增 `[1.9.0]`
- [ ] Step 4: 改 `CLAUDE.md` 四处（关键文件 / 设计决策 / 阶段归属 / 版本+目标）
- [ ] Step 5: 跑 Acceptance grep 判据，确认三处版本号一致
- [ ] Step 6: Commit。建议信息：`docs(release): bump 1.9.0 + CHANGELOG + CLAUDE.md 同步`

**Cross-Task Dependencies:**
- 描述性内容依赖 Task 1-4 已确定的文件名（`finishing/SKILL.md`）与字段名

---

## 执行说明（给 Codex）

- 5 个 Task 推荐顺序：Task 1 → Task 4 → Task 3 → Task 2 → Task 5。理由：Task 1 建 finishing skill 是核心；Task 4 先确立 `codex_session_id` 字段契约；Task 3 消费它；Task 2 接线依赖 Task 1；Task 5 收尾依赖前四者文件名确定。
- 每个 Task 独立 commit。commit 信息可按建议，orchestrator 可能改写。
- 本项目无测试框架——不要尝试搭建测试运行器；Acceptance 的 grep / 文件检查就是验收手段。
- 不要触碰线上部署相关功能（本期范围外）；项目类型只实现 `local` / `remote` 两类。
