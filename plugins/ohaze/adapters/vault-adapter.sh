#!/usr/bin/env bash
# ohaze vault adapter
# 由 Claude Code hooks 自动调用，将 ohaze 生命周期事件写入 ~/Brain
# 调用形式: vault-adapter.sh on-write | pre-bash
# stdin: Claude Code hook payload (JSON)

set -euo pipefail

EVENT="${1:-}"
VAULT="${HOME}/Brain"
TODAY=$(date +%Y-%m-%d)
NOW=$(date +%Y-%m-%dT%H:%M:%S)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${HOME}/.claude/logs/ohaze-vault-adapter.log"

mkdir -p "$(dirname "$LOG_FILE")"

# ─── logging ─────────────────────────────────────────────────────────

log() {
  echo "[$(date +%H:%M:%S)] [ohaze-vault] $*" >> "$LOG_FILE" 2>&1 || true
}

# ─── JSON helpers ─────────────────────────────────────────────────────

# Parse a top-level key from a JSON string
# Usage: parse_json "$json_str" "key"
parse_json() {
  local json="$1" key="$2"
  python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    v = d.get(sys.argv[2], '')
    if v is None or v == '':
        print('')
    elif isinstance(v, (dict, list)):
        print(json.dumps(v))
    else:
        print(str(v))
except:
    print('')
" "$json" "$key" 2>/dev/null || echo ""
}

# Parse nested key: tool_input.file_path
parse_nested() {
  local json="$1"
  shift
  python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    keys = sys.argv[2:]
    for k in keys:
        d = d.get(k, {}) if isinstance(d, dict) else {}
    print('' if not isinstance(d, (str, int, float)) else str(d))
except:
    print('')
" "$json" "$@" 2>/dev/null || echo ""
}

# ─── vault helpers ────────────────────────────────────────────────────

# 从 worktree_path 提取项目名
# /Users/x/Project/aura-admin-dashboard/.worktrees/feat-xxx → aura-admin-dashboard
project_from_worktree() {
  local wt="$1"
  echo "$wt" | sed 's|/.worktrees/.*||' | xargs basename 2>/dev/null || echo ""
}

# 从 plan_path 提取 feature slug
# .../plans/2026-05-12-bulk-delete.md → 2026-05-12-bulk-delete
feature_from_plan() {
  local p="$1"
  basename "$p" .md 2>/dev/null || echo "unknown-feature"
}

# 确保项目目录存在
ensure_project_dir() {
  local proj="$1"
  local dir="${VAULT}/20_Projects/${proj}"
  mkdir -p "${dir}/discussions" "${dir}/decisions"
  if [[ ! -f "${dir}/progress.md" ]]; then
    cat > "${dir}/progress.md" << EOF
---
type: project
tags: [project, progress]
created: ${TODAY}
updated: ${TODAY}
source: ohaze-adapter
author: ohaze
private: true
status: active
---

# ${proj} 进度
EOF
    log "created progress.md for ${proj}"
  fi
}

# 写一个新 vault 文档（带 frontmatter）
write_doc() {
  local path="$1" type="$2" title="$3" related="$4"
  shift 4
  # remaining args: content lines
  cat > "$path" << EOF
---
type: ${type}
tags: [${type}, ohaze]
created: ${TODAY}
updated: ${TODAY}
source: ohaze
author: ohaze
private: true
status: active
related: ${related}
---

# ${title}

EOF
  for line in "$@"; do
    echo "$line" >> "$path"
  done
}

# append 行到 vault 文件，同时刷新 frontmatter updated
vault_append() {
  local path="$1"
  shift
  printf '%s\n' "$@" >> "$path"
  # 更新 frontmatter updated 字段
  sed -i '' "s/^updated: .*/updated: ${TODAY}/" "$path" 2>/dev/null || true
}

# Brain git commit（如无变更则跳过）
brain_commit() {
  local msg="$1"
  cd "${VAULT}" || return 0
  git add -A 2>/dev/null || return 0
  if ! git diff --cached --quiet 2>/dev/null; then
    git -c user.email=ohaze@local -c user.name=ohaze \
      commit -q -m "[ohaze-adapter] ${msg}" 2>/dev/null || true
    log "brain commit: $msg"
  fi
}

# ─── sync state ───────────────────────────────────────────────────────

# .vault-sync-state 存在 handoff 旁边的 .ohaze/ 目录
read_sync_state() {
  local ohaze_dir="$1"
  local f="${ohaze_dir}/.vault-sync-state.json"
  [[ -f "$f" ]] && cat "$f" || echo "{}"
}

write_sync_state() {
  local ohaze_dir="$1" json="$2"
  echo "$json" > "${ohaze_dir}/.vault-sync-state.json"
}

# ─── on-write dispatcher ──────────────────────────────────────────────
# 触发：LLM 用 Write 工具写 .ohaze/ 下任意文件

handle_on_write() {
  local stdin_json
  stdin_json=$(cat)

  local file_path content
  file_path=$(parse_nested "$stdin_json" tool_input file_path)
  content=$(parse_nested "$stdin_json" tool_input content)
  [[ -z "$content" ]] && return 0

  case "$file_path" in
    *".ohaze/current-ship.json")
      log "on-write: current-ship.json"
      _handle_shipjson "$file_path" "$content"
      ;;
    *".ohaze/review-verdict.json")
      log "on-write: review-verdict.json"
      _handle_verdict "$file_path" "$content"
      ;;
    *".ohaze/ship-result.json")
      log "on-write: ship-result.json"
      _handle_result "$file_path" "$content"
      ;;
    *)
      return 0
      ;;
  esac
}

# ─── E1-E_pause: current-ship.json handler ────────────────────────────

_handle_shipjson() {
  local file_path="$1" content="$2"

  local worktree_path plan_path spec_path state retries codex_run_id started_at
  worktree_path=$(parse_json "$content" worktree_path)
  plan_path=$(parse_json "$content" plan_path)
  spec_path=$(parse_json "$content" spec_path)
  state=$(parse_json "$content" state)
  retries=$(parse_json "$content" retries)
  codex_run_id=$(parse_json "$content" codex_run_id)
  started_at=$(parse_json "$content" started_at)

  [[ -z "$worktree_path" ]] && { log "no worktree_path, skip"; return 0; }

  local proj feature ohaze_dir
  proj=$(project_from_worktree "$worktree_path")
  feature=$(feature_from_plan "$plan_path")
  ohaze_dir=$(dirname "$file_path")

  [[ -z "$proj" || -z "$feature" ]] && { log "cannot determine proj/feature, skip"; return 0; }
  log "proj=${proj} feature=${feature} state=${state} retries=${retries}"

  ensure_project_dir "$proj"

  # 读 sync state
  local sync_json discussions_path prev_codex_id prev_retries prev_state
  sync_json=$(read_sync_state "$ohaze_dir")
  discussions_path=$(parse_json "$sync_json" discussions_path)
  prev_codex_id=$(parse_json "$sync_json" codex_run_id)
  prev_retries=$(parse_json "$sync_json" retries)
  prev_state=$(parse_json "$sync_json" prev_state)

  local vault_changed=false

  # ── E1: 首次写入 → 建 discussions 文档 ──────────────────────────────
  if [[ -z "$discussions_path" ]]; then
    discussions_path="${VAULT}/20_Projects/${proj}/discussions/${feature}.md"
    local decisions_ref="[[20_Projects/${proj}/decisions/${feature}]]"
    write_doc "$discussions_path" "discussion" \
      "${proj}: ${feature}" \
      "$decisions_ref" \
      "## 启动" \
      "" \
      "- **项目**: \`${proj}\`" \
      "- **功能**: \`${feature}\`" \
      "- **Spec**: \`${spec_path}\`" \
      "- **Plan**: \`${plan_path}\`" \
      "- **开始时间**: \`${started_at}\`"
    log "E1: created discussions doc: $discussions_path"
    vault_changed=true
  fi

  # ── E2: codex_run_id 首次出现 → 记录派发 ───────────────────────────
  if [[ -n "$codex_run_id" && "$codex_run_id" != "$prev_codex_id" ]]; then
    vault_append "$discussions_path" \
      "" \
      "## Codex 派发" \
      "" \
      "- **时间**: \`${NOW}\`" \
      "- **run_id**: \`${codex_run_id}\`"
    log "E2: appended Codex dispatch"
    vault_changed=true
  fi

  # ── E4: retries 增加 → 审查失败重试 ────────────────────────────────
  local cur_retries="${retries:-0}"
  local old_retries="${prev_retries:-0}"
  if [[ "$cur_retries" -gt "$old_retries" ]] 2>/dev/null; then
    vault_append "$discussions_path" \
      "" \
      "## 审查循环 (retry ${cur_retries})" \
      "" \
      "- **时间**: \`${NOW}\`" \
      "- **状态**: FAIL → Codex 重试"
    log "E4: appended review retry ${cur_retries}"
    vault_changed=true
  fi

  # ── E_pause: state 变为 kept / self-edit-pending ─────────────────
  if [[ "$state" != "$prev_state" ]]; then
    if [[ "$state" == "kept" ]]; then
      vault_append "$discussions_path" \
        "" \
        "## 流程暂停" \
        "" \
        "- **时间**: \`${NOW}\`" \
        "- **原因**: 用户选择保持现状 (option 3)" \
        "- **恢复**: \`/ohaze:ship-finish\`"
      log "E_pause: appended kept state"
      vault_changed=true
    elif [[ "$state" == "self-edit-pending" ]]; then
      vault_append "$discussions_path" \
        "" \
        "## 流程暂停" \
        "" \
        "- **时间**: \`${NOW}\`" \
        "- **原因**: 用户自行编辑 (option 5c)" \
        "- **恢复**: \`/ohaze:ship-finish\`"
      log "E_pause: appended self-edit state"
      vault_changed=true
    fi
  fi

  # 更新 sync state
  local new_sync
  new_sync=$(python3 -c "
import json
print(json.dumps({
    'discussions_path': '$discussions_path',
    'codex_run_id': '$codex_run_id',
    'retries': $cur_retries,
    'prev_state': '$state'
}))
" 2>/dev/null || echo "{}")
  write_sync_state "$ohaze_dir" "$new_sync"

  if [[ "$vault_changed" == true ]]; then
    brain_commit "update ${proj}/${feature}"
  fi
}

# ─── review-verdict.json handler (#3) ────────────────────────────────
# 触发：codex-executor 写 .ohaze/review-verdict.json 后
# 内容：{iteration, verdict, issues:[...]}

_handle_verdict() {
  local file_path="$1" content="$2"
  local ohaze_dir
  ohaze_dir=$(dirname "$file_path")

  local verdict iteration
  verdict=$(parse_json "$content" verdict)
  iteration=$(parse_json "$content" iteration)
  [[ -z "$verdict" ]] && { log "verdict: empty verdict field, skip"; return 0; }

  # 从 sync state 拿 discussions_path + 已处理过的 verdict key（去重）
  local sync_json discussions_path last_verdict_key cur_verdict_key
  sync_json=$(read_sync_state "$ohaze_dir")
  discussions_path=$(parse_json "$sync_json" discussions_path)
  last_verdict_key=$(parse_json "$sync_json" last_verdict_key)
  cur_verdict_key="${iteration}:${verdict}"

  [[ -z "$discussions_path" || ! -f "$discussions_path" ]] && {
    log "verdict: no discussions doc yet, skip"
    return 0
  }

  # 同一 iteration+verdict 已写过，跳过
  if [[ "$cur_verdict_key" == "$last_verdict_key" ]]; then
    log "verdict: duplicate ${cur_verdict_key}, skip"
    return 0
  fi

  local issues_md=""
  if [[ "$verdict" == "FAIL" ]]; then
    issues_md=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
issues = d.get('issues', [])
print('\n'.join('  - ' + i for i in issues) if issues else '  （无详情）')
" "$content" 2>/dev/null || echo "  （解析失败）")
  fi

  if [[ "$verdict" == "PASS" ]]; then
    vault_append "$discussions_path" \
      "" \
      "## 审查通过 (iteration ${iteration:-?})" \
      "" \
      "- **时间**: \`${NOW}\`" \
      "- **结论**: PASS"
  else
    vault_append "$discussions_path" \
      "" \
      "## 审查未通过 (iteration ${iteration:-?})" \
      "" \
      "- **时间**: \`${NOW}\`" \
      "- **结论**: FAIL" \
      "- **问题列表**:" \
      "${issues_md}"
  fi

  # 把 last_verdict_key 写回 sync state（去重用）
  local new_sync
  new_sync=$(python3 -c "
import json, sys
state = json.loads(sys.argv[1] or '{}')
state['last_verdict_key'] = sys.argv[2]
print(json.dumps(state))
" "$sync_json" "$cur_verdict_key" 2>/dev/null || echo "$sync_json")
  write_sync_state "$ohaze_dir" "$new_sync"

  log "verdict: appended ${verdict} (iter ${iteration}) to discussions"
  brain_commit "verdict $(basename $(dirname "$ohaze_dir"))"
}

# ─── ship-result.json handler (#2) ────────────────────────────────────
# 触发：ship-review / ship-finish 在 finishing 时写 .ohaze/ship-result.json
# 内容：{action, branch, remote?, pr_url?, pr_number?}

_handle_result() {
  local file_path="$1" content="$2"
  local ohaze_dir
  ohaze_dir=$(dirname "$file_path")

  # 把 result 存入 sync state，E5 pre-bash 读取用
  local sync_json new_sync
  sync_json=$(read_sync_state "$ohaze_dir")
  new_sync=$(python3 -c "
import json, sys
state = json.loads(sys.argv[1])
result = json.loads(sys.argv[2])
state['ship_result'] = result
print(json.dumps(state))
" "$sync_json" "$content" 2>/dev/null || echo "$sync_json")
  write_sync_state "$ohaze_dir" "$new_sync"
  log "result: saved ship-result to sync state"
}

# ─── E5: pre-bash handler ─────────────────────────────────────────────
# 触发：LLM 执行 rm .ohaze/current-ship.json 前（PreToolUse）
# 此时 handoff 文件还在，可以读取

handle_pre_bash() {
  local stdin_json
  stdin_json=$(cat)

  local cmd
  cmd=$(parse_nested "$stdin_json" tool_input command)

  # 只处理「rm ... current-ship.json」在同一行的命令
  # 用 grep 逐行匹配，避免多行脚本中 rm 和路径不在同行时误触发
  if ! echo "$cmd" | grep -q 'rm.*current-ship\.json'; then
    return 0
  fi
  log "pre-bash triggered: rm current-ship.json"

  # 从命令中提取 handoff 路径
  local handoff_path
  handoff_path=$(echo "$cmd" | grep -oE '[^ ]+\.ohaze/current-ship\.json' | head -1)
  [[ -z "$handoff_path" ]] && {
    log "cannot extract handoff path from: $cmd"
    return 0
  }
  [[ ! -f "$handoff_path" ]] && { log "handoff not found: $handoff_path"; return 0; }

  local content
  content=$(cat "$handoff_path")

  local worktree_path plan_path spec_path base_ref state retries codex_run_id
  worktree_path=$(parse_json "$content" worktree_path)
  plan_path=$(parse_json "$content" plan_path)
  spec_path=$(parse_json "$content" spec_path)
  base_ref=$(parse_json "$content" base_ref)
  state=$(parse_json "$content" state)
  retries=$(parse_json "$content" retries)
  codex_run_id=$(parse_json "$content" codex_run_id)

  [[ -z "$worktree_path" ]] && { log "no worktree_path in handoff"; return 0; }

  local proj feature ohaze_dir
  proj=$(project_from_worktree "$worktree_path")
  feature=$(feature_from_plan "$plan_path")
  ohaze_dir=$(dirname "$handoff_path")

  log "E5: finishing ${proj}/${feature} state=${state} retries=${retries}"

  ensure_project_dir "$proj"

  # 读 sync state，获取 discussions_path
  local sync_json discussions_path
  sync_json=$(read_sync_state "$ohaze_dir")
  discussions_path=$(parse_json "$sync_json" discussions_path)

  # 读 ship_result（由 _handle_result 预存）
  local ship_result_json ship_action ship_remote ship_pr_url ship_branch
  ship_result_json=$(parse_json "$sync_json" ship_result)
  if [[ -n "$ship_result_json" && "$ship_result_json" != "None" ]]; then
    ship_action=$(parse_json "$ship_result_json" action)
    ship_remote=$(parse_json "$ship_result_json" remote)
    ship_pr_url=$(parse_json "$ship_result_json" pr_url)
    ship_branch=$(parse_json "$ship_result_json" branch)
  fi

  # 确定最终结果描述
  local disposition="完成"
  case "${ship_action:-}" in
    push)    disposition="已推送到远端 (${ship_remote:-origin})" ;;
    pr)      disposition="已创建 PR${ship_pr_url:+: ${ship_pr_url}}" ;;
    discard) disposition="已丢弃" ;;
    *)
      case "$state" in
        kept)               disposition="暂停保留（未 finish）" ;;
        self-edit-pending)  disposition="暂停自编辑（未 finish）" ;;
      esac
      ;;
  esac

  # 获取 commits（worktree 还在）
  local commits=""
  local commit_count=0
  if [[ -d "$worktree_path" && -n "$base_ref" ]]; then
    commits=$(git -C "$worktree_path" log --oneline "${base_ref}..HEAD" 2>/dev/null || true)
    if [[ -n "$commits" ]]; then
      commit_count=$(echo "$commits" | wc -l | tr -d ' ')
    fi
  fi

  # ── 写 decisions ADR ──────────────────────────────────────────────
  local decisions_path="${VAULT}/20_Projects/${proj}/decisions/${feature}.md"
  local discussion_ref="[[20_Projects/${proj}/discussions/${feature}]]"

  {
    cat << EOF
---
type: decision
tags: [decision, ohaze]
created: ${TODAY}
updated: ${TODAY}
source: ohaze
author: ohaze
private: true
status: active
related: ${discussion_ref}
---

# ${proj}: ${feature} — 决策记录

## 结论

| 字段 | 值 |
|---|---|
| 最终结果 | ${disposition} |
| 完成时间 | ${NOW} |
| 操作类型 | ${ship_action:-unknown} |
| 分支 | ${ship_branch:-N/A} |
| PR 链接 | ${ship_pr_url:-N/A} |
| 审查重试次数 | ${retries:-0} |
| Codex run_id | ${codex_run_id:-N/A} |
| Commits 数量 | ${commit_count} |

## 流水账

→ ${discussion_ref}

## Commits

\`\`\`
${commits:-（无 commit）}
\`\`\`

## 相关文件

- **Spec**: \`${spec_path}\`
- **Plan**: \`${plan_path}\`
EOF
  } > "$decisions_path"
  log "E5: wrote decisions doc: $decisions_path"

  # ── 更新 discussions 文档，追加完结记录 ──────────────────────────
  if [[ -n "$discussions_path" && -f "$discussions_path" ]]; then
    vault_append "$discussions_path" \
      "" \
      "## 流程结束" \
      "" \
      "- **时间**: \`${NOW}\`" \
      "- **最终结果**: ${disposition}" \
      "- **Commits**: ${commit_count} 个" \
      "- **决策记录**: [[decisions/${feature}]]"
    log "E5: appended completion to discussions"
  fi

  # ── 更新 progress.md ────────────────────────────────────────────
  local progress_path="${VAULT}/20_Projects/${proj}/progress.md"
  vault_append "$progress_path" \
    "" \
    "## ${TODAY} — ${feature}" \
    "" \
    "- **结果**: ${disposition}" \
    "- **审查重试**: ${retries:-0} 次" \
    "- **Commits**: ${commit_count} 个" \
    "- **详情**: [[decisions/${feature}]]"
  log "E5: updated progress.md"

  # ── 同步更新 README.md 的 stage/next/last_active ────────────────
  # 只有真正交付（push / pr）才更新；discard 和暂停都不登记
  local readme_path="${VAULT}/20_Projects/${proj}/README.md"
  if [[ ( "${ship_action:-}" == "push" || "${ship_action:-}" == "pr" ) && -f "$readme_path" ]]; then
    # 提取 feature 的语义描述（去掉日期前缀 YYYY-MM-DD-）
    local feature_desc
    feature_desc=$(echo "$feature" | sed 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-//')

    # 更新 frontmatter 中的 last_active 和 milestone 字段（如果有）
    sed -i '' "s/^last_active: .*/last_active: ${TODAY}/" "$readme_path" 2>/dev/null || true

    # 在 ## 当前阶段 或 ## Next 后追加已完成记录（如果 section 存在）
    if grep -q "^## 当前阶段\|^## Next\|^## 当前目标" "$readme_path" 2>/dev/null; then
      # 在文件末尾追加一个已完成记录区块（幂等：只追加，不覆盖原有内容）
      if ! grep -q "shipped-features" "$readme_path" 2>/dev/null; then
        vault_append "$readme_path" \
          "" \
          "## 完成记录" \
          "<!-- shipped-features -->" \
          ""
      fi
      vault_append "$readme_path" \
        "- \`${TODAY}\` ${feature_desc}（retries: ${retries:-0}，commits: ${commit_count}）→ [[decisions/${feature}]]"
    fi
    log "E5: updated README.md for ${proj}"
  fi

  # ── 更新源项目 CLAUDE.md 的当前目标 section ────────────────────────
  # 只在真正完成（push / pr / discard）时才改源码 CLAUDE.md
  if [[ "${ship_action:-}" == "push" || "${ship_action:-}" == "pr" || "${ship_action:-}" == "discard" ]]; then
    local source_claude
    # worktree_path → 主项目根（去掉 .worktrees/xxx）
    source_claude=$(echo "$worktree_path" | sed 's|/.worktrees/.*||')/CLAUDE.md
    if [[ -f "$source_claude" ]]; then
      local feature_desc_short feature_desc_escaped
      feature_desc_short=$(echo "$feature" | sed 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-//')
      # escape sed BRE 元字符（\ / . * [ ] ^ $ &）防注入
      feature_desc_escaped=$(python3 -c '
import sys
s = sys.argv[1]
special = r"\/.*[]^$&"
print("".join(("\\" + c) if c in special else c for c in s))
' "$feature_desc_short" 2>/dev/null || echo "$feature_desc_short")
      # 在匹配 feature 描述的行把第一个 - [ ] 改为 - [x]（仅命中第一处，避免误改其他 todo）
      sed -i '' "/${feature_desc_escaped}/s/- \[ \]/- [x]/" "$source_claude" 2>/dev/null || true
      log "E5: updated source CLAUDE.md for ${proj}"
    fi
  fi

  brain_commit "finish ${proj}/${feature}"
}

# ─── main ─────────────────────────────────────────────────────────────

log "=== event=${EVENT} ==="

# 确保 Brain 目录存在
[[ ! -d "$VAULT" ]] && { log "Brain vault not found: $VAULT"; exit 0; }

case "$EVENT" in
  on-write) handle_on_write ;;
  pre-bash) handle_pre_bash ;;
  *)
    log "unknown event: $EVENT"
    exit 0
    ;;
esac

exit 0
