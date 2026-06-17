# doc-finish 收口契约加固 — Guidance Plan

> **For Codex (the executor):** Each Task below specifies WHAT must be true at completion, not HOW to write it line by line. You have autonomy over internal naming, paragraph phrasing, helper extraction, and bullet ordering within a section. You do NOT have autonomy over public interfaces (the proposed wording verbatim text is the contract surface for downstream skills that read these SKILL.md files), file paths in Files lists, acceptance criteria, or cross-Task invariants. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Strengthen ohaze's doc-finish 链路 so it enforces global four-piece contract — 防止下游项目 (vault 等) 在 ship 过程中产出膨胀文档 / 僵尸条目 / 旁路绕过 preview。本 plan 修改 3 个 SKILL.md 文件；四件套对齐 (CLAUDE.md / ROADMAP / CHANGELOG / plugin.json) 由 doc-finish 收口 (见 plan 末尾 § Four-Piece Boundary)。

**Architecture:** 三处加固呈"契约本体 → 源头预防 → 旁路双闸"层叠：
- `finishing/SKILL.md` Class 1 引用 `~/Project/hazeflow/_shared/versioning.md ## CHANGELOG 写作风格` 契约 + tick → prune 行为变更 = **契约本体**
- `writing-plans/SKILL.md` Task Structure 段加红线 = **plan 写作时源头预防**
- `plan-to-codex-prompt/SKILL.md` `<grounding_rules>` + `<action_safety>` 双闸 = **Codex 执行时旁路防护**

三层防护意图：上游 (plan 写作) 漏写时，下游 (Codex prompt) 仍能拦截。

**Tech Stack:** Pure Markdown SKILL.md files. No code, no test suite. Acceptance = `grep` assertions against the modified files + structural sanity checks.

---

## File Structure

| File | Responsibility | Touched by |
|---|---|---|
| `plugins/ohaze/skills/finishing/SKILL.md` | Phase 7 finishing 主流程 — Class 1 是 CHANGELOG/manifest/ROADMAP tick 步骤的契约描述 | Task 1 |
| `plugins/ohaze/skills/writing-plans/SKILL.md` | 写 guidance plan 时的 Task 结构约束 — Task Structure 段 + No Placeholders 段 | Task 2 |
| `plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md` | 把 plan 翻译成 Codex XML prompt 的模板 — `<grounding_rules>` + `<action_safety>` 段 | Task 3 |

每个 Task 自包含、可独立验证。Task 之间无 cross-dependency（仅同主题 thematic）。

---

## Task 1: finishing/SKILL.md Class 1 — CHANGELOG 篇幅+视角硬约束 + tick→prune

**Files:**
- Modify: `plugins/ohaze/skills/finishing/SKILL.md`
  - 影响段落: `## Step: doc-finish (内化 neat 路由)` → `### Class 1 — Progress machine-readable contract` (around Line 222-244)
  - 其他 Class (2/3/4) + boundary + preview 段不动
- 无新建文件
- 无测试文件（Markdown plugin 无测试套件）

**Behavior Contract:**

子契约 1A — CHANGELOG 写入约束:
- Class 1 第一条 bullet (描述 CHANGELOG entry 追加) 必须引用 `~/Project/hazeflow/_shared/versioning.md ## CHANGELOG 写作风格` 契约
- 必须列出 4 条硬约束: ① 单 bullet ≤ 200 字符 ② 视角 = 消费者感知 ③ 末尾必带 commit hash (可选追加 spec/plan path link) ④ 禁内嵌过程性内容
- 第 ④ 条**必须只引用**禁内嵌清单出处 (versioning.md)，**不复述**清单内容 — 这是为了避免双份维护漂移
- 现有 `[Unreleased] or version entry` 表达可保留 (写 `[Unreleased]` 即可)

子契约 1B — tick → prune:
- Class 1 描述 `linked_todo` 行处理的 bullet (around Line 240) 行为从 "Tick `- [ ]` → `- [x]`" 改为 "整行删除"
- 删除目标段固定为 `## 当前主线`（与 ship.md Step A 限定的 capture 范围对称）
- 三个分支保留:
  - `linked_todo` is `null` → skip silently（不变）
  - `linked_todo` non-null AND exact text found in `## 当前主线` → 整行删除 (不留 `- [x]`, 不留 `~~划掉~~`, 不留空行)
  - `linked_todo` non-null BUT exact text NOT found → emit WARNING + skip prune (现有 cross-version + manual-edit edge case 措辞中 "Tick skipped" 改为 "Prune skipped")
- 新增段落空保留分支: 删除后如果 `## 当前主线` 段只剩主题句没有 todo 行 → 保留主题句不动 (标记当期主线已收完，不强制清空段落)
- 内联说明铁律: WHY 引用 `~/CLAUDE.md`「CHANGELOG 朝过去 / ROADMAP 朝未来」铁律 (一句话内联即可)

**Acceptance Criteria:**

子契约 1A 验证:
- [ ] `grep -n "versioning.md" plugins/ohaze/skills/finishing/SKILL.md` 至少有 1 处命中且位于 Class 1 段内 (Line 220-280 区间)
- [ ] `grep -c "≤ 200 字符" plugins/ohaze/skills/finishing/SKILL.md` ≥ 1
- [ ] `grep -c "必带 commit hash" plugins/ohaze/skills/finishing/SKILL.md` ≥ 1
- [ ] `grep -c "消费者" plugins/ohaze/skills/finishing/SKILL.md` ≥ 1 (位于 Class 1 段)
- [ ] **不复述断言**: `grep -E "sub-ship 编号|reviewer finding|fixture 细节|改了 N 行|多源对抗结果|hash 列表|反思段" plugins/ohaze/skills/finishing/SKILL.md` 返回 0 (Class 1 段不能含 versioning.md 的禁内嵌清单原文，否则违反"只引用不复述"约束)

子契约 1B 验证:
- [ ] `grep -n -i "prune" plugins/ohaze/skills/finishing/SKILL.md` 命中 Class 1 段 ≥ 1 处
- [ ] `grep -n "整行删除" plugins/ohaze/skills/finishing/SKILL.md` 命中 Class 1 段 ≥ 1 处
- [ ] `grep -n "Prune skipped\|prune skipped" plugins/ohaze/skills/finishing/SKILL.md` 命中 Class 1 段 (WARNING 措辞已切换)
- [ ] Class 1 段不再以 "Tick the exact `linked_todo` line" 作为主行为 (主行为 = prune；如保留 "tick" 历史词作 deprecated 提醒可接受，但主要叙述应是 prune)
- [ ] Class 1 段提到「CHANGELOG 朝过去 / ROADMAP 朝未来」铁律或等价表述 (引用 `~/CLAUDE.md` 一次即可)

整体回归:
- [ ] Class 2 / Class 3 / Class 4 段未被错改 — `diff` 显示这三段无意外行变 (允许行号自然偏移)
- [ ] Class 1 段以外 (Inputs / Detect Project Type / Finish Preferences / Menu / 6th Option / 7th Option / Step: commit / Step: merge / Step: push / Step: pr / Step: remove-worktree / Modify Sub-Flow / Final Summary / Failure Modes) 全部不动

**TDD Sequence (Markdown plugin adapted):**
- [ ] Step 1: Read current `## Step: doc-finish` 段 (Class 1 区域) 完整范围，identify 现有 6-8 bullets 的精确位置
- [ ] Step 2: 把现有 Line 238 单 bullet 替换成 spec §修改 1 Proposed Wording 的 5-bullet form (含 versioning.md 引用 + 4 项硬约束 + 不复述说明)
- [ ] Step 3: 把现有 Line 240-244 tick branches 替换成 spec §修改 2 Proposed Wording 的 prune branches (含 3 个 branches + 新空段保留分支)
- [ ] Step 4: 跑所有上面 Acceptance Criteria 的 grep 断言，全部通过
- [ ] Step 5: 跑 Class 2/3/4 unchanged 断言，确认无意外漂移
- [ ] Step 6: Commit. Suggested message: `feat(finishing): Class 1 加 CHANGELOG 篇幅+视角硬约束 + tick→prune`

**Cross-Task Dependencies:**
- None. This Task is independent of Task 2/3.

---

## Task 2: writing-plans/SKILL.md — 四件套禁列 Task 红线

**Files:**
- Modify: `plugins/ohaze/skills/writing-plans/SKILL.md`
  - 影响段落:
    - `## Task Structure (guidance form)` 段 (Line 155-192) 顶部加 callout
    - `## No Placeholders` 段 (Line 213-224) 现有清单末尾追加一条
  - 其他段 (Overview / Reading the Spec / Scope Check / File Structure / Bite-Sized Task Granularity / Plan Document Header / Acceptable code blocks / Calibration / Remember / Self-Review / Optional / Execution Handoff / What this skill does NOT do / Attribution) 全部不动

**Behavior Contract:**

- Task Structure 段顶部 (在 "Every Task uses this exact structure:" 之前) 必须加一段 blockquote callout，明示:
  - 五个文件名: `CLAUDE.md` / `README.md` / `ROADMAP.md` / `CHANGELOG.md` / manifest (`plugin.json` / `package.json` / `Cargo.toml` 等)
  - 写入路径: 由 `ohaze:finishing` 的 doc-finish step 收口处理
  - Plan Task 边界: Files 列表禁列四件套, Acceptance Criteria 禁含「CHANGELOG entry exists」「ROADMAP ticked」这类四件套断言
  - 替代写法: 如果 spec 提到需要更新四件套, 在 plan 末尾加注一句「四件套同步由 doc-finish 收口」即可, 不要落 Task
- No Placeholders 段现有 placeholder 清单 (6-8 条) 末尾追加一条:
  - 内容描述: 四件套写入作为 Task 交付物 — 一律删除并下挂到 doc-finish 收口 (引用 Task Structure 顶 callout)

**Acceptance Criteria:**

- [ ] `grep -n "禁列四件套" plugins/ohaze/skills/writing-plans/SKILL.md` 命中 ≥ 1 处
- [ ] `grep -n "doc-finish" plugins/ohaze/skills/writing-plans/SKILL.md` 命中 ≥ 2 处 (Task Structure callout + No Placeholders 段)
- [ ] callout 段必须明示 5 个文件名 (`CLAUDE.md` / `README.md` / `ROADMAP.md` / `CHANGELOG.md` / manifest)
- [ ] No Placeholders 段保留原有 6-8 条 placeholder 检查不变，仅末尾追加一条新约束 (无意外删除或重排)
- [ ] Task Structure 段的 Files / Behavior Contract / Acceptance Criteria / TDD Sequence / Cross-Task Dependencies 子字段标题不变 (callout 是新加段，不替换原结构)

**TDD Sequence:**
- [ ] Step 1: Read Task Structure 段 + No Placeholders 段精确范围
- [ ] Step 2: 在 "Every Task uses this exact structure:" 之前插入 spec §修改 3 Proposed Wording 的 callout blockquote
- [ ] Step 3: 在 No Placeholders 段现有清单末尾追加一条新 placeholder 检查 (spec §修改 3 提供的 wording)
- [ ] Step 4: 跑 Acceptance Criteria 的 grep 断言
- [ ] Step 5: Diff 确认其他段未被错改
- [ ] Step 6: Commit. Suggested message: `feat(writing-plans): 禁列四件套作为 Task 交付物`

**Cross-Task Dependencies:**
- None. Independent of Task 1/3.

---

## Task 3: plan-to-codex-prompt/SKILL.md — 双闸禁 Codex 写四件套

**Files:**
- Modify: `plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md`
  - 影响段落:
    - `<grounding_rules>` block (Line 78-83 附近) 末尾追加一条 soft red-line
    - `<action_safety>` block (Line 89-95 附近) 末尾追加一条 hard never-modify
  - 其他 block (`<task>` / `<completeness_contract>` / `<commit_handling>` / `<verification_loop>` / `<implementation_autonomy>` / `<missing_context_gating>` / `<output_report>`) 全部不动
  - 其他段 (Overview / When to invoke / Inputs / Output contract 段 in-line description / Notes for Claude / What this skill does NOT do) 全部不动

**Behavior Contract:**

子契约 3A — `<grounding_rules>` 加 soft red-line:
- 必须描述: 即便 plan Task 错列四件套写入 (e.g. `Modify: CHANGELOG.md`), Codex 跳过该文件改动
- 必须描述上报机制: 在 `<output_report>` 的 "Tasks with concerns" 中标注，格式 `"plan Task N 越权列了 <file>, 已跳过留 doc-finish 处理"`
- 必须描述继续行为: Continue executing the rest of the Task normally (不因此 abort 整个 Task)
- 五文件清单: `CLAUDE.md` / `README.md` / `ROADMAP.md` / `CHANGELOG.md` / manifest 列举至少一处 (允许列在 grounding_rules 或 action_safety 任一)

子契约 3B — `<action_safety>` 加 hard never-modify:
- 必须描述: Never modify the project's four-piece contract files
- 必须列举五文件: `CLAUDE.md` / `README.md` / `ROADMAP.md` / `CHANGELOG.md` / manifest (`package.json` / `Cargo.toml` / `.claude-plugin/plugin.json` / etc.)
- 必须描述 territory boundary: These are doc-finish's exclusive territory.

子契约 3C — 两闸协调:
- 措辞协调: grounding_rules 描述「detect + graceful action」, action_safety 是绝对底线
- 两条不重复 (avoid copy-paste 同一段)，而是从两个不同角度补强同一规则

**Acceptance Criteria:**

- [ ] `grep -n "doc-finish" plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md` 命中 ≥ 2 处 (一处在 grounding_rules, 一处在 action_safety)
- [ ] `grep -n "Tasks with concerns" plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md` 命中 grounding_rules 段 ≥ 1 处 (与新 soft red-line 关联)
- [ ] `grep -n "Never modify" plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md` 命中 action_safety 段 ≥ 1 处
- [ ] action_safety 段含完整 5 文件清单 (CLAUDE.md, README.md, ROADMAP.md, CHANGELOG.md, manifest with examples package.json/Cargo.toml/.claude-plugin/plugin.json)
- [ ] grounding_rules 段含 "越权列了" 或等价中文/英文表达 + "已跳过留 doc-finish 处理" 模板
- [ ] 其他 XML block (`<task>` / `<completeness_contract>` / `<commit_handling>` / `<verification_loop>` / `<implementation_autonomy>` / `<missing_context_gating>` / `<output_report>`) 文本不动 (允许行号自然偏移)

**TDD Sequence:**
- [ ] Step 1: Read 当前 `<grounding_rules>` + `<action_safety>` 两段精确范围
- [ ] Step 2: 在 `<grounding_rules>` 末尾插入 spec §修改 4 Proposed Wording 的 soft red-line (single bullet)
- [ ] Step 3: 在 `<action_safety>` 末尾插入 spec §修改 4 Proposed Wording 的 hard never-modify (single bullet)
- [ ] Step 4: 跑 Acceptance Criteria 的 grep 断言
- [ ] Step 5: Diff 确认其他 XML block 文本未动
- [ ] Step 6: Commit. Suggested message: `feat(plan-to-codex-prompt): 双闸禁 Codex 写四件套`

**Cross-Task Dependencies:**
- None. Independent of Task 1/2.

---

## Cross-Task Invariants (整体规约)

- 三个 SKILL.md 文件的非目标段必须完全不动 (允许行号自然偏移, 不允许字符内容变更)
- 所有 Acceptance 都基于 `grep` + 视觉 diff，**不**依赖任何测试套件 (项目无自动化测试)
- 所有改动幂等可逆 (纯 Markdown 文本, 任何 diff 可 `git revert`)
- 三个 Task 可任意顺序执行 (无 cross-dep), 推荐顺序 Task 1 → Task 2 → Task 3 (从契约本体 → 源头预防 → 旁路防护, 思维顺序自然)

---

## Four-Piece Boundary (重要！本 plan 的 self-dogfood 范例)

**这是本 ship 自己提前应用新约束的体现 — 即便 writing-plans/SKILL.md 还没改, 本 plan 已按新约束写。**

以下四件套修改属于本 ship 范围, 但 **NOT in any Task** — 由 `ohaze:finishing` 的 doc-finish step 收口处理 (Phase 7):

1. **`CLAUDE.md`** — `## Agent 行为约定` 段加一行明示 doc-finish 唯一收口契约 (spec §修改 5a)
2. **`ROADMAP.md`** — `## 当前主线` v2.2.0 段清 3 行历史 `- [x]` 勾痕 (spec §修改 5b)
3. **`ROADMAP.md`** — `## Backlog` 删问题 10/11/12 三条 (spec §修改 5c)
4. **`CHANGELOG.md`** — 新增 `## [2.2.1] - 2026-06-17` 段 (spec §修改 6)
5. **`plugins/ohaze/.claude-plugin/plugin.json`** — `version` 字段 `2.2.0` → `2.2.1` (spec §修改 6)

**Codex 实施期间禁直接动这五个文件**，即便其中部分属于 spec 范围。这些写入由 Claude 主线程在 Phase 7 doc-finish 阶段统一收口（本 ship 是 finishing 用旧规则收口的特殊情况 — 见 spec §时序前提）。

如果 Codex 误把上述任一文件加进 Files 列表执行了写入，应被 plan-to-codex-prompt 的 `<grounding_rules>` + `<action_safety>` 双闸拦截 (但本 ship 中 Codex 用的还是旧版 plan-to-codex-prompt prompt，所以靠 Codex 自身遵守 plan 的 Files 列表约束 + 本 plan 没列四件套 = Codex 不该动)。

---

## Codex Output Report Expected Format

Per `<output_report>` template:
- Tasks completed: 3 / 3
- Tasks with concerns: (无, plan 没列四件套，Codex 不会触发四件套越权报告)
- Final test status: N/A (项目无测试套件), 用各 Task 的 grep Acceptance 替代
- Touched files: Modify 列出 3 个 SKILL.md
- Commits made: skipped (orchestrator handles)
- Notable implementation choices: 2-5 bullets

---

## Acceptance Summary (供 Phase 5 cross-source review 一键查)

```bash
# Task 1
grep -n "versioning.md" plugins/ohaze/skills/finishing/SKILL.md
grep -c "≤ 200 字符" plugins/ohaze/skills/finishing/SKILL.md
grep -c "必带 commit hash" plugins/ohaze/skills/finishing/SKILL.md
grep -c "消费者" plugins/ohaze/skills/finishing/SKILL.md
grep -E "sub-ship 编号|reviewer finding|fixture 细节|改了 N 行|多源对抗结果|hash 列表|反思段" plugins/ohaze/skills/finishing/SKILL.md  # MUST return 0
grep -n -i "prune" plugins/ohaze/skills/finishing/SKILL.md
grep -n "整行删除" plugins/ohaze/skills/finishing/SKILL.md
grep -n "Prune skipped" plugins/ohaze/skills/finishing/SKILL.md

# Task 2
grep -n "禁列四件套" plugins/ohaze/skills/writing-plans/SKILL.md
grep -n "doc-finish" plugins/ohaze/skills/writing-plans/SKILL.md  # ≥ 2 hits

# Task 3
grep -n "doc-finish" plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md  # ≥ 2 hits
grep -n "Tasks with concerns" plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md  # ≥ 1 hit
grep -n "Never modify" plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md  # ≥ 1 hit
```
