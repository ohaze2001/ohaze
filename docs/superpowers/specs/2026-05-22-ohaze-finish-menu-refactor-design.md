# ohaze 第一期改造 — finish menu 重构 + 文档漂移自动修 + Codex session id 精确化

> Spec / 设计文档 · 2026-05-22 · 目标版本 1.9.0

## 背景与动机

本次 session 暴露了 ohaze 三个真实问题：

1. **Codex resume 不精确** — `codex-executor` 的 retry / modify 子流程用 `codex exec resume --last`。`--last` 是全局「最近一次 session」，并行跑两个 ship 时会接错会话、改错 worktree。这是正确性 bug。
2. **文档漂移无人管** — 本 session 就发现 ohaze `CLAUDE.md` 对 codex 调用模型的描述落后代码 3 个版本（1.7→1.8），靠人肉偶然发现。ship 完一个功能后没有任何机制检测「这次改动是否让设计文档失真」。
3. **finish menu 不认项目类型** — 当前 6 选项菜单是固定的并列 git 动作，不区分「纯本地 / 远程仓库」项目，且缺「合并+推送」这一最常用组合；逐项选择繁琐。

本期（第一期/核心）解决以上三点 + 4 个连带的架构问题（P1–P4）。第二期（vault 智能提取习惯、自定义收尾的复杂解析、线上部署相关）不在本 spec 范围。

## 范围

### 本期范围

- R1 Codex session id 精确捕获与 resume
- R2 文档漂移自动检测（advisory）+ finishing 阶段半自动修复
- R3 finish menu 重构为「项目类型检测 → 推荐收尾链 → 一键执行」（项目类型仅分 `local` / `remote` 两类）
- R6 「保留 worktree」从菜单平级选项降级为不显眼的 escape hatch
- R7 「继续修改」modify 子流程 — 确认现状满足，本期不改
- R8 resume 边界写进 ohaze 文档
- P1–P4 四个架构问题的方案（见「架构决策」）

### 明确不在本期范围

- **线上部署相关，整体推迟到下一次改造** — 包括项目类型的 `remote-deploy` 细分、部署平台检测、deploy 确认点、ohaze 执行部署命令。原因：是否让 ohaze 接管部署、以及部署环的交互形态尚未对齐，留待专门一次改造处理。本期 finishing 只认 `local` / `remote` 两类。
- vault 智能提取用户收尾习惯（本期仅做偏好文件 + 内置默认 + 菜单选择回写）
- 自定义收尾方案的复杂自由文本解析（本期做基础版：见 A7）
- `/ohaze:status` 的 codex 孤儿进程 reconcile 检测（单独 backlog）

## 需求详述

### R1 — Codex session id 精确捕获

- `ship.md` Phase 4 派发 `codex exec` 后，捕获本次 Codex session id（UUID），写入 `.ohaze/current-ship.json` 的新字段 `codex_session_id`。
- `codex-executor` 的 retry 循环与 modify 子流程（5a）一律改用 `codex exec resume <codex_session_id>`，**废弃 `--last`**。
- codex-cli 0.133.0 实测：`codex exec resume [SESSION_ID]` 接受 UUID 精确恢复。
- 捕获方式不写死（留给 plan / Codex 实测确定）；契约是：`current-ship.json` 必须含可用的 `codex_session_id`，且 resume 全程不依赖 `--last`。
- 兜底：若 session id 捕获失败（旧 codex 版本 / 输出格式变化），降级回 `resume --last` 并在日志显著标注「session id 缺失，resume 可能不精确」，不静默。

### R2 — 文档漂移自动检测 + 半自动修复（方向 B）

- `codex-executor` 的 reviewer prompt 增加一个 advisory PART（命名 `DOC-DRIFT`，与现有 `ADVERSARIAL` 同级——**不进 PASS/FAIL gate**）。
- 检测对象：本次 `git diff` 是否让**目标项目** `CLAUDE.md` 的描述性 section 失真。描述性 section 限定为：`关键文件` / `设计决策` / `阶段归属` / `前置要求` / `外部依赖`。**不检测** `当前目标` checkbox 区（那是进度，由进度契约管，见 P1）。
- reviewer 产出 doc-drift 清单，写入 `review-verdict.json` 的新字段 `doc_drift`（字符串数组，每条形如 `"<section>: <失真描述>"`；无漂移则为 `[]`）。
- 检测全自动；**修复必须经用户过目**——在 finishing 的「文档收尾」步骤生成同步 patch，列给用户，用户可一键全部接受 / 跳过 / 逐条挑。绝不默默改 `CLAUDE.md`（它是注入 agent context 的指令文件）。

### R3 — finish menu 重构

- finishing 入口先做**项目类型检测**（见 A6），归为两类之一：`local`（无 remote）/ `remote`（有 remote）。
- 按类型从**偏好文件**（见 A5）取「推荐收尾链」；偏好文件无对应条目则用内置默认链：
  - `local`：commit → 合并 main → 删 worktree
  - `remote`：commit → 合并 main → push → 删 worktree
- 新菜单（取代当前固定 6 项）：
  1. 执行推荐收尾（一键到底，链式执行，不再逐环 yes/no）
  2. 继续修改（进 modify 子流程）
  3. 丢弃此次工作
  4. 先不处理（escape hatch — worktree 留着，稍后 `/ohaze:ship-finish`）
  5. 自定义收尾方案
- 菜单展示时先打印检测到的项目类型 + 推荐链全文，让用户看清「选 1 会发生什么」。
- 用户每次的选择（选 1 接受推荐 / 选 5 自定义）回写偏好文件对应类型条目。

### R6 — 保留 worktree 降级

- 当前 Option 4「保持现状」从菜单平级选项降级为新菜单的「4. 先不处理」escape hatch（措辞不显眼、不作推荐）。
- worktree 保留**能力本身保留** — modify 子流程 5c「我自己改」仍依赖 worktree 存在 + handoff 文件保留。

### R7 — 继续修改（确认不动）

- Option「继续修改」modify 子流程（5a Codex 续跑 / 5b Claude 直接改 / 5c 我自己改）现状已满足需求。
- 本期唯一相关改动：5a 的 `codex exec resume --last` 随 R1 一并改为 `resume <codex_session_id>`。modify 流程逻辑本身不动。
- modify 子流程结束后仍 loop back 回新 finish menu（现状已如此）。

### R8 — resume 边界文档化

- 在 `codex-executor/SKILL.md` 写明 resume 边界规则，并在项目 `CLAUDE.md` 的「设计决策」加一条摘要：
  - `resume` 仅用于**同一个 ship 生命周期内**（review retry / modify）。
  - ship 走完 finishing 后出现的 bug = **新的 fix ship**（新 worktree / 新 plan / 新 codex session），**不** resume 旧 session。
  - 原功能的 plan / vault decisions / 相关 commit 作为**显式参考材料**喂给新 ship 的 prompt，而非依赖 codex 的 session memory 续上下文。

## 架构决策

### A1 — 新建 `ohaze:finishing` skill（解决 P3）

当前 finishing 菜单逻辑在 `ship-review.md` 和 `ship-finish.md` 各有一份近乎重复的拷贝。重构若只改一处立即制造新漂移。

**决策**：把整个 Phase 7 finishing 逻辑（项目类型检测、菜单、推荐链执行、文档收尾、modify 子流程入口、ship-result.json 写入与 worktree 清理）抽成一个新 skill `ohaze:finishing`。`ship-review.md` 和 `ship-finish.md` 都改为 invoke 这个 skill，各自只保留进入 finishing 之前的差异化前置逻辑。

理由：`codex-executor` 已经很大（dispatch + review + retry + modify），不宜再塞 finishing；finishing 是一个边界清晰的独立单元，单独成 skill 符合「小而自洽」。

### A2 — 统一「文档收尾」步骤（解决 P1）

文档漂移修（R2）与进度可机读契约（CHANGELOG `[Unreleased]` + manifest `version` + `CLAUDE.md`「当前目标」打勾）都要改 `CLAUDE.md`，必须合并为单一步骤，否则两套逻辑各写各的会冲突。

**决策**：`ohaze:finishing` 中设一个「文档收尾」步骤，**位于推荐收尾链的 commit 步骤之前**，统一处理：

1. **进度契约**：CHANGELOG 追加 `[Unreleased]` 条目、bump manifest `version`、勾选 `CLAUDE.md`「当前目标」对应 `linked_todo`。
2. **漂移修复**：读 `review-verdict.json` 的 `doc_drift`，生成 `CLAUDE.md` 描述性 section 的同步 patch。
3. 两类改动合并成一份 patch 预览呈现给用户；用户确认后应用。
4. 文档改动由收尾链的 commit 步骤提交为一个独立的 `docs:` commit（代码改动已在 review 前由 codex-executor Phase 5.0 提交，故此处只提交文档收尾产生的改动）。

「文档收尾」在收尾链中是可跳过的：无漂移且无进度契约改动时静默跳过。

### A3 — 收尾链步骤化执行 + 失败即停（解决 P2）

**决策**：推荐收尾链定义为一个**有序步骤列表**，每步是一个独立的、有明确成功判据的操作（文档收尾 / commit / merge / push / 删 worktree）。执行契约：

- 严格按顺序逐步执行，每步执行后检查成功判据（git 命令退出码 / 预期状态）。
- **任一步失败立即中止**，不执行后续步骤，把失败步骤 + 错误原文报给用户，交还菜单。
- 特别地：`merge` 成功但 `push` 失败时，**严禁**继续执行「删 worktree」——worktree 和分支必须保留以便用户重试 push。
- 失败中止后，`current-ship.json` 状态保持可恢复，用户可修复后重新进 finishing。

### A4 — vault hook 时序保持（P4）

`ohaze:finishing` 重构后必须保持现有 vault-adapter 时序契约不变：

- 用 **Write 工具**（非 bash heredoc）写 `<worktree>/.ohaze/ship-result.json` —— 触发 `PostToolUse(Write)` → vault-adapter E5 finish。
- 顺序严格为：**Write ship-result.json → rm current-ship.json（handoff）→ 删 worktree**。
- 删 worktree 是破坏性操作，必须最后；vault E5 运行时需要 worktree 与 handoff 都在场。

### A5 — 偏好文件

- 路径：`~/.ohaze/finish-prefs.json`（全局，跨项目共享 haze 的收尾习惯）。
- 结构：
  ```json
  {
    "local":  ["doc-finish", "commit", "merge", "remove-worktree"],
    "remote": ["doc-finish", "commit", "merge", "push", "remove-worktree"]
  }
  ```
- 文件不存在 / 对应类型条目缺失 → 用内置默认链（同上结构）。
- 用户在菜单选 1（接受推荐）或选 5（自定义）后，把最终执行的链回写对应类型条目。
- 读写均 best-effort：偏好文件损坏不阻塞 finishing，降级到内置默认并提示。

### A6 — 项目类型检测

在 `ohaze:finishing` 入口执行，基于**主仓**（非 worktree）：

- `git remote` 为空 → `local`
- `git remote` 非空 → `remote`

检测结果同时写入 `current-ship.json`（字段 `project_type`），供 `/ohaze:status` 等复用。

（线上部署项目的进一步细分留待下一次改造，本期不检测部署配置。）

### A7 — 自定义收尾方案（基础版）

本期不做自由文本解析。选「5. 自定义收尾方案」时，给用户一组**收尾动作积木**（`doc-finish` / `commit` / `merge` / `push` / `pr` / `remove-worktree` / `keep-worktree`）让其按序勾选组合成一条链，然后按 A3 的步骤化执行契约跑。组合结果回写偏好文件。

## 组件与数据流

```
ship.md Phase 4
  └─ 派发 codex exec → 捕获 codex_session_id
  └─ Write current-ship.json { ..., codex_session_id, project_type }

codex-executor (Phase 5 review)
  └─ reviewer prompt 含 DOC-DRIFT advisory PART
  └─ Write review-verdict.json { iteration, verdict, issues, doc_drift }
  └─ retry / modify-5a 用 codex exec resume <codex_session_id>

ship-review.md ─┐
                ├─→ invoke ohaze:finishing
ship-finish.md ─┘
                     │
ohaze:finishing
  ├─ A6 项目类型检测 → project_type (local / remote)
  ├─ A5 读 ~/.ohaze/finish-prefs.json → 推荐链
  ├─ 展示新菜单（1 推荐 / 2 改 / 3 弃 / 4 不处理 / 5 自定义）
  ├─ 选 1 或 5 → 链式执行（A3 失败即停）：
  │     doc-finish(A2) → commit → merge → push → remove-worktree
  ├─ A4 时序：Write ship-result.json → rm handoff → 删 worktree
  └─ 回写偏好文件
```

## 涉及文件清单

| 文件 | 改动 |
|---|---|
| `plugins/ohaze/commands/ship.md` | Phase 4 加 codex_session_id 捕获；handoff 加 `codex_session_id` / `project_type` 字段 |
| `plugins/ohaze/skills/codex-executor/SKILL.md` | reviewer prompt 加 DOC-DRIFT PART；retry/modify resume 改用 session id；review-verdict.json 加 `doc_drift`；写入 R8 resume 边界说明 |
| `plugins/ohaze/commands/ship-review.md` | 移除内联 finishing 菜单，改为 invoke `ohaze:finishing` |
| `plugins/ohaze/commands/ship-finish.md` | 移除内联 finishing 菜单，改为 invoke `ohaze:finishing` |
| `plugins/ohaze/skills/finishing/SKILL.md` | **新建** — Phase 7 finishing 全部逻辑（A1–A7） |
| `plugins/ohaze/CLAUDE.md` | 「设计决策」加 R8 resume 边界摘要 + finishing 新形态描述；同步关键文件表 |
| `CHANGELOG.md` | 新增 `[1.9.0]` 条目 |
| `plugins/ohaze/.claude-plugin/plugin.json` | `version` → `1.9.0` |

## 验收标准

ohaze 是 Markdown skills/commands 插件，无构建、无单元测试框架。验收以**文件内容检查 + 一次真实 dogfood ship** 为准：

1. `grep -r "resume --last" plugins/ohaze/` 在 retry/modify 路径无残留（兜底分支除外，且兜底有显著告警）。
2. `current-ship.json` 样例 / 文档含 `codex_session_id`、`project_type` 字段；`review-verdict.json` 含 `doc_drift` 字段。
3. `ohaze:finishing/SKILL.md` 存在；`ship-review.md` 与 `ship-finish.md` 均不再含内联 finishing 菜单文本，改为 invoke 语句。
4. `ohaze:finishing` 内含：A6 类型检测、A5 偏好文件读写、新 5 项菜单、A3 失败即停契约、A2 文档收尾步骤、A4 时序说明。
5. codex-executor reviewer prompt 含 `DOC-DRIFT` PART，且明确「不进 PASS/FAIL gate」。
6. `CLAUDE.md` 设计决策含 R8 resume 边界条目。
7. 三处版本号（CHANGELOG / plugin.json / CLAUDE.md 当前版本）一致为 `1.9.0`。
8. dogfood：本次改造自身走完 `/ohaze:ship` → `/ohaze:ship-review` → 新 finish menu，能正确识别 ohaze 为 `remote` 类型并给出 `commit→merge→push→删worktree` 推荐链。

## 版本与发布

- 类型：feature 级（新增能力 + 行为变更），SemVer bump MINOR → **1.9.0**。
- CHANGELOG `[1.9.0]` 主题一句话：「finish menu 项目类型化 + 文档漂移自动检测 + Codex session 精确 resume」。
- 同步 CHANGELOG / plugin.json / CLAUDE.md 三处版本字段（进度可机读契约）。
