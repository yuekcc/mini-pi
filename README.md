# mp

**my own coding agent, inspired by Pi**

`mp` 是用 [c3 语言](https://c3-lang.org) 实现的命令行 coding agent，通过 OpenAI 兼容的 Chat Completions API 与大模型交互，内置一组文件操作与命令执行工具，支持交互式多轮对话与非交互式批处理。

## 特性

- [x] Agent Loop
  - [x] 支持 OpenAI Chat Completions API（流式 SSE）
  - [x] 多轮对话
  - [x] 支持工具调用（单次回复中的多个 tool_call）
  - [x] 支持 reasoning_content（思考链）
- [x] 内置工具
  - [x] ReadFile — 读取文件内容，输出 `line:hash|content` 锚点格式，支持 `offset`/`limit` 分页（默认 2000 行）
  - [x] ListDir — 列出目录内容（`ls -ahl`），支持指定路径
  - [x] Grep — 基于 [rg](https://github.com/BurntSushi/ripgrep) 搜索内容，支持正则、忽略大小写、literal 模式、上下文行、glob 过滤
  - [x] EditFile — 精确编辑文件，通过 `oldText` 精确匹配后替换为 `newText`
  - [x] HashEditFile — 基于行哈希的精确编辑，通过 `line`+`hash` 锚定行后执行替换/删除/插入/区间替换；支持批量原子提交（全部通过或全部拒绝）
  - [x] WriteFile — 写入/创建文件，自动创建父目录
  - [x] Bash — 执行 shell 命令（`sh -c`），输出超过 2000 行自动截断并保存完整输出
  - [x] Glob — 基于 [fd](https://github.com/sharkdp/fd) 按 glob 模式搜索文件名
  - [x] Task — 以子进程方式启动子 agent 执行任务（递归调用 `mp` 自身）
- [x] skill 支持（从 `~/.agents/skills/` 与 `.agents/skills/` 加载 SKILL.md）
- [x] 通过 task 工具启动一个子 agent
- [x] 支持 AGENTS.md 文件（只支持当前目录）
- [x] 分级日志（debug/info/warn/error），`--debug` 时转储 HTTP 请求/响应
- [x] NO_COLOR 环境变量支持
- [ ] 多 agent 支持
  - [ ] 通过 --agent 指定 agent
  - [ ] 通过 --agent-list 列出全部 agent
  - [ ] 支持不同的 agent 配置不同的工具
- [ ] 部分兼容 claude code 生态（CLAUDE.md，.claude, 部分 claude code plugins）

## 交互式命令

在交互模式下，`mp` 支持以下内置命令（不经过 LLM）：

| 命令          | 说明                                                              |
| ------------- | ----------------------------------------------------------------- |
| `/export`     | 将当前对话导出为 Markdown 文件，文件名 `<session_id>.md`           |
| `/clear`      | 清空当前对话历史，开启新会话并生成新的 session ID                 |
| `/exit`, `/e` | 退出会话，同时显示当前 Session ID                                 |

## 命令行用法

```bash
mp [选项]
```

全部命令行开关见 [docs/flags.md](docs/flags.md)。

## 构建

需要最新版本 [c3c](https://github.com/c3lang/c3c/releases/tag/latest-prerelease-tag)。

```sh
# 构建
c3c build

# 发布
sh scripts/release.sh
```

运行时依赖同目录下的 `libcurl-x64.dll`（Windows），以及系统中的 `rg`、`fd`、`sh`、`ls`。

### 架构设计

见 [docs/arch.md](docs/arch.md)

### 更新 libcurl

见 [docs/update-libcurl.md](docs/update-libcurl.md)
