# mp (mini-pi)

**a pi coding agent clone, my own coding agent.**


## 命令行用法

```bash
mp [选项]
```

### 选项

见 [docs/flags.md](docs/flags.md)

## 架构图

见 [docs/arch.md](docs/arch.md)

## 模块说明

| 模块 | 文件 | 职责 |
|------|------|------|
| **入口层** | `main.c3` | 程序入口、Agent 主循环、用户输入读取、消息打印 |
| **核心层** | `context.c3` | Context/Message/ToolCall/InitOptions 等核心数据结构 |
| **HTTP 层** | `http/http_client.c3` | HTTP 客户端封装 (GET/POST/request)，基于 curl |
| **API 层** | `http/openai_completions.c3` | OpenAI Chat Completions API 集成、请求构建、响应解析 |
| **工具系统** | `tools/tools.c3` | ToolPool 调度中心、Tool 接口定义 |
| **工具实现** | `tools/*_tool.c3` | 7 个内置工具：bash, edit, write, grep, ls, read, find |
| **命令层** | `cmd.c3` | 外部进程执行 (execute) |
| **工具函数** | `util.c3` | JSON 转义、时间戳、日志转储 (宏)、ANSI 格式化 (宏) |
| **外部依赖** | `lib/` | `curl.c3l` (libcurl 绑定), `c3x::object` (JSON 处理) |

## TODOs

- [x] Agent loop
  - [x] 支持 OpenAI Chat Completions API
  - [x] 多轮交互
  - [x] 支持调用工具
  - [x] 支持 thinking 配置
- [x] 工具 (7/7)
  - [x] read
  - [x] ls
  - [x] grep
  - [x] edit
  - [x] write
  - [x] bash
  - [x] find (基于 fd)
- [x] 第一次重构
  - [x] 分层 ui-loop-request
  - [x] 集成 libcurl
  - [x] 日志转储 (dump 宏)
  - [x] 集成 JSON 库 (已使用 c3x::object)
- [ ] 第二次重构
  - [ ] 改为基于 thread pool 的 event-loop 模式
  - [ ] 增加工具事件
  - [ ] 在 `~/.cache/mp/workspace/${project_name}_${sessionId}` 目录保存日志
- [x] 命令行参数支持 (InitOptions)
- [x] 基础审计日志 (请求/响应自动转储至 logs/)
- [ ] 多 agent 支持
  - [ ] 通过 --agent 指定 agent
  - [ ] 通过 --agent-list 列出全部 agent
  - [ ] 支持不同的 agent 配置不同的工具
- [ ] 支持 Ralph loop 模式
- [ ] skills 支持
- [x] 支持 AGENTS.md 文件


## 更新 libcurl-x64.dll

curl 官方的 windows 版本只提供了 mingw-w64 的 .a 文件，没有 msvc 编译需要的 .lib，可以从 .def 文件生成 .lib：

> 需要 msvc，可以使用 [portable-msvc.py](https://gist.github.com/mmozeiko/7f3162ec2988e81e56d5c4e22cde9977) 安装便携版。

设置 msvc prompt 里执行：

```cmd
lib.exe /def:libcurl-x64.def /out:lib/curl.c3l\windows-x64\libcurl.lib /machine:x64
```

## LICENSE

MIT
