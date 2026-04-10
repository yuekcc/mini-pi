当前项目是 c3 语言实现的一个 coding agent。

## 关键目录结构

```sh
/src            # 代码目录
/test           # 单元测试目录
/lib            # 三方库目录
project.json    # 项目定义
```

## c3 语言简介

见 [docs/c3_intro.md](docs/c3_intro.md)。

## 相关命令

```sh
# 构建
c3c build

# 执行单元测试
c3c test

# 执行某个单元测试并打印单元测试的 stdout
c3c test --test-filter TEST_FUNCTION_NAME --test-show-output
```
