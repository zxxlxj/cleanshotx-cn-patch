# CleanShot X 简体中文汉化补丁

一个面向 macOS 的 **CleanShot X 运行时中文汉化补丁**。

它不改动 CleanShot X 的机器码，也不包含、不分发 CleanShot X 的任何官方文件 ——
只在本机编译一个轻量动态库，在应用运行时把界面上的英文替换成中文。
卸载脚本可完整还原。

> **本项目与 CleanShot X、Make The Web 及其开发团队没有任何关联。**
> 请在**拥有正版授权**的前提下自用。使用前请自行备份应用。

---

## ⚠️ 先读这一段：兼容性

补丁依赖 `DYLD_INSERT_LIBRARIES` 注入动态库，能否生效取决于目标应用的签名方式：

| 应用签名情况 | 能否汉化 |
|---|---|
| ad-hoc 签名 / 未签名 | ✅ 可以 |
| 正式签名 + 公证 + Hardened Runtime（官方渠道版） | ⚠️ 需要先 ad-hoc 重签名，见下 |

安装脚本会**自动对应用做 ad-hoc 重签名**，这会去掉 Hardened Runtime 标志，
使注入生效。但重签名同时意味着：

- 应用的**官方签名身份丢失**，Sparkle 自动更新会失效（更新后重新跑一次安装脚本即可）；
- 首次启动可能被 Gatekeeper 拦下，需要「右键 → 打开」；
- macOS 会把它当成**新的代码身份**，屏幕录制等权限需要重新授权（见下方「权限」一节）。

动手前先跑一次预检，脚本会打印版本、签名、entitlements 并给出结论：

```bash
./scripts/preflight.sh "/Applications/CleanShot X.app"
```

**已验证版本：CleanShot X 5.0。** 4.8.8 亦可（见 `docs/VERSION.txt`）。

---

## 功能

汉化范围（实测覆盖）：

- **设置窗口全部 10 个页面**：通用、快捷键、快速访问、壁纸、截图、录制、标注、云、高级、关于
- **菜单栏图标下拉菜单**（21 项）
- **快捷键页全部动作名**（含视频编辑器动作，100+ 条）
- 各类对话框、错误提示、上传/导出流程、首次启动引导
- 设置页里的富文本说明（含 Markdown 链接的那种）
- 运行时拼接的文案：`30 秒`、`60 帧/秒`、`800 × 自动（默认）`、`确定要删除 "文件名"？`

**有意保留英文**：品牌名与技术缩写（`CleanShot X`、`Twitter / X`、`YouTube`、`PNG`、`OCR`、`API`）、
快捷键符号（`⌘C`、`⇧⌘S`、`⌥⏎`）。

词条表现有 **1011 条**，全部能在应用二进制里找到对应原文（覆盖率 100%）。

---

## 快速开始

需要 Xcode Command Line Tools（提供 `clang` 和 `python3`）：

```bash
xcode-select --install
```

然后：

```bash
git clone https://github.com/<你的用户名>/cleanshotx-cn-patch.git
cd cleanshotx-cn-patch
./scripts/install.sh
```

CleanShot X 不在默认路径时，把路径作为参数传进去：

```bash
./scripts/install.sh "/你的路径/CleanShot X.app"
```

安装脚本会依次完成：生成词条表 → 编译 `libCleanShotCN.dylib` → 复制进应用包 →
写入 `Info.plist` 的 `LSEnvironment` → 安装 `zh-Hans` 语言包并把应用语言设为简体中文 →
ad-hoc 重签名 → 重启应用。同时在 `backups/` 下留一份安装前备份。

### 换设备 / 重装后

汉化库是**本机编译**的，直接在新设备上重新跑一次 `./scripts/install.sh` 即可。

---

## 卸载

```bash
./scripts/uninstall.sh
```

会移除注入配置、动态库和语言包，并重新签名应用。
需要连权限记录一起清掉时：

```bash
RESET_TCC=1 ./scripts/uninstall.sh
```

---

## 权限：重签名会让授权作废（最常见的坑）

ad-hoc 签名下，**macOS 的权限记录（TCC）是按 CDHash 认身份的**，不是按包名。
补丁每次改动都要重签名 → CDHash 变 → 旧授权作废。于是会出现：

> 系统设置里的开关**显示是开的**（那是旧身份的记录），
> 但应用按新身份去申请，系统判定「未授权」——
> 表现就是「我明明开了屏幕录制，CleanShot 还是一直报没权限」。

只拨动开关通常没用，因为改的还是旧身份那条记录。

**修复步骤：**

1. 完全退出 CleanShot X（退出进程，不是关窗口）
2. 移除旧记录，二选一：
   - 图形界面：系统设置 → 隐私与安全性 → **屏幕与系统音频录制** → 选中 CleanShot X → 点 **「−」移除**
   - 终端：`tccutil reset ScreenCapture pl.maketheweb.cleanshotx`
3. 重新打开应用，让它重新申请权限并允许
4. **授权后必须再退出、重新打开一次** —— macOS 对屏幕录制权限要求重启应用才生效，这步最容易漏

只要之后不再改 `src/CleanShotCN.m`，CDHash 就保持不变，授权一次长期有效。

---

## 原理

CleanShot X 5.0 把设置界面重写成了 SwiftUI，单一手段覆盖不全，所以这里用了
**三条互补的翻译通道**，它们共用同一张词条表：

| 通道 | 负责范围 | 做法 |
|---|---|---|
| **A 视图遍历** | 侧边栏、窗口标题、AppKit 控件、菜单栏图标菜单 | 挂钩 `NSMenu` 的 `insertItem:atIndex:` / `addItem:` / `setItems:` 与 `NSStatusItem setMenu:`，直接替换 `NSMenuItem.title`；定时器遍历 `NSApp.windows` |
| **B 本地化查询拦截** | SwiftUI `Text("字面量")`、`.strings` 资源 | 用 `__DATA,__interpose` 重绑 `NSBundle` / `CFBundleCopyLocalizedString`，按词条表翻译查询结果；同时安装 `zh-Hans.lproj` 语言包 |
| **C 渲染层拦截** | SwiftUI 变量文本、快捷键动作名、Markdown 富文本 | 重绑 `CTLineCreateWithAttributedString`、`CTTypesetterCreateWithAttributedString(AndOptions)`、`CTFramesetterCreateWithAttributedString`、`CFAttributedStringCreate`，并在 `NSAttributedString` 的 `drawAtPoint:` / `drawInRect:` / `drawWithRect:options:context:` 绘制点整句替换 |

**为什么必须有通道 C**：SwiftUI 里 `Text("…[链接](url)…")` 这类富文本，
既不经过 `CTLine`，也不经过 `initWithString:attributes:`，
只有真正落笔绘制时才拿得到「解析后的完整句子」。

**通道 C 的关键坑**：`__interpose` 生效后，
`dlsym(RTLD_NEXT / RTLD_DEFAULT / dlopen 句柄)` 都会解析回**我们自己**的替换函数，
拿原函数会无限递归爆栈。唯一可靠做法是用**本镜像内的直接引用**
（`&CTLineCreateWithAttributedString`），它不会被 interpose 改写。

细节和踩坑记录见 [`docs/开发与维护.md`](docs/开发与维护.md)。

---

## 目录结构

```
.
├── README.md                     # 本文件
├── LICENSE                       # MIT
├── src/
│   ├── CleanShotCN.m             # 注入库源码：三条通道 + 运行时翻译表
│   └── translations.txt          # 词条表（唯一数据源，1011 条）
├── scripts/
│   ├── install.sh                # 一键安装
│   ├── uninstall.sh              # 一键卸载
│   ├── preflight.sh              # 兼容性预检
│   ├── build.sh                  # 只编译 dylib（开发用）
│   ├── gen-strings.py            # 词条表 → C 头文件 + .strings 语言包
│   ├── extract-strings.py        # 从应用二进制提取界面文案候选
│   ├── check-coverage.py         # 词条覆盖率统计
│   ├── dedupe-translations.py    # 词条去重
│   └── repair-preferences.sh     # 修复设置/快捷键保存异常
└── docs/
    ├── VERSION.txt               # 已验证版本
    ├── 开发与维护.md              # 架构说明、巡检方法、踩坑记录
    └── screenshots-5.0-cn/       # 汉化效果截图
```

---

## 参与贡献 / 补漏翻项

词条表 `src/translations.txt` 是**唯一数据源**，格式为 `英文原文<Tab>简体中文`，
以 `#` 开头的是注释。改完后跑一次 `./scripts/install.sh` 即可生效。

**自动找漏翻项**（不用人工翻界面）：

```bash
# 1. 从应用二进制提取所有像界面文案的串
python3 scripts/extract-strings.py > /tmp/candidates.txt

# 2. 与词条表求差集，剩下的就是没覆盖的
python3 - <<'PY'
table = {l.split('\t',1)[0] for l in open('src/translations.txt', encoding='utf-8')
         if l.strip() and not l.startswith('#') and '\t' in l}
for c in open('/tmp/candidates.txt', encoding='utf-8'):
    c = c.rstrip('\n')
    if c and c not in table:
        print(c)
PY
```

**运行时看真实渲染的文案**：

```bash
touch /tmp/cleanshot-cn-debug /tmp/cleanshot-cn-cycle   # 开日志 + 自动遍历设置页
pkill -x "CleanShot X"; open -a "CleanShot X"
# 等约 50 秒，看渲染层里仍未命中的串
grep "^MISS" /tmp/cleanshot-cn-ct.log
rm -f /tmp/cleanshot-cn-debug /tmp/cleanshot-cn-cycle   # 收尾
```

> 日志默认**不写盘**，必须存在 `/tmp/cleanshot-cn-debug` 标记文件才会输出。

运行时拼接的句子（`确定要删除 "X"？`、`缩放 40%`）走
`src/CleanShotCN.m` 里 `CNDynamicLookup()` 的正则规则，新增这类文案改那个函数。

---

## 常见问题

**Q：装完界面还是英文？**
先看 `./scripts/preflight.sh` 的结论。若应用带 Hardened Runtime 且重签名失败，
注入会被系统剥离；确认 `libCleanShotCN.dylib` 确实存在于
`CleanShot X.app/Contents/MacOS/` 下。

**Q：CleanShot 报没有屏幕录制权限，但系统设置里明明是开的？**
见上面「权限」一节，是 CDHash 变了。按那 4 步走。

**Q：应用更新后汉化没了？**
正常。重新跑一次 `./scripts/install.sh`。若新版本改了界面文案，
按「参与贡献」一节补词条。

**Q：快捷键 / 设置过一阵子丢了？**
跑 `./scripts/repair-preferences.sh`。

---

## 来源与致谢

本项目的早期版本来自
[CodeApe-Xiaoyin/cleanshotx-cn-patch](https://github.com/CodeApe-Xiaoyin/cleanshotx-cn-patch)（MIT），
在此基础上做了以下扩展：

- 适配 CleanShot X 5.0（SwiftUI 设置界面）
- 新增渲染层拦截通道（CoreText + NSAttributedString），解决 SwiftUI 变量文本与 Markdown 富文本
- 词条表从 359 条扩充到 1011 条，改为 `translations.txt` 单一数据源
- 新增二进制文案提取、覆盖率统计、日志总开关等工具

## 许可证

[MIT](LICENSE)。本项目不含任何 CleanShot X 官方文件。
