# mp (mini-pi)

**a pi coding agent clone, my own coding agent.**

## 特性

- [x] Agent Loop
  - [x] 支持 OpenAI Chat Completions API
  - [x] 多轮对话
  - [x] 支持工具调用
- [ ] 多 agent 支持
  - [ ] 通过 --agent 指定 agent
  - [ ] 通过 --agent-list 列出全部 agent
  - [ ] 支持不同的 agent 配置不同的工具
- [ ] 支持 Ralph Loop 长任务模式
- [x] 内置工具 (7/7)
  - [x] read
  - [x] ls
  - [x] grep (依赖 [rg](github.com/BurntSushi/ripgrep))
  - [x] edit
  - [x] write
  - [x] bash
  - [x] find (依赖 [fd](https://github.com/sharkdp/fd))
- [x] 支持 AGENTS.md 文件(只支持当前目录)
- [x] 审计日志 `~/.config/mp/workspace/${project_name}/${sessionId}.jsonl`
- [x] 全局设置文件 `~/.config/mp/mp.json`

## 命令行用法

```bash
mp [选项]
```

### 选项

见 [docs/flags.md](docs/flags.md)

## 构建

需要最新版本 [c3c](https://github.com/c3lang/c3c/releases/tag/latest-prerelease-tag)

```sh
# 构建
c3c build

# 发布
sh scripts/release.sh
```

### 模块说明

| 模块         | 文件                         | 职责                                                  |
| ------------ | ---------------------------- | ----------------------------------------------------- |
| **入口层**   | `main.c3`                    | 程序入口、Agent 主循环、用户输入读取、消息打印        |
| **核心层**   | `context.c3`                 | Context/Message/ToolCall/InitOptions 等核心数据结构   |
| **HTTP 层**  | `http/http_client.c3`        | HTTP 客户端封装 (GET/POST/request)，基于 curl         |
| **API 层**   | `http/openai_completions.c3` | OpenAI Chat Completions API 集成、请求构建、响应解析  |
| **工具系统** | `tools/tools.c3`             | ToolPool 调度中心、Tool 接口定义                      |
| **工具实现** | `tools/*_tool.c3`            | 7 个内置工具：bash, edit, write, grep, ls, read, find |
| **命令层**   | `cmd.c3`                     | 外部进程执行 (execute)                                |
| **工具函数** | `util.c3`                    | JSON 转义、时间戳、日志转储 (宏)、ANSI 格式化 (宏)    |
| **外部依赖** | `lib/`                       | `curl.c3l` (libcurl 绑定), `c3x::object` (JSON 处理)  |

### 架构图

见 [docs/arch.md](docs/arch.md)

### 更新 libcurl

见 [docs/update-libcurl.md](docs/update-libcurl.md)
