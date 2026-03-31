# mini-pi (mp)

## 架构图

```plantuml
@startuml mini-pi-architecture
!theme plain

title mini-pi 架构图

package "入口层 (main.c3)" {
    [main()\n程序入口] as Entry
    [agent_loop()\nAgent 主循环] as AgentLoop
    [InitOptions\n初始化配置] as InitOpts
}

package "核心层 (core.c3)" {
    [Context\n上下文结构体] as Context
    [Message\n消息结构体] as Message
    [ToolCall\n工具调用结构体] as ToolCall
    [push_message()\n添加消息] as PushMsg
}

package "API 层 (openai-completions.c3)" {
    [send_completion_request()\n发送请求] as SendReq
    [build_request()\n构建请求体] as BuildReq
    [read_response_to_message()\n解析响应] as ParseResp
}

package "HTTP 层 (http_client.c3)" {
    [HttpClient\nHTTP 客户端] as HttpClient
    [libcurl\nC URL 库] as LibCurl
}

package "工具系统" {
    [tools.c3] {
        [ToolPool\n工具调度中心] as ToolPool
        [tool_core.c3] {
            [bash\n执行 Shell] as Bash
            [edit\n编辑文件] as Edit
            [write\n写入文件] as Write
            [read\n读取文件] as Read
            [grep\n搜索内容] as Grep
            [find\n查找文件] as Find
            [ls\n列出目录] as Ls
        }
    }
}

package "命令层 (cmd.c3)" {
    [execute()\n执行命令] as Execute
    [process::SubProcess\n子进程] as SubProcess
}

package "工具函数 (util.c3)" {
    [escape()\nJSON 转义] as Escape
    [timestamp_id()\n时间戳] as Timestamp
}

package "外部依赖 (lib/)" {
    [curl.c3l\nHTTP 绑定] as CurlLib
    [cjson.c3l\nJSON 解析] as CJson
}

' 数据流关系
Entry --> InitOpts : 配置
Entry --> Context : 初始化
Context --> AgentLoop : 运行

AgentLoop --> SendReq : 发送请求
SendReq --> BuildReq : 构建请求
BuildReq --> HttpClient : HTTP POST
HttpClient --> LibCurl : 调用 curl
BuildReq <-- ParseResp : 解析响应
ParseResp --> Context : 更新消息

AgentLoop --> PushMsg : 添加消息
PushMsg --> Context

' 工具调用流程
AgentLoop --> ToolPool : 分发工具
ToolPool --> Bash
ToolPool --> Edit
ToolPool --> Write
ToolPool --> Read
ToolPool --> Grep
ToolPool --> Find
ToolPool --> Ls

Bash --> Execute
Edit --> Execute
Write --> Execute
Read --> Execute
Grep --> Execute
Find --> Execute
Ls --> Execute

Execute --> SubProcess : 创建进程

' 外部依赖
ParseResp --> CJson : JSON 解析
HttpClient --> CurlLib : HTTP 请求

@enduml
```

## 模块说明

| 模块 | 文件 | 职责 |
|------|------|------|
| **入口层** | `main.c3` | 程序入口、Agent 主循环 |
| **核心层** | `core.c3` | Context/Message 等核心数据结构 |
| **API 层** | `openai-completions.c3` | OpenAI Completions API 集成 |
| **HTTP 层** | `http.c3` | HTTP 客户端封装 |
| **工具系统** | `tools.c3` | 7 个内置工具及调度中心 |
| **命令层** | `cmd.c3` | 外部进程执行 |
| **工具函数** | `util.c3` | JSON 转义、时间戳等 |

这个 coding agent 是我在学习 Ralph loop 时的一个想法。

Ralph loop 号称 All you need is bash，本身是通过 Loop 让 coding agent 不断完成任务。我认为 plan-with-files 等等都可以认为是 Ralph loop 的一种变形。我原计划是实现一个简单的 js 脚本用于实现我自己的 Ralph loop。但是我发现在执行过程会缺少审计日志，无法知晓当前进度，这是一个痛点。

我也使用过比如 OpenCode 内部集成的 Ralph loop，但是本质是一个 Coding agent 进程完成各个任务。这样就容易出现 80G 内存的占用。

我的解法是自制软件。基于 pi-coding-agent 也是一个好想法，不过我更倾向自己开发。pi 有很多拓展功能，明显我是不需要的。因此我参考 pi 的设计，开发这个 coding agent。

## TODOs

- [x] Agent loop
  - [x] 支持 OpenAI Completions API (Text only)
  - [x] 多轮交互
  - [x] 支持调用工具
- [x] 工具
  - [x] read
  - [x] ls
  - [x] grep
  - [x] find
  - [x] edit
  - [x] write
  - [x] bash
- [ ] 第一次重构
  - [x] 分层 ui-loop-request
  - [x] 集成 libcurl
  - [ ] 集成 cjson
- [ ] 命令行参数支持 
- [ ] 多 agent 支持
- [ ] 支持 Ralph loop
- [ ] skills 支持
- [ ] 审计日志


## 更新 libcurl-x64.dll

curl 官方的 windows 版本只提供了 mingw-w64 的 .a 文件，没有 msvc 编译需要的 .lib，可以从 .def 文件生成 .lib：

> 需要 msvc，可以使用 [portable-msvc.py](https://gist.github.com/mmozeiko/7f3162ec2988e81e56d5c4e22cde9977) 安装便携版。

设置 msvc prompt 里执行：

```cmd
lib.exe /def:libcurl-x64.def /out:lib/curl.c3l\windows-x64\libcurl.lib /machine:x64
```

## LICENSE

MIT
