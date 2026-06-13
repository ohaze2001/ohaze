# codex-dispatch-reliability — Implementation Spec
> 给 Codex 看。brief 在 .ohaze/brief-draft.md（Phase 2 后挪到 docs/ohaze/briefs/2026-06-13-codex-dispatch-reliability-brief.md）给 haze 看。

## Context & Goal

ohaze plugin 内 5 个 codex CLI 调用点偶发卡死，根因有二：

- **Bug 2（codex 0.137 内部 bug）**：`codex exec [resume <tid>] --json < <prompt_file>` 当 stdin 走 regular file redirect 时偶发 silent crash — codex 进程 fork-detach 后立即假死、所有 `--json` event 永不到来、强 kill zsh wrapper 才解锁。2026-06-12 wiki-drafts-archive ship 一次撞 4 次（spec review iter 2 连挂 3 次每次 30+ 分钟 + Phase 4 dispatch 1 次）。实测 mitigation：把 prompt 作为 CLI 参数传 + 显式 `< /dev/null` 关掉 stdin（顶层 codex 适用，resume 不接受 PROMPT 参数所以不适用）
- **Bug 3（ohaze SKILL 规约 bug）**：`spec-to-codex-review/SKILL.md:49` 写「Do NOT run in background. Phase 1.6 is synchronous」字面规约 vs 实战观察「`Bash(run_in_background: true)` 才稳定」相矛盾 → main agent 行为分裂：大多数走 background，偶尔走前台 sync 撞 stdin crash 时卡死主线程 10 分钟。haze 澄清：line 49 原意是禁止 v1 时代 `nohup codex exec ... &` + ScheduleWakeup 的 OS-level detach 模式，**不是**禁止 `Bash(run_in_background: true)`（harness 层 background）；术语「background」多义导致误读

## Code references read in Phase 1.5

### Same-area existing code
- `plugins/ohaze/skills/spec-to-codex-review/SKILL.md:30-49` — Codex Invocation Contract（Phase 1.6 dispatch）
- `plugins/ohaze/skills/codex-executor/SKILL.md:36-103` — Phase 4 initial dispatch + Step 5 报告并放权
- `plugins/ohaze/skills/codex-executor/SKILL.md:355-380` — Phase 6 retry（resume + background）
- `plugins/ohaze/skills/finishing/SKILL.md:140-166` — 6th-option ADVERSARIAL fix mini-loop（前台 + tee）
- `plugins/ohaze/skills/finishing/SKILL.md:395-415` — modify 2a（前台 + tee）

### Caller-callee neighbors
- `plugins/ohaze/commands/ship.md:163-189` — Phase 4 orchestration 调 codex-executor
- `plugins/ohaze/commands/ship-review.md:45-89` — review 模式 re-invoke + Phase 5/6 入口
- `plugins/ohaze/commands/ship-finish.md:89-135` — finishing 模式 re-entry + ADVERSARIAL fix
- `plugins/ohaze/skills/codex-executor/SKILL.md:106-133` — Phase 5.0 报告抽取（区分 background path vs foreground path）

### Related existing spec/plan cross-reference
- `docs/ohaze/specs/2026-06-09-bdd-plan-tdd-do-design.md` — v2.1 总体设计（Phase 1.6 引入、default-go、ADVERSARIAL 处理）
- `docs/ohaze/plans/2026-06-10-bdd-plan-tdd-do.md` — v2.1 实施 plan
- 当前 ROADMAP.md `## Bug` 段：codex stdin redirect silent crash + dispatch mode 不一致条目（本 ship 完成后移除）

### CHANGELOG similar entries and prior decisions
- `CHANGELOG.md [Unreleased] Fixed`：刚 inline 修的「Phase 1 brief approval gate 缺失」（同一组 dogfood 观察衍生）+ 前 commit「brainstorming → ship Phase 2 hand-off 卡死」（同一个 brainstorming SKILL hand-off 语义协议化主题）
- `CHANGELOG.md [2.1.0]` — Phase 3.5 真正可打断窗口 fix（同样涉及 codex dispatch 控制流的精细化）

## Architecture

### 5 调用点 + 当前 dispatch 模式 + 修法 mapping

| # | 调用点 | 文件:行 | 当前 mode | 当前 stdin | 修法 |
|---|---|---|---|---|---|
| 1 | Phase 1.6 spec audit | spec-to-codex-review/SKILL.md:35-49 | 模糊（line 49 字面禁 background，实战大多走 background，偶尔前台 sync） | `< prompt_file` | (A) 改 prompt-as-arg + `< /dev/null` (B) 明确 `Bash(run_in_background: true)` (C) line 49 文字术语澄清 |
| 2 | Phase 4 initial dispatch | codex-executor/SKILL.md:54-61 | Background 明确 | `< prompt_file` | (A) 改 prompt-as-arg + `< /dev/null`（保留 background） |
| 3 | Phase 6 retry | codex-executor/SKILL.md:367-371 | Background 明确 | `< prompt_file`（resume 限制） | (D) 加 dispatch liveness check + kill-retry 1 次 |
| 4 | 6th-option mini-loop | finishing/SKILL.md:149-154 | **必须前台** + tee（架构约束 line 145） | `< prompt_file` + `| tee <output>` | (E) 加 SKILL NOTE 教用户 ctrl-c 救场 |
| 5 | modify 2a | finishing/SKILL.md:400-413 | **必须前台** + tee（同上） | 同上 | (E) 同上 |

### 关键术语统一（codex-executor SKILL 顶层 anchor）

引入「Dispatch Mode Vocabulary」段，明确三类：

- **harness background**（允许且必须，除非架构约束反例）：`Bash(run_in_background: true)`。Bash 子进程由 harness 管，main agent 跑完仍然拥有任务 id 可以 `BashOutput(<id>)` claim 输出。codex 完成后 harness 自动 re-invoke main agent
- **OS-level background**（禁止）：`nohup codex exec ... &` / `codex exec ... > log 2>&1 &` / `echo $! > pid_file` 等让 codex 脱离当前 session 在 OS 层 detach 的模式。配套需要 `ScheduleWakeup` 回神检查，是 v1 老路径
- **foreground sync**（仅允许特定架构反例：finishing 6th-option + modify 2a）：`Bash(...)` 不设 `run_in_background: true`，main agent 阻塞等 codex 返回。理由仅一个：finishing skill 必须在前台保持 alive 跨 commit / re-review / finish chain 等多步骤 mini-loop，背景 dispatch 会让 skill 在 harness re-invoke 后失去执行权

其他 SKILL 文件用 cross-reference（如「per `codex-executor` Dispatch Mode Vocabulary」）refer 此 anchor，不再各自定义。

## Tasks

### Task 1 — spec-to-codex-review/SKILL.md（Bug 2 + Bug 3 主战场）

**Files:**
- `plugins/ohaze/skills/spec-to-codex-review/SKILL.md`

**Changes:**

1.1 改 Codex Invocation Contract（line 30-49）命令模板：

before:
```bash
cd <work_dir> && codex exec \
  --sandbox danger-full-access \
  --skip-git-repo-check \
  --json \
  < <prompt_file>
```

after:
```bash
cd <work_dir> && codex exec \
  --sandbox danger-full-access \
  --skip-git-repo-check \
  --json \
  "$(cat <prompt_file>)" \
  < /dev/null
```

1.2 改 line 49 「Do NOT run in background」为术语澄清版本：

before:
```
- Do NOT use `nohup`.
- Do NOT run in background. Phase 1.6 is synchronous and should finish in seconds to tens of seconds.
```

after:
```
- Do NOT use `nohup`, OS-level detachment (`&`, `> log 2>&1 &`, `echo $! > pid_file`), or any v1-style ScheduleWakeup pattern. Those let codex escape the session and break harness tracking.
- DO use `Bash(run_in_background: true)` for the dispatch. This is "harness background" (the harness owns the task id; main agent reads output via `BashOutput(<id>)`), not "OS-level background" (which is forbidden above). Going harness-background prevents stdin-redirect silent-crash scenarios from blocking the main thread. See `codex-executor` SKILL "Dispatch Mode Vocabulary" for the full term map.
- Phase 1.6 typically completes in tens of seconds; harness background does not slow it down because main agent polls `BashOutput` directly without scheduling a wakeup.
```

1.3 验证修改后无残留歧义 — grep `background` 在改后的 SKILL.md，每条都明确属于「harness background」「OS-level background」其中之一

1.4 **Background completion protocol（替换原 sync 模型）**：当前 SKILL.md:175-185「Output Validation」段假设 codex sync 返回后立即抽 JSON。改成 background 模式后协议变成：

```
After dispatch (Bash run_in_background:true, capture codex_bg_id):

1. Run dispatch liveness check: BashOutput(codex_bg_id) filter='thread.started' for up to 30s. If no thread.started event arrives within 30s → KillBash, re-dispatch ONCE exactly (same prompt file, same Bash run_in_background:true). Same 30s check on retry. If 2nd retry also dry → write the malformed-JSON-fallback verdict (codex-output-unparseable stub, see SKILL.md:194-211) + surface visible warning + return.

2. Block on codex completion via Claude Code harness primitive TaskOutput(task_id=codex_bg_id, block=true, timeout=300000). **TaskOutput is a Claude Code harness-native blocking-wait primitive (dogfood-verified in this very ship's spec audit iter 2 + iter 3, both used `TaskOutput(task_id, block=true, timeout=300000)` successfully to wait on `Bash(run_in_background: true)` codex tasks until exit; behaviorally equivalent to "main agent yields to harness scheduler, harness wakes the agent in the same conversation once background task exits or timeout elapses").** It is paired with Bash run_in_background:true. The frontmatter allowed-tools for ship.md / ship-review.md / ship-finish.md MUST include TaskOutput (per Task 4.4). This is NOT polling because the agent does not repeatedly check state at intervals — it yields once and the harness wakes it on the actual exit event. If TaskOutput rejects (e.g. unknown task id) or times out before codex exits, fall back to: end the main turn after dispatch + rely on harness re-invoke on codex exit + state gate to resume (same control-flow shape as Phase 4 initial dispatch in codex-executor SKILL.md:99-103). The fallback path requires Phase 1.6 to write a temporary handoff at `<work_dir>/.ohaze/spec-audit-handoff.json` with `state=spec_audit_running, codex_bg_id, brief_path, spec_path` so a harness re-invoke can resume Phase 1.6 verdict extraction; this fallback is **defensive only** because dogfood shows the happy path (TaskOutput block-wait) is reliable.

3. After TaskOutput returns: extract the final JSON verdict via BashOutput(codex_bg_id) filter='"type":"message"' (the same pattern used by codex-executor Phase 5.0 line 114 for "Background path" report extraction). Parse the last message event's text field as JSON.

4. If JSON parses + schema validates: write to <work_dir>/.ohaze/spec-review-verdict.json.

5. If JSON malformed: follow existing "Malformed JSON Fallback" section SKILL.md:187-212 — retry once with stricter reminder using the same background protocol (re-dispatch via Bash run_in_background:true + new 30s liveness check + new TaskOutput block + new BashOutput filter='"type":"message"' extraction). If 2nd parse also malformed, write the stub verdict.

6. Return control to /ohaze:ship Phase 1.6 caller.
```

Rationale: The combination (Bash run_in_background → 30s liveness via BashOutput filter='thread.started' → TaskOutput block-wait → BashOutput filter='"type":"message"' for final verdict) reuses Claude Code harness primitives already used elsewhere in ohaze (Bash run_in_background + BashOutput stream filter is the v2 codex-executor pattern; TaskOutput block-wait is the harness's documented blocking-wait counterpart). No new "tool" is invented; only existing primitives are composed. The 30s liveness is a transport-layer crash detector (see Task 2.6), distinct from completion wait.

**Acceptance:**
- `grep '"$(cat' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` 命中 1+ 次（命令模板用 prompt-as-arg）
- `grep '< /dev/null' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` 命中 1+ 次
- `grep -n 'background' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` 每行可读出明确「harness」或「OS-level」上下文
- `grep -n 'Do NOT run in background' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` 命中 0 次（旧歧义规约已删除）
- `grep 'TaskOutput' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` 命中 1+ 次（completion protocol）
- `grep 'liveness check' plugins/ohaze/skills/spec-to-codex-review/SKILL.md` 命中 1+ 次（dispatch liveness）

### Task 2 — codex-executor/SKILL.md（Phase 4 + Phase 6 + 术语 anchor）

**Files:**
- `plugins/ohaze/skills/codex-executor/SKILL.md`

**Changes:**

2.1 顶层新增「Dispatch Mode Vocabulary」段（建议放在 Phase 4 段之前，line 36 之上）：定义 harness background / OS-level background / foreground sync 三类术语（用「Architecture」段落的定义文字）

2.2 改 Phase 4 Step 2 命令模板（line 54-61）：

before:
```bash
codex exec \
  --sandbox danger-full-access \
  --skip-git-repo-check \
  --cd <worktree_path> \
  --json \
  < <prompt_file>
```

after:
```bash
codex exec \
  --sandbox danger-full-access \
  --skip-git-repo-check \
  --cd <worktree_path> \
  --json \
  "$(cat <prompt_file>)" \
  < /dev/null
```

2.3 Phase 4 Step 2 紧跟 Strict rules（line 63-67）补条 + 新增 Step 2.5 dispatch liveness check:

补 Strict rules（line 63-67）:
```
- **`stdin` MUST be closed explicitly via `< /dev/null`** — codex 0.137 偶发在读 stdin 的「非 tty 非 closed pipe」时死锁/silent crash（regular-file stdin redirect 触发率最高）。Passing prompt as CLI argument + closing stdin eliminates this. Verified in dogfood (wiki-drafts-archive ship, 2026-06-12).
- **Dispatch via `Bash(run_in_background: true)`** — see Dispatch Mode Vocabulary above; "harness background" is the only allowed mode for initial dispatch.
```

新增 Step 2.5 (insert between Step 2 and Step 3 — between line 68 and line 69):

```
### Step 2.5 — Dispatch liveness check (codex 0.137 stdin silent-crash detector)

Right after dispatching the background task, BashOutput(codex_bg_id) filter='thread.started' once for up to 30s (single bounded check). If no thread.started event appears within 30s:

1. This is a codex 0.137 stdin-redirect silent crash (rare; even with prompt-as-arg + < /dev/null mitigation, the residual chance is non-zero on some platforms).
2. KillBash <codex_bg_id> to kill the dead background task.
3. Re-dispatch the SAME command (same prompt file, same Bash run_in_background:true). Capture the new codex_bg_id and update .ohaze/current-ship.json.codex_bg_id per Read-modify-Write protocol.
4. Re-run the 30s liveness check on the retry.
5. If the retry also produces no thread.started within 30s: surface the failure verbatim to the user (`WARNING: codex initial dispatch failed liveness check twice; codex 0.137 stdin crash. Suggest re-running /ohaze:ship.`). Do NOT auto-retry past 1.

The check is transport-layer (proves codex process is alive and reading prompt), not completion (codex implementation may take minutes to hours). thread.started typically arrives within 1-3s of healthy dispatch; 30s is 10x safety margin.

The same liveness logic applies in Phase 6 retry (Step 4 below) and spec-to-codex-review Phase 1.6 (per Task 1.4). Format identical, only context differs.
```

2.4 改 Phase 6 retry 命令模板段（line 365-371）加 dispatch liveness check：

before（含 line 365 「Dispatch via `Bash(run_in_background: true)`」直跟命令）:
```bash
cd <worktree_path> && codex exec resume <thread_id> \
  --json \
  < <worktree_path>/.ohaze/codex-fix-iter<N>.xml
```

after 在命令之后追加：
```
**Dispatch liveness check (silent-crash mitigation)**:

Right after dispatching the background task, poll `BashOutput(codex_bg_id) filter='thread.started'` once per 5s for up to 30s total. If no `thread.started` event appears within 30s:

1. This is a codex 0.137 stdin-redirect silent crash (resume cannot use prompt-as-arg because `codex exec resume` does not accept a PROMPT argument — see flag asymmetry note above).
2. Use `KillBash <codex_bg_id>` to kill the dead background task.
3. Re-dispatch the SAME command exactly once (same thread_id, same prompt file). Capture the new `codex_bg_id` and update `.ohaze/current-ship.json.codex_bg_id` per Read-modify-Write protocol.
4. Re-run the 30s liveness check on the retry.
5. If the retry also produces no `thread.started` within 30s: surface the failure verbatim to the user (`WARNING: codex resume dispatch failed liveness check twice; codex 0.137 stdin crash. Suggest /ohaze:ship-review --more or manual resume.`). Do NOT auto-retry past 1.

Typical codex 0.137 `thread.started` arrives within 1-3s of dispatch when the session is healthy; 30s is 10x safety margin without being unreasonably long.
```

2.5 改 SKILL line 65「No nohup, no trailing &」段术语统一 — cross-reference Dispatch Mode Vocabulary 而非各自定义

2.6 **改全局 no-poll invariant（解决与 Phase 6 liveness check 的逻辑冲突）**：

- 改 SKILL.md:99 — 原文「Don't poll, don't sleep, don't `ScheduleWakeup`. Report to the user and return control to the caller; the main agent's turn ends.」改为：

```
Don't poll asynchronously for completion, don't sleep, don't ScheduleWakeup. The ONLY exception is the bounded 30s dispatch-liveness check immediately after dispatch (Phase 4 initial dispatch + Phase 6 retry dispatch) — that is a transport-level crash detector, not a completion poll, and is scoped to a single 30s window. Report to the user and return control to the caller; the main agent's turn ends. The harness will re-invoke the main agent when the background codex task exits.
```

- 改 SKILL.md:403-404 — 原文「Does NOT poll Codex synchronously. The control-flow pattern is...」改为：

```
- Does NOT poll Codex synchronously for completion. The control-flow pattern for completion is: `Bash(run_in_background)` dispatch → main turn ends → harness re-invokes on codex exit → `/ohaze:ship-review` state gate picks up. The ONLY bounded synchronous poll allowed is the 30s dispatch-liveness check right after dispatch (initial in Phase 4 + each retry in Phase 6 + spec audit in spec-to-codex-review) to detect codex 0.137 stdin silent crash; this is a transport-layer crash detector, not a completion poll.
```

**Acceptance:**
- `grep '"$(cat' plugins/ohaze/skills/codex-executor/SKILL.md` 命中 1+ 次（Phase 4 命令模板）
- `grep '< /dev/null' plugins/ohaze/skills/codex-executor/SKILL.md` 命中 1+ 次
- `grep 'Dispatch Mode Vocabulary' plugins/ohaze/skills/codex-executor/SKILL.md` 命中 1+ 次（顶层 anchor 段存在）
- `grep 'liveness check' plugins/ohaze/skills/codex-executor/SKILL.md` 命中 2+ 次（Phase 6 retry 补丁 + 全局 no-poll invariant 例外说明）
- Phase 6 retry 段含「thread.started」「30s」「KillBash」「retry 1 次」等关键词
- `grep 'transport-layer crash detector\|transport-level crash detector' plugins/ohaze/skills/codex-executor/SKILL.md` 命中 1+ 次（明确 liveness check 是 transport-layer 概念，区分于 completion poll）

### Task 3 — finishing/SKILL.md（6th-option + modify 2a 文档兜底）

**Files:**
- `plugins/ohaze/skills/finishing/SKILL.md`

**Changes:**

3.1 6th-option mini-loop（line 145-154）命令块后追加 NOTE 段：

```
**NOTE — Codex stdin silent crash (codex 0.137 known issue, foreground variant):**

`codex exec resume` does not accept a PROMPT argument, so this dispatch must use stdin redirect. In rare cases codex 0.137 deadlocks on stdin from a regular file and never emits `thread.started`. When this happens in a **foreground** dispatch (this command), main agent blocks indefinitely until the user intervenes.

If the dispatch appears stuck (no output to `<worktree>/.ohaze/codex-adversarial-fix-output.jsonl` after 30 seconds, tail the file with `tail -f` to check):

1. Press `Ctrl-C` to kill the foreground codex process.
2. Return to the finishing menu and re-select the 6th option (it is idempotent — same `<task>` list, same thread_id).
3. Re-dispatch typically succeeds; if it crashes again on retry, surface the issue to the user and consider falling back to manual resume via shell.

This is a user-engaged scenario (menu option) so manual intervention is acceptable; auto-retry wrapper is deliberately out of scope (haze 2026-06-13 decision: option C 纯文档兜底).
```

3.2 modify 2a（line 400-413）命令块后追加 NOTE 段 — 同 3.1 但场景文字改为「修改 spec/plan 后重跑 codex」

3.3 SKILL 「Failure modes」段（line 454 附近）新增条目：

```
- **Foreground codex resume hits stdin silent crash (codex 0.137)**: user sees the Bash command stuck with no `Running… (Xm Ys)` time progressing in a sane way, and the tee output file (`.ohaze/codex-*-output.jsonl`) stays at 0 bytes after 30s. Recovery: Ctrl-C kill, re-trigger the same menu option. See per-section NOTE for details.
```

**Acceptance:**
- `grep 'stdin silent crash' plugins/ohaze/skills/finishing/SKILL.md` 命中 2+ 次（6th-option + modify 2a + Failure modes，可能 3 次）
- `grep 'Ctrl-C' plugins/ohaze/skills/finishing/SKILL.md` 命中 2+ 次
- `grep 'codex 0.137' plugins/ohaze/skills/finishing/SKILL.md` 命中 2+ 次

### Task 4 — ship.md / ship-review.md / ship-finish.md 同步术语 + frontmatter 工具补全 + 全局 grep

**Files:**
- `plugins/ohaze/commands/ship.md`
- `plugins/ohaze/commands/ship-review.md`
- `plugins/ohaze/commands/ship-finish.md`

**Changes:**

4.1 全局 grep `nohup\|ScheduleWakeup\|run_in_background\|background` 在 commands/ + skills/，所有 codex dispatch 相关引用统一术语：
   - 「`Bash(run_in_background: true)`」/「harness background」 表示允许 mode
   - 「nohup」「OS-level detachment」「ScheduleWakeup pattern」 表示禁止 mode
   - 「foreground sync」 仅在 finishing 6th-option + modify 2a 出现（架构反例）

4.2 ship.md Phase 4 段（line 163, 187, 189）已用「`run_in_background`, no nohup, no ScheduleWakeup」标题 + 文字描述，无需大改。补一句 cross-reference codex-executor Dispatch Mode Vocabulary

4.3 ship-review.md / ship-finish.md 现有「v2 control flow = `run_in_background` + harness re-invoke + idempotent state gate」措辞已正确，保留；补 cross-reference 链到 codex-executor anchor

4.4 **Frontmatter allowed-tools 补 KillBash + TaskOutput**（运行时工具授权前置）：当前三个命令的 allowed-tools 都是 `Bash, BashOutput, Read, Write, Edit, Skill, Agent, AskUserQuestion` — 缺 `KillBash`（Phase 6 retry 撞 silent crash 时 kill 用）+ `TaskOutput`（Phase 1.6 spec audit background completion protocol 用 block=true wait）。改三个文件 frontmatter：

```yaml
allowed-tools: Bash, BashOutput, KillBash, TaskOutput, Read, Write, Edit, Skill, Agent, AskUserQuestion
```

涉及文件：
- `plugins/ohaze/commands/ship.md` line 4
- `plugins/ohaze/commands/ship-review.md` line 4
- `plugins/ohaze/commands/ship-finish.md` line 4

**Acceptance:**
- 全局 grep 后无遗漏「ambiguous background」用法（每条引用都可判断属于 harness / OS-level / foreground 三类之一）
- `grep 'Dispatch Mode Vocabulary' plugins/ohaze/` 命中 4+ 次（codex-executor 定义 + spec-to-codex-review/ship.md/ship-review.md/ship-finish.md/finishing cross-ref）
- `grep '^allowed-tools:.*KillBash' plugins/ohaze/commands/ship.md plugins/ohaze/commands/ship-review.md plugins/ohaze/commands/ship-finish.md` 命中 3 次（每个命令 frontmatter 都含 KillBash）
- `grep '^allowed-tools:.*TaskOutput' plugins/ohaze/commands/ship.md plugins/ohaze/commands/ship-review.md plugins/ohaze/commands/ship-finish.md` 命中 3 次

### Task 5 — plan-to-codex-prompt/SKILL.md 同步去 pipe 描述

**Files:**
- `plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md`

**Changes:**

5.1 改 line 8 `description` 段「piped into codex exec」为新模式描述：

```
Translate an `ohaze:writing-plans` output (`docs/superpowers/plans/<date>-<feature>.md`) into a complete XML-block prompt that is passed as the top-level prompt argument to `codex exec` by `ohaze:codex-executor` (the prompt is written to a file for structural safety, then `codex-executor` cats the file content into the CLI argument and closes stdin with `< /dev/null`).
```

5.2 改 line 26 「Output contract」段「ready to be written to a prompt file and piped into codex exec」为：

```
Produce a single string ready to be written to a prompt file. `ohaze:codex-executor` then passes the file content as the top-level `codex exec` prompt argument while closing stdin (`< /dev/null`). The string MUST follow this exact XML block layout, in this order:
```

5.3 改 line 113 「Notes for Claude when assembling the prompt」段「pipes it into codex exec」为：

```
- After producing the prompt string, the caller (typically `ohaze:codex-executor` skill) writes it to `<worktree>/.ohaze/codex-prompt.xml` and passes the file content as the top-level prompt argument to `codex exec --sandbox danger-full-access` running in the background (`Bash(run_in_background: true)`), with stdin redirected to `/dev/null` to avoid codex 0.137 stdin silent crash. See `codex-executor` Phase 4 Step 2 for the exact dispatch command.
```

**Acceptance:**
- `grep -E 'pipe[ds]?\\s+into|pipes?\\s+it\\s+into' plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md` 命中 0 次（所有 "piped/pipes into" 措辞清理完毕）
- `grep -E 'top-level prompt argument|< /dev/null' plugins/ohaze/skills/plan-to-codex-prompt/SKILL.md` 命中 2+ 次（新措辞已落档）

### Task 6 — 文档落档（ROADMAP / CHANGELOG）

**Files:**
- `ROADMAP.md`
- `CHANGELOG.md`

**Changes:**

6.1 ROADMAP `## Bug` 段移除两条已修条目：
   - 原「codex exec --json + stdin redirect 偶发 silent crash」+ 配套「影响的 skill 命令模板」「修法落地」「实战预案文档」子项 → 全部移除（已修）
   - 「spec-to-codex-review Phase 1.6 dispatch mode 行为不一致」→ 移除（已修）

6.2 CHANGELOG `## [Unreleased]` `### Fixed` 段新增条目：

```markdown
- **Codex dispatch reliability hardening（2026-06-13 dogfood ship）**：修两个 codex CLI 调用相关 bug + 重写 dispatch mode 术语规约。Bug 2 = codex 0.137 `codex exec [resume <tid>] --json < <prompt_file>` 偶发 silent crash（wiki-drafts-archive ship 撞 4 次）；Bug 3 = `spec-to-codex-review/SKILL.md:49`「Do NOT run in background」术语多义导致 main agent 偶发走前台 sync 撞 crash 卡死主线程 10 分钟。修法：① 顶层 codex exec (Phase 1.6 + Phase 4 initial dispatch) 改 prompt-as-arg + `< /dev/null` 关 stdin（实测稳定） ② Phase 6 retry (codex exec resume background) 因 resume 不支持 PROMPT arg 保留 stdin redirect + 加 30s dispatch liveness check + kill-retry 1 次 ③ 6th-option + modify 2a (前台 resume + tee) 保持当前架构 + SKILL 加 NOTE 教用户 ctrl-c 救场 ④ `codex-executor/SKILL.md` 顶层新增「Dispatch Mode Vocabulary」段定义 harness background / OS-level background / foreground sync 三类术语 anchor，其他 SKILL cross-reference 而非各自定义 ⑤ `spec-to-codex-review/SKILL.md:49` 旧歧义规约「Do NOT run in background」改写为明确「禁止 nohup/OS detach/ScheduleWakeup；要求 Bash(run_in_background:true)」。
```

**Acceptance:**
- ROADMAP.md `## Bug` 段不再 grep 命中「codex exec --json」「stdin redirect」「dispatch mode 不一致」
- CHANGELOG.md `## [Unreleased] ### Fixed` 段新增 codex-dispatch-reliability 条目

## Out of Scope

- 修 codex CLI 自身（OpenAI 责任，0.137 内部 bug 等 0.138+ 解决）
- 升级 codex 到 0.138+（独立工作，需评估 breaking change，独立 ship）
- 监控 / 告警 / 自动通知机制
- 全 plugin 重写 codex dispatch 调用约定（只外科改 5 个调用点 + 规约文字）
- 6th-option / modify 2a 自动 retry wrapper（haze 2026-06-13 决定选 option C 纯文档兜底）

## Risks

- **R1**: Phase 6 retry 的 30s liveness 阈值可能误杀慢启动 codex（特别是冷启动或大 prompt）。Mitigation: 30s 是 10x 安全余量（典型 thread.started 1-3s），并且只 retry 1 次失败即 surface（不会无限循环）
- **R2**: prompt-as-arg `"$(cat <file>)"` 模式可能撞 shell 引号特殊字符问题（特别是 prompt 含 backtick / `$` / 大量换行）。Mitigation: prompt XML 已通过 Write tool 写到文件，cat 出来再 quote 走 shell 是 wiki-drafts-archive 实测路径，已 dogfood 验证稳定
- **R3**: 全局 grep 验证可能漏识未来新加 SKILL 的 codex dispatch 调用点。Mitigation: codex-executor SKILL 顶层 Dispatch Mode Vocabulary anchor 是中央术语源，未来新 SKILL 写 codex 调用时按惯例 cross-reference 即可

## Open Questions for Phase 1.6 Codex Audit

- 「Dispatch Mode Vocabulary」段是否应该放到 codex-executor SKILL 顶层 vs 拆到独立 reference 文件（如 `plugins/ohaze/skills/codex-executor/references/dispatch-modes.md`）？倾向顶层（不引入额外文件，simplicity）但可在 audit 时讨论
- Phase 6 retry liveness check 用 `BashOutput(codex_bg_id) filter='thread.started'` 是否准确？有更精确的检测方法吗（比如直接 tail BashOutput stream 看首行）？

## Verification (dogfood)

- 本次 ship 进 Phase 1.6 spec audit 时 codex 应走 `Bash(run_in_background: true)` 模式（不是前台 sync）
- 本次 ship Phase 4 codex initial dispatch 应跑 prompt-as-arg + `< /dev/null` 命令模式
- 如果 dogfood 期间撞到 codex stdin crash，本 spec 描述的 mitigation 应该真实生效（liveness check kill + retry）
- 修完 commit + 跑 grep 验证全部 Acceptance 通过

---

## Post-implementation Revert Addendum (2026-06-13)

Cross-source review iter 1（reviewer 异源审查）FAIL 后，haze 拍板 option A — revert 部分 spec 段落。本 addendum 注明 spec 与最终实现的 delta（commit `8d1aa4a`）。

### Reverted 内容

- **Task 1.4 «Background completion protocol»（含 TaskOutput + spec-audit-handoff defensive fallback）整段 revert**：spec 原描述「Phase 1.6 改成 background mode + TaskOutput(block=true) wait + BashOutput filter='message' 抽 verdict + defensive fallback 写 spec-audit-handoff.json」均不再适用。`spec-to-codex-review/SKILL.md` 现 sync return model（命令模板用 prompt-as-arg + `< /dev/null` 已消除 stdin crash 风险，无需 background completion protocol）。
- **Task 4.4 frontmatter `TaskOutput` allowed-tools 不再加入**：原 spec 要求 ship/ship-review/ship-finish 三个 command frontmatter 加 `KillBash, TaskOutput`；最终仅加 `KillBash`（TaskOutput 不引入，理由：跨 session 稳定性未验证 + 当前实现路径无需）。

### Retained 内容（5 项 surgical fix 全保留）

- Task 1.1-1.3：prompt-as-arg + `< /dev/null` + line 49 反转 + Dispatch Mode Vocabulary cross-ref
- Task 2 全部：Dispatch Mode Vocabulary anchor + Phase 4 命令模板 + Phase 4 Step 2.5 + Phase 6 retry liveness + no-poll invariant 例外
- Task 3 全部：finishing 6th-option + modify 2a NOTE
- Task 4.1-4.3：frontmatter 加 KillBash（TaskOutput 不加）+ Phase 4 段 cross-ref
- Task 5 全部：plan-to-codex-prompt 去 pipe 描述
- Task 6 全部：ROADMAP/CHANGELOG 落档

### 新增 dispatch_failed state hygiene（review finding #3 补救）

- `codex-executor/SKILL.md` Phase 4 Step 2.5 + Phase 6 retry：二次失败前 transition `current-ship.json.state=dispatch_failed`（清 codex_bg_id，Phase 4 同清 thread_id，Phase 6 retry 保留 thread_id 供手动 resume）+ 警告文案加 state 信息
- `ship-review.md` / `ship-finish.md` state gate 加 `dispatch_failed` 分支

### Reviewer 元洞察

本 ship 自身是「spec audit 越审越深」元问题（ROADMAP backlog top）的真实数据点：iter 1 codex 找 4 个 IMPORTANT → 我 spec 扩 Background protocol；iter 2 codex 找 TaskOutput 未文档化 → 我加 cite + defensive fallback；iter 3 minimum fix + accept；cross-source reviewer 异源视角揪出 TaskOutput cross-session 稳定性问题 + orphan handoff，scope drift 一目了然。Per haze decision，revert 后 spec scope 与 brief surgical 范围对齐。

依据：`.ohaze/review-verdict.json` iter 1 + iter 2、commit `8d1aa4a`。
