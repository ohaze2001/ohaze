# ohaze 5 件套合规修复 — 设计 spec

> 日期: 2026-05-29 · 分支: `fix/5-piece-compliance` · 执行方式: Claude 主线程直接改 + review subagent 把关（不走 Codex 流水线）

## 背景

vault-system S15 ship（2026-05-29）重构了 5 件套规约，权威真本是
`~/Project/vault-system/docs/5-piece-set-schema.md`，配套手册
`~/Project/hazeflow/_shared/5-piece-set-auto-maintain.md`。ohaze 的 5 件套是按旧规写的，多处违规。
本 spec 记录对照结论与修复方案（ohaze-overview session 已先行讨论，本次执行）。

ohaze 项目类型 = **发行产品**（有 `plugin.json` manifest + git push + SemVer + tag + CHANGELOG）→ 要求完整 5 件套。

## 违规对照（vs 真本 schema）

| 文件 | 合规度 | 违规点 |
|---|---|---|
| CLAUDE.md | ⛔ 几乎全违规 | 缺顶部 4 链接 / `## 项目类型` / `## Agent 行为约定` / `## 集成点`；`## 关键文件` 需改名 `## 关键文件 / 入口`；`基本信息`·`设计决策`·`阶段归属`·`前置要求`·`常用命令`·`外部依赖`·`版本号` 不在 schema；`当前目标` = 与 ROADMAP 双真本 |
| README.md | ⚠️ 中度 | 缺 `## 架构` / `## 历史` / `## 相关项目 / 文档`；`命令清单`→`常用命令`；`安装`→`安装 / 部署`；`它是什么`·`前置依赖` 需并入；`路线图` = 与 ROADMAP 双真本 |
| CHANGELOG.md | ⚠️ 轻度 | `## [Unreleased]` 缺 6 子段骨架（Added/Changed/Fixed/Removed/Planned/Backlog） |
| ROADMAP.md | ✓ 合规占位 | 仅 untracked 未 commit |
| VAULT-CONTEXT.md | ✓ 完全合规 | 仅 untracked 未 commit |
| plugin.json | ✓ 合规 | version 1.9.1 与 CHANGELOG 一致 |
| PROGRESS.md | ⛔ schema 外 | 5-18 旧物，内容已被 ROADMAP+CHANGELOG 取代 |

## 修复方案（全部一次到位）

1. **CLAUDE.md** 按 schema 6 段全重写：tagline + 顶部 4 链接 / `## 项目类型` / `## Agent 行为约定` / `## 关键文件 / 入口` / `## 集成点`。删 `## 当前目标`（双真本）。
2. **README.md** 重构为 schema 7 段：`安装 / 部署`（并 前置依赖+安装）/ `架构`（吸收 它是什么 + 设计决策 + 从 CLAUDE.md 迁来的 阶段归属）/ `常用命令`（命令清单改名 + 吸收 CLAUDE.md 常用命令）/ `使用`（使用示例改名）/ `历史`（指向 ROADMAP+CHANGELOG）/ `相关项目 / 文档`（新）/ `License`（保留）。删 `## 路线图`（双真本）。
3. **CHANGELOG.md** `## [Unreleased]` 补 6 子段骨架，`待规划 2.0.0` 归到 `### Planned`。历史叙事与已发布版本不动。
4. **PROGRESS.md** `git rm`。
5. **ROADMAP.md / VAULT-CONTEXT.md** 仅 `git add` 纳管，内容不动（dream / C 类领地）。

## 范围外（仅标记）

- 全局 `~/CLAUDE.md` line 56 死引用 `~/Project/ohaze/docs/branch-strategy.md`（待 Ship O1 创建，从未创建）—— 不在 ohaze 仓库内，本次不动，由 haze 后续单独处理。

## 验收

- 5 件套结构逐项匹配真本 schema（review subagent 核对）。
- 无双真本（CLAUDE.md / README 不再承载进度路线）。
- 内容搬运无丢失（设计决策 / 阶段归属 / 使用示例 完整迁到 README）。
- 版本号字段三处一致（plugin.json / CLAUDE.md 项目类型 / CHANGELOG 顶部）。
