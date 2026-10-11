#!/bin/zsh
# 编译运行时翻译器 libCleanShotCN.dylib
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/src/CleanShotCN.m"
OUT="$ROOT/build/libCleanShotCN.dylib"

mkdir -p "$ROOT/build"

# 词条表是唯一数据源，编译前必须先由它生成 src/GeneratedCNTable.h
PYTHON_BIN="$(command -v python3 || true)"
if [[ -z "$PYTHON_BIN" ]]; then
  for cand in /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
    if [[ -x "$cand" ]]; then PYTHON_BIN="$cand"; break; fi
  done
fi
if [[ -n "$PYTHON_BIN" ]]; then
  "$PYTHON_BIN" "$ROOT/scripts/gen-strings.py"
else
  echo "⚠️  未找到 python3，跳过词条表生成（若 src/GeneratedCNTable.h 已存在仍可编译）" >&2
fi

clang -dynamiclib \
  -o "$OUT" \
  "$SRC" \
  -fobjc-arc \
  -O2 \
  -framework Foundation \
  -framework AppKit \
  -framework CoreGraphics \
  -framework CoreFoundation \
  -framework CoreText \
  -arch x86_64 -arch arm64 \
  -install_name @rpath/libCleanShotCN.dylib \
  2>&1

echo "✅ 已生成：$OUT"
ls -la "$OUT"
