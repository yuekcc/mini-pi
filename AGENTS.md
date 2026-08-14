当前项目 `mp` 是用 c3 语言实现的一个 coding agent，灵感来自 Pi。版本 2.0.0（三线程架构）。

## 目录结构

```sh
/src
    /api          # LLM API（请求构造、SSE 解析、curl multi 执行）与 API worker 线程
    /app          # AppContext（统一全局状态）+ TokenLedger + 事件类型/通道
    /context      # 消息类型与系统提示词装配（含 3 个 prompt 模板）
    /tool         # 工具系统（ToolHub + 工具实现 + JSON Schema）
    /util         # 通用工具（子进程、哈希、ID、输入轮询、Ctrl+C、Markdown 解析）
    transcript.c3 # TranscriptWriter（会话 JSONL 落盘，支撑 --resume，schema v1）
    main.c3 / cli.c3 / rat_loop.c3 / skill.c3 / log.c3 / ui.c3 / version.c3
/test             # 单元测试（80 个，含进程级集成与中断注入）
/lib              # 三方库（c3l 子模块）：cjson、curl
/resources        # 内置资源：agents(6) / skills(prd) / error_responses
/scripts          # 构建/发布脚本
/docs             # 文档
project.json      # 项目定义（version 2.0.0）
```

## 线程模型（v2 核心）

- **主线程（UI）**：AppContext 初始化与所有权；渲染/日志/notice 事件循环；stdin 轮询；Ctrl+C 分流（L1/L3 + 杀工具子进程）；shutdown 协调。
- **Agent 线程**：显式状态机（IDLE / AWAITING_API / EXECUTING_TOOLS / CANCELLING / SHUTDOWN），turn 管理、工具串行调度、transcript 全部事件写入、token 记账。
- **API worker 线程**：收请求快照 → curl multi 事件循环（100ms 轮询 cancel_flag）→ SSE 解析 → 回报。

通道：ui→agent（unbounded）/ agent→ui（unbounded）/ agent→api（buffered 1）/ api→agent（unbounded）。共享可变原语只有四处：`cancel_flag`（atomic）、`g_current_child_handle`（atomic，L2 杀子进程）、`g_ctrl_c`（atomic，Ctrl+C handler 单写 / 主循环读）、Logger 文件句柄（mutex）。

## 约定与陷阱（看代码不易发现的）

- **注册的工具**：`ReadFile / Bash / HashEditFile / WriteFile / Grep / Glob / ListDir / Task`（见 `tool.c3` 的 `switch` 与 `cli.c3` 的 `DEFAULT_TOOLS`）。编辑请用 `HashEditFile`（基于 `ReadFile` 输出的 `line:hash` 锚点）。
- **系统提示词会自动注入 cwd 下的 `AGENTS.md`**（包在 `<project_instructions>` 中）以及已安装 skill 列表。改了 AGENTS.md 会直接影响 agent 行为。
- **`Task` 工具递归调用 `mp` 自身**：通过 `MP_PARENT_SESSION` 环境变量串联父-子会话，并继承 `--no-transcript` 与 headless 续跑参数。父会话信息从 `ToolContext`（AppContext 的轻量视图）读取。
- **Transcript**：每次会话以 JSONL 追加写入 `<config_dir>/transcripts/<session_id>.jsonl`（`--no-transcript` 关闭）。全部事件只在 Agent 线程写（无需锁）。`--resume <session_id>` 从该文件重建消息续跑（system prompt 用快照，丢弃未收尾的最后一轮）。设计见 docs/transcript.md。
- **中断语义**：Ctrl+C 三级——L1 请求中断（worker 取消 → `request_cancelled` 事件 → 丢弃半成品 turn）、L2 工具中断（taskkill 杀进程树 → `tool_cancelled` 事件 → 丢弃半成品 turn）、L3 空闲中断（等价 /exit）。headless 中断 = 优雅停机（`session_end(reason=interrupted)` + exit 1）。
- **内存规则**：跨线程通道负载一律 `&allocators::LIBC_ALLOCATOR` 堆分配，接收方显式释放；`tmem` 仅限线程内临时值；新线程必须 `@pool_init` 包裹（否则 panic）；传给 C 函数（curl 等）的字符串必须 NUL 结尾；`String.free` 前注意静态 `""` 不可 free（len 守卫）。
- **tool ↔ app 循环 import**：c3 0.8.3 不支持循环 import，工具接口收 `ToolContext*` 而非 `AppContext*`。
- **c3 0.8.3 不支持模块级 `$if`**：平台条件编译只能写在函数体内；平台 extern 声明一律无条件声明（未使用平台不引用，不参与链接）。
- **杀子进程必须整树击杀**（Windows `taskkill /F /T`，且 spawn 必须 `INHERIT_ENV`，否则 taskkill 报「module could not be found」）：孙进程继承 stdout 管道写端，只杀 sh 管道不 EOF、read_stdout 挂到孙进程退出。
- **版本号**：非 RELEASE 硬编码 `2.0.0`；RELEASE 构建由 `scripts/version.sh` 注入 `2.0.0-<commit>`。
- **外部运行时依赖**：`rg`(ripgrep)、`fd`、`sh`，分别被 Grep / Glob / Bash 调用，需系统已安装。`ListDir` 是纯 c3 实现（用 `std::io::path::ls`），无外部命令依赖。

## 开发命令

```sh
c3c build                              # 开发构建
sh scripts/release.sh                  # 发布构建（c3c clean + c3c build --trust=full -O2 -D RELEASE）
sh scripts/install.sh                  # 构建后拷贝到 /D/app/mp-agent
sh scripts/build_cjson_lib.sh          # 显式重编 cjson 静态库（一般自动重编，无需手动）
c3c test                               # 全部单元测试
c3c test --test-filter <name> --test-show-output   # 单测 + 打印 stdout
```

## 运行

```sh
mp                                      # 交互模式
mp --headless --task "..."              # 非交互模式
mp --resume <session_id>                # 从 transcript 恢复会话
mp --no-transcript                      # 关闭 transcript 写入
mp --max-tokens <n>                     # token 预算上限（软 0.8 / 硬 0.95 阈值）
```

交互命令：`/exit` `/clear` `/export` `/usage`（累计 token 用量）。完整参数见 [docs/flags.md](docs/flags.md)。构建产物 `build/mp(.exe)` 运行时依赖同目录的 `libcurl-x64.dll`。

## 参考

- [c3 语言简介](docs/c3-intro.md)
- [架构设计](docs/arch.md) / [v2 架构方案](docs/arch-next.md) / [v2 实施规格](docs/arch-next-spec.md)
- [命令行参数](docs/flags.md)
- [配置目录](docs/config.md)
- [Transcript 设计](docs/transcript.md)
- [更新 libcurl](docs/update-libcurl.md)
