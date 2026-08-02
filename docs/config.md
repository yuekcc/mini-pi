# 配置目录

默认在 `~/.config/mp/`，在启动通过 `--config <dir_path>` 或 `-c <dir_path>` 可以指定项目目录。

**内容**

```bash
~/.config/mp/
    log/    # 日志
    temp/   # 临时文件
    agents/     # 自定义 agent
        my-agent.md
        ...
    commands/   # 自定义 / 命令
        my-slash-command.md
        ...
    config.json # 配置
    SYSTEM.md # 自定义的系统提示词
    SYSTEM_APPEND.md # 系统提示词追加内容，可以不重写内置的系统提示词情况下，追加新内容
```
