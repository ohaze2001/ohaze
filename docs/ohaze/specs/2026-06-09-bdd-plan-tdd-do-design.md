# BDD Plan + TDD Do (ohaze v2.1) — Design Spec

> Date: 2026-06-09
> Slug: `bdd-plan-tdd-do`
> Branch (when implemented): `feat/bdd-plan-tdd-do`
> Target version: ohaze v2.1.0

---

## Why this exists

haze 当前用 ohaze 做 vibe coding,核心诉求是：

> "我并不想接触太多技术层面的实现,我只想跟你描述我的需求、描述这个功能、描述我要得到一个什么样的产品。"

但现状 `ohaze:brainstorming` 的对话指导是 "Cover: architecture, components, data flow, error handling, testing" — 妥妥的技术对话。spec/plan 这两个产物也越来越 "haze 看不进去"(haze 原话："不管是 spec 或者是 plan,我已经很久没有看了")。

同时,TDD 节奏其实在 ohaze 里**已经存在**:`writing-plans` 每个 Task 的 TDD Sequence + `codex-executor` reviewer 的 PART 2.5 实跑测试。所以 TDD 侧不需要改造。

需要改造的是 **brainstorming 阶段 + spec 产出阶段** — 把对话锁在需求侧,把 spec 写作交给 Claude 自决,新增一份给人看的 brief,并引入 Codex 反向异源审 spec(对称翻转现有 "Codex 实现 → Claude 审" 的模式)。

灵感参考 [garrytan/gstack](https://github.com/garrytan/gstack) 的 `/office-hours`(forcing questions)、`/spec`(mandatory code-reading)、`/codex`(second opinion)、`/plan-ceo-review`(4-mode scope reflection)、`/investigate`(no fix without investigation)、`/cso`(OWASP+STRIDE)。

---

## Architecture

```
旧 (v2.0.0):
  brainstorm 一次问完 ──→ spec ──→ plan ──→ codex 实现 ──→ Claude 审 ──→ finish
   (技术 + 需求混着问)    (haze 必看但讨厌)

新 (v2.1.0):
  Phase 1   BDD brainstorm (forcing questions 锁需求侧 + 4-modes scope)
              │  产物 → feature brief (给 haze 看,人话,新产物)
              ↓
            haze approve brief
              ↓
  Phase 1.5 Claude 自动从 brief 推 spec
              │  mandatory code-reading 4 类相关文件,引用 file:line
              │  关键边界 (5 类触发条件) 单点问 haze
              │  spec 写完回填 brief 的 "Claude 替你决定的关键技术方向" 段
              ↓
  Phase 1.6 Codex 异源审 spec (反向对称)
              │  调用新 skill: ohaze:spec-to-codex-review
              │  ┌─ PASS ────────────────────────────────┐
              │  ↓                                        │
              └─ NEEDS-CLARIFICATION (max 2 轮)           │
                  ↓                                        │
                按 issue.routing 处理:                     │
                  - fix-in-spec → Claude 改 spec ─────────┤
                  - ask-haze → 单点问 haze → 改 spec ─────┘
              ↓
  Phase 2   worktree + commit (brief + spec 都进 feat 分支)
              ↓
  Phase 3   writing-plans (Claude 写 plan,docs/ohaze/plans/)
              ↓
  Phase 3.5 plan 一句话摘要 → default-go (haze 可打断,默认自动进)
              ↓
  Phase 4-6 codex 实现 → Claude 审实现 → retry loop
              └─ retry fix prompt 加 <investigate_first> block (Iron Law)
              ↓
  Phase 7   finishing (6 项现状 + 新增第 7 项 conditional)
              └─ 第 7 项: 安全审查 (web/API 项目可选)
```

**对称美**:
- Codex 实现 → Claude 审实现(现有)
- Claude 写 spec → Codex 审 spec(新增)
- 实施侧 ↔ 设计侧各有异源把关

**核心特征**:
- Phase 1 haze 深度参与(只聊需求)
- Phase 1.5 / 1.6 haze **几乎不介入**,只在 Codex 审出"需求模糊"或 spec 关键边界时被单点问
- Phase 2+ 流程不变(只改路径名 superpowers → ohaze)

---

## Phase 1 — BDD-flavored brainstorm

### 7 类 forcing questions(SKILL.md 内 hint,不强制顺序/全问/问法)

LLM 看上下文判断哪个该问、哪个能跳、哪个该追问几轮。**这是 hint 套路,不是模板**。

| 类别 | 问什么 |
|---|---|
| Pain | 具体痛在哪? 给一个 specific example,不要 hypothetical |
| Reframe push-back | 你说要做 X,但听起来你描述的是 Y,确认? |
| User | 给谁用? 调用者/用户/触发者在啥情景下用? |
| Visible outcome | 用完之后,他看到什么不一样了? |
| Out of scope | 哪些场景明确不做? |
| Capability extraction | 听下来这功能要能做 1/2/3/4/5...,漏了什么? |
| Scope 4-modes | 推荐 Expansion / Selective Expansion / Hold Scope / Reduction + 理由,haze approve/push back |

### Feature brief 模板

落点:`docs/ohaze/briefs/<YYYY-MM-DD>-<slug>-brief.md`

```markdown
# <feature 名> — Feature Brief
> 给 haze 看。spec 在 docs/ohaze/specs/... 给 Codex 看,你不用看。

## 这是干嘛的
<一句话产品定位 — reframed 之后的,可能跟你最初说的不一样>

## 给谁用
<调用者/用户/触发者>

## 用户场景 (Scenarios)
### Scenario 1: <happy path 名>
- Given <初始状态>
- When <用户做的事>
- Then <看到的结果>

### Scenario 2: <边界>
### Scenario 3: <失败/恢复>

## "完成的样子" Checklist
- [ ] 能 ...
- [ ] 不能 ...
- [ ] 失败时能 ...

## 不做什么 (Out of Scope)
- ...

## Scope 决策
- **模式**: <Expansion | Selective Expansion | Hold Scope | Reduction>
- **理由**: <一句话>

## Claude 替你决定的关键技术方向 (Phase 1.5 后回填,事后扫一眼)
- <一句话每条,不同意 push back>
```

### 终态

Phase 1 终态 = haze approve feature brief。**不写 spec**。spec 由 Phase 1.5 处理。

---

## Phase 1.5 — Claude 自动写 spec

### Mandatory code-reading(4 类相关文件)

写 spec **之前**,Claude 先 list 4 类要读的文件并真读:

1. 同领域现有代码(functional area)
2. 调用方 / 被调用方
3. 现有相关 spec / plan(cross-reference)
4. CHANGELOG 同类条目(历史决策)

spec 写作时引用 `file:line`,避免拍脑袋。

### 关键边界单点问触发条件(5 类)

命中即用 `AskUserQuestion` 单点问(不开放对话)。**门槛拉高原则**:能 Claude 自决就自决,只在有 product impact 时才打扰 haze。

1. 涉及外部 API(Shopify / Supabase / Vercel / 第三方)— 选用直接影响功能/成本/上线路径
2. 涉及部署目标 / 上线影响 — 产品决策
3. 跟现有架构显著冲突 — 仅当冲突会破坏 brief 里承诺的 scenario 时才问;纯重构判断 Claude 自决
4. 涉及成本 / 计费(增加 API 调用、长跑 job)— 产品决策
5. 多个技术方案有**明显 user-visible tradeoff**(成本 / 性能 / UX 等可被产品决策的差异)— 纯实现风格差异(用 lib A vs lib B 但功能等价)不问

### 输出

- spec → `docs/ohaze/specs/<YYYY-MM-DD>-<slug>-design.md`(沿用现有 spec 格式)
- 完成后回填 brief 的 "Claude 替你决定的关键技术方向" 段

---

## Phase 1.6 — Codex 异源审 spec(新 skill)

### 新 skill:`ohaze:spec-to-codex-review`

落点:`plugins/ohaze/skills/spec-to-codex-review/SKILL.md`

跟现有 `ohaze:plan-to-codex-prompt` 同构 — 一个 thin wrapper,封装 Codex 审 spec 的 XML prompt 模板。

### 调用方式

`codex exec`(一次性,**非 background** — spec review 几秒到几十秒),**不复用 `thread_id`**(独立 session,跨 ship 不污染)。Loop 内多轮重审也是 fresh exec(不用 `codex exec resume`),保证每轮 Codex 上下文干净,只看当前 spec 而不被前轮 verdict 影响判断。

### Prompt 模板(完整,直接落 SKILL.md)

````xml
<task>
You are about to implement the spec at {spec_path} for feature "{feature_name}".
Before you start coding, audit it from the implementer's perspective.

Your job is NOT to nitpick design or rate prose quality. Your job is to find
the spec issues that WILL block you (or another implementer) at execution time:
ambiguity that forces a guess, missing constraints that force a rework,
contradictions with existing code that force a redesign, scope drift from
what the user actually asked for.
</task>

<inputs>
- Feature brief (what the user wants, in user-language): {brief_path}
- Spec (technical design, what you'll implement): {spec_path}
- Relevant code context (Claude read these while writing the spec): {code_refs}
- Project type: {project_type}
- Project root: {main_repo_path}
</inputs>

<review_dimensions>
Walk through these 5 dimensions in order. Do not skip any.

A) BRIEF ↔ SPEC ALIGNMENT (scope drift)
   - For each "完成的样子" checkbox in the brief: is there a corresponding
     section in the spec that covers it?
   - Does the spec add anything the brief did NOT ask for? (scope creep)
   - Does the spec remove or skip anything the brief asked for? (scope cut)
   - Out-of-scope items in the brief: does the spec accidentally implement them?

B) AMBIGUITY (2-interpretation test)
   - For each requirement / behavior / interface in the spec: read it twice
     and pretend you are a different implementer the second time. Did you
     reach the same conclusion both times?
   - Specifically check: data flow direction, error handling boundaries,
     concurrency assumptions, what state is owned by whom, idempotency
     expectations, what counts as "success".
   - For each ambiguity found: quote the exact spec text and list the ≥ 2
     reasonable interpretations.

C) MISSING DETAILS (implementer "卡住" test)
   - Walk a hypothetical first hour of implementation. At which point would
     you have to stop and ask a question that the spec does not answer?
   - Check for: missing input/output formats, undefined error states,
     undefined timeouts/retries/limits, missing file paths, undefined
     interface signatures, missing dependency on external state (env vars,
     config files, network).

D) CONFLICTS WITH EXISTING CODE
   - Read the {code_refs} files. For each: does the spec contradict an
     established pattern, API, or invariant in this code?
   - Does the spec assume a function / module / type exists that does not?
   - Does the spec assume a function / module / type does NOT exist that
     actually does (so the implementer should reuse instead of recreate)?

E) TECHNICAL DECISION CHALLENGE
   - For each non-trivial decision in the spec (library choice, architecture
     pattern, data structure, retry strategy, etc.): is there a simpler,
     safer, or cheaper alternative the spec did not consider?
   - Only flag if your alternative is concretely better (cite the
     comparison). Do NOT flag "I would have done it differently" without
     a specific tradeoff argument.
</review_dimensions>

<constraints>
- Confidence gate: only report an issue if you are ≥ 7/10 confident it
  is a real problem. Skip "this might be confusing" — only report
  "this WILL force a guess / WILL cause rework / WILL conflict with X".
- Each issue must cite specific evidence: spec file:line OR code file:line.
  No "the spec is unclear about errors" without quoting the line.
- Do NOT critique the brief's requirements (haze decides product scope,
  not you). You can flag brief↔spec drift in dimension A, but you cannot
  say "this feature shouldn't exist".
- Do NOT suggest style changes, naming preferences, or formatting fixes.
- Each issue must be tagged with one of: {AMBIGUITY, MISSING, CONFLICT,
  DRIFT, ALT-DECISION} and routed to one of: {fix-in-spec, ask-haze}.
  - fix-in-spec = Claude can resolve by editing the spec without user input
  - ask-haze = haze needs to decide on a product / scope / requirement
    question. Prefer fix-in-spec for technical decisions. You MAY route a
    technical decision to ask-haze ONLY when it has meaningful product
    impact (affects a brief scenario, cost, UX, or external dependency).
    Pure implementation-style choices (lib A vs lib B with same behavior,
    internal naming, control flow shape) MUST be fix-in-spec.
</constraints>

<output_format>
Return a single JSON object with this exact shape (no surrounding prose):

{
  "verdict": "PASS" | "NEEDS-CLARIFICATION",
  "summary": "<one sentence>",
  "issues": [
    {
      "id": "<short slug e.g. 'auth-flow-ambiguous'>",
      "category": "AMBIGUITY" | "MISSING" | "CONFLICT" | "DRIFT" | "ALT-DECISION",
      "severity": "CRITICAL" | "IMPORTANT" | "NICE-TO-HAVE",
      "routing": "fix-in-spec" | "ask-haze",
      "evidence": "<file:line citation + quoted text>",
      "problem": "<what's wrong>",
      "suggestion": "<concrete recommendation: either spec change text OR question to ask haze>",
      "confidence": <integer 7-10>
    }
  ]
}

verdict = "PASS" if and only if issues contains zero CRITICAL items AND
zero IMPORTANT items. NICE-TO-HAVE items alone do NOT cause NEEDS-CLARIFICATION.
</output_format>
````

### verdict 落点

`<worktree_path>/.ohaze/spec-review-verdict.json`(在 Phase 2 worktree 创建之后才写;Phase 1.6 在 main 上跑时用临时路径 `<main_repo_path>/.ohaze/spec-review-verdict.json` — 临时性,迁移到 worktree 后清掉)。

### Loop 行为

- **PASS** → 继续 Phase 2(worktree + commit)
- **NEEDS-CLARIFICATION** → 按 `issue.routing` 处理:
  - `fix-in-spec`:Claude 直接改 spec,**回到 Phase 1.6** 再审一遍
  - `ask-haze`:Claude 用 `AskUserQuestion` 把所有 `ask-haze` 类 issue 合并问 haze 一次(一个 question 最多 4 个 option 不够就分批),改 spec 后**回到 Phase 1.6**
- **Loop max 2 轮** — 第 3 轮还有 issues 就 surface 给 haze 决定 "强制接受 / 改 brief / 砍 feature"

---

## Phase 3.5 — Plan 一句话摘要 + default-go(去掉 haze 'go' gate)

### 为什么加这个 phase

现有 `ohaze:writing-plans` 终态要求 haze reply 'go' 才进 Codex 实现 — 这意味着 plan 内容(`formatter.py:50-77 整段删`、`§3 Dead code 清理` 这种 Task 级别技术细节)会直接展示在 haze 面前,违反 vibe coding 诉求(haze 给的两张 ship 截图都印证了 plan/spec 内容**比 spec 还细**)。

### 行为

writing-plans 写完 plan 后:

1. **Claude 自动生成 plan 摘要**(一句话级别),格式:
   ```
   📋 Plan 写好了 → docs/ohaze/plans/<file>.md
      拆了 <N> 个 Task,大致涉及 <X / Y / Z 三块>(架构层面,不展开细节)。
      准备进 Codex 实现,你可以打断(输入任意非 go 内容)或等待自动 go。
   ```

2. **default-go**:不等待 haze 明确 'go'。Claude 直接进 Phase 4(`ohaze:codex-executor` mode='dispatch')。

3. **可打断机制**:haze 仍可以在摘要展示后立即打断 — 一旦 haze 在摘要展示后下一轮回了任何非 "go" / 非默认确认的内容,Phase 4 dispatch 取消,流程进 modify/cancel 分支(走 finishing skill 的 modify 子流程)。

### 为什么不加 plan 异源审(选 option C 而非 A / B)

讨论过 3 个 options:
- A. Codex dry-run 审 plan(同源,不算严格异源)
- B. Claude general-purpose subagent 审 plan(同 model 异源 prompt,弱异源)
- **C. 不审 plan,直接 default-go(选这个)**

选 C 的理由:
1. plan 是 spec 的派生,spec 已经在 Phase 1.6 被 Codex 异源审过
2. Phase 5 Claude 异源审实现是最后一道闸门 — 会真跑 `project_test_command`,plan 写歪了实现必然测试失败,自动进 Phase 6 retry loop
3. A / B 都是双重保险,token 成本 + 等待时间增加,收益边际
4. C 最贴 vibe coding 诉求

升级路径:如果未来发现 plan 写歪概率高(observed pattern),从 C 升 A / B 不破坏现状,只是再加一个 thin wrapper skill(类似 `spec-to-codex-review` 的 `plan-to-codex-review`)。

### 实施改动

- `plugins/ohaze/skills/writing-plans/SKILL.md` — "Execution Handoff" 段去掉 "Wait for user's 'go'",改成"Output plan 摘要,handoff 给 ship.md Phase 3.5"
- `plugins/ohaze/commands/ship.md` — Phase 3 调用 writing-plans 后,新增 Phase 3.5(生成摘要 + 自动调 Phase 4 dispatch),haze 仍可在摘要后下一轮打断

### 失败模式

| 模式 | 处理 |
|---|---|
| haze 打断,但没说清要改什么 | Claude 用 `AskUserQuestion` 单点问:revise plan / 砍 feature / 暂停 ship |
| haze 没回任何东西(去喝咖啡了) | default-go 已经触发,Codex 实际上已在跑;haze 回来时 Phase 4-5 可能已完成,看 `/ohaze:status` 即可 |
| Codex dispatch 失败 | 同现状 Phase 4 失败模式处理(`codex-executor` Phase 4 已有)|

---

## Phase 6 — Iron Law fix prompt 改造

现有 `codex-executor.md` Phase 6 retry 的 fix prompt 已有 `<task>` / `<anti_regression>` / `<action_safety>` / `<verification_loop>` 四 block。**最前面**加一个:

```xml
<investigate_first>
改动任何代码前,先写出根因诊断:
- 违反的是哪个 contract / AC?
- 上一轮为什么没修对? (具体证据)
- 你的根因假设是什么? (证据支撑)
如果说不清根因,直接停下报告,不要硬修。
</investigate_first>
```

借鉴 gstack `/investigate` 的 Iron Law:no fixes without investigation。防止 Codex 在 retry 时不调查根因就闷头改导致越改越乱。

**跟现有 stuck-detection 的关系**(避免误解):
- `<investigate_first>` 在 **每次 retry 都强制** 给 Codex 的(让 Codex 自我约束),作用域是 Codex prompt 内部
- stuck-detection 是 **Claude 层** 跨轮检测(iteration N 跟 N-1 issue 重叠才升级),作用域是 retry loop 外部
- 两者层次不同,不冲突,叠加生效

---

## Phase 7 — 新增第 7 项 Security Review(conditional)

### 触发条件(2 选 1 即可)

- 项目类型为 web / API
- OR 涉及外部用户输入 / auth / 数据存储

(`project_type` 在 `current-ship.json` 已有,Phase 1 brainstorm 写入。涉及外部输入这一类需要在 brief 元数据加 `has_external_input: true` 字段或者从 spec 关键词推断。)

### 菜单条目

```
7. 安全审查 (可选,适用于 web/API 项目)
```

### Prompt 要点(借 `/cso`)

- OWASP Top 10 + STRIDE
- Confidence gate:只报 confidence ≥ 8/10 的 finding(比 Phase 1.6 严,因为安全噪音杀伤大)
- 每个 finding 必须包含具体 exploit scenario(不是"理论上可能 XSS"这种泛泛而谈)

### 结果接入

输出作为 ADVERSARIAL 类 finding,合进现有第 6 项「修复对抗审查」流程 — haze 可以选 fix 或 accept。

---

## 涉及文件改动清单

### 新建

- `plugins/ohaze/skills/spec-to-codex-review/SKILL.md` — 新 skill,封装 Codex 审 spec XML prompt(全文如上)

### 改造

| 文件 | 改什么 |
|---|---|
| `plugins/ohaze/skills/brainstorming/SKILL.md` | Phase 1 改造:7 类 forcing hints(灵活,不强制)、brief 模板、终态从 "design approved" → "brief approved"、不再写 spec |
| `plugins/ohaze/commands/ship.md` | Phase 1 调用规则改;新增 Phase 1.5(spec 自动生成 + mandatory code-reading + 5 类单点问)、Phase 1.6(调 `spec-to-codex-review` + loop max 2);**新增 Phase 3.5**(plan 一句话摘要 + default-go,可打断);Phase 2 写 brief + spec 双文件;spec 路径 `docs/superpowers/specs/` → `docs/ohaze/specs/`;新增 brief 路径 `docs/ohaze/briefs/` |
| `plugins/ohaze/skills/writing-plans/SKILL.md` | plan 路径 `docs/superpowers/plans/` → `docs/ohaze/plans/`;**"Execution Handoff" 段去掉 "Wait for user's 'go'"**,改成输出 plan 摘要并 handoff 给 ship.md Phase 3.5 |
| `plugins/ohaze/skills/codex-executor/SKILL.md` | Phase 6 fix prompt 加 `<investigate_first>` block;引用 plan/spec 路径处同步更新 |
| `plugins/ohaze/skills/finishing/SKILL.md` | 新增第 7 项 Security Review(conditional);引用路径同步更新 |
| `plugins/ohaze/.claude-plugin/plugin.json` | version `2.0.0` → `2.1.0` |
| `CLAUDE.md` / `README.md` / `ROADMAP.md` / `CHANGELOG.md` | 四件套同步:架构小节加 BDD/spec-review 流程;CHANGELOG 记 v2.1.0 |
| `.gitignore` | `.ohaze/spec-review-verdict.json` 加白 |

### 不动

- `plugins/ohaze/skills/using-git-worktrees/SKILL.md`
- `plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md`
- `plugins/ohaze/commands/ship-review.md`, `ship-finish.md`, `status.md`

### 数据契约改动

`.ohaze/current-ship.json` 加字段:

```json
{
  "brief_path": "<absolute path to docs/ohaze/briefs/<date>-<slug>-brief.md>",
  "spec_review_iteration": 0,
  "project_category": "web | api | cli | plugin | agent | other"
}
```

`brief_path` 给 finishing 阶段 doc-finish 路由用。`spec_review_iteration` 计数 Phase 1.6 loop(独立于 Phase 6 的 `retries`)。`project_category` 决定第 7 项菜单显示。

---

## 失败模式 + 恢复

| 失败模式 | 恢复策略 |
|---|---|
| Phase 1 haze 中途取消 | 干净退出,不留产物 |
| Phase 1.5 mandatory code-reading 找不到相关文件(全新项目) | 跳过 code-reading,spec 注明"全新模块,无历史 ref"继续 |
| Phase 1.6 codex CLI 缺失 | 沿用 Pre-flight 的 hard dependency check,要求安装 codex |
| Phase 1.6 codex 返回非 JSON | 一次重试(更严格的 format reminder);仍失败 → surface 给 haze,fallback 到"无 spec review 直接进 Phase 2"(降级运行) |
| Phase 1.6 loop > 2 轮仍 FAIL | surface 完整 issues 给 haze,3 选 1:强制接受当前 spec / 改 brief 重跑 / 砍 feature |
| Phase 7 项目类型推断不准 | 用户可以从菜单手动启用 第 7 项 即使触发条件未命中 |

---

## Out of scope(v2.1.0 不做)

- 改造现有 `superpowers:writing-plans` 的 TDD Sequence(haze 已确认现状够用)
- 把 ADVERSARIAL/CSO security findings 自动 fix(纯 advisory,haze 决定)
- 迁移历史项目的 `docs/superpowers/` 到 `docs/ohaze/`(新路径只用于新流程产物,旧项目保持现状)
- 跨 ship 的 metric tracking(无 retro 类需求)
- 真浏览器跑验收测试(`/qa` 类功能,产品类项目 v3.x backlog)
- Continuous checkpoint mode(Codex 异步跑无法插入 WIP commit)

---

## Open questions(实现时定)

1. Phase 1.6 临时 verdict 文件落点:在 main 上跑时是 `<main_repo_path>/.ohaze/spec-review-verdict.json` 还是 `/tmp/...`? 推荐前者(便于 debug),迁移到 worktree 后清理。
2. `project_category` 怎么自动识别? 推荐 brainstorm 时 Claude 推断 + haze 一次确认(brief 里写),不自动从 manifest 推。
3. Phase 7 触发条件 "涉及外部输入" 怎么标记? 推荐 brief 加 `has_external_input: bool` 字段(brainstorm Phase 1 抓 Scenario 时自动判断)。

---

## Attribution

- Forking inspiration: [garrytan/gstack](https://github.com/garrytan/gstack) — `/office-hours`, `/spec` mandatory code-reading, `/codex` second opinion, `/plan-ceo-review` 4-mode scope, `/investigate` Iron Law, `/cso` OWASP+STRIDE confidence gate
- BDD/TDD framing: Behavior-Driven Development(Dan North et al.) + Test-Driven Development(Kent Beck)— ohaze 用 BDD 锁需求侧,TDD 锁实现侧
- 原有 ohaze v2.0.0 流程基线:`brainstorm → worktree+spec → plan → codex exec → adversarial review → finishing`
