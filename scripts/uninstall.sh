#!/bin/zsh
set -euo pipefail

APP_PATH="${1:-/Applications/CleanShot X.app}"
BUNDLE_ID="pl.maketheweb.cleanshotx"
DYLIB_NAME="libCleanShotCN.dylib"
RESET_TCC="${RESET_TCC:-0}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "找不到 CleanShot X：$APP_PATH"
  echo "用法: ./scripts/uninstall.sh [CleanShot X.app 路径]"
  exit 1
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
MACOS_DIR="$APP_PATH/Contents/MacOS"

echo "正在退出 CleanShot X..."
osascript -e 'tell application "CleanShot X" to quit' >/dev/null 2>&1 || true
pkill -x "CleanShot X" >/dev/null 2>&1 || true
sleep 1

echo "正在移除汉化注入配置..."
/usr/libexec/PlistBuddy -c 'Delete :LSEnvironment' "$INFO_PLIST" >/dev/null 2>&1 || true
rm -f "$MACOS_DIR/$DYLIB_NAME"

echo "正在移除中文语言包..."
rm -rf "$APP_PATH/Contents/Resources/zh-Hans.lproj"
defaults delete "$BUNDLE_ID" AppleLanguages >/dev/null 2>&1 || true

echo "正在重新签名..."
# 同 install.sh：--deep 会被包内非标准 framework 卡住，改为只签主包
codesign --force --sign - "$APP_PATH"
codesign --verify "$APP_PATH" >/dev/null 2>&1 \
  && echo "签名校验通过" \
  || echo "提示：嵌套 framework 结构不标准，codesign 校验会告警（原始应用同样如此，不影响运行）"

if [[ "$RESET_TCC" == "1" ]]; then
  echo "正在重置权限记录..."
  tccutil reset ScreenCapture "$BUNDLE_ID" >/dev/null 2>&1 || true
  tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
  tccutil reset ListenEvent "$BUNDLE_ID" >/dev/null 2>&1 || true
else
  echo "已保留现有系统权限记录。若权限异常，可用 RESET_TCC=1 ./scripts/uninstall.sh 手动重置。"
fi

echo "卸载完成。重新打开 CleanShot X 后，如系统提示权限，请重新允许。"
