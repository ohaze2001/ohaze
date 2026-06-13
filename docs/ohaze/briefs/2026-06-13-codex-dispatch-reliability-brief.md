# codex-dispatch-reliability — Feature Brief
> 给 haze 看。spec 在 docs/ohaze/specs/... 给 Codex 看,你不用看。

## 这是干嘛的
让 /ohaze:ship 流程内所有 codex CLI 调用点不再偶发卡死：顶层 codex exec 调用直接消除 stdin redirect silent crash 风险；resume 路径加自动 detect + retry 兜底；同时澄清 dispatch mode 规约术语防止 main agent 把「background」误读成「harness 层也不能用」走前台 sync。

## 给谁用
haze 自己（跑 /ohaze:ship 修任何项目的人），尤其会跑 spec audit / Codex 实施 / review retry 的场景。

## 用户场景 (Scenarios)

### Scenario 1: spec audit 不再卡 30 分钟（happy path）
- Given /ohaze:ship 进 Phase 1.6 codex audit spec 阶段
- When codex 进程启动
- Then 任务在 Bash 层 background 跑、main agent 能读到 thread.started event 持续输出、不撞 silent crash 卡死

### Scenario 2: Phase 4 Codex 实施 dispatch 不撞 silent crash（happy path）
- Given /ohaze:ship Phase 4 把 plan 派发给 codex
- When codex exec 启动
- Then 不再撞 stdin redirect silent crash，main agent 能正常 detect codex 跑起来

### Scenario 3: resume 路径偶发撞 crash 能自动 detect + retry（边界 / 失败恢复）
- Given codex review fail，main agent 进 Phase 6 retry 用 codex exec resume（resume 不支持 prompt-as-arg，只能 stdin redirect 没法根治）
- When dispatch 偶发撞 silent crash
- Then main agent 30s 内 detect 到无 thread.started event → kill + retry 1 次 → 仍失败才 surface 给 haze，不再卡 30 分钟

### Scenario 4: dispatch mode 行为一致（防退化）
- Given Phase 1.6 spec-to-codex-review 任意一次启动
- When main agent 读 SKILL 决定怎么调 codex
- Then 永远走 Bash(run_in_background:true)，不偶尔走前台 sync Bash 撞 crash 卡死 main agent 10 分钟

### Scenario 5: 6th-option + modify 2a 前台撞 crash 时用户能自救（人工兜底）
- Given finishing menu 第 6 项 / 修改 2a 触发前台 codex resume + tee（架构必须前台）
- When 偶发撞 silent crash 卡住主线程
- Then SKILL 文档明确教用户 ctrl-c 杀掉、回到 menu 重选同一选项；不引入复杂自动 retry wrapper

## "完成的样子" Checklist
- [ ] 顶层 codex exec 调用点（Phase 1.6 + Phase 4 initial dispatch）不再撞 stdin silent crash
- [ ] Phase 6 retry（background resume）撞 crash 能自动 detect + kill-retry 1 次，最多 surface 1 次失败给 haze
- [ ] 6th-option + modify 2a（前台 resume）撞 crash 时 SKILL NOTE 教用户 ctrl-c 救场
- [ ] Phase 1.6 dispatch mode 行为一致永远 Bash(run_in_background:true)，不再走前台 sync
- [ ] SKILL 规约术语清晰：禁止 nohup/OS-level detach + ScheduleWakeup 模式，要求 Bash(run_in_background) + main thread polls 模式
- [ ] dogfood 验证：本次 ship 自己跑 Phase 1.6 spec audit 不撞 crash 不走前台

## 不做什么 (Out of Scope)
- 修 codex CLI 自身（OpenAI 的事，0.137 内部 bug 等 0.138+ 解决）
- 升级 codex 到 0.138+（独立工作，需评估 breaking change，独立 ship）
- 监控 / 告警 / 自动通知机制（不在 ship 流程修复范围）
- 全 plugin 重写 codex dispatch 调用约定（只外科改受影响调用点 + 规约文字）
- 6th-option / modify 2a 自动 retry wrapper（haze 拍板选 C 纯文档兜底）

## Scope 决策
- **模式**: Selective Expansion
- **理由**: Bug 2 + Bug 3 同主题（codex dispatch 可靠性），3 个调用点（Phase 1.6 + Phase 4 + Phase 6 resume）打包一次修；6th-option + modify 2a 用文档兜底；不附带 codex 升级 / 监控等扩展工作

## Claude 替你决定的关键技术方向 (Phase 1.5 后回填,事后扫一眼)
- 顶层 codex exec 调用（Phase 1.6 + Phase 4 initial dispatch）改 `codex exec ... "$(cat <prompt>)" < /dev/null`：prompt 作为 CLI 参数 + 显式关 stdin。理由：实测稳定（wiki-drafts-archive ship 第 4 次切到此方案后稳跑）
- Phase 6 retry（codex exec resume）保留 stdin redirect（resume 不接受 PROMPT arg），加 dispatch liveness check：dispatch 后 30s 内 `BashOutput(codex_bg_id) filter='thread.started'` 没看到 event = 视为 silent crash → kill bg task → retry 1 次 → 仍失败 surface verbatim
- 6th-option + modify 2a（前台 resume + tee）保持当前架构（finishing skill 必须前台保持 alive 跨 mini-loop），SKILL 加 NOTE 段教用户撞 crash 时 ctrl-c 救场重跑 menu option
- spec-to-codex-review SKILL:49 「Do NOT run in background」改写为术语澄清版本：明确「Do NOT use nohup / OS-level process detachment / ScheduleWakeup pattern; DO use Bash(run_in_background: true) so silent-crash scenarios don't block the main thread」，消除「background」词语歧义
- codex-executor SKILL 顶层加术语 anchor 段（harness background vs OS-level background vs foreground sync 三类明确）让其他 SKILL refer，不再各自重复
- ROADMAP Bug 段移除已修 Bug 2 + Bug 3 条目；CHANGELOG [Unreleased] Fixed 段新增 codex-dispatch-reliability 条目
