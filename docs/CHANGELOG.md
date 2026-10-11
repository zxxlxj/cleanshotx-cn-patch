# 更新日志

## v5.0-cn.1

适配 CleanShot X 5.0（设置界面重写为 SwiftUI）。

- **新增渲染层拦截通道（CoreText + NSAttributedString）**，解决 SwiftUI 变量文本、
  快捷键动作名、以及带 Markdown 链接的富文本无法汉化的问题。
- **词条表重构**：从 `CleanShotCN.m` 内嵌字典迁移到 `src/translations.txt` 单一数据源，
  由 `scripts/gen-strings.py` 同时生成 C 头文件与 `zh-Hans` 语言包。
- **词条 359 → 1011 条**，覆盖视频编辑器、标注工具、上传/导出流程、
  对话框与错误提示、首次启动引导等。
- **新增运行时拼接文案的正则规则**（`CNDynamicLookup`）：
  `30 秒`、`60 帧/秒`、`800 × 自动（默认）`、`确定要删除 "文件名"？` 等。
- **新增工具**：`extract-strings.py`（二进制文案提取）、
  `check-coverage.py`（覆盖率统计）、`dedupe-translations.py`（去重）、
  `preflight.sh`（兼容性预检）。
- **日志默认不写盘**，改为标记文件开关（`/tmp/cleanshot-cn-debug`）。
- 安装脚本不再使用 `codesign --deep`（会被包内非标准 framework 卡住），
  改为单独签动态库 + 不带 `--deep` 签主包；并在签名前后比对 CDHash，变化时提示重新授权。

## v4.8.8-cn.2

- 新增 `scripts/repair-preferences.sh`，用于修复快捷键或设置保存后又丢失的问题，
  并保留退出前/退出后两份偏好快照。
- 安装和卸载脚本默认不再重置 macOS 权限记录，避免屏幕录制、辅助功能、
  输入监听权限反复失效。
- 安装时会同步备份 CleanShot X 偏好设置文件，并清理偏好设置文件上的异常隔离属性。

## v4.8.8-cn.1

- 支持 CleanShot X 4.8.8。
- 使用运行时动态库汉化设置页、快捷键页、菜单和常见按钮。
- 提供安装和卸载脚本。
- 安装时自动重新签名并重置相关权限记录。
- 仓库结构调整为 `src/`、`scripts/`、`docs/`，发布包通过 GitHub Releases 提供。
