# mp (mini-pi)

**a pi coding agent clone, my own coding agent.**

## 特性

- [x] Agent Loop
  - [x] 支持 OpenAI Chat Completions API
  - [x] 多轮对话
  - [x] 支持工具调用
- [x] 内置工具
  - [x] read
  - [x] ls
  - [x] grep (依赖 [rg](https://github.com/BurntSushi/ripgrep))
  - [x] edit
  - [x] write
  - [x] bash
  - [x] find (依赖 [fd](https://github.com/sharkdp/fd))
  - [x] task
  - [ ] skill
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

### 架构

见 [docs/arch.md](docs/arch.md)

### 更新 libcurl

见 [docs/update-libcurl.md](docs/update-libcurl.md)
