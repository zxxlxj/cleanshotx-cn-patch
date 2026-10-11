#!/bin/zsh
# CleanShot X 汉化可行性预检
#
# 汉化补丁依赖 DYLD_INSERT_LIBRARIES 注入动态库。这个机制能否生效，
# 完全取决于目标应用的签名方式：
#   - ad-hoc 签名 + 无 Hardened Runtime  → 可以注入
#   - Developer ID 签名 + Hardened Runtime（官方公证版）→ 注入会被系统直接剥离
#
# 所以换版本（尤其是 4.x → 5.0）之前，先跑这个脚本判断可行性。
#
# 用法: ./scripts/preflight.sh ["/路径/CleanShot X.app"]

set -uo pipefail

APP_PATH="${1:-/Applications/CleanShot X.app}"
BUNDLE_ID="pl.maketheweb.cleanshotx"

echo "════════════════════════════════════════════════════════"
echo " CleanShot X 汉化可行性预检"
echo "════════════════════════════════════════════════════════"
echo

if [[ ! -d "$APP_PATH" ]]; then
  echo "❌ 找不到应用：$APP_PATH"
  echo "   用法: ./scripts/preflight.sh [\"CleanShot X.app 路径\"]"
  exit 1
fi

echo "应用路径 : $APP_PATH"
echo

# ── 1. 版本 ──────────────────────────────────────────────
VERSION=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "未知")
BUILD=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo "未知")
echo "① 版本"
echo "   CFBundleShortVersionString = $VERSION"
echo "   CFBundleVersion            = $BUILD"
echo

# ── 2. 签名信息 ──────────────────────────────────────────
echo "② 签名信息"
SIGINFO=$(codesign -dv "$APP_PATH" 2>&1)
echo "$SIGINFO" | sed 's/^/   /'

FLAGS=$(echo "$SIGINFO" | grep -o 'flags=0x[0-9a-fA-F]*([^)]*)' | head -1)
AUTHORITY=$(echo "$SIGINFO" | grep '^Authority=' | head -1)
SIGNATURE=$(echo "$SIGINFO" | grep '^Signature=' | head -1)
echo

# ── 3. 关键判定：Hardened Runtime ────────────────────────
echo "③ 关键判定"
RUNTIME_OK=1
if echo "$SIGINFO" | grep -q 'flags=.*(runtime)'; then
  echo "   ⚠️  检测到 Hardened Runtime"
  RUNTIME_OK=0
else
  echo "   ✅ 无 Hardened Runtime"
fi

if [[ -n "$AUTHORITY" ]]; then
  echo "   ⚠️  带正式签名：$AUTHORITY"
  echo "       （官方公证版会校验动态库，注入大概率被剥离）"
  RUNTIME_OK=0
else
  echo "   ✅ 无正式签名（ad-hoc 或未签名），可自由注入"
fi

# ── 4. entitlements ─────────────────────────────────────
echo
echo "④ entitlements（与注入相关的项）"
ENT=$(codesign -d --entitlements :- "$APP_PATH" 2>/dev/null || true)
if [[ -z "$ENT" ]]; then
  echo "   （无 entitlements）"
else
  echo "$ENT" | sed 's/^/   /'
fi
if echo "$ENT" | grep -q 'allow-dyld-environment-variables'; then
  echo "   ✅ 已显式允许 DYLD 环境变量"
fi
if echo "$ENT" | grep -q 'disable-library-validation'; then
  echo "   ✅ 已关闭库校验"
fi

# ── 5. 现状 ─────────────────────────────────────────────
echo
echo "⑤ 当前汉化状态"
DYLIB="$APP_PATH/Contents/MacOS/libCleanShotCN.dylib"
INJECTED=$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment:DYLD_INSERT_LIBRARIES' \
            "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "")
if [[ -f "$DYLIB" ]]; then
  echo "   汉化库   : 已存在（$(stat -f%z "$DYLIB") 字节）"
else
  echo "   汉化库   : 不存在"
fi
if [[ -n "$INJECTED" ]]; then
  echo "   注入配置 : $INJECTED"
else
  echo "   注入配置 : 未设置"
fi

# ── 6. 结论 ─────────────────────────────────────────────
echo
echo "════════════════════════════════════════════════════════"
if [[ $RUNTIME_OK -eq 1 ]]; then
  echo " 结论：✅ 可以汉化，直接运行 ./scripts/install.sh"
  echo "       补漏翻项：touch /tmp/cleanshot-cn-debug 后重启应用，"
  echo "       再看 /tmp/cleanshot-cn-ct.log 里的 MISS 条目"
else
  echo " 结论：⚠️  这个副本很可能无法注入汉化"
  echo "       原因：Hardened Runtime / 正式签名会剥离 DYLD_INSERT_LIBRARIES"
  echo "       先跑 ./scripts/install.sh 试一下；若应用启动后"
  echo "       汉化未生效（界面仍是英文），就说明注入被拦下了。"
fi
echo "════════════════════════════════════════════════════════"
