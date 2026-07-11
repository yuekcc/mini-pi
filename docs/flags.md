# 命令行参数说明

`mp` 是一个 coding agent。

## 参数列表

| 参数                    | 说明                                                                    | 默认值                                   |
| ----------------------- | ----------------------------------------------------------------------- | ---------------------------------------- |
| `--config, -c <path>`   | 指定配置目录                                                            | `~/.config/mp/`                          |
| `--agent <name>`        | 指定智能体角色名称                                                      | `default`                                |
| `--model <id>`          | 指定使用的模型 ID                                                       | `Any`                                    |
| `--tools <list>`        | 允许使用的工具列表（逗号分隔）                                          | `ReadFile,Bash,EditFile,WriteFile,Grep,Glob,ListDir,Task` |
| `--headless`            | 启用非交互模式                                                          | 交互模式（默认）                         |
| `--task, -t <msg>`      | 指定初始任务内容                                                        | -                                        |
| `--task-file, -f <path>`| 从指定文件读取内容作为初始任务（与 `--task` 互斥，`--task-file` 优先）  | -                                        |
| `--output-file, -o <p>` | 将最后一次 LLM 的回复内容输出到指定文件（通常与 `--headless` 配合使用） | -                                        |
| `--list-skills`         | 列出全部可用 skill                                                      | -                                        |
| `--help, -h`            | 显示帮助信息                                                            | -                                        |
| `--version, -v`         | 显示版本号                                                              | -                                        |
| `--debug`               | 启动 DEBUG 模式，将 HTTP 请求/响应转储到 `logs/` 目录                   | -                                        |

## 详细说明

### `--config, -c <path>`

指定配置目录的路径。配置目录中存放 `mp.json` 等配置文件。

### `--agent <name>`

指定智能体角色的名称，用于区分不同的 Agent 配置。当前版本预留，尚未实现多 agent 差异化配置。

### `--model <id>`

指定要使用的 AI 模型 ID，格式为 `provider/model-name`。

### `--tools <list>`

设置允许使用的工具列表，可用的工具包括：

| 工具       | 说明                                          |
| ---------- | --------------------------------------------- |
| `ReadFile` | 读取文件内容，带行号显示                      |
| `Bash`     | 执行 shell 命令                               |
| `EditFile` | 对文件进行文本替换编辑                        |
| `WriteFile`| 写入/创建文件                                 |
| `Grep`     | 基于 ripgrep 的文本搜索                       |
| `Glob`     | 基于 fd 的文件查找                            |
| `ListDir`  | 列出目录内容                                  |
| `Task`     | 启动子 agent 执行子任务（递归调用 `mp` 自身） |

多个工具用逗号分隔。

### `--headless`

以非交互模式运行，不启动交互式界面。在此模式下，程序接收初始任务后自动执行 Agent Loop，完成后退出。通常与 `--task`（或 `--file`）和 `--output-file` 配合使用。

### `--task, -t <msg>`

设置程序启动时的初始任务内容。需与 `--headless` 配合使用。

```bash
mp --headless --task "请帮我创建一个 hello world 程序"
```

### `--task-file, -f <path>`

从指定文件读取内容作为初始任务。当 `--task` 和 `--file` 同时指定时，`--file` 优先。

```bash
mp --headless --file prompt.txt
```

### `--output-file, -o <path>`

将最后一次 LLM 的回复内容写入指定文件。通常与 `--headless` 配合，用于批处理任务的输出收集。

### `--list-skills`

列出全部可用的 skill。每个 skill 对应一个独立的代理能力模块。

### `--debug`

启用 DEBUG 模式。在此模式下，所有 HTTP 请求和响应会被转储到 `logs/` 目录（`logs/req_<timestamp>.json` 和 `logs/resp_<timestamp>.json`），方便排查 API 交互问题。

## 配置文件（预留）

全局配置文件位于 `~/.config/mp/mp.json`，计划支持以下字段：

```json
{
  "api_key": "your-api-key",
  "base_url": "http://127.0.0.1:5678",
  "model": "Any"
}
```

> **注意**：配置文件读取尚未实现，目前所有参数使用硬编码默认值。

## 使用示例

```bash
# 显示帮助信息
mp --help

# 显示版本号
mp --version

# 交互模式（默认）
mp

# 使用指定模型和 agent 运行
mp --model provider/custom-model --agent my-agent

# 非交互模式执行任务
mp --headless --task "请帮我创建一个 hello world 程序"

# 从文件读取任务并输出结果到文件
mp --headless --file prompt.txt --output-file result.txt

# 限制可用工具
mp --tools ReadFile,Grep,Glob

# 启用 debug 模式
mp --debug --headless --task "列出当前目录的文件"
```
