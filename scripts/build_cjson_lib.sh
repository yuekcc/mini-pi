#!/bin/bash
#
# 重新生成 cjson 的预编译静态库 (lib/cjson.c3l/windows-x64/cjson.lib)
#
# 说明（重要变更）：
#   自 0.2.x 起，Windows 平台的 cjson 已改为由主工程通过 manifest.json
#   的 `c-sources` 现场编译 cJSON.c（与 Linux/macOS 一致），主工程 `c3c build`
#   在 cjson.lib 缺失时会自动重新编译并链接，无需手动预编译。
#
#   本脚本仅用于「显式重新生成一份独立的预编译静态库」，例如：
#     - 修改了 lib/cjson.c3l/src/cJSON.c 或 cJSON.h 且希望单独产出 .lib
#     - CI / 发布流程需要一份确定的预编译产物
#
#   注意：wrapper.c3 提供 CJsonItem 的扩展方法，是模块接口的一部分，
#   仍由 c3c 在主工程构建时正常增量编译，不会被编进这个 .lib。
#
# 何时需要运行本脚本：
#   - 你确实想要一份独立的 lib/cjson.c3l/windows-x64/cjson.lib 产物时。
#   仅仅是「删了 cjson.lib 后主工程编不出来」的话，直接 `c3c build` 即可自愈。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 注意：子工程目录名为 `pkg`（不是 `build`），因为仓库 .gitignore 的 `build/`
# 规则会忽略所有名为 build 的目录，会把 project.json 一起忽略掉、无法入库。
BUILD_DIR="${SCRIPT_DIR}/../lib/cjson.c3l/pkg"
OUTPUT_DIR="${SCRIPT_DIR}/../lib/cjson.c3l/windows-x64"

# 前置校验：pkg 子工程定义必须存在。
# 否则 c3c 会向上递归查找并误编主工程（生成 build/mp.exe 而非 cjson.lib）。
if [ ! -f "${BUILD_DIR}/project.json" ]; then
  echo "ERROR: 缺少 ${BUILD_DIR}/project.json（cjson 静态库子工程定义）。" >&2
  echo "       该文件是仓库跟踪文件，请从版本库恢复后再运行。" >&2
  exit 1
fi

cd "$BUILD_DIR"

# 强制清理增量缓存，避免在缓存异常时「跳过链接却没产出 .lib」
c3c clean >/dev/null 2>&1 || true

# 确保输出目录存在（极端情况下被整体删除时）
mkdir -p "$OUTPUT_DIR"

c3c build

# 校验产物，缺失则明确报错而不是静默成功
if [ ! -f "${OUTPUT_DIR}/cjson.lib" ]; then
  echo "ERROR: 构建完成但未生成 ${OUTPUT_DIR}/cjson.lib" >&2
  exit 1
fi

echo "OK: cjson.lib 已更新 -> lib/cjson.c3l/windows-x64/cjson.lib"
