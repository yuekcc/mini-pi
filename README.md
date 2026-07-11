# mp

**my own coding agent, inspired by Pi**

## 特性

- [x] Agent Loop
  - [x] 支持 OpenAI Chat Completions API
  - [x] 多轮对话
  - [x] 支持工具调用
- [x] 内置工具
  - [x] ReadFile — 读取文件内容，支持 `offset`/`limit` 分页（默认 2000 行），自动添加行号
  - [x] ListDir — 列出目录内容（`ls -ahl`），支持指定路径，默认 500 条
  - [x] Grep — 基于 [rg](https://github.com/BurntSushi/ripgrep) 搜索内容，支持正则、忽略大小写、literal 模式、上下文行、glob 过滤
  - [x] EditFile — 精确编辑文件，通过 `oldText` 精确匹配后替换为 `newText`
  - [x] WriteFile — 写入/创建文件，自动创建父目录
  - [x] Bash — 执行 shell 命令，输出超过 2000 行自动截断并保存完整输出
  - [x] Glob — 基于 [fd](https://github.com/sharkdp/fd) 按 glob 模式搜索文件名
  - [x] Task — 启动子 agent 执行任务
- [x] skill 支持
- [x] 通过 task 工具启动一个子 agent
- [ ] 多 agent 支持
  - [ ] 通过 --agent 指定 agent
  - [ ] 通过 --agent-list 列出全部 agent
  - [ ] 支持不同的 agent 配置不同的工具
- [x] 支持 Ralph Loop 长任务模式：通过子agent方式可以实现类似效果，参考 [ralph-loop-task.md](docs/ralph-loop-task.md)
- [ ] 内置 PDCA-based SDD 流程
- [x] 支持 AGENTS.md 文件(只支持当前目录)
- [x] 审计日志 `~/.config/mp/workspace/${project_name}/${sessionId}.jsonl`
- [x] 全局设置文件 `~/.config/mp/mp.json`

## 命令行用法

```bash
mp [选项]
```

全部命令行开关见 [docs/flags.md](docs/flags.md)

## 构建

需要最新版本 [c3c](https://github.com/c3lang/c3c/releases/tag/latest-prerelease-tag)

```sh
# 构建
c3c build

# 发布
sh scripts/release.sh
```

### 架构设计

见 [docs/arch.md](docs/arch.md)

### 更新 libcurl

见 [docs/update-libcurl.md](docs/update-libcurl.md)
