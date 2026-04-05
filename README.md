# mp (mini-pi)

**a pi coding agent clone, my own coding agent.**

## 架构图

```mermaid
flowchart TB
    subgraph Entry["入口层 (main.c3)"]
        main["main()"]
        init["InitOptions 配置"]
        loop["agent_loop()"]
        read_in["read_input()"]
        print["print_last_message()"]
    end

    subgraph Core["核心层 (context.c3)"]
        ctx["Context\n上下文结构体"]
        msg["Message\n消息结构体"]
        tc["ToolCall\n工具调用结构体"]
        opts["InitOptions\n初始化选项"]
    end

    subgraph HTTP["HTTP 层 (http/)"]
        subgraph Client["http_client.c3"]
            http["HttpClient"]
            resp["Response"]
            get["get()"]
            post["post()"]
            request["request()"]
        end

        subgraph API["openai_completions.c3"]
            send["send_completion_request()"]
            parse["read_response_to_message()"]
            req_body["RequestBody"]
            msg_view["MessageView"]
            tc_view["ToolCallView"]
        end
    end

    subgraph Tools["工具系统 (tools/)"]
        subgraph Pool["tools.c3"]
            pool["ToolPool\n调度中心"]
            schema["schema()"]
            dispatch["dispatch()"]
            tool_if["Tool Interface"]
        end

        bash["BashTool"]
        edit["EditTool"]
        write["WriteTool"]
        grep["GrepTool"]
        ls["LsTool"]
        read_t["ReadTool"]
        find_t["FindTool"]
    end

    subgraph Cmd["命令层 (cmd.c3)"]
        exec["execute()"]
        result["CommandResult"]
    end

    subgraph Utils["工具函数 (util.c3)"]
        esc["escape() JSON转义"]
        ts["timestamp_id() 时间戳"]
        dump["dump() 宏/日志保存"]
        fmt["error_message() / system_message()"]
    end

    subgraph External["外部依赖"]
        cl["curl.c3l\nlibcurl 绑定"]
        c3x["c3x::object\nJSON 序列化/反序列化"]
    end

    main --> init --> ctx --> loop
    
    loop <--> read_in
    loop <--> print
    
    loop --> send
    send --> req_body
    req_body --> msg_view
    send --> http
    http --> post
    request --> cl
    
    send <--> parse
    parse --> msg
    send --> dump
    
    loop --> pool
    pool --> tool_if
    pool --> schema
    
    pool --> dispatch
    dispatch --> bash
    dispatch --> edit
    dispatch --> write
    dispatch --> grep
    dispatch --> ls
    dispatch --> read_t
    dispatch --> find_t
    
    bash --> exec
    edit --> exec
    write --> exec
    grep --> exec
    ls --> exec
    read_t --> exec
    find_t --> exec
    
    ts --> dump
```

## 命令行用法

```bash
mp [选项]
```

### 选项

| 开关 | 说明 | 默认值 |
|------|------|--------|
| `--agent <name>` | Agent 名称 | `default` |
| `--model <model_id>` | 模型 ID | `minimax.com/MiniMax-M2.7` |
| `--headless` | 无交互模式 | - |
| `--init-message <msg>` | 启动时发送的初始消息，需要同时设置 `--headless` | `""` |
| `--help`，`-h` | 显示帮忙信息 | |
| `--version`，`-v` | 显示版本号 | |


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
- [x] 命令行参数支持 (InitOptions)
- [x] 基础审计日志 (请求/响应自动转储至 logs/)
- [ ] 多 agent 支持
- [ ] 支持 Ralph loop 模式
- [ ] skills 支持
- [x] 集成 JSON 库 (已使用 c3x::object)

## 更新 libcurl-x64.dll

curl 官方的 windows 版本只提供了 mingw-w64 的 .a 文件，没有 msvc 编译需要的 .lib，可以从 .def 文件生成 .lib：

> 需要 msvc，可以使用 [portable-msvc.py](https://gist.github.com/mmozeiko/7f3162ec2988e81e56d5c4e22cde9977) 安装便携版。

设置 msvc prompt 里执行：

```cmd
lib.exe /def:libcurl-x64.def /out:lib/curl.c3l\windows-x64\libcurl.lib /machine:x64
```

## LICENSE

MIT
