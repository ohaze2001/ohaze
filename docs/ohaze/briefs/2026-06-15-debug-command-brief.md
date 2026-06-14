# /ohaze:debug — Feature Brief

> 给 haze 看。spec 在 .ohaze/spec-draft.md 给 Codex 看,你不用看。

## 这是干嘛的

**bug 修复模式** —— 跟 `/ohaze:ship` 同形状(开 worktree、走 finishing 合并),但把 feature-dev 专属 phase(BDD brief / spec audit)替换成 systematic-debugging 形状(4 阶段根因调研 + 防回归测试)。

> **debug 和 ship 的本质区别 = 应对修复 vs 应对开发**。形状不同,强行套同一个流程 = 让 bug 写"用户场景"、让 spec audit 反审"修复路径"。

## 给谁用

- **haze 显式打**:`/ohaze:debug <症状> [可选猜测原因]`
- **跨命令 reframe 跳转**:`/ohaze:ship`(以及未来的 `auto-ship` / `loop`)在中段发现"这是 bug 不是 feature" → 提示切 debug
- **brainstorm 末兜底**:`/ohaze:ship` 走完 Phase 1 后 brief 形状明显是 bug 修复 → 最后一道防线提示

## 用户场景 (Scenarios)

### Scenario 1:显式入口 + 已知猜测原因(最常见 happy path)
- **Given** haze 遇到一个 bug,自己有猜测的根因
- **When** 打 `/ohaze:debug "<症状>" --cause="<猜测>"`
- **Then** 进入 4 阶段 root cause investigation(root cause → pattern → hypothesis → impl)
- **And** 调研结果与猜测一致 → 自动通过 G1
- **And** hypothesis 形成后 **scope lock** 物理冻结可编辑文件
- **And** 修复 + 防回归测试 + cross-source review + finishing menu 一气呵成(default-go 风格)

### Scenario 2:显式入口 + 只有症状(无猜测)
- **Given** haze 只看到症状,不知道根因
- **When** 打 `/ohaze:debug "<症状>"`(无 `--cause`)
- **Then** G1 inactive(无对照基准),LLM 自定根因 → scope lock → 继续 happy path

### Scenario 3:跨命令 reframe 跳转
- **Given** haze 误打 `/ohaze:ship` 修 bug
- **When** ship 调研/spec/plan 任一 phase 发现"this is fix-shaped not feature-shaped"
- **Then** AskUserQuestion:"看起来是 bug,是否切到 `/ohaze:debug`?"
- **And** haze 接受 → 转 debug 流程;haze 否决 → 继续 ship

### Scenario 4:G1 根因偏离 gate
- **Given** Scenario 1 启动(haze 给了猜测原因)
- **When** 调研结果与猜测不一致
- **Then** AskUserQuestion:接受调研根因 / 重新调研 / 退出

### Scenario 5:G2 3-strike gate
- **Given** 修复阶段连续 3 次假设失败
- **When** 准备第 4 次 retry 前
- **Then** AskUserQuestion:换思路 / 升级 ship / 放弃

### Scenario 6:G3 blast-radius gate
- **Given** 修复触及 > 5 文件
- **When** codex 准备 commit
- **Then** AskUserQuestion:接受宽修 / 缩 scope / 升级 ship

## 「完成的样子」Checklist

- [ ] 启动接收 `<症状>` + 可选 `--cause=<猜测原因>`
- [ ] 4 阶段 systematic 调研(root cause → pattern → hypothesis → implementation)
- [ ] **G1 根因偏离 gate**(条件性,启动给猜测时 active)
- [ ] **G2 3-strike gate**(强制,~20-30% 触发率)
- [ ] **G3 blast-radius gate**(>5 文件阈值,~15-25% 触发率)
- [ ] **Scope lock 全程**:hypothesis 形成后 codex 物理冻结到假设涉及文件
- [ ] 走 worktree + `ohaze:finishing` 同款收尾(commit / merge / PR / push 都继承 ship)
- [ ] cross-source review 继承 ship(general-purpose subagent 异源审)
- [ ] **防回归测试按项目类型适配**:有测试套件 → failing test + 全套件实跑;markdown plugin / 无静态代码 → grep / JSON-load / 结构断言 + dogfood 端到端冒烟;以 `.ohaze/current-ship.json.project_test_command` 为准
- [ ] **调研报告只写进 CHANGELOG `[Unreleased]` Fixed 段**(不另起 `docs/ohaze/debug/` 目录)
- [ ] `/ohaze:ship` Phase 1/2 埋点 reframe 跳转协议(auto-ship / loop 各自 ship 时再加)
- [ ] brainstorm 末兜底提示点埋入 ship Phase 1 末尾

## 不做什么 (Out of Scope)

- **5 分钟能改完的小 bug**:haze 在 Claude Code 或编辑器 inline 修,不打这个命令(这是 debug 的"使用边界",不是 debug 的子档位)
- **新 feature 开发**:走 `/ohaze:ship`
- **大重构 / 架构改动**:走 `/ohaze:ship` 配 spec audit
- **给修复建议但不改代码**:debug 模式必须落地修复(跟 superpowers / gstack 的核心架构差异 —— 它们不管合并,ohaze:debug 管)
- **`/ohaze:auto-ship` 和 `/ohaze:loop` 的 reframe 跳转**:本 ship 不实现(两个命令还未开发,各自 ship 时再加跳转逻辑)

## Scope 决策

- **模式**:**Selective Expansion**
- **理由**:在「修 bug」核心基础上选择性引入 ship 的成熟元素(worktree / cross-source review / finishing 合并),但不照搬 BDD brief 和 spec audit(feature-dev 专属,与 bug 修复形状错位)。同时加入 ship 没有的 systematic-debugging 形状(4 阶段调研 + scope lock + 3 个条件性 gate)。

## Claude 替你决定的关键技术方向 (Phase 1.5 后回填)

- **新命令文件 `commands/debug.md`**: 跟 `ship.md` 平级独立 command,不在 `ship.md` 内加 mode 分支(解耦,符合"档位"概念)
- **新 skill fork `skills/systematic-debugging/`**: 基线 superpowers v5.1.0 + ohaze 改造(加 G1 条件性 gate、scope_lock_files 产出、ohaze 风格中文章节)
- **新 skill `skills/debug-to-codex-prompt/`**: 把 root cause investigation 报告 + 修复方案 + scope lock 文件列表打包成 XML(类似 `plan-to-codex-prompt` 但输入不同)
- **复用现有 skill**: `using-git-worktrees` / `codex-executor` / `finishing` 跟 ship 共用,**不动**
- **`current-ship.json` 加 `ship_mode: "ship" | "debug"` 字段 + `scope_lock_files` 数组字段 + `investigation_path` 字段 + `cause_hypothesis` 字段**: review 阶段读这些分流;v2.2 内仅 ship-review 用到分流(L2 scope_lock 强制断言 + G3 blast-radius)
- **Scope lock 「物理冻结」用 KD6 三层防御实现 (codex 0.137 不提供文件级 sandbox 的最强可行方案)**:L1 = `debug-to-codex-prompt` XML 内 `<editable_files>` 强约束 + escape hatch 协议;L2 = `ship-review.md` 主线程实跑 `git diff --name-only` 对比 `scope_lock_files`,越界 = CRITICAL finding 触发 retry;L3 = G3 blast-radius gate AskUserQuestion 兜底。三层叠加效果接近物理冻结,未来 codex CLI 升级提供文件白名单时升级 L1。
- **ship-review.md 加 L2 + G3 两段**: 都在 Phase 5.0 commit 之前 + `ship_mode=debug` 时触发;L2 写 CRITICAL finding 触发 codex-executor Phase 6 retry,G3 触发 AskUserQuestion 让 haze 决定
- **ship.md reframe 兜底 3 处**(对应 brief Scenario 3 "调研/spec/plan 任一 phase"):Phase 1 brainstorm 终态后 (≥2 of 4 signals)、Phase 1.5 mandatory code-reading 后 (≥2 of 3 signals)、Phase 3 writing-plans 后 (≥2 of 3 signals)
- **「切到 debug」接受路径 = manual restart (KD9)**: brief 中"转 debug 流程"在本期实现为 ship 干净退出 + 提示 haze 重新打 `/ohaze:debug "<symptom>" [--cause=<猜测>]`,不实现 in-process 转换。理由: in-process 跨 command 边界需重写 state 机 + ohaze:brainstorming/writing-plans 协作退出协议,远超本期 surgical scope;manual restart 在 plugin 上下文 cost ≈ 1 命令 + paste symptom,可接受;后续 `/ohaze:auto-ship` 引入"档位预选" 时统一加 in-process 转换
- **Worktree 创建提前到 Pre-flight 之后立即建 (KD10)**: 不同于 ship 流程在 brainstorm/spec/spec-audit 完成后才建 worktree,debug 先建 worktree 再跑 systematic-debugging,确保 investigation 全程在隔离 worktree 内进行,避免污染主仓
- **G2 3-strike 复用 codex-executor Phase 6**: 现有 max-3 retry 机制天然就是 G2,无需新增
- **版本号 2.1.3 → 2.2.0**: MINOR bump(新 command + 新 skill 是新 feature)
