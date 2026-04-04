# mini-pi (mp)

## 架构图

```mermaid
flowchart TB
    subgraph Entry["入口层 (main.c3)"]
        main["main()"]
        init["InitOptions 配置"]
        loop["agent_loop()"]
        read["read_input()"]
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
        end

        bash["BashTool"]
        edit["EditTool"]
        write["WriteTool"]
        grep["GrepTool"]
        ls["LsTool"]
        read["ReadTool"]
    end

    subgraph Cmd["命令层 (cmd.c3)"]
        exec["execute()"]
        exec_str["execute_to_string()"]
        result["CommandResult"]
    end

    subgraph Utils["工具函数 (util.c3)"]
        esc["escape() JSON转义"]
        ts["timestamp_id() 时间戳"]
        dump["dump() 日志保存"]
        fmt["error_message() / system_message()"]
    end

    subgraph External["外部依赖 (lib/)"]
        cl["curl.c3l HTTP绑定"]
    end

    main --> init
    init --> opts
    opts --> ctx
    ctx --> loop
    
    loop <--> read
    loop <--> print
    
    loop --> send
    send --> req_body
    req_body --> msg_view
    send --> http
    http --> post
    post --> request
    request --> cl
    
    send <--> parse
    parse --> msg
    parse <--> tc_view
    
    send --> dump
    
    parse --> ctx
    loop --> ctx
    
    loop --> pool
    pool --> schema
    
    pool --> dispatch
    dispatch --> bash
    dispatch --> edit
    dispatch --> write
    dispatch --> grep
    dispatch --> ls
    dispatch --> read
    
    bash --> exec
    edit --> exec
    write --> exec
    grep --> exec
    ls --> exec
    read --> exec
    
    exec --> result
    exec --> exec_str
    
    ts --> dump
```

## 模块说明

| 模块 | 文件 | 职责 |
|------|------|------|
| **入口层** | `main.c3` | 程序入口、Agent 主循环、用户输入读取 |
| **核心层** | `context.c3` | Context/Message/ToolCall 等核心数据结构 |
| **HTTP 层** | `http/http_client.c3` | HTTP 客户端封装 (GET/POST/request) |
| **API 层** | `http/openai_completions.c3` | OpenAI Chat Completions API 集成 |
| **工具系统** | `tools/tools.c3` | ToolPool 调度中心及 6 个内置工具 |
| **命令层** | `cmd.c3` | 外部进程执行 (execute/execute_to_string) |
| **工具函数** | `util.c3` | JSON 转义、时间戳、日志保存等 |
| **外部依赖** | `lib/` | libcurl 绑定 |

这个 coding agent 是我在学习 Ralph loop 时的一个想法。

Ralph loop 号称 All you need is bash，本身是通过 Loop 让 coding agent 不断完成任务。我认为 plan-with-files 等等都可以认为是 Ralph loop 的一种变形。我原计划是实现一个简单的 js 脚本用于实现我自己的 Ralph loop。但是我发现在执行过程会缺少审计日志，无法知晓当前进度，这是一个痛点。

我也使用过比如 OpenCode 内部集成的 Ralph loop，但是本质是一个 Coding agent 进程完成各个任务。这样就容易出现 80G 内存的占用。

我的解法是自制软件。基于 pi-coding-agent 也是一个好想法，不过我更倾向自己开发。pi 有很多拓展功能，明显我是不需要的。因此我参考 pi 的设计，开发这个 coding agent。

## TODOs

- [x] Agent loop
  - [x] 支持 OpenAI Chat Completions API
  - [x] 多轮交互
  - [x] 支持调用工具
- [x] 工具
  - [x] read
  - [x] ls
  - [x] grep
  - [x] edit
  - [x] write
  - [x] bash
- [x] 第一次重构
  - [x] 分层 ui-loop-request
  - [x] 集成 libcurl
  - [x] 日志转储 (dump)
- [x] 命令行参数支持 (InitOptions)
- [ ] 多 agent 支持
- [ ] 支持 Ralph loop
- [ ] skills 支持
- [ ] 审计日志
- [ ] 集成 cjson (已使用 std::encoding::json)


## 更新 libcurl-x64.dll

curl 官方的 windows 版本只提供了 mingw-w64 的 .a 文件，没有 msvc 编译需要的 .lib，可以从 .def 文件生成 .lib：

> 需要 msvc，可以使用 [portable-msvc.py](https://gist.github.com/mmozeiko/7f3162ec2988e81e56d5c4e22cde9977) 安装便携版。

设置 msvc prompt 里执行：

```cmd
lib.exe /def:libcurl-x64.def /out:lib/curl.c3l\windows-x64\libcurl.lib /machine:x64
```

## LICENSE

MIT
