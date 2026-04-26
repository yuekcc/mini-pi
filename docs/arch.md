# 架构

## 模块说明

| 模块         | 文件                                     | 职责                                                                    |
| ------------ | ---------------------------------------- | ----------------------------------------------------------------------- |
| **入口层**   | `main.c3`                                | 程序入口、Agent 主循环、用户输入读取、消息打印                          |
| **配置层**   | `flags.c3`, `version.c3`                 | 命令行参数解析、版本信息管理                                            |
| **核心层**   | `context/`                               | Context/Message/ToolCall/InitOptions 等核心数据结构                     |
| **系统模板** | `context/system_prompt_template.md`      | 系统提示词模板，支持动态变量替换（cwd/date/os）                         |
| **HTTP 层**  | `http/http_client.c3`                    | HTTP 客户端封装 (GET/POST/request)，基于 libcurl                        |
| **API 层**   | `http/openai_completions.c3`             | OpenAI Chat Completions API 集成、请求构建、响应解析                    |
| **工具系统** | `tools/tools.c3`                         | ToolPool 调度中心、Tool 接口定义、工具注册与分发                        |
| **工具实现** | `tools/*_tool.c3`, `tools/*_schema.json` | 内置工具及其 JSON Schema：bash, edit, write, grep, ls, read, find, task |
| **命令层**   | `cmd.c3`                                 | 外部进程执行 (execute)、命令结果封装                                    |
| **工具函数** | `util.c3`                                | 路径哈希、时间戳、ANSI 格式化 (宏)、日志转储 (宏)、配置路径获取         |
| **外部依赖** | `lib/`                                   | `curl.c3l` (libcurl 绑定), `c3x::object` (JSON 处理)                    |


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
