---
description: End-to-end feature shipping. Brainstorm → plan → Codex execute → (later /ohaze:ship-review for review + finishing).
argument-hint: "[feature description]"
allowed-tools: Bash, Read, Write, Edit, Skill, Agent, AskUserQuestion
---

Orchestrate the ohaze workflow for the user's request. Treat the user's argument as the feature description:

`$ARGUMENTS`

If `$ARGUMENTS` is empty, ask the user what they want to ship before proceeding.

## Pre-flight

1. Verify both required plugins are present:
   ```bash
   ls ~/.claude/plugins/marketplaces/openai-codex/plugins/codex/.claude-plugin/plugin.json
   ls ~/.claude/plugins/cache/claude-plugins-official/superpowers/*/skills/brainstorming/SKILL.md
   ```
   If either is missing, stop and tell the user to install:
   - `/plugin install superpowers@claude-plugins-official`
   - `/plugin install codex@openai-codex`

2. Detect current project: `pwd` and `git rev-parse --show-toplevel`. Confirm with user this is the project they want to ship in.

## Vault Context (pre-brainstorm read)

Before brainstorming, silently load vault context to inform the session. Do NOT summarize this to the user unless it reveals a blocker.

```bash
PROJECT_NAME=$(basename $(git rev-parse --show-toplevel))
VAULT="$HOME/Brain"
PROJ_DIR="${VAULT}/20_Projects/${PROJECT_NAME}"
```

3. Read vault project state (best-effort — skip silently if files don't exist):
   - `${PROJ_DIR}/README.md` — current stage / next / blockers
   - `${VAULT}/99_System/Logs/decision-patterns.md` — user's implicit preferences
   - The 3 most recent files in `${PROJ_DIR}/decisions/` — past feature decisions

3a. **Cross-project related reads (the knowledge graph edges)**:

   Parse the `related` field from the current project's README.md frontmatter:
   ```bash
   # frontmatter has: related: [proj1, proj2]  or  related: []
   RELATED=$(awk '/^---$/{f++;next} f==1 && /^related:/{
     sub(/^related: *\[/,""); sub(/\] *$/,""); gsub(/,/," "); gsub(/"/,"");
     print; exit
   }' "${PROJ_DIR}/README.md" 2>/dev/null)
   ```

   For each name in `${RELATED}`, read `${VAULT}/20_Projects/${name}/README.md` (best-effort). Cap at 5 related projects to avoid context bloat; if there are more, take the first 5.

   Use these related READMEs to:
   - Check for shared contracts / public APIs that the ship target might break
   - Detect duplicate-effort risk (a related project already solved this — propose reuse)
   - Surface coupling concerns the user might have forgotten

   In brainstorming, flag any of these explicitly if relevant:
   > "注意: related 项目 `<name>` 的 stage 是 `<stage>`, next 是 `<next>` — 这次改动会影响它吗?"

   If `related: []` (empty) or field missing, skip silently. Don't fabricate edges.

   Combined use of all context above:
   - Anchor brainstorming around the project's actual current state (not just the user's prompt)
   - Avoid proposing approaches that conflict with `decision-patterns.md`
   - Notice if the requested feature overlaps with a recent decision
   - Catch cross-project break risks before they ship

## Phase 1 — Brainstorm (superpowers)

3. Invoke the `superpowers:brainstorming` skill.
   - It will lead the user through clarifying questions, design proposals, and write a spec to `docs/superpowers/specs/<date>-<topic>-design.md`.
   - DO NOT bypass any user-approval gates inside brainstorming.
   - Wait until the spec is committed and the user explicitly approves it.
   - **CRITICAL — Override brainstorming's terminal state:** brainstorming's last instruction says "invoke writing-plans skill" as the next step. DO NOT do that yet. Phase 2 (worktree) MUST run before writing-plans, otherwise Codex will write code on the wrong branch. After brainstorming finishes its spec self-review and the user approves the spec, proceed to Phase 2 explicitly.

## Phase 2 — Worktree (superpowers) — DO NOT SKIP

4. Invoke the `superpowers:using-git-worktrees` skill.
   - This step is **mandatory** even though brainstorming may have implied "go straight to writing-plans". Without this step the implementation lands on whatever branch the user happened to be on (often `main`), defeating the isolation guarantee.
   - Branch name: derive from the spec filename (e.g. spec `2026-05-08-login-page-design.md` → branch `feat/login-page`).
   - Capture the worktree path and base branch (typically `main`); these are needed in Phase 4 and Phase 5.
   - After the worktree is created and the clean test baseline passes, **`cd` into the worktree** before invoking writing-plans, so the plan and all subsequent work happens inside the isolated worktree.

## Phase 3 — Plan (ohaze)

5. Invoke the `ohaze:writing-plans` skill.
   - It saves a **guidance plan** (behavior contracts + acceptance criteria, no prescriptive code bodies) to `docs/superpowers/plans/<date>-<feature>.md`.
   - Capture the absolute plan file path.
   - The skill already presents an ohaze-specific 'go' prompt at the end — no need to override anything.
   - When the user replies 'go', proceed directly to Phase 4. Do NOT invoke `superpowers:subagent-driven-development` or `superpowers:executing-plans` — those execution models are explicitly out of the ohaze workflow.
   - **Why not `superpowers:writing-plans`?** Upstream writing-plans produces fully-prescriptive plans (complete function bodies in every step), which reduces Codex to a typist. `ohaze:writing-plans` is a contract-form fork that preserves the architectural rigor (Scope Check, File Structure, TDD rhythm, Self-Review) but leaves implementation autonomy to Codex.

## Phase 4 — Hand off to Codex (ohaze)

6. Invoke the `ohaze:plan-to-codex-prompt` skill with:
   - `plan_path`: the path captured in step 5
   - `project_test_command`: detect from project files (`package.json` → `npm test`, `Cargo.toml` → `cargo test`, `pyproject.toml` → `pytest`, etc.). If unclear, ask user.

   The skill returns a single XML prompt string. Capture it.

7. Invoke the `ohaze:codex-executor` skill with:
   - `codex_prompt`: the XML from step 6
   - `plan_path`: same as step 5
   - `base_ref`: base branch from step 4 (typically `main`)
   - `mode`: `--background` (V1 default)

   The skill dispatches `codex exec --sandbox danger-full-access` in the background (via Claude Code's `Bash(run_in_background)`) and records `codex_pid_file` / `codex_log_file` paths in the handoff.

## Stop here

The skill ends `/ohaze:ship` after Phase 4. Codex runs in the background. Tell the user:

> "Phase 1-4 完成. Codex 在后台执行 plan (job_id=`<id>`, sandbox=danger-full-access). 下一步:
> - `tail -f <codex_log_file>` — 实时看 Codex 输出
> - `ps -p $(cat <codex_pid_file>)` — 看进程是否还在
> - `/ohaze:ship-review` — 跑完后触发审查 + finishing"

DO NOT auto-poll. DO NOT trigger Phase 5 in this same `/ohaze:ship` invocation. The user invokes `/ohaze:ship-review` when they're ready.

## Persisting context for /ohaze:ship-review

To make `/ohaze:ship-review` self-sufficient (it runs in a possibly-different session), write a small handoff file at the end of Phase 4.

### Step A — Link to a CLAUDE.md todo (precision auto-tick)

Before writing the handoff, ask the user which `- [ ]` in the source project's CLAUDE.md (if any) this ship corresponds to. When the ship completes, vault-adapter will tick exactly that line — no fuzzy matching.

1. Locate the **source project** CLAUDE.md (the main repo, not the worktree). From the worktree path strip `/.worktrees/<name>`:
   ```bash
   SOURCE_ROOT=$(echo "$worktree_path" | sed 's|/.worktrees/.*||')
   PENDING=$(grep -nE '^- \[ \] ' "${SOURCE_ROOT}/CLAUDE.md" 2>/dev/null || true)
   ```

2. If `$PENDING` is empty, set `linked_todo: null` and proceed to Step B. Don't bother asking.

3. Otherwise use `AskUserQuestion` with options = each pending todo text (strip the `- [ ] ` prefix; keep the rest verbatim including any leading marks like `☆`) + a final option **"无对应 todo (跳过)"**. Question header: *"这次 ship 对应 CLAUDE.md 哪条 todo?"*.

4. Capture the user's choice as `linked_todo`:
   - If they picked a real todo: store the **exact text without the `- [ ] ` prefix** (so adapter can do `sed s/- \[ \] <exact text>/- [x] <exact text>/`).
   - If they picked "无对应 todo (跳过)": store JSON `null`.

### Step B — Write the handoff file

**IMPORTANT — order of operations** (the `Write` tool does NOT create parent directories, so the dir MUST exist first):

1. Run `mkdir -p .ohaze` via Bash (relative to the worktree path).
2. Verify the dir exists with `ls -d .ohaze`.
3. THEN use the `Write` tool to create `.ohaze/current-ship.json`.

**Must be `Write` tool, not `cat > heredoc`**: vault-adapter's `hooks.json` only fires `PostToolUse` on the `Write` tool. A `Bash` heredoc bypasses E1 entirely — vault never records ship start, and the whole lifecycle chain degrades to silent failure.

If you skip step 1, the first `Write` attempt will fail with "Error writing file", forcing a retry. Don't make that mistake — always `mkdir -p` first.

Handoff file shape:
```json
{
  "plan_path": "<absolute path>",
  "base_ref": "<branch>",
  "worktree_path": "<absolute path>",
  "spec_path": "<absolute path>",
  "started_at": "<ISO timestamp>",
  "retries": 0,
  "codex_job_id": "<ohaze-<unix_ts>-<pid> generated in codex-executor Phase 4>",
  "codex_run_id": "<same as codex_job_id (vault-adapter back-compat)>",
  "codex_pid_file": "<worktree>/.ohaze/codex-<job_id>.pid",
  "codex_log_file": "<worktree>/.ohaze/codex-<job_id>.log",
  "state": "running",
  "linked_todo": "<exact todo text from Step A, or null>"
}
```

`.ohaze/` should be added to `.gitignore` (do this once via the worktree skill or here if missing).

## Failure modes

- User aborts during brainstorming or plan review: stop cleanly, leave the worktree in place, do not dispatch Codex.
- `superpowers:writing-plans` returns no usable plan path: stop and ask user.
- `ohaze:codex-executor` fails to dispatch (Codex unauthenticated, etc.): stop and surface the error.

## Notes

- This command does NOT call `superpowers:subagent-driven-development` or `superpowers:executing-plans`. Those are replaced by `ohaze:codex-executor` for the execution stage.
- This command does NOT call `superpowers:finishing-a-development-branch`. That happens in `/ohaze:ship-review` after the review loop.
