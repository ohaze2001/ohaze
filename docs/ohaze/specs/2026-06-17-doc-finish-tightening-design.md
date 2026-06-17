# doc-finish 收口契约加固 — Implementation Spec (v2.2.1)

> 给 Codex 看。brief 在 `docs/ohaze/briefs/2026-06-17-doc-finish-tightening-brief.md`。
> 本 spec 描述 4 个 SKILL.md 修改点 + 3 处 ohaze 自身四件套对齐 + 版本号同步契约。

## 真相源 (anchors)

- **CHANGELOG 写作风格契约**: `~/Project/hazeflow/_shared/versioning.md` `## CHANGELOG 写作风格` 段 (Line 44-61)
- **全局四件套契约**: `~/CLAUDE.md` `## 项目文档契约（四件套）` 段 (含「单条目体量上限」+「信息落点路由」铁律)
- **doc-finish Class 1 现状**: `plugins/ohaze/skills/finishing/SKILL.md:236-264`
- **writing-plans Task Structure 现状**: `plugins/ohaze/skills/writing-plans/SKILL.md:156-192`
- **plan-to-codex-prompt XML 模板**: `plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md:28-105`
- **ship.md `linked_todo` capture 契约**: `plugins/ohaze/commands/ship.md:243-245` (Step A — 只从 `## 当前主线` capture)
- **ohaze 自己 CLAUDE.md `## Agent 行为约定` 段**: `CLAUDE.md:14-32`
- **ohaze 自己 ROADMAP `## 当前主线`**: `ROADMAP.md:6-11`
- **ohaze 自己 ROADMAP `## Backlog` 问题 10/11/12 条**: `ROADMAP.md:23-27`
- **ohaze plugin manifest**: `plugins/ohaze/.claude-plugin/plugin.json` (`version` field)

---

## 修改 1 — finishing/SKILL.md Class 1 CHANGELOG 写入加篇幅+视角硬约束

### Context

`plugins/ohaze/skills/finishing/SKILL.md:236-244` Class 1 是 doc-finish 的「Progress machine-readable contract」段，负责写 CHANGELOG + bump manifest + tick ROADMAP。当前 Line 238 仅一句话：

```
- Append an appropriate `[Unreleased]` or version entry to `CHANGELOG.md` at `main_repo_path`.
```

**零篇幅约束、零视角约束、零禁内嵌清单**。vault dogfood 实测产出 2500 字单条 entry / 128KB CHANGELOG。

`~/Project/hazeflow/_shared/versioning.md ## CHANGELOG 写作风格` 已经是完整真相源 (≤ 200 字符 + 消费者视角 + 7 项禁内嵌清单 + 好/坏示例)。Class 1 应该指向它而非本地复述（避免双份维护漂移）。

### Behavior Contract

- Class 1 第一条 bullet (CHANGELOG entry 写入) 引用 versioning.md 的 CHANGELOG 写作风格契约
- 列出最 actionable 的 3-4 条硬约束 (**不复述** versioning.md 的具体禁内嵌清单 / 好坏示例 — 真相源只有一份，避免漂移)
- 视角语言强调 "消费者感知"
- 末尾 commit hash 必带（spec/plan path 可选追加）— 保持 CHANGELOG ↔ commit graph 强连接

### Proposed Wording (替换 finishing/SKILL.md:238)

```markdown
- Append a `[Unreleased]` entry to `CHANGELOG.md` at `main_repo_path`, following the writing style contract at `~/Project/hazeflow/_shared/versioning.md ## CHANGELOG 写作风格`. Hard constraints:
  - 单 bullet 一句话主述 ≤ 200 字符, 末尾必带 commit hash (可选追加 spec/plan path link)
  - 视角 = 消费者 / 集成方感知到的变化, 不是「怎么修的」
  - 禁内嵌过程性内容 — 具体禁列清单与好/坏示例见 versioning.md, 此处不复述以避免双份维护漂移
  - 过程性细节落 commit body + spec + plan, 不进 CHANGELOG
```

### Acceptance

- [ ] `grep -n "versioning.md" plugins/ohaze/skills/finishing/SKILL.md` 命中至少 1 条引用 (Class 1 段内)
- [ ] `grep -n "≤ 200 字符" plugins/ohaze/skills/finishing/SKILL.md` 命中 Class 1 段
- [ ] `grep -n "必带 commit hash" plugins/ohaze/skills/finishing/SKILL.md` 命中 Class 1 段
- [ ] `grep -n "禁内嵌\|消费者" plugins/ohaze/skills/finishing/SKILL.md` 命中 Class 1 段
- [ ] **不复述断言**: `grep -c "sub-ship 编号\|reviewer finding\|fixture 细节" plugins/ohaze/skills/finishing/SKILL.md` 返回 0 (Class 1 段不能含 versioning.md 的禁内嵌清单原文)
- [ ] **hash 必带断言**: 本 ship 自己产生的每条 CHANGELOG entry 末尾匹配 `` `[a-f0-9]{7,12}` `` 反引号 hash 模式 (finishing 阶段手动填 / 验证)
- [ ] Class 1 原有 bump manifest + tick ROADMAP 步骤保持不变（除修改 2 涉及的 tick 逻辑）

---

## 修改 2 — finishing/SKILL.md Class 1 tick → prune

### Context

`plugins/ohaze/skills/finishing/SKILL.md:240-244` 当前 tick 逻辑：

```
- Tick the exact `linked_todo` line in the main project `ROADMAP.md` "## 当前主线" section from `- [ ]` to `- [x]` ...
- Branches:
  - `linked_todo` is `null` → skip silently
  - `linked_todo` non-null AND exact text found in `## 当前主线` → tick `- [ ]` → `- [x]`
  - `linked_todo` non-null BUT exact text NOT found → WARNING, skip
```

`- [x]` 行体留在 ROADMAP，CHANGELOG 又同时写一份 → 双份信息源，违反 `~/CLAUDE.md` 「CHANGELOG 朝过去 / ROADMAP 朝未来」铁律。vault dogfood 实测 ROADMAP 91KB 半数体量是 `- [x]` 僵尸条目。

`ship.md:243-245` Step A 已限定 `linked_todo` 只从 `## 当前主线` capture，**不从 Backlog**。所以本 spec 的 prune 范围只针对 `## 当前主线`，与 `ship.md` 契约对称。

### Behavior Contract

- tick 行为改 prune（整行删除）
- `linked_todo` null 分支保留不动
- `linked_todo` 找不到分支保留 WARNING + skip 不动（cross-version + manual-edit edge case 不变）
- 找到分支：从 `## 当前主线` 段整行删除（不留 `- [x]`，不留 `~~划掉~~`，不留空行）
- 删除后段落如果只剩主题句没有 todo 行：保留主题句不动（标记当期主线已收完，不强制清空段落）

### Proposed Wording (替换 finishing/SKILL.md:240-244 这一组 bullet + branches)

```markdown
- Prune the exact `linked_todo` line from the main project `ROADMAP.md` "## 当前主线" section (entire line removed, NOT ticked to `- [x]`). CHANGELOG bullet above is the todo's permanent home; ROADMAP 当前主线 朝未来不留勾痕 (遵守 `~/CLAUDE.md`「CHANGELOG 朝过去 / ROADMAP 朝未来」铁律). Note: `ship.md` Step A only captures `linked_todo` from `## 当前主线`, never Backlog — so this prune step is symmetric.
- Branches:
  - `linked_todo` is `null` → skip this sub-step silently (no todo was linked at ship time).
  - `linked_todo` non-null AND exact text found in `ROADMAP.md` `## 当前主线` → **整行删除** (不留 `- [x]`, 不留 `~~划掉~~`, 不留空行).
  - `linked_todo` non-null BUT exact text NOT found in `ROADMAP.md` `## 当前主线` (cross-version case: pre-F8 handoff captured from CLAUDE.md before the F8 contract; OR user manually edited ROADMAP between ship dispatch and finish): emit one explicit WARNING and skip the prune — `WARNING: linked_todo "<text>" not found in <main_repo_path>/ROADMAP.md ## 当前主线. Either the handoff was created before the linked_todo→ROADMAP.md contract (pre-F8), or the ROADMAP was edited mid-ship. Prune skipped; please prune manually if the todo still belongs there.` Continue to the other Class steps.
  - 删除后, 如果 `## 当前主线` 段只剩主题句没有 todo 行 → 保留主题句不动 (标记当期主线已收完, 不强制清空段落).
```

### Acceptance

- [ ] `grep -n "Prune\|prune\|整行删除" plugins/ohaze/skills/finishing/SKILL.md` 命中 Class 1 段
- [ ] `grep -n "tick" plugins/ohaze/skills/finishing/SKILL.md` 在 Class 1 段不再出现 (作为主要行为；WARNING 措辞里如还提 "tick" 历史 backward-compat 可接受)
- [ ] 删除分支 + null 分支 + NOT found 分支 三个 case 都明示
- [ ] WARNING 措辞从 "Tick skipped" 改为 "Prune skipped"

---

## 修改 3 — writing-plans/SKILL.md 加四件套禁列 Task 红线

### Context

`plugins/ohaze/skills/writing-plans/SKILL.md:156-192` Task Structure 段定义了 Task 的 Files / Behavior Contract / Acceptance / TDD Sequence 结构。当前**无任何「禁列四件套」红线**。

vault dogfood 实测 (`docs/ohaze/plans/2026-06-17-brain-feed-extend-link.md:221`)：plan Task 4 直接 `Modify: CHANGELOG.md` + DoD 强制 commit hash + spec/plan path → Codex 跟着执行 → 完全绕过 doc-finish preview。

`No Placeholders` 段 (Line 213-224) 是另一个自然提醒位 —— 收尾 self-review 时被扫到。

### Behavior Contract

- Task Structure 段顶部 (Line 156 附近) 加 callout block，第一眼看到
- No Placeholders 段 (Line 213 附近) 加一条「四件套禁列 Task Files / Acceptance」作为收尾检查
- callout 文字明示：四件套 = CLAUDE.md / README.md / ROADMAP.md / CHANGELOG.md / manifest 五个文件
- callout 文字明示：doc-finish 是收口；plan 描述需求时，提到「需要更新四件套」只能在 plan 末尾加注 (例如「四件套同步由 doc-finish 收口」)，不能落 Task

### Proposed Wording

**Task Structure 段顶部 (Line 156 之后，Task Structure 标题之前；或紧接标题加 callout)**:

```markdown
> **禁列四件套写入作为 Task 交付物** — 四件套 (`CLAUDE.md` / `README.md` / `ROADMAP.md` / `CHANGELOG.md` / manifest) 由 `ohaze:finishing` 的 doc-finish step 收口处理。Codex 实施期间不应直接动这五个文件。Task **Files 列表禁列四件套**，Acceptance Criteria 禁含「CHANGELOG entry exists」「ROADMAP ticked」这类四件套断言。如果 spec 提到需要更新四件套，在 plan 末尾加注一句「四件套同步由 doc-finish 收口」即可，不要落 Task。
```

**No Placeholders 段 (Line 213-224) 现有清单末尾加一条**:

```markdown
- 四件套写入作为 Task 交付物 — 一律删除并下挂到 doc-finish 收口（见 Task Structure 顶 callout）
```

### Acceptance

- [ ] `grep -n "禁列四件套\|doc-finish 收口" plugins/ohaze/skills/writing-plans/SKILL.md` 命中 ≥ 2 处（Task Structure 段 + No Placeholders 段）
- [ ] callout 明示 5 个文件名 (CLAUDE/README/ROADMAP/CHANGELOG/manifest)
- [ ] No Placeholders 段保留原有 6 条 placeholder 检查不变，仅末尾追加一条新约束
- [ ] 其他 Task Structure 字段 (Files / Behavior Contract / Acceptance / TDD Sequence) 文本不动

---

## 修改 4 — plan-to-codex-prompt/SKILL.md 双闸禁 Codex 写四件套

### Context

`plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md:28-105` 是生成 Codex XML prompt 的模板。包含多个 block：`<task>` / `<completeness_contract>` / `<commit_handling>` / `<verification_loop>` / `<implementation_autonomy>` / `<grounding_rules>` / `<missing_context_gating>` / `<action_safety>` / `<output_report>`。

当前 `<grounding_rules>` (Line 78-83) 有「stay within Files lists」「don't change deps」等约束，但**无四件套写入禁令**。`<action_safety>` (Line 89-95) 有「never push / force-push / delete unlisted」，**也无四件套禁令**。

writing-plans 的红线是「prevent」(plan 写出来时就拦)，plan-to-codex-prompt 的双闸是「detect-and-graceful-degrade」(plan 万一漏拦，Codex 收到 prompt 后跳过 + 标注)。

### Behavior Contract

- `<grounding_rules>` 加一条「soft」 红线：即便 plan 错列四件套，Codex 跳过 + 在 `<output_report>` 的 "Tasks with concerns" 中标注
- `<action_safety>` 加一条「hard」 禁令：Never modify 5 个四件套文件
- 两条措辞协调：grounding_rules 描述「detect + graceful action」，action_safety 是绝对底线

### Proposed Wording

**`<grounding_rules>` 段 (现有 Line 78-83 末尾追加)**:

```
- 四件套 (CLAUDE.md / README.md / ROADMAP.md / CHANGELOG.md / manifest 如 package.json / Cargo.toml / .claude-plugin/plugin.json) 写入由 ohaze 的 doc-finish step 收口处理。即便 plan Task 错误列出四件套改动 (e.g. `Modify: CHANGELOG.md`), 跳过该文件改动并在 <output_report> 的 "Tasks with concerns" 中标注 "plan Task N 越权列了 <file>, 已跳过留 doc-finish 处理"。Continue executing the rest of the Task normally.
```

**`<action_safety>` 段 (现有 Line 89-95 末尾追加)**:

```
- Never modify the project's four-piece contract files: CLAUDE.md, README.md, ROADMAP.md, CHANGELOG.md, or the manifest (package.json / Cargo.toml / .claude-plugin/plugin.json / etc.). These are doc-finish's exclusive territory.
```

### Acceptance

- [ ] `grep -n "doc-finish" plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md` 命中 ≥ 2 处 (grounding_rules + action_safety)
- [ ] grounding_rules 段含 "Tasks with concerns" + 标注模板
- [ ] action_safety 段含 "Never modify" + 完整 5 文件清单
- [ ] 其他 XML block (`<task>` / `<completeness_contract>` / `<commit_handling>` / `<verification_loop>` / `<implementation_autonomy>` / `<missing_context_gating>` / `<output_report>`) 文本不动

---

## 修改 5 — ohaze 自身四件套对齐 (hygiene)

### 5a. CLAUDE.md `## Agent 行为约定` 段加一行

**Context**: `CLAUDE.md:14-32` `## Agent 行为约定` 段是 ohaze 项目特殊约定的落点。新加一条 bullet 明示「doc-finish 是四件套写入唯一收口」契约，与本 ship 加固的 plan-to-codex 双闸 / writing-plans 红线呼应。

**Proposed Wording** (CLAUDE.md `## Agent 行为约定` `项目特殊约定` 子列表末尾追加一条):

```markdown
  - doc-finish 是四件套 (CLAUDE.md/README.md/ROADMAP.md/CHANGELOG.md/manifest) 写入唯一收口; Codex 实施期间禁直接写四件套 (即便 plan Task 错列), 由 plan-to-codex-prompt 双闸拦截 + writing-plans 红线源头预防
```

**Acceptance**:
- [ ] `grep -n "doc-finish.*四件套.*唯一收口" CLAUDE.md` 命中 1 行
- [ ] 该行字符数 ≤ 150 (满足 `~/CLAUDE.md` 「单条目体量上限」表中 CLAUDE.md 单 bullet ≤ 150 字符约束)
- [ ] 原有「Agent 行为约定」其他 bullets 不动

### 5b. ROADMAP.md `## 当前主线` v2.2.0 段清 3 行 `- [x]` 勾痕

**Context**: `ROADMAP.md:9-11` 是 v2.2.0 ship 完成后留下的 3 行 `- [x]` 勾痕：

```
- [x] `/ohaze:debug`：systematic-debugging 四阶段根因调研 + scope-lock prompt + 复用 ship-review/finishing
- [x] `/ohaze:ship` reverse reframe checkpoints：Phase 1 / Phase 1.5 / Phase 3 三处提示误入 bug 修复切 debug
- [x] `ship_mode` + ship-review branching：debug-only L2 scope_lock enforcement + G3 blast-radius gate
```

按本 ship 加固的「prune」规则，这 3 行应该全部删除（CHANGELOG v2.2.0 段已有完整记录，是唯一归宿）。删除后段落只剩主题句：

```
## 当前主线
v2.2.0 流程档位扩展：debug 修复档位 + ship 反向 reframe + `ship_mode` 下游分流。
```

**Proposed**: 直接删除 ROADMAP.md Line 9-11 三行 `- [x]` 内容。保留主题句 (Line 7)。

**Note**: 此 hygiene 改动是「示范修改 2 的预期效果」，但发生在 ohaze 自身四件套上。本 ship merge 后，ohaze 的 ROADMAP 立即处于「新约束应有的状态」。

**Acceptance**:
- [ ] `grep -c "^- \[x\]" ROADMAP.md` 在 `## 当前主线` 段返回 0
- [ ] `## 当前主线` 段下仍保留 v2.2.0 主题句
- [ ] 其他段 (`## Backlog` / `## Bug` / `## 长期目标` / `## In-flight` / `## Cancelled / Frozen`) 保留 (除 5c 涉及的 Backlog 删 3 条)

### 5c. ROADMAP.md `## Backlog` 删问题 10/11/12 三条

**Context**: `ROADMAP.md:23-25` 是问题 10 / 11 / 12 三条 backlog (vault 四件套体量审计暴露的高优先项)。本 ship 完成后，这三条由 CHANGELOG `## [2.2.1]` 段的 bullet 替代（CHANGELOG 是它们的最终归宿）。

**Proposed**: 删除 ROADMAP.md Line 23-25 三条 backlog entry。

**注意**: 中优先「debug-to-codex-prompt 同款禁令」(问题 13, Line 26) 和「codex-executor drift detection 扩展」(问题 14, Line 27) **保留不删**（out of scope，单独 ship）。

**Acceptance**:
- [ ] `grep -c "doc-finish Class 1\|writing-plans / plan-to-codex-prompt 禁止把四件套" ROADMAP.md` 返回 0
- [ ] 中优先「debug-to-codex-prompt 同款禁令」+「codex-executor drift detection 扩展」+「`/ohaze:debug` 全英文 bug」三条保留
- [ ] 其他 backlog / bug / 长期目标段未受影响

---

## 修改 6 — 版本号同步 (v2.2.0 → v2.2.1)

### Context

按 ohaze CLAUDE.md `## 版本号规范` 段和 `~/CLAUDE.md` 项目文档契约，版本号字段在 manifest + CHANGELOG + (README / CLAUDE.md 版本演进串如果有) **必须全部同步**。

本 ship 性质 = 约束加固 (向后兼容，行为变更落在 doc-finish step 一侧)，按 SemVer 偏 PATCH (v2.2.0 → v2.2.1)。

### Behavior Contract

- `plugins/ohaze/.claude-plugin/plugin.json` `version` 字段从 `2.2.0` → `2.2.1`
- `CHANGELOG.md` 新增 `## [2.2.1] - 2026-06-17` 段，含 `### Changed` / `### Fixed`（按内容分类）
- `## [Unreleased]` 段保留空 placeholder 结构 (Added / Changed / Fixed / Removed 四个空 header)
- 不需要 git tag（本 ship 的 commit 阶段不打 tag；按全局契约「发版时打 tag」，但「发版」语义对 local-merge ship 是模糊的；保持现状，tag 议题留给历史 tag 补打 backlog 单独处理）
- 不需要 README 改动 (无版本演进串 / 无对外 user-facing 介绍变更)

### Proposed Wording (CHANGELOG.md 新增段)

```markdown
## [2.2.1] - 2026-06-17

v2.2.1 主题：doc-finish 收口契约加固 — 防止下游项目 (vault 等) 在 ship 过程中产出膨胀文档 / 僵尸条目 / 旁路绕过 preview。

### Changed
- **doc-finish CHANGELOG 篇幅+视角硬约束 / doc-finish-changelog-tightening**: `finishing/SKILL.md` Class 1 写 CHANGELOG entry 引用 versioning.md 风格契约 — ≤ 200 字符 + 消费者视角 + 末尾必带 hash。(`<hash>`)
- **doc-finish ROADMAP tick→prune / doc-finish-roadmap-prune**: `finishing/SKILL.md` Class 1 把 `linked_todo` 从 ROADMAP `## 当前主线` 整行删除, 不留 `- [x]` — CHANGELOG bullet 是唯一归宿。(`<hash>`)
- **plan→codex 链禁四件套写入 / plan-codex-four-piece-firewall**: `writing-plans` 加红线禁列四件套作为 Task 交付物; `plan-to-codex-prompt` 在 grounding_rules + action_safety 双闸禁 Codex 直接写四件套。(`<hash>`)

### Fixed
- **ohaze 自身四件套对齐 / ohaze-self-alignment**: CLAUDE.md 加一行明示 doc-finish 唯一收口契约; ROADMAP `## 当前主线` v2.2.0 段清 3 行历史勾痕; Backlog 删问题 10/11/12 三条。(`<hash>`)
```

**Note on entry length + hash placeholder**:
- 本 ship 自己写的 CHANGELOG entry 也需要符合新约束 (≤ 200 字符 + 消费者视角 + 禁内嵌 + 末尾必带 hash)。上面 4 条 bullet 手动控制在 110-160 字符（不含 ``<hash>`` 占位）。
- ``<hash>`` 占位由 finishing 阶段填充：feature commit hash 是 Codex 实施 commit (Phase 5.0 后已存在), 不是 docs commit 自身; finishing/doc-finish 写 CHANGELOG entry 时把每条 bullet 末尾的 ``<hash>`` 替换成对应 feature commit short hash (7-12 字符)。
- 本 ship finishing 阶段使用**旧规则**收口，但 haze 手动监督 + Claude 主线程把 Codex 报告的过程性细节留在 commit body 不带进 CHANGELOG (模拟新规则) + 手动填 hash 占位。

### Acceptance

- [ ] `plugins/ohaze/.claude-plugin/plugin.json` `version` = `"2.2.1"`
- [ ] CHANGELOG.md 含 `## [2.2.1] - 2026-06-17` 段
- [ ] 每条 bullet 一句话 ≤ 200 字符，不内嵌 process 细节
- [ ] **hash 必带断言**: `## [2.2.1]` 段每条 bullet 末尾匹配 ``([a-f0-9]{7,12})`` 模式 (finishing 阶段填完 `<hash>` 占位后), 用 `grep -E '\(\`?[a-f0-9]{7,12}\`?\)\.?$' CHANGELOG.md` 验证
- [ ] `## [Unreleased]` 段 Added / Changed / Fixed / Removed 四个空 header 保留 (placeholder 结构)

---

## Files List (汇总)

**Modify**:
- `plugins/ohaze/skills/finishing/SKILL.md` (Class 1 段 Line 236-264 区域)
- `plugins/ohaze/skills/writing-plans/SKILL.md` (Task Structure 段 Line 156 附近 + No Placeholders 段 Line 213 附近)
- `plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md` (`<grounding_rules>` + `<action_safety>` 两段)
- `CLAUDE.md` (`## Agent 行为约定` 段 Line 14-32)
- `ROADMAP.md` (`## 当前主线` 删 3 行 + `## Backlog` 删 3 条)
- `CHANGELOG.md` (新增 `## [2.2.1]` 段)
- `plugins/ohaze/.claude-plugin/plugin.json` (`version` 字段)

**Create**: 无 (brief + spec 由 ship Phase 2b 写进 worktree，不属本 Task list)

**Delete**: 无

---

## 时序前提 (本 ship finishing 阶段的特殊性)

本 ship 改的 SKILL.md 在 worktree 路径，main repo 注册的 plugin path 还是旧版。所以本 ship 自己的 finishing 阶段 (Phase 7) **必然使用旧 doc-finish 规则**。已知 + 接受：

- haze 在 finishing 阶段手动监督：CHANGELOG bullet 长度 / 视角 / 不内嵌
- haze 手动 prune ROADMAP `linked_todo` 行（模拟新规则）
- 真 dog-food 在下次自然 ship (任何后续 ship) 自动发生

本 spec 不要求 Codex 在 ship 末做任何 finishing 行为，finishing 由 Claude 主线程接管（Phase 7 ohaze:finishing skill）。

---

## Out of Scope (重申，避免 scope creep)

- debug-to-codex-prompt 同款禁令 (问题 13) — 单独 ship
- codex-executor drift detection 扩展 (问题 14) — 单独 ship
- ohaze:debug 全英文产出 bug — 单独 ship
- 历史 v2.1.1 / v2.1.2 / v2.1.3 缺 tag 补打 — 单独 ship
- Phase 1.5 spec quality self-check 工艺改进 — 跨 ship 工艺，单独 ship
- 历史 CHANGELOG entry 重写到 ≤ 200 字符 — 不动已发版段
- 测试套件 — ohaze 项目无自动化测试套件 (Markdown plugin)，verify 靠 grep 断言 + dogfood (本 spec 各修改的 Acceptance 段已列出 grep 断言)
