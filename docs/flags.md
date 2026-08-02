# 命令行参数说明

`mp` 是一个 coding agent。

## 参数列表

| 参数                     | 说明                                                           | 默认值                                                        |
| ------------------------ | -------------------------------------------------------------- | ------------------------------------------------------------- |
| `--config, -c <path>`    | 指定配置目录                                                   | `~/.config/mp/`                                               |
| `--agent <name>`         | 指定智能体角色名称                                             | `default`                                                     |
| `--model <id>`           | 指定使用的模型 ID                                              | `Any`                                                         |
| `--base-url <url>`       | 指定 OpenAI 兼容 API 的 base URL                               | `http://127.0.0.1:5678`                                       |
| `--api-key <key>`        | 指定 Completions API key                                       | `sk-1234`                                                     |
| `--tools <list>`         | 允许使用的工具列表（逗号分隔）                                 | `ReadFile,Bash,HashEditFile,WriteFile,Grep,Glob,ListDir,Task` |
| `--headless`             | 启用非交互模式                                                 | 交互模式（默认）                                              |
| `--task, -t <msg>`       | 指定初始任务内容                                               | -                                                             |
| `--task-file, -f <path>` | 从指定文件读取内容作为初始任务（与 `--task` 互斥，优先）       | -                                                             |
| `--output-file, -o <p>`  | 将最后一次 LLM 的回复内容输出到指定文件（常配合 `--headless`） | -                                                             |
| `--list-skills`          | 列出全部可用 skill                                             | -                                                             |
| `--help, -h`             | 显示帮助信息                                                   | -                                                             |
| `--version, -v`          | 显示版本号                                                     | -                                                             |
| `--debug`                | 启动 DEBUG 模式，将 HTTP 请求/响应转储到 `logs/` 目录          | -                                                             |

## 详细说明

### `--config, -c <path>`

指定配置目录的路径。配置目录中存放日志、task_store 等运行时数据，结构见 [config.md](config.md)。

实际写入位置：

- 日志文件：`<config_dir>/log/<session_id>.log`
- Bash / Task 工具的中间产物：`<config_dir>/task_store/<id>_output.txt`

### `--agent <name>`

指定智能体角色的名称，用于区分不同的 Agent 配置。当前版本预留，尚未实现多 agent 差异化配置。

### `--model <id>`

指定要使用的 AI 模型 ID，格式为 `provider/model-name`，透传给 Chat Completions API 的 `model` 字段。

### `--base-url <url>`

OpenAI 兼容 API 的 base URL。实际请求地址为 `<base_url>/chat/completions`。

### `--api-key <key>`

Completions API key，以 `Authorization: Bearer <key>` 形式发送。

### `--tools <list>`

设置允许使用的工具列表，可用的工具包括：

| 工具           | 说明                                          |
| -------------- | --------------------------------------------- | ----------------- |
| `ReadFile`     | 读取文件内容，输出 `line:hash                 | content` 锚点格式 |
| `Bash`         | 执行 shell 命令（`sh -c`）                    |
| `HashEditFile` | 基于行哈希锚点的编辑，支持批量原子提交        |
| `WriteFile`    | 写入/创建文件                                 |
| `Grep`         | 基于 ripgrep 的文本搜索                       |
| `Glob`         | 基于 fd 的文件查找                            |
| `ListDir`      | 列出目录内容                                  |
| `Task`         | 启动子 agent 执行子任务（递归调用 `mp` 自身） |

多个工具用逗号分隔。工具按列表顺序注册到 ToolHub，未列出的工具不可用。

### `--headless`

以非交互模式运行，不启动交互式界面。在此模式下，程序接收初始任务后自动执行 Agent Loop，完成一轮对话后退出。通常与 `--task`（或 `--task-file`）和 `--output-file` 配合使用。

### `--task, -t <msg>`

设置程序启动时的初始任务内容。需与 `--headless` 配合使用。

```bash
mp --headless --task "请帮我创建一个 hello world 程序"
```

### `--task-file, -f <path>`

从指定文件读取内容作为初始任务。当 `--task` 和 `--task-file` 同时指定时，`--task-file` 优先。

```bash
mp --headless --task-file prompt.txt
```

### `--output-file, -o <path>`

将最后一次 LLM 的回复内容写入指定文件。通常与 `--headless` 配合，用于批处理任务的输出收集。

### `--list-skills`

列出全部可用的 skill。skill 从 `~/.agents/skills/*/SKILL.md`（全局）和 `.agents/skills/*/SKILL.md`（本地）加载。

### `--debug`

启用 DEBUG 模式。在此模式下：

- 所有 HTTP 请求体转储到 `logs/req_<request_id>.json`
- 所有 HTTP 响应体转储到 `logs/req_<request_id>_<status_code>.json`
- `log::debug` 输出生效（默认静默）

方便排查 API 交互问题。

## 配置文件

当前所有参数通过命令行 flag 传入，`~/.config/mp/mp.json` 全局配置文件读取尚未实现。

## 使用示例

```bash
# 显示帮助信息
mp --help

# 显示版本号
mp --version

# 交互模式（默认）
mp

# 指定模型与 base url 运行
mp --model provider/custom-model --base-url http://localhost:1234

# 非交互模式执行任务
mp --headless --task "请帮我创建一个 hello world 程序"

# 从文件读取任务并输出结果到文件
mp --headless --task-file prompt.txt --output-file result.txt

# 限制可用工具
mp --tools ReadFile,Grep,Glob

# 启用 debug 模式
mp --debug --headless --task "列出当前目录的文件"
```
