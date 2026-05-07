# ohaze 进度

## 2026-05-07
- 完成：V1 设计锁定（5 决策点全部按推荐组合确定）
  - Codex 端到端执行
  - 审查自动触发
  - 审查重试上限 3 次
  - 默认 `--background`
  - 整体 review（非逐 Task）
- 完成：项目骨架搭建（CLAUDE.md / PROGRESS.md / 目录结构）
- 完成：5 个核心文件全部到位（plugin.json / 2 commands / 2 skills）
- 修正：发现 Claude Code 不识别 `~/.claude/plugins/<name>/` 直接路径，必须经 marketplace
  → 重构为 marketplace+plugin 布局：仓库根放 `.claude-plugin/marketplace.json`，
     plugin 实体在 `plugins/ohaze/`
- 待处理：本地 marketplace 安装测试 → 真实项目跑通 `/ohaze:ship` → 推 GitHub
