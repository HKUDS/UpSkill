# Upskill — Claude Code Integration

Upskill 是一个集成于 Claude Code 的个人知识蒸馏系统。当你日常使用 CC 时，若某个任务失败，系统会自动保存失败现场；你可以随时触发 **building**——让更强的模型分析失败原因并生成 **skill**，经验证后存入你的私人 skill 库。此后，所有项目中 CC 都会自动加载这些经验，让你常用的模型表现越来越好。

---

## 目录

- [核心概念](#核心概念)
- [架构总览](#架构总览)
- [快速开始](#快速开始)
- [日常使用流程](#日常使用流程)
- [Building 管道](#building-管道)
- [Skill Serving（经验注入）](#skill-serving经验注入)
- [管理命令](#管理命令)
- [配置](#配置)
- [Serve Mode](#serve-mode)
- [文件结构](#文件结构)

---

## 核心概念

### 三种角色

| 角色 | 配置位置 | 用途 |
|------|---------|------|
| **日常模型** | CC `settings.json` | 你平时干活用的，随时切换，完全独立 |
| **Teacher** | `upskill.conf` | 强模型，用于分析失败、生成 skill |
| **Student** | `upskill.conf` | 弱模型，skill 的验证目标。skill 为它优化 |

### Skill（Skill 输出）

一次 building 产出的经验包，包含三种载体：

| 载体 | 加载方式 | 内容 |
|------|---------|------|
| **CLAUDE.md** | CC 启动时自动加载（全局） | 简短摘要 + skill 指针（~5行/skill） |
| **Skill** | CC 主动调用时加载（按需） | 完整陷阱分析 + 操作指南 |
| **Memory** | 每 session 同步，CC 自动加载 | 简短反馈规则（1-2行/条） |

### 为什么这样设计

- **CLAUDE.md 轻量常驻**：所有 skill 摘要始终在 context 中，但每个只占 ~5 行。20 个 skill ≈ 600 tokens，不会膨胀
- **Skill 按需加载**：完整内容仅在 CC 主动调用时才消耗 context
- **Memory 自动提醒**：经验规则自动注入，不需要手动触发

---

## 架构总览

```
~/.claude/
├── upskill.conf              # Teacher/Student 模型 + Serve Mode
├── upskill-store/            # skill 持久化存储
│   ├── CLAUDE.md               # 全局 skill 索引（claudeMd 指向此文件）
│   ├── <category>/
│   │   ├── manifest.yaml       # 条目索引（含 trigger_keywords, base_model）
│   │   ├── CLAUDE.md           # 该 category 的完整 skill 内容
│   │   ├── .claude/skills/
│   │   └── memory/
│   └── .building/               # 正在进行的 building 临时文件
├── hooks/                      # Hook 脚本
│   ├── before-session.sh       # 每 session 启动时执行
│   ├── after-session.sh        # session 结束时执行
│   ├── save-session.sh         # 按需保存当前 session（/upskill-build 调用）
│   ├── upskill-build.sh        # Building 管道（核心）
│   ├── inject-skill.sh           # Memory 同步
│   ├── upskill-store.sh      # skill 库管理 CLI
│   └── parse-skill.py          # 解析 CC 输出提取 skill 文件
├── skills/                     # 管理命令（Slash Commands）
│   ├── upskill-init.md       # /upskill-init  安装向导
│   ├── upskill-list.md       # /upskill-list  浏览 skill 库
│   ├── upskill-build.md       # /upskill-build  手动触发 building
│   ├── upskill-status.md     # /upskill-status 查看统计
│   ├── upskill-remove.md     # /upskill-remove 删除 skill
│   ├── upskill-mode.md       # /upskill-mode  切换 serve mode
│   ├── upskill-model.md      # /upskill-model 配置模型
│   ├── upskill-run.md        # /upskill-run   交互式 building
│   ├── upskill-configure.md  # /upskill-configure 配置设置
│   └── upskill-uninstall.md  # /upskill-uninstall 卸载
├── settings.local.json         # CC 配置（hooks + claudeMd）
└── projects/<slug>/memory/     # CC 项目 memory（skill memory 注入至此）
```

### 数据流向

```
Session 失败
    │
    ▼
after-session hook → 保存 prompt + session log → 设置 pending 标记
    │
    ▼
用户执行 /upskill-skill（或看到通知后确认）
    │
    ▼
upskill-build.sh
    ├─ Phase 0: 创建 git worktree（隔离环境）
    ├─ Phase 2: Teacher 解决任务
    ├─ Phase 3: Teacher 分析失败 → 生成 skill
    ├─ Phase 4: 解析 skill 文件
    └─ Phase 5: Ralph 验证（Student + skill 重试，最多 3 轮）
         │
         ├─ PASS → 存入 upskill-store/<category>/
         │         → upskill-store.sh sync → 更新全局索引 + skills
         │
         └─ FAIL → 丢弃
```

---

## 快速开始

### 远程安装（一行命令）

```bash
curl -sSL https://raw.githubusercontent.com/HKUDS/Upskill/main/cc-integration/install.sh | bash -s -- --remote
```

安装脚本会自动完成所有设置。如需更新到最新版，随时运行 `/upskill-init`。

### 本地安装

```bash
cd cc-integration && bash install.sh
```

### 启用项目 Building

在每个需要 building 的项目中运行：

```bash
/upskill-configure
```

这会配置项目的 hooks（claudeMd、before_session、after_session），使 Upskill 能自动捕获失败并注入技能。

### 卸载

运行 `/upskill-uninstall` 或在源码目录执行：

```bash
cd cc-integration && bash install.sh --uninstall
```

---

## 日常使用流程

### 正常使用（完全无感）

你照常使用 CC，任何模型都可以。每次 session：

```
Session 启动
    │
    ▼
before-session hook
    ├─ 同步全局 skill 索引到当前项目
    └─ 检查 pending 标记 → 有则提醒用户 /upskill-build
    │
    ▼
CC 加载 context：
    ├─ 项目 CLAUDE.md
    ├─ ~/.claude/upskill-store/CLAUDE.md（全局 skill 摘要，始终加载）
    ├─ ~/.claude/skills/（全局 skills，按需调用）
    └─ ~/.claude/projects/<slug>/memory/（skill memories）
    │
    ▼
CC 正常执行任务 ...
    │
    ▼
Session 结束
    │
    ▼
after-session hook（始终触发）
    ├─ 检测失败（exit code ≠ 0 或 CC 自报失败）
    ├─ 保存 prompt.txt + session.log
    ├─ 失败 → 设置 pending 标记 + 打印提示
    └─ 成功 → 仅保存上下文（供手动 /upskill-build 使用）
```

### CC 如何使用 skill

CC 在 context 中看到全局 CLAUDE.md，包含所有 skill 摘要：

```markdown
## Skill: data-analysis (3 skills)
**Base model:** deepseek-v4-flash
**Trigger:** csv, encoding, json, database, query
**Model:** Validated on `deepseek-v4-flash`. For best results, use this model.

  - `skill_20260605_001` — For Python CSV data-processing tools with filter/sort
    → Read `~/.claude/upskill-store/data-analysis/skill_20260605_001/SKILL.md`
  - `skill_20260605_002` — Database query optimization with proper index usage
    → Read `~/.claude/upskill-store/data-analysis/skill_20260605_002/SKILL.md`
```

- **interactive 模式（默认）**：使用 `/upskill-run` 触发匹配流程，CC 展示所有 skill 供选择
- **auto 模式**：CC 在每次 prompt 时自动扫描匹配的 skill 并主动提示

---

## Building 管道

### 触发方式

| 方式 | 触发条件 |
|------|---------|
| **自动提示** | Session 以非零退出码结束 → 下次打开 CC 时提示 `/upskill-build` |
| **手动触发** | 任何时候输入 `/upskill-build` |

### 触发条件 vs 影响范围

| 场景 | 是否触发 | 说明 |
|------|:--:|------|
| 项目根有 `verify.sh`，CC 执行命令失败 | 是 | 任务类场景 |
| 项目根无 `verify.sh` | 否 | 非任务场景，不干预 |
| 同一任务已 skill 过 | 否 | 防重复，检查 skill tags |
| 今日已超过上限 | 否 | 控制成本 |
| 用户正常对话/代码审查 | 否 | 无 verify.sh，无触发 |

**关键**: 不触发时，用户使用 CC 的体验与安装前完全一致，零额外延迟。

### 五个 Phase

```
Phase 0: Setup
  ├─ 创建 git worktree（隔离环境）
  ├─ 复制 HEAD + 已修改的跟踪文件 + 未跟踪文件
  └─ 非 git 项目：rsync 排除 node_modules/.venv 等大目录

Phase 1: 加载失败轨迹
  └─ 读取 session.log 最后 500 行

Phase 2: Teacher 解决任务
  └─ Teacher 模型在 worktree 中独立完成任务

Phase 3: skill 生成
  └─ Teacher 分析 Student 的失败轨迹
     生成三个文件（使用 ===BEGIN_FILE=== / ===END_FILE=== 标记）：
       • CLAUDE.md       — 常见陷阱 + 正确方法 + 验证清单
       • solve-task.md   — 分步技能
       • feedback_lessons.md — 持久记忆

Phase 4: 解析
  └─ parse-skill.py 提取标记文件 → 写入 skill 输出目录

Phase 5: Ralph 验证（最多 3 轮）
  ├─ 创建新的 worktree
  ├─ 部署 skill（CLAUDE.md + skills + memory）
  ├─ Student 模型重试任务
  ├─ 检查 ===BUILD_RESULT: PASS=== 标记
  ├─ PASS → 存入 upskill-store → sync 全局索引 → 完成 ✓
  └─ FAIL → Teacher 修订 skill → 重试（最多 3 次）→ 仍失败则丢弃
```

### 验证标准

Ralph 验证通过的条件：Student 模型在 worktree 中完成任务后，输出中包含 `===BUILD_RESULT: PASS===`。

---

## Skill Serving（经验注入）

### 两种层级

| 层级 | 安装位置 | 加载时机 | 作用域 |
|------|---------|---------|--------|
| **全局** | `~/.claude/upskill-store/CLAUDE.md` | CC 启动时自动 | 所有 project |
| **全局** | `~/.claude/skills/upskill-*.md` | CC 调用时 | 所有 project |
| **项目** | `~/.claude/projects/<slug>/memory/` | 每 session 同步 | 当前 project |

### 模型兼容性

每个 skill 记录其验证时的 Student 模型（`base_model`）。Serving 时：

- **全局 CLAUDE.md / skills**：始终可见，标注 base model 和兼容性提示
- **不按模型过滤**：通用经验（如"CSV 先检查编码"）适用于多种模型
- 用户可通过 `/upskill-mode` 切换提示方式

---

## 管理命令

全部通过 `/upskill-*` 斜杠命令调用。

| 命令 | 功能 |
|------|------|
| `/upskill-list` | 列出所有已安装的 skill（按 category 分组） |
| `/upskill-build` | 分析 session 并生成 skill |
| `/upskill-run` | 交互式 build 工作流：扫描 → 匹配 → 加载 → 执行 |
| `/upskill-status` | 查看 skill 数量和状态 |
| `/upskill-remove` | 删除指定 skill 或整个 category |
| `/upskill-mode` | 切换或查看 serve mode |
| `/upskill-model` | 配置 Teacher / Student 模型 |
| `/upskill-configure` | 在当前项目中启用 Upskill hooks |
| `/upskill-uninstall` | 卸载 Upskill |
| `/upskill-init` | 初始化 Upskill |

---

### /upskill-init

更新 Upskill 到最新版本。重新运行安装器以刷新 hooks、skills 和配置。如有旧版设置会自动迁移。

```bash
/upskill-init
```

---

### /upskill-list

列出所有 category 下的 skill。

```bash
/upskill-list
/upskill-list software-engineering     # 只显示指定 category
```

底层调用：`bash ~/.claude/hooks/upskill-store.sh list`

---

### /upskill-status

查看 skill 总数和活跃 building 状态。

```bash
/upskill-status
```

---

### /upskill-remove

删除 skill 或 category。

```bash
/upskill-remove
/upskill-remove --category data-analysis --skill-id skill_20260605_001
/upskill-remove --category data-analysis     # 删除整个 category（需确认）
```

---

### /upskill-build

分析最近的 session 并生成 skill。支持失败和成功两种场景。

```bash
/upskill-build                          # 自动检测 category
/upskill-build --category software-engineering
/upskill-build --session <session_id>
```

---

### /upskill-run

交互式 build 工作流。

```bash
/upskill-run
```

流程：
1. 收集任务描述
2. 扫描已安装 skill 并匹配
3. 展示匹配结果（★ = 推荐）
4. 用户选择 skill（或 "none" 跳过）
5. 模型不匹配时提示切换
6. 加载 SKILL.md 并执行任务

---

### /upskill-mode

切换 serve mode。

```bash
/upskill-mode           # 查看当前模式
/upskill-mode auto      # 切换到 auto
/upskill-mode interactive  # 切换到 interactive
```

---

### /upskill-model

查看或切换模型配置。

```bash
/upskill-model          # 查看当前预设
/upskill-model teacher  # 提示如何切换到 Teacher 模型
/upskill-model student  # 提示如何切换到 Student 模型
```

---

### /upskill-configure

在当前项目中启用 Upskill hooks。配置 `.claude/settings.local.json`，添加 claudeMd、before_session 和 after_session hooks。

```bash
/upskill-configure
```

---

### /upskill-uninstall

卸载 Upskill，移除 hooks、skills、配置文件。

```bash
/upskill-uninstall
```

---

## 配置

### `~/.claude/upskill.conf`

```bash
UPSKILL_TEACHER="deepseek-v4-pro[1m]"   # 强模型（分析失败、生成 skill）
UPSKILL_STUDENT="deepseek-v4-flash"     # 弱模型（skill 验证目标）
UPSKILL_SERVE_MODE="interactive"         # 服务模式
```

- **TEACHER** 应选用强模型（如 claude-opus、deepseek-v4-pro）
- **STUDENT** 应选用你希望提升的弱模型（如 claude-haiku、deepseek-v4-flash）
- **日常模型**在 CC `settings.json` 中独立设置，与以上两者无关

修改配置后运行 `bash ~/.claude/hooks/upskill-store.sh sync` 或 `/upskill-mode` 即可生效。

---

## Serve Mode

| 模式 | 行为 |
|------|------|
| **interactive**（默认） | 使用 `/upskill-run` 主动触发，展示所有 skill 供用户选择 |
| **auto** | 每次 prompt 自动关键词匹配，匹配到 skill 时主动提示 CC 应用 |

切换方式：

```
/upskill-mode              # 查看当前模式
/upskill-mode auto         # 切换到 auto
/upskill-mode interactive  # 切换到 interactive
```

### interactive 模式下的 CLAUDE.md 条目

```markdown
<!-- UPSKILL:data-analysis -->
## Skill: data-analysis (3 skills)
**Base model:** deepseek-v4-flash
**Trigger:** csv, encoding, json, database, query
**Model:** Validated on `deepseek-v4-flash`. For best results, use this model.

Use `/upskill-run` to browse skills, get recommendations, and apply guidance.
```

### auto 模式下的 CLAUDE.md 条目

```markdown
<!-- UPSKILL:data-analysis -->
## Skill: data-analysis (3 skills)
**Base model:** deepseek-v4-flash
**Trigger:** csv, encoding, json, database, query
**Model:** Validated on `deepseek-v4-flash`. For best results, use this model.

Skills are auto-matched on every prompt. Confirm before applying.
```

---

## 文件结构

### 源码仓库

```
cc-integration/
├── bootstrap.sh                # curl | bash 入口
├── install.sh                  # 安装器（支持 --remote）
├── upskill-build.sh            # Building 管道
├── inject-skill.sh               # Memory 同步
├── upskill-store.sh          # skill 库管理 CLI
├── parse-skill.py              # skill 文件解析
├── hooks/
│   ├── before-session.sh       # CC before_session hook
│   ├── after-session.sh        # CC after_session hook
│   └── save-session.sh         # On-demand session saver
├── skills/
│   ├── upskill-init.md       # /upskill-init
│   ├── upskill-list.md       # /upskill-list
│   ├── upskill-build.md       # /upskill-build
│   ├── upskill-status.md     # /upskill-status
│   ├── upskill-remove.md     # /upskill-remove
│   ├── upskill-mode.md       # /upskill-mode
│   ├── upskill-model.md      # /upskill-model
│   ├── upskill-run.md        # /upskill-run
│   ├── upskill-configure.md  # /upskill-configure
│   └── upskill-uninstall.md  # /upskill-uninstall
└── templates/
    ├── upskill.conf          # 模型配置模板
    ├── settings-patch.json     # CC hooks + claudeMd 配置
    └── manifest.yaml           # skill store 清单模板
```

### 用户安装后（`~/.claude/`）

```
~/.claude/
├── upskill.conf
├── upskill-store/
│   ├── CLAUDE.md               # 全局 skill 摘要（CC 自动加载）
│   ├── manifest.yaml
│   ├── <category>/
│   │   ├── manifest.yaml       # 含 base_model, trigger_keywords
│   │   ├── CLAUDE.md           # 完整内容
│   │   ├── .claude/skills/
│   │   └── memory/
│   └── .building/               # 临时文件（session 上下文 + building 日志）
├── hooks/
│   ├── before-session.sh
│   ├── after-session.sh
│   ├── upskill-build.sh
│   ├── inject-skill.sh
│   ├── upskill-store.sh
│   └── parse-skill.py
├── skills/
│   ├── upskill-init.md
│   ├── upskill-list.md
│   ├── upskill-build.md
│   ├── upskill-status.md
│   ├── upskill-remove.md
│   ├── upskill-mode.md
│   ├── upskill-model.md
│   ├── upskill-run.md
│   ├── upskill-configure.md
│   ├── upskill-uninstall.md
│   └── upskill-<category>.md  # skill 全局 skills（sync 生成）
├── settings.local.json
└── projects/<slug>/memory/      # skill memory 注入目标
```

---

## 与现有 CC 目录的兼容性

Upskill 写入的 `~/.claude/` 路径不会与 CC 原有文件冲突：

| Upskill 写入 | CC 是否使用 | 兼容方式 |
|---------------|------------|---------|
| `settings.local.json` | ✓ CC 原生 | **合并**而非覆盖，保留用户已有配置 |
| `skills/upskill-*.md` | ✓ CC 读取 | 不同文件名，与用户 skill 共存 |
| `projects/<slug>/memory/` | ✓ CC 读取 | 追加 skill memory，不删用户 memory |
| `hooks/` | ✗ CC 不用 | Upskill 专属目录 |
| `upskill-store/` | ✗ CC 不用 | Upskill 专属目录 |
| `upskill.conf` | ✗ CC 不用 | Upskill 专属配置文件 |
