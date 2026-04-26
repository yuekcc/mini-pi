当前项目是 c3 语言实现的一个 coding agent。

## 关键目录结构

```sh
/src            # 代码目录
/test           # 单元测试目录
/lib            # 三方库目录
    /c3x.c3l    # json 处理库
    /curl.c3l   # libcurl 在 c3 绑定
project.json    # 项目定义
```

## 开发命令

```sh
# 构建
c3c build

# 执行单元测试
c3c test

# 执行某个单元测试并打印单元测试的 stdout
c3c test --test-filter test_execute_to_string --test-show-output
```

## 参考

- [c3 语言简介](docs/c3_intro.md)
