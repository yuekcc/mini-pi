# rtk ls

1. 使用 c3 代码实现（不再调用 ls 命令）

2. 简化输出

    查看某个目录时，输出：

    ```sh
    755  .agents/
    755  .claude/
    755  .git/
    755  .workbuddy/
    755  build/
    755  docs/
    755  lib/
    755  logs/
    755  notes/
    755  resources/
    755  scripts/
    755  src/
    755  test/
    755  testdata/
    644  .c3fmt  193B
    644  .editorconfig  132B
    644  .gitattributes  172B
    644  .gitignore  204B
    644  .nojekyll  0B
    644  AGENTS.md  3.2K
    644  CLAUDE.md  16B
    644  LICENSE  1.0K
    644  README.md  3.1K
    644  commit_task.md  2.5K
    644  curl-ca-bundle.crt  219.8K
    644  index.css  17.4K
    644  index.html  17.7K
    644  index.js  3.7K
    644  libcurl-x64.def  2.5K
    755  libcurl-x64.dll  3.3M
    644  project.json  433B

    Summary: 17 files, 14 dirs (4 .md, 1 .crt, 1 .gitattributes, 1 .c3fmt, 1 no ext, +9 more)
    ```

3. Windows/Linux 兼容考虑，只有在 Linux 环境里输出权限码
