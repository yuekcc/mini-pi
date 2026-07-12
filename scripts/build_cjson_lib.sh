#!/bin/bash
#
# 重新生成 cjson 的预编译静态库 (lib/cjson.c3l/windows-x64/cjson.lib)
#
# 当以下文件有变动时需要重新执行本脚本：
#   - lib/cjson.c3l/src/cJSON.c
#   - lib/cjson.c3l/src/cJSON.h
#   - lib/cjson.c3l/cjson.c3i
#   - lib/cjson.c3l/src/wrapper.c3
#
# 说明：主工程构建时不再从源码编译 cJSON.{c,h}，而是直接链接本预编译库
#       (见 lib/cjson.c3l/manifest.json 中 windows-x64 的 linked-libraries)。
#       仅把 cJSON 的 C 代码预编译进库；wrapper.c3 仍由 c3c 正常增量编译
#       (它提供 CJsonItem 的扩展方法，是模块接口的一部分)。

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/../lib/cjson.c3l/build"

cd "$BUILD_DIR"
c3c build

echo "OK: cjson.lib 已更新 -> lib/cjson.c3l/windows-x64/cjson.lib"
