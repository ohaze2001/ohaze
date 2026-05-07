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

## 使用

```text
/ohaze:ship 给 hazeflow 加用户登录页

# Claude 跑完 brainstorm + plan 后会把整份 plan 后台扔给 Codex
# 提示你用 /codex:status 看进度

/ohaze:ship-review

# Codex 跑完后用这条命令触发：
# - superpowers:code-reviewer 子 agent 审查 git diff vs plan
# - 不通过 → 自动 codex --resume 修复（上限 3 次）
# - 通过 → superpowers:finishing-a-development-branch 收尾
```

## 设计决策（V1）

- 执行粒度：**端到端**，整份 plan 一次性给 Codex
- Codex 模式：默认 `--background --write`
- 审查策略：Codex 完成后 `superpowers:code-reviewer` 自动审查
- 审查重试：失败 → Codex `--resume`，上限 3 次

详细见 [CLAUDE.md](CLAUDE.md)。

## License

MIT
