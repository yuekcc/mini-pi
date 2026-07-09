# mp - Mini Pi Agent Runtime

> 一个用 C3 语言编写的轻量级编码 Agent 运行时。

`mp` 是一个可交互的 coding agent，通过调用 OpenAI-compatible API（支持思考/推理能力）驱动 LLM，结合内置工具集，帮助开发者阅读文件、执行命令、编辑代码和编写新文件。

---

## 目录

- [特性](#特性)
- [快速开始](#快速开始)
- [架构概览](#架构概览)
- [内置能力](#内置能力)
  - [Tool System 工具系统](#tool-system-工具系统)
  - [Skill System 技能系统](#skill-system-技能系统)
  - [对话管理](#对话管理)
  - [推理循环 (Reasoning Loop)](#推理循环-reasoning-loop)
  - [API 通信层](#api-通信层)
- [内置工具详解](#内置工具详解)
  - [ReadFile - 读取文件](#readfile---读取文件)
  - [Bash - 执行命令](#bash---执行命令)
  - [EditFile - 精确编辑](#editfile---精确编辑)
  - [WriteFile - 写入文件](#writefile---写入文件)
  - [Grep - 内容搜索](#grep---内容搜索)
  - [Glob - 文件查找](#glob---文件查找)
  - [ListDir - 目录列表](#listdir---目录列表)
  - [Task - 子代理](#task---子代理)
- [命令行使用](#命令行使用)
- [配置说明](#配置说明)
- [开发笔记](#开发笔记)

---

## 特性

- **🚀 轻量运行时** — 单二进制文件，无外部依赖（仅需 libcurl）
- **🔧 8 个内置工具** — 覆盖文件读写、命令执行、内容搜索、子代理等场景
- **🧩 Skill 扩展** — 通过 Markdown 文件定义可复用的专业技能指令
- **🤖 多 Agent 支持** — Task 工具可派生子 Agent，隔离执行独立任务
- **💡 推理支持** — 原生支持 reasoning/thinking 内容输出
- **🔌 OpenAI 兼容** — 对接任意 OpenAI-compatible API（可自定义 base URL）
- **📝 Debug 模式** — 自动保存请求/响应 JSON，便于排查问题

---

## 快速开始

```bash
# 启动交互模式（默认连接本地 API）
mp

# 指定任务和模型
mp -t "分析 src 目录的结构" --model "your-model-id"

# 非交互模式（headless），执行完自动退出
mp --headless -t "帮我重构 login.c3"

# 从文件读取任务
mp -f task.txt --headless

# 查看帮助
mp --help

# 列出所有可用 Skill
mp --list-skills
```

---

## 架构概览

```
┌─────────────────────────────────────────────────┐
│                    main.c3                       │
│               (入口 / 初始化)                     │
├─────────────────────────────────────────────────┤
│                                                  │
│   ┌──────────┐  ┌──────────┐  ┌──────────────┐  │
│   │ cli.c3   │  │ skill.c3 │  │ context.c3   │  │
│   │ CLI 解析  │  │ Skill 加载│  │ 上下文管理    │  │
│   └──────────┘  └──────────┘  └──────────────┘  │
│                                                  │
│   ┌──────────────────────────────────────────┐   │
│   │            rat_loop.c3                   │   │
│   │      Reasoning-Action-Tool Loop          │   │
│   │  (用户输入 → API 调用 → 工具执行 → 回复)   │   │
│   └──────────────────────────────────────────┘   │
│                          │                       │
│            ┌─────────────┼─────────────┐         │
│            ▼                           ▼         │
│   ┌──────────────┐          ┌──────────────┐    │
│   │  api.c3      │          │  tool/*.c3   │    │
│   │ LLM 通信层   │          │  8 个内置工具   │    │
│   │ (HTTP/JSON)  │          │              │    │
│   └──────────────┘          └──────────────┘    │
│                                                  │
│   ┌──────────────┐  ┌──────────────────────┐    │
│   │ util/*.c3    │  │ global.c3            │    │
│   │ 工具函数库    │  │ 全局状态管理          │    │
│   └──────────────┘  └──────────────────────┘    │
└─────────────────────────────────────────────────┘
```

---

## 内置能力

### Tool System 工具系统

工具系统是 `mp` 的核心执行层，基于 C3 interface 实现多态分发：

- **`Tool` interface** — 定义了所有工具必须实现的三个方法：
  - `name()` → 返回工具名称
  - `schema()` → 返回 OpenAI function calling 格式的 JSON Schema
  - `execute(allocator, out, args)` → 执行工具逻辑并输出结果

- **`ToolHub`** — 工具注册中心：
  - 初始化时根据允许的工具列表激活对应工具
  - `schema()` 聚合所有激活工具的 JSON Schema，注入 API 请求体
  - `do_dispatch()` 根据工具名称路由到对应的 execute 方法

- **Schema 嵌入** — 每个工具的 JSON Schema 通过 `$embed` 编译期嵌入二进制，实现零配置文件依赖。

### Skill System 技能系统

Skill 是可复用的专业化指令模板，本质上是一个 `SKILL.md` 文件：

```markdown
---
name: code-reviewer
description: A professional code reviewer specializing in C3
---

你是一个 C3 代码审查专家...

(具体的技能指令内容)
```

**加载位置（自动扫描）：**

| 优先级 | 路径 | 说明 |
|--------|------|------|
| 1 | `~/.agents/skills/<skill-name>/SKILL.md` | 全局技能（所有项目可用） |
| 2 | `.agents/skills/<skill-name>/SKILL.md` | 项目级技能（当前项目可用） |

**Skill 有效性校验：** 必须同时满足 — 名称非空 + 描述非空 + 正文非空。

**运行时集成：** 已安装的 Skill 列表会被注入到 system prompt 中，当任务匹配某个 Skill 的描述时，LLM 可通过 ReadFile 工具加载对应的 SKILL.md 文件获取详细指令。

### 对话管理

- **上下文结构 (`Context`)** — 维护完整的会话状态：
  - `messages` — 完整消息历史数组，支持 multi-turn
  - `session_id` — 基于时间戳的会话标识
  - 持有 `ToolHub`、`SkillHub`、`Flag` 的引用

- **System Prompt 组装：**
  ```
  [内置模板]  ← 动态注入 date / cwd / os
      +
  [AGENTS.md]  ← 如果存在
      +
  [已安装 Skill 列表]  ← XML 格式
  ```

- **消息类型支持：**
  - `system` — 系统指令
  - `user` — 用户输入
  - `assistant` — 模型回复（含可选 thinking content）
  - `tool` — 工具执行结果

### 推理循环 (Reasoning Loop)

`rat_loop.c3` 实现了经典的 ReAct（Reason + Act）循环：

```
┌──────────────────────────────────────────────┐
│                  RAT_LOOP                     │
│                                              │
│  ┌─────────┐    ┌──────────────┐             │
│  │ 获取输入 │───▶│ API 调用     │             │
│  │(用户/任务)│   │ completions()│             │
│  └─────────┘    └──────┬───────┘             │
│                        │                     │
│              ┌─────────▼─────────┐           │
│              │ 有 tool_call?      │           │
│              └─────┬────────┬────┘           │
│                    │ Yes    │ No             │
│          ┌─────────▼──┐  ┌──▼──────────┐    │
│          │ 执行工具    │  │ 输出回复     │    │
│          │ dispatch() │  │ 回到循环     │    │
│          └─────────┬──┘  └─────────────┘    │
│                    │                         │
│              ┌─────▼──────┐                  │
│              │ 结果注入    │                  │
│              │ messages   │                  │
│              └─────┬──────┘                  │
│                    └──── 回到 API 调用 ────── │
└──────────────────────────────────────────────┘
```

**运行模式：**
- **交互模式** — 等待用户输入 `>>> ` 提示符
- **Headless 模式** — 从参数/文件读取初始任务，一轮对话后输出 `DONE` 并退出
- **连续工具调用** — 如果 LLM 连续发出 tool_call，循环会先执行完所有工具再交还控制权给人类

### API 通信层

- **协议：** OpenAI-compatible Chat Completions API
- **端点：** `{baseUrl}/chat/completions`
- **非流式：** `stream: false`，等待完整响应
- **认证：** Bearer <REDACTED> (`Authorization: Bearer {apiKey}`)
- **HTTP 引擎：** 基于 libcurl，封装了 GET/POST 方法
- **Thinking 支持：** 携带 `"thinking": {"type": "enabled"}` 请求参数，响应中解析 `reasoning_content` 字段

---

## 内置工具详解

### ReadFile - 读取文件

读取文本文件内容，支持分页和行号显示。

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | string | ✅ | 文件路径（相对或绝对） |
| `offset` | number | ❌ | 起始行号（1-indexed），默认从第 1 行开始 |
| `limit` | number | ❌ | 最大读取行数，默认 2000 行 |

**实现要点：**
- 自动统一换行符（`\r\n` → `\n`）
- 输出带行号的格式化内容（右对齐，补零）
- 大文件自动截断，提示总行数和当前查看范围

### Bash - 执行命令

在 Shell 环境中执行命令，捕获 stdout+stderr。

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `command` | string | ✅ | 要执行的 bash 命令 |
| `timeout` | number | ❌ | 超时时间（秒），暂默认无限制 |

**实现要点：**
- 使用 `sh -c` 执行命令
- 自动关闭 stdin 防止命令等待输入
- 输出超过 **2000 行**时自动截断，完整输出保存到 `task_store/{id}_output.txt`
- 显示退出码（非零时提示）

### EditFile - 精确编辑

通过精确文本匹配来修改文件内容，适合局部修改。

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | string | ✅ | 要编辑的文件路径 |
| `oldText` | string | ✅ | 要替换的原文（必须完全匹配，包括空白和换行） |
| `newText` | string | ✅ | 替换后的新文本 |

**实现要点：**
- 不同于 `sed` 等流式编辑器，这是一个结构化编辑工具
- `oldText` 必须在文件中存在且唯一匹配，否则返回错误提示
- 自动统一换行符后再匹配

### WriteFile - 写入文件

创建新文件或完整覆盖已有文件。

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | string | ✅ | 文件路径 |
| `content` | string | ✅ | 要写入的内容 |

**实现要点：**
- 自动创建父目录
- 写入后返回成功确认

### Grep - 内容搜索

基于 `rg` (ripgrep) 的强大内容搜索工具。

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `pattern` | string | ✅ | 搜索模式（正则或字面量） |
| `path` | string | ❌ | 搜索目录或文件（默认当前目录） |
| `glob` | string | ❌ | 文件过滤 glob，如 `*.ts` |
| `ignoreCase` | boolean | ❌ | 忽略大小写（默认 false） |
| `literal` | boolean | ❌ | 将 pattern 视为字面字符串（默认 false） |
| `context` | number | ❌ | 匹配行前后上下文行数（默认 0） |
| `limit` | number | ❌ | 最大匹配数（默认 100） |

**实现要点：**
- 自动尊重 `.gitignore`
- 长行截断至 500 字符
- 支持 regex 和 fixed-strings 两种模式

### Glob - 文件查找

基于 `fd` 的文件名搜索工具。

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `pattern` | string | ✅ | Glob 模式，如 `*.ts`、`**/*.json` |
| `path` | string | ❌ | 搜索目录（默认当前目录） |
| `limit` | number | ❌ | 最大结果数（默认 1000） |

**实现要点：**
- 自动尊重 `.gitignore`
- 输出按字母排序
- 目录带 `/` 后缀标识

### ListDir - 目录列表

列出目录内容。

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | string | ❌ | 目标目录（默认当前目录） |
| `limit` | number | ❌ | 最大条目数（默认 500） |

**实现要点：**
- 使用 `ls -ahl` 列出详细信息
- 包含隐藏文件（dotfiles）
- 目录条目标识 `/` 后缀

### Task - 子代理

派生独立的子 Agent 执行特定任务，拥有干净的上下文环境。

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `agent` | string | ❌ | 子 Agent 角色名（默认 `default`） |
| `prompt` | string | ✅ | 任务详细内容 |
| `description` | string | ✅ | 任务的简短描述 |

**实现要点：**
- 子 Agent 作为独立进程启动：`mp --agent {name} --headless -f {input} -o {output}`
- 输入/输出文件存储在 `task_store/` 目录
- 子 Agent 完全隔离上下文，完成后返回结果摘要

---

## 命令行使用

```
mp - a coding agent, my own coding agent.

flags:
    --config, -c      指定配置目录
    --agent           指定智能体角色，默认为 default
    --tools           允许使用的工具列表，默认值是 read,bash,edit,write,grep,find,ls
    --task, -t        指定默认任务
    --task-file, -f   从指定文件中读出内容，并设置为默认任务
    --output-file, -o 将最后一次 LLM 回复输出到指定文件
    --headless        设置为非交互模式，一轮对话后会自动退出

    --model           指定使用的模型 ID，默认 'Any'
    --base-url        指定 OpenAI-compatible API base URL，默认 'http://127.0.0.1:5678'
    --api-key         指定 Completions API key，默认 'sk-1234'

    --list-skills     列出全部可用 skill

    --help            显示帮助信息
    --version         查看版本号
    --debug           启动 DEBUG 模式
```

**示例：**

```bash
# 自定义模型和 API 连接
mp --model "claude-sonnet-4" --base-url "https://api.anthropic.com/v1" --api-key "sk-xxx"

# 限制可用工具
mp --tools "ReadFile,Bash,WriteFile"

# Debug 模式（保存请求/响应到 log/ 目录）
mp --debug -t "分析这段代码"

# Headless 执行 + 输出到文件
mp --headless -t "生成本周报告" -o report.md
```

---

## 配置说明

### 默认配置

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `model` | `Any` | 模型 ID |
| `baseUrl` | `http://127.0.0.1:5678` | API 端点 |
| `apiKey` | `sk-1234` | 认证密钥 |
| `tools` | `ReadFile,Bash,EditFile,WriteFile,Grep,Glob,ListDir,Task` | 可用工具集 |
| `config_dir` | `~/.config/mp` | 配置文件目录 |
| `agent` | `default` | Agent 角色 |

### AGENTS.md

在项目根目录放置 `AGENTS.md` 文件，其内容会自动追加到 system prompt 中。适合存放：
- 项目特定的编码规范
- 架构约定
- 常用命令快捷方式

### 工具白名单

通过 `--tools` 参数可以限制 Agent 可使用的工具，提升安全性：

```bash
# 只读模式 — Agent 只能查看文件，不能执行命令
mp --tools "ReadFile,Glob,ListDir,Grep"

# 开发模式 — 移除 Task 工具以节省 token
mp --tools "ReadFile,Bash,EditFile,WriteFile,Grep,Glob,ListDir"
```

---

## 开发笔记

### 技术栈

- **语言：** C3（一个注重互操作性的系统编程语言）
- **HTTP 客户端：** libcurl
- **JSON 处理：** `c3x::object`（C3 生态的 JSON 库）
- **内存管理：** 基于 arena allocator（`tmem`），模块级内存池

### 设计决策

1. **Schema 嵌入 (`$embed`)** — 工具的 JSON Schema 在编译期嵌入二进制，运行时零文件依赖，发布单文件即可。

2. **非流式 API** — 当前使用 `stream: false`，简化循环逻辑且兼容更多 API 提供商。

3. **工具多态分发** — 通过 C3 的 interface + 动态分发实现，新增工具只需实现 `Tool` interface 并在 `ToolHub.init` 中注册。

4. **子 Agent 进程隔离** — Task 工具通过 `cmd::execute` 启动独立 `mp` 进程，彻底隔离内存和上下文，避免污染主对话。

### 目录结构

```
src/
├── main.c3                  # 入口
├── cli.c3                   # 命令行解析
├── global.c3                # 全局状态
├── version.c3               # 版本号
├── rat_loop.c3              # 推理循环
├── skill.c3                 # Skill 系统
├── api/
│   ├── api.c3               # LLM API 调用
│   └── http_client.c3       # HTTP 客户端
├── context/
│   ├── context.c3           # 上下文管理
│   └── system_prompt_template.md  # 系统提示模板
├── tool/
│   ├── tool.c3              # Tool interface + ToolHub
│   ├── common.c3            # 工具共享工具函数
│   ├── bash_tool.c3         # Bash 工具
│   ├── read_file_tool.c3    # ReadFile 工具
│   ├── write_file_tool.c3   # WriteFile 工具
│   ├── edit_file_tool.c3    # EditFile 工具
│   ├── grep_tool.c3         # Grep 工具
│   ├── glob_tool.c3         # Glob 工具
│   ├── list_dir_tool.c3     # ListDir 工具
│   ├── task_tool.c3         # Task 工具
│   └── *_tool_schema.json   # 工具 JSON Schema 定义
└── util/
    ├── cmd.c3               # 命令执行
    ├── id.c3                # ID 生成
    ├── strings.c3           # 字符串工具
    └── parse_markdown.c3    # Markdown 解析 (frontmatter)
```

### 未来方向

- [ ] 从配置文件读取 apiKey / baseUrl（当前硬编码在 CLI 默认值）
- [ ] 流式 API 支持 (`stream: true`)
- [ ] 工具执行超时控制
- [ ] 会话持久化（导出/导入对话历史）
- [ ] Skill 依赖管理与版本控制
