# 更新 libcurl-x64.dll

目前是动态链接 libcurl。

curl 官方的 windows 版本只提供了 mingw-w64 的 .a 文件. c3c 默认使用 msvc 编译的链接器，只支持 .lib。可以通过 lib 命令从 .def 文件生成 .lib：

> 两个方法，二选一：
>
> 1. 安装需要 msvc，可以使用 [portable-msvc.py](https://gist.github.com/mmozeiko/7f3162ec2988e81e56d5c4e22cde9977) 安装便携版。
> 2. 安装 [zig](https://ziglang.org/download/)，zig 内置了 lib 的命令行功能，可以代替 msvc 的 lib.exe。

在 msvc prompt 里执行：

```cmd
lib.exe /def:libcurl-x64.def /out:lib/curl.c3l\windows-x64\libcurl.lib /machine:x64
```

或使用 zig 内置的 lib 命令：

```cmd
zig lib /def:libcurl-x64.def /out:lib/curl.c3l/windows-x64/libcurl.lib /machine:x64
```
