#!/bin/zsh
set -euo pipefail

APP_PATH="${1:-/Applications/CleanShot X.app}"
BUNDLE_ID="pl.maketheweb.cleanshotx"
SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
SRC="$PROJECT_DIR/src/CleanShotCN.m"
BUILD_DIR="$PROJECT_DIR/build"
DYLIB_NAME="libCleanShotCN.dylib"
PREF_PLIST="$HOME/Library/Preferences/$BUNDLE_ID.plist"
RESET_TCC="${RESET_TCC:-0}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "找不到 CleanShot X：$APP_PATH"
  echo "用法: ./scripts/install.sh [CleanShot X.app 路径]"
  exit 1
fi

if [[ ! -f "$SRC" ]]; then
  echo "找不到源码文件：$SRC"
  exit 1
fi

if ! command -v clang >/dev/null 2>&1; then
  echo "找不到 clang。请先安装 Xcode Command Line Tools：xcode-select --install"
  exit 1
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
MACOS_DIR="$APP_PATH/Contents/MacOS"
TARGET_DYLIB="$MACOS_DIR/$DYLIB_NAME"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$PROJECT_DIR/backups/$STAMP"

mkdir -p "$BUILD_DIR" "$BACKUP_DIR"

if [[ -f "$PREF_PLIST" ]]; then
  echo "正在备份 CleanShot 设置..."
  cp -p "$PREF_PLIST" "$BACKUP_DIR/$BUNDLE_ID.pre-install.plist"
fi

echo "正在退出 CleanShot X..."
osascript -e 'tell application "CleanShot X" to quit' >/dev/null 2>&1 || true
pkill -x "CleanShot X" >/dev/null 2>&1 || true
sleep 1

echo "正在备份 Info.plist..."
cp -p "$INFO_PLIST" "$BACKUP_DIR/Info.plist"
if [[ -f "$TARGET_DYLIB" ]]; then
  cp -p "$TARGET_DYLIB" "$BACKUP_DIR/$DYLIB_NAME"
fi
if [[ -f "$PREF_PLIST" ]]; then
  cp -p "$PREF_PLIST" "$BACKUP_DIR/$BUNDLE_ID.post-quit.plist"
fi

ARCH_FLAGS=()
case "$(uname -m)" in
  arm64) ARCH_FLAGS=(-arch arm64) ;;
  x86_64) ARCH_FLAGS=(-arch x86_64) ;;
esac

# 生成词条表需要 python3。优先用 PATH 里的，其次找常见安装位置。
PYTHON_BIN="$(command -v python3 || true)"
if [[ -z "$PYTHON_BIN" ]]; then
  for cand in /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
    if [[ -x "$cand" ]]; then PYTHON_BIN="$cand"; break; fi
  done
fi

# ── 生成词条产物（必须在编译之前）──────────────────────────────
# scripts/gen-strings.py 从 src/translations.txt 生成两份东西：
#   src/GeneratedCNTable.h            —— 运行时翻译表（编译进 dylib）
#   build/zh-Hans.lproj/Localizable.strings —— 系统语言包
if [[ -n "$PYTHON_BIN" && -f "$PROJECT_DIR/scripts/gen-strings.py" ]]; then
  echo "正在生成词条表..."
  "$PYTHON_BIN" "$PROJECT_DIR/scripts/gen-strings.py"
else
  echo "错误：未找到 python3，无法生成词条表" >&2
  exit 1
fi

echo "正在编译汉化动态库..."
clang -dynamiclib -fobjc-arc -fblocks "${ARCH_FLAGS[@]}" \
  -framework AppKit -framework Foundation -framework CoreGraphics -framework CoreFoundation \
  -framework CoreText \
  "$SRC" -o "$BUILD_DIR/$DYLIB_NAME"

echo "正在安装动态库..."
cp -p "$BUILD_DIR/$DYLIB_NAME" "$TARGET_DYLIB"

echo "正在写入启动注入配置..."
/usr/libexec/PlistBuddy -c 'Delete :LSEnvironment' "$INFO_PLIST" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c 'Add :LSEnvironment dict' "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :LSEnvironment:DYLD_INSERT_LIBRARIES string $TARGET_DYLIB" "$INFO_PLIST"

# ── 安装中文语言包 ────────────────────────────────────────────
# 运行时翻译表已由 GeneratedCNTable.h 编译进 dylib；
# 这里额外把同一份词条装成 zh-Hans 语言包，并让应用以简体中文运行，
# 让走系统本地化通道的文案（含 macOS 标准菜单项）也变成中文。
if [[ -d "$PROJECT_DIR/build/zh-Hans.lproj" ]]; then
  rm -rf "$APP_PATH/Contents/Resources/zh-Hans.lproj"
  cp -R "$PROJECT_DIR/build/zh-Hans.lproj" "$APP_PATH/Contents/Resources/zh-Hans.lproj"
  echo "正在将应用语言设为简体中文..."
  defaults write "$BUNDLE_ID" AppleLanguages -array zh-Hans
else
  echo "提示：未生成语言包，跳过"
fi

echo "正在重新签名..."
# 注意：本机 CleanShot X 内的 Lava/Sparkle/VectorBoolean 等 framework 结构不标准，
# codesign --deep 会在遇到它们时报 "bundle format is ambiguous" 并中断，
# 导致主包 Info.plist 封签写坏、应用无法启动（错误 -54）。
# 因此改为：先单独签注入的动态库，再不带 --deep 签主包。
CDHASH_BEFORE="$(codesign -d --verbose=4 "$APP_PATH" 2>&1 | grep -i '^CDHash' | head -1 | cut -d= -f2)"
codesign --force --sign - "$TARGET_DYLIB"
codesign --force --sign - "$APP_PATH"
CDHASH_AFTER="$(codesign -d --verbose=4 "$APP_PATH" 2>&1 | grep -i '^CDHash' | head -1 | cut -d= -f2)"
# 该应用内含非标准 framework，--deep 校验必然告警，这里只做提示不中断
codesign --verify "$APP_PATH" >/dev/null 2>&1 \
  && echo "签名校验通过" \
  || echo "提示：嵌套 framework 结构不标准，codesign 校验会告警（原始应用同样如此，不影响运行）"

# ad-hoc 签名下，macOS 的权限记录（TCC）是按 CDHash 认身份的。
# CDHash 一变，之前授予的屏幕录制 / 辅助功能 / 输入监听就全部作废，
# 表现为「系统设置里勾是开的，但应用一直报没有权限」。
if [[ -n "$CDHASH_BEFORE" && "$CDHASH_BEFORE" != "$CDHASH_AFTER" ]]; then
  echo
  echo "┌──────────────────────────────────────────────────────────┐"
  echo "│ ⚠️  应用代码身份已改变，系统权限需要重新授权              │"
  echo "└──────────────────────────────────────────────────────────┘"
  echo "   旧 CDHash: $CDHASH_BEFORE"
  echo "   新 CDHash: $CDHASH_AFTER"
  echo
  echo "   处理办法："
  echo "     1. 完全退出 CleanShot X"
  echo "     2. 系统设置 → 隐私与安全性 → 屏幕与系统音频录制"
  echo "        选中 CleanShot X，点「−」移除，再重新添加"
  echo "        （只拨开关通常无效，因为那是旧身份的记录）"
  echo "     3. 授权后必须【退出并重新打开】应用才生效"
  echo "   或直接在终端执行："
  echo "     tccutil reset ScreenCapture $BUNDLE_ID"
  echo
else
  echo "CDHash 未变化，已有系统权限保持有效。"
fi

if [[ -f "$PREF_PLIST" ]]; then
  echo "正在修复设置文件属性..."
  xattr -d com.apple.quarantine "$PREF_PLIST" >/dev/null 2>&1 || true
  chmod 600 "$PREF_PLIST" >/dev/null 2>&1 || true
  chown "$(id -un)":staff "$PREF_PLIST" >/dev/null 2>&1 || true
  killall cfprefsd >/dev/null 2>&1 || true
fi

if [[ "$RESET_TCC" == "1" ]]; then
  echo "正在重置旧权限记录，稍后请在系统设置里重新允许 CleanShot X..."
  tccutil reset ScreenCapture "$BUNDLE_ID" >/dev/null 2>&1 || true
  tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
  tccutil reset ListenEvent "$BUNDLE_ID" >/dev/null 2>&1 || true
else
  echo "已保留现有系统权限记录。若权限异常，可用 RESET_TCC=1 ./scripts/install.sh 手动重置。"
fi

echo "正在启动 CleanShot X..."
open -a "CleanShot X"

echo
echo "安装完成。"
echo "如果系统提示权限，请重新允许 CleanShot X 的屏幕录制/辅助功能权限。"
echo "备份位置：$BACKUP_DIR"
