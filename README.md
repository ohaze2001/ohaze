# ohaze

> 个人 Claude Code 工作流插件：让 superpowers 负责思考、Codex 负责执行、Claude 负责审查。

## 它是什么

`ohaze` 把三个工具的强项串成一条闭环流水线：

| 阶段 | 谁干 | 来源 |
|---|---|---|
| 1. brainstorming（澄清需求） | Claude | `superpowers` |
| 2. using-git-worktrees（隔离工作区） | Claude | `superpowers` |
| 3. writing-plans（生成 TDD 实现计划） | Claude | `superpowers` |
| 4. plan → Codex prompt | Claude | `ohaze` |
| 4. 执行整份 plan | Codex | `codex` 插件 |
| 5. 审查 git diff vs plan | Claude | `ohaze` + `superpowers:code-reviewer` |
| 6. 修复（如审查不通过） | Codex `--resume`（最多 3 次） | `codex` 插件 |
| 7. finishing（merge / PR） | Claude | `superpowers` |

一条 `/ohaze:ship "做什么"` 命令端到端跑完。

## 前置依赖

- [superpowers](https://github.com/obra/superpowers) plugin
- [codex](https://github.com/openai/codex) plugin（含 `codex-companion`）

```bash
/plugin install superpowers@claude-plugins-official
/plugin install codex@openai-codex
```

## 安装

ohaze 本身是一个 Claude Code marketplace（仓库即 marketplace，里面只有一个 plugin）。

**方式 A：从 GitHub 安装（推送后可用）**

```text
/plugin marketplace add muling-dev/ohaze
/plugin install ohaze@ohaze
```

**方式 B：本地路径安装（开发期）**

```text
/plugin marketplace add /Users/apple/Project/ohaze
/plugin install ohaze@ohaze
```

安装后两个命令立即可用：`/ohaze:ship` 和 `/ohaze:ship-review`。

## 命令清单

| 命令 | 作用 |
|---|---|
| `/ohaze:ship "需求"` | 端到端：brainstorm → worktree → plan → Codex 后台执行 |
| `/ohaze:ship-review [--more]` | Codex 跑完后触发：审查 → 重试上限 3 → 5 选项 finishing 菜单 |
| `/ohaze:ship-finish [--skip-review]` | 续跑：从"保持现状"或"自己改"状态恢复，可选再 review，进 finishing |
| `/ohaze:status` | 跨 worktree 工作流总览：哪个在跑、哪个等审查、哪个 stale |

## 使用示例

### 主流程

```text
/ohaze:ship 给 hazeflow 加用户登录页

# Claude 走 brainstorm + worktree + plan 后把整份 plan 后台扔给 Codex
# 提示用 /codex:status 看进度

/ohaze:ship-review

# Codex 跑完后:
# - 主线程帮 Codex 补 commit (沙箱拦了 .git/)
# - superpowers:code-reviewer 审查 git diff vs plan
# - 不通过 → 自动 codex --resume 修复 (上限 3 次)
# - 通过 → 5 选项 finishing 菜单
```

### Finishing 菜单

```
1. 推送到远端
2. 创建 Pull Request
3. 保持现状 (稍后处理)
4. 丢弃此次工作
5. 继续修改 (小改动)   ← 不需要走完整 ship 的小调整
```

选 5 后子菜单：
- a) Codex 续跑 (`--resume`，沿用同一 thread)
- b) Claude 主线程直接改 (改名/加注释/单行 fix)
- c) 我自己改 (退出，手改完跑 `/ohaze:ship-finish`)

### 跨 worktree 总览

```text
/ohaze:status

# 输出:
# 项目: myproject
# 📍 主目录    main      干净
# 🔧 worktrees:
#   feat-login   分支:feat/login    🟡 Codex 跑中 (run_id, 4m)
#   fix-auth     分支:fix/auth      🟢 等审查
#   experiment-x 分支:experiment/x  🟡 stale (7+ 天)
# 📊 远端 PRs (gh): #42 ...
```

## 设计决策（V1）

- 执行粒度：**端到端**，整份 plan 一次性给 Codex
- Codex 模式：默认 `--background --write`
- 审查策略：Codex 完成后 `superpowers:code-reviewer` 自动审查
- 审查重试：失败 → Codex `--resume`，上限 3 次

详细见 [CLAUDE.md](CLAUDE.md)。

## License

MIT
