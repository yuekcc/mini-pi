# 命令行参数说明

`mp` 是一个 pi coding agent 克隆程序，用于自动化编程辅助。

## 参数列表

| 参数                   | 说明                                                                           | 默认值                              |
| ---------------------- | ------------------------------------------------------------------------------ | ----------------------------------- |
| `--agent <name>`       | 指定智能体角色名称                                                             | `default`                           |
| `--model <id>`         | 指定使用的模型 ID                                                              | `minimax.com/MiniMax-M2.2`          |
| `--tools <list>`       | 允许使用的工具列表（逗号分隔）                                                 | `read,bash,edit,write,grep,find,ls` |
| `--headless`           | 启用非交互模式                                                                 | 交互模式                            |
| `--init-message <msg>` | 指定默认提示词（需要同时设置 --headless），支持 @filename 方式从文件获取提示词 | -                                   |
| `--help`, `-h`         | 显示帮助信息                                                                   | -                                   |
| `--version`, `-v`      | 显示版本号                                                                     | -                                   |
| `--debug`              | 启动 DEBUG 模式                                                                | -                                   |

## 详细说明

### `--agent <name>`

指定智能体角色的名称，用于区分不同的 Agent 配置。

### `--model <id>`

指定要使用的 AI 模型 ID，格式为 `provider/model-name`。

### `--tools <list>`

设置允许使用的工具列表，可用的工具包括：

- `read` - 读取文件内容
- `bash` - 执行 bash 命令
- `edit` - 编辑文件
- `write` - 写入文件
- `grep` - 搜索文件内容
- `find` - 查找文件
- `ls` - 列出目录内容

多个工具用逗号分隔。

### `--headless`

以非交互模式运行，不启动交互式界面。配合 `--init-message` 使用可以执行批处理任务。

### `--init-message <msg>`

设置程序启动时的初始消息内容，必须同时指定 `--headless` 参数。

## 使用示例

```bash
# 显示帮助信息
mp --help

# 显示版本号
mp --version

# 使用指定模型运行
mp --model provider/custom-model --agent my-agent

# 非交互模式执行任务
mp --headless --init-message "请帮我创建一个 hello world 程序"

# 限制可用工具
mp --tools read,grep,find
```
