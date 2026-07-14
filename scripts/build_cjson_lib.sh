#!/bin/bash
# 重新生成 cjson 的预编译静态库 (lib/cjson.c3l/windows-x64/cjson.lib)
#
# 0.2.x 起 Windows 也改为现场编译 cJSON.c，主工程 `c3c build` 在 cjson.lib
# 缺失时会自动重编。本脚本仅用于显式产出一份独立的预编译 .lib（如改过
# cJSON.c/h、或 CI 需要确定产物）。
# wrapper.c3 仍由主工程增量编译，不进这个 .lib。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 子工程目录名为 pkg 而非 build：仓库 .gitignore 会忽略 build/，连带忽略 project.json
BUILD_DIR="${SCRIPT_DIR}/../lib/cjson.c3l/pkg"
OUTPUT_DIR="${SCRIPT_DIR}/../lib/cjson.c3l/windows-x64"

# project.json 必须存在，否则 c3c 会向上递归误编主工程（产出 mp.exe 而非 cjson.lib）
[ -f "${BUILD_DIR}/project.json" ] || {
  echo "ERROR: 缺少 ${BUILD_DIR}/project.json，请从版本库恢复" >&2
  exit 1
}

cd "$BUILD_DIR"
c3c clean >/dev/null 2>&1 || true
mkdir -p "$OUTPUT_DIR"
c3c build

[ -f "${OUTPUT_DIR}/cjson.lib" ] || {
  echo "ERROR: 构建完成但未生成 cjson.lib" >&2
  exit 1
}

echo "OK: cjson.lib 已更新 -> lib/cjson.c3l/windows-x64/cjson.lib"
