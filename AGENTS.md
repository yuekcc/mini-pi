当前项目 `mp` 是用 c3 语言实现的一个 coding agent，灵感来自 Pi。版本 0.2.0。

## 关键目录结构

```sh
/src                 # 源代码目录
    /api             # LLM API 与 HTTP 客户端
        api.c3            # OpenAI Chat Completions（流式 SSE）
        http_client.c3    # 基于 curl.c3l 的 HttpClient 封装
    /context          # 核心数据结构
        context.c3         # Context / Message / ToolCall，系统提示词装配
        system_prompt_template.md  # 系统提示词模板
    /tool             # 工具系统
        tool.c3            # ToolHub 调度中心、Tool 接口
        common.c3          # 共享工具函数（task_store 路径）
        *_tool.c3          # 9 个内置工具实现
        *_schema.json      # 各工具的 JSON Schema
    /util             # 工具函数
        cmd.c3             # 子进程执行
        hash.c3            # 行哈希（FNV-1a，hashline 锚点）
        id.c3             # 时间戳 ID、路径哈希
        strings.c3         # 行尾归一化等字符串工具
        parse_markdown.c3  # Markdown + YAML frontmatter 解析
    main.c3           # 程序入口
    cli.c3            # Flag 解析、默认值
    rat_loop.c3       # Agent 主循环（交互 / headless）
    skill.c3          # Skill 加载（~/.agents/skills 与 .agents/skills）
    global.c3         # 线程级单例 GlobalStore
    log.c3            # 分级日志宏（debug/info/warn/error）
    ui.c3             # 终端渲染、NO_COLOR 支持
    version.c3        # 版本号
/test                 # 单元测试目录（14 个测试文件）
/lib                  # 三方库目录
    /cjson.c3l         # json 处理库
    /curl.c3l          # libcurl 在 c3 的绑定
/resources            # 内置资源
    /agents            # 6 个预设 Agent 定义（designer/explorer/fixer/librarian/oracle/orchestrator）
    /skills            # 内置 skill（prd）
    /error_responses   # 错误响应样本
/scripts              # 构建/发布脚本
/docs                 # 文档目录
project.json          # 项目定义（version 0.2.0）
```

## 开发命令

```sh
# 构建（开发）
c3c build

# 发布构建
sh scripts/release.sh        # 等价于 c3c build --trust=full -O2 -D RELEASE

# 安装到本地（构建后拷贝到 /D/app/mp-agent）
sh scripts/install.sh

# 执行全部单元测试
c3c test

# 执行某个单元测试并打印单元测试的 stdout
c3c test --test-filter test_execute_to_string --test-show-output
```

## 运行

构建产物为 `build/mp`（Windows 下 `build/mp.exe`），运行时依赖同目录下的 `libcurl-x64.dll`。

```sh
# 交互模式
mp

# 非交互模式
mp --headless --task "请帮我创建一个 hello world 程序"
```

完整命令行参数见 [docs/flags.md](docs/flags.md)。

## 外部依赖

运行时依赖系统中的 `rg`（ripgrep）、`fd`、`ls`、`sh`，分别被 Grep / Glob / ListDir / Bash 工具调用。`Task` 工具会以子进程方式递归调用 `mp` 自身。

## 参考

- [c3 语言简介](docs/c3_intro.md)
- [c3 语言学习笔记](docs/learn-c3.md)
- [架构设计](docs/arch.md)
- [命令行参数](docs/flags.md)
- [配置目录](docs/config.md)
- [更新 libcurl](docs/update-libcurl.md)
