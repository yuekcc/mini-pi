当前项目 `mp` 是用 c3 语言实现的一个 coding agent，灵感来自 Pi。版本 1.0.0。

## 目录结构

```sh
/src
    /api          # LLM API 与 HTTP 客户端（OpenAI 流式 SSE）
    /context      # 核心数据结构与系统提示词装配（含 3 个 prompt 模板）
    /tool         # 工具系统（ToolHub + 工具实现 + JSON Schema）
    /util         # 通用工具（子进程、哈希、ID、字符串、Markdown 解析）
    transcript.c3 # 会话 JSONL 落盘，支撑 --resume（schema v1）
    main.c3 / cli.c3 / rat_loop.c3 / skill.c3 / global.c3 / log.c3 / ui.c3 / version.c3
/test             # 单元测试（16 个）
/lib              # 三方库（c3l 子模块）：cjson、curl
/resources        # 内置资源：agents(6) / skills(prd) / error_responses
/scripts          # 构建/发布脚本
/docs             # 文档
project.json      # 项目定义（version 1.0.0）
```

## 约定与陷阱（看代码不易发现的）

- **注册的工具**：`ReadFile / Bash / HashEditFile / WriteFile / Grep / Glob / ListDir / Task`（见 `tool.c3` 的 `switch` 与 `cli.c3` 的 `DEFAULT_TOOLS`）。旧 `EditFile`（逐字节文本匹配）已从工具注册表移除并删除源文件，编辑请用 `HashEditFile`（基于 `ReadFile` 输出的 `line:hash` 锚点）。
- **系统提示词会自动注入 cwd 下的 `AGENTS.md`**（包在 `<project_instructions>` 中）以及已安装 skill 列表。改了 AGENTS.md 会直接影响 agent 行为。
- **`Task` 工具递归调用 `mp` 自身**：通过 `MP_PARENT_SESSION` 环境变量串联父-子会话，并继承 `--no-transcript` 与 headless 续跑参数。
- **Transcript**：每次会话以 JSONL 追加写入 `<config_dir>/transcripts/<session_id>.jsonl`（`--no-transcript` 关闭）。`--resume <session_id>` 从该文件重建消息续跑（system prompt 用快照，丢弃未收尾的最后一轮）。设计见 docs/transcript.md。
- **版本号**：非 RELEASE 硬编码 `1.0.0`；RELEASE 构建由 `scripts/version.sh` 注入 `1.0.0-<commit>`。
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
```

完整参数见 [docs/flags.md](docs/flags.md)。构建产物 `build/mp(.exe)` 运行时依赖同目录的 `libcurl-x64.dll`。

## 参考

- [c3 语言简介](docs/c3-intro.md)
- [架构设计](docs/arch.md)
- [命令行参数](docs/flags.md)
- [配置目录](docs/config.md)
- [Transcript 设计](docs/transcript.md)
- [更新 libcurl](docs/update-libcurl.md)
