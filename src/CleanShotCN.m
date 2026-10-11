#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreText/CoreText.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "GeneratedCNTable.h"

static NSDictionary<NSString *, NSString *> *CNTranslationTable(void) {
    static NSDictionary<NSString *, NSString *> *map;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 词条统一维护在 src/translations.txt，
        // 由 scripts/gen-strings.py 生成 src/GeneratedCNTable.h
        map = [CNGeneratedTranslations() copy];
    });
    return map;
}

// 动态规则：处理「数字 + 单位」这类运行时拼出来的文案，
// 例如 "30 seconds" / "3 days" / "60 fps" / "800 x auto (default)"。
// 这类串无法穷举成固定词条，只能用模式匹配。精确词条优先。
static NSString *CNDynamicLookup(NSString *s) {
    if (s.length == 0 || s.length > 120) return nil;

    // ── 第一组：运行时拼接出来的整句（含变量，无法精确登记）──
    // 典型形态是「固定前缀 + "变量" + 固定后缀」，例如
    //   Are you sure you want to delete "IMG_0001.png"?
    // 这类只能按模式识别，再把变量原样搬回译文。
    static NSArray<NSArray *> *textRules;
    static dispatch_once_t textOnceToken;
    dispatch_once(&textOnceToken, ^{
        NSArray<NSArray<NSString *> *> *patterns = @[
            @[@"^Are you sure you want to delete \"(.+)\"\\?$", @"确定要删除“%@”吗？"],
            @[@"^Are you sure you want to delete \"(.+)\"$",    @"确定要删除“%@”"],
            @[@"^No shortcuts match \"(.+)\"$",                 @"没有匹配“%@”的快捷键"],
            @[@"^It appears that \"(.+)\"$",                    @"似乎“%@”"],
            @[@"^Do you want to assign \"(.+)\"$",              @"要将“%@”分配给"],
            @[@"^Zoom (\\d+)%$",                                @"缩放 %@%"],
            @[@"^Set new hotkey:\\s*(.+)$",                     @"设置新快捷键：%@"],
            @[@"^Image size:\\s*(.+)$",                         @"图像大小：%@"],
            @[@"^Your video has been successfully exported\\.\\s*File size:\\s*(.+)$",
              @"视频已成功导出。文件大小：%@"],
        ];
        NSMutableArray<NSArray *> *compiled = [NSMutableArray array];
        for (NSArray<NSString *> *p in patterns) {
            NSRegularExpression *re =
                [NSRegularExpression regularExpressionWithPattern:p[0] options:0 error:NULL];
            if (re) [compiled addObject:@[re, p[1]]];
        }
        textRules = compiled;
    });

    // 最短的模式也有 8 个字符，短串直接跳过，省下正则开销。
    if (s.length >= 8) {
        NSRange textFull = NSMakeRange(0, s.length);
        for (NSArray *rule in textRules) {
            NSRegularExpression *re = rule[0];
            NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:textFull];
            if (!m) continue;
            NSString *out = rule[1];
            for (NSInteger i = (NSInteger)m.numberOfRanges - 1; i >= 1; i--) {
                NSRange gr = [m rangeAtIndex:(NSUInteger)i];
                if (gr.location == NSNotFound) continue;
                NSString *val = [s substringWithRange:gr];
                out = [out stringByReplacingOccurrencesOfString:@"%@" withString:val];
            }
            return out;
        }
    }

    // ── 第二组：数字 + 单位 ──
    // 只处理短串，且必须含数字，避免误伤正常文案。
    if (s.length > 40) return nil;

    BOOL hasDigit = NO;
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c >= '0' && c <= '9') { hasDigit = YES; break; }
    }
    if (!hasDigit) return nil;

    static NSArray<NSArray *> *rules;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSArray<NSString *> *> *patterns = @[
            @[@"^(\\d+) seconds?$", @"%@ 秒"],
            @[@"^(\\d+) minutes?$", @"%@ 分钟"],
            @[@"^(\\d+) hours?$", @"%@ 小时"],
            @[@"^(\\d+) days?$", @"%@ 天"],
            @[@"^(\\d+) fps$", @"%@ 帧/秒"],
            @[@"^(\\d+) x auto \\(default\\)$", @"%@ × 自动（默认）"],
            @[@"^(\\d+) x auto$", @"%@ × 自动"],
            @[@"^(\\d+) x (\\d+)$", @"%@ × %@"],
        ];
        NSMutableArray<NSArray *> *compiled = [NSMutableArray array];
        for (NSArray<NSString *> *p in patterns) {
            NSRegularExpression *re =
                [NSRegularExpression regularExpressionWithPattern:p[0] options:0 error:NULL];
            if (re) [compiled addObject:@[re, p[1]]];
        }
        rules = compiled;
    });

    NSRange full = NSMakeRange(0, s.length);
    for (NSArray *rule in rules) {
        NSRegularExpression *re = rule[0];
        NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:full];
        if (!m) continue;
        NSString *out = rule[1];
        for (NSInteger i = (NSInteger)m.numberOfRanges - 1; i >= 1; i--) {
            NSRange gr = [m rangeAtIndex:(NSUInteger)i];
            if (gr.location == NSNotFound) continue;
            NSString *val = [s substringWithRange:gr];
            out = [out stringByReplacingOccurrencesOfString:@"%@" withString:val];
        }
        return out;
    }
    return nil;
}

static NSString *CNLookup(NSString *s) {
    if (s.length == 0) return nil;
    NSString *hit = CNTranslationTable()[s];
    if (hit) return hit;
    return CNDynamicLookup(s);
}

static void CNLogCandidate(NSString *s);

static NSString *CNTranslate(NSString *s) {
    if (s.length == 0) return s;

    NSString *direct = CNLookup(s);
    if (direct) return direct;

    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *trimmed = [s stringByTrimmingCharactersInSet:ws];
    NSString *trimmedTranslation = CNLookup(trimmed);
    if (!trimmedTranslation) {
        // 确实没翻到：若是「像界面文案」的串，记进日志备查
        CNLogCandidate(s);
        return s;
    }

    NSRange trimRange = [s rangeOfString:trimmed];
    if (trimRange.location == NSNotFound) return trimmedTranslation;

    NSMutableString *result = [s mutableCopy];
    [result replaceCharactersInRange:trimRange withString:trimmedTranslation];
    return result;
}

static void CNTranslateMenu(NSMenu *menu) {
    for (NSMenuItem *item in menu.itemArray) {
        NSString *translated = CNTranslate(item.title);
        if (translated && ![translated isEqualToString:item.title]) {
            item.title = translated;
        }
        if (item.submenu) CNTranslateMenu(item.submenu);
    }
}

static void CNTranslateView(NSView *view) {
    if ([view isKindOfClass:[NSTextField class]]) {
        NSTextField *field = (NSTextField *)view;
        if (!field.isEditable) {
            NSString *translated = CNTranslate(field.stringValue);
            if (translated && ![translated isEqualToString:field.stringValue]) {
                field.stringValue = translated;
            }
        }
    }

    if ([view isKindOfClass:[NSButton class]]) {
        NSButton *button = (NSButton *)view;
        NSString *translated = CNTranslate(button.title);
        if (translated && ![translated isEqualToString:button.title]) {
            button.title = translated;
        }
    }

    if ([view isKindOfClass:[NSPopUpButton class]]) {
        NSPopUpButton *popup = (NSPopUpButton *)view;
        CNTranslateMenu(popup.menu);
    }

    if ([view isKindOfClass:[NSTabView class]]) {
        NSTabView *tabView = (NSTabView *)view;
        for (NSTabViewItem *item in tabView.tabViewItems) {
            NSString *translated = CNTranslate(item.label);
            if (translated && ![translated isEqualToString:item.label]) {
                item.label = translated;
            }
        }
    }

    if ([view isKindOfClass:[NSTableView class]]) {
        NSTableView *table = (NSTableView *)view;
        for (NSTableColumn *column in table.tableColumns) {
            NSString *translated = CNTranslate(column.headerCell.stringValue);
            if (translated && ![translated isEqualToString:column.headerCell.stringValue]) {
                column.headerCell.stringValue = translated;
            }
        }

        NSRange visibleRows = [table rowsInRect:table.visibleRect];
        if (visibleRows.location != NSNotFound) {
            NSUInteger end = NSMaxRange(visibleRows);
            for (NSUInteger row = visibleRows.location; row < end; row++) {
                for (NSUInteger col = 0; col < table.numberOfColumns; col++) {
                    NSView *cellView = [table viewAtColumn:col row:row makeIfNecessary:NO];
                    if (cellView) CNTranslateView(cellView);
                }
            }
        }
    }

    for (NSView *subview in view.subviews) {
        CNTranslateView(subview);
    }
}

static void CNTranslateWindow(NSWindow *window) {
    NSString *translatedTitle = CNTranslate(window.title);
    if (translatedTitle && ![translatedTitle isEqualToString:window.title]) {
        window.title = translatedTitle;
    }

    for (NSToolbarItem *item in window.toolbar.items) {
        NSString *label = CNTranslate(item.label);
        if (label && ![label isEqualToString:item.label]) item.label = label;

        NSString *palette = CNTranslate(item.paletteLabel);
        if (palette && ![palette isEqualToString:item.paletteLabel]) item.paletteLabel = palette;

        if (item.toolTip.length > 0) {
            NSString *tip = CNTranslate(item.toolTip);
            if (tip && ![tip isEqualToString:item.toolTip]) item.toolTip = tip;
        }
    }

    if (window.contentView) CNTranslateView(window.contentView);
}

// 诊断开关：存在 /tmp/cleanshot-cn-noA 时停用「视图遍历」这一整套机制，
// 用来判断某条文案到底是靠视图遍历翻的，还是靠本地化查询翻的。
static BOOL CNMechanismAEnabled(void) {
    static BOOL enabled = YES;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        enabled = ![[NSFileManager defaultManager]
            fileExistsAtPath:@"/tmp/cleanshot-cn-noA"];
    });
    return enabled;
}

static void CNTranslateVisibleUI(void) {
    if (NSApp.mainMenu) CNTranslateMenu(NSApp.mainMenu);
    for (NSWindow *window in NSApp.windows) {
        CNTranslateWindow(window);
    }
}

// ─────────────────────────────────────────────────────────────
// 菜单栏图标下拉菜单的支持
//
// 原来的实现只遍历 NSApp.mainMenu 和 NSApp.windows，而状态栏图标
// （NSStatusItem）挂的 NSMenu 两者都不属于，且菜单行是私有
// NSMenuItemView 而非 NSTextField/NSButton，所以走视图遍历也翻译不到。
//
// 这里改为在「菜单项被加入菜单」和「菜单即将弹出」两个时机直接处理
// NSMenuItem 对象本身，从根上覆盖状态栏菜单。
// 同时把遇到的所有菜单项写入日志，便于核对漏翻项。
// ─────────────────────────────────────────────────────────────

static NSMutableSet<NSString *> *CNLoggedTitles;
static NSMutableSet<NSString *> *CNLoggedUIStrings;
static NSMutableSet<NSString *> *CNTranslatedValues;
static dispatch_queue_t CNLogQueue;

// ─────────────────────────────────────────────────────────────
// 日志总开关（默认关闭）
//
// 汉化库在正常运行时不写任何日志文件，避免持续往 /tmp 落盘。
// 需要排查问题时，创建标记文件后重启应用即可打开全部日志：
//
//     touch /tmp/cleanshot-cn-debug        # 打开全部日志
//     rm -f /tmp/cleanshot-cn-debug        # 关闭（重启应用生效）
//
// 兼容旧的单项开关：/tmp/cleanshot-cn-ct-dump 仍可单独打开渲染层日志。
// ─────────────────────────────────────────────────────────────
static BOOL CNDebugLogEnabled(void) {
    static BOOL enabled = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        // ct-dump 是渲染层日志的单项开关，它存在时同样需要放行写盘。
        enabled = [fm fileExistsAtPath:@"/tmp/cleanshot-cn-debug"] ||
                  [fm fileExistsAtPath:@"/tmp/cleanshot-cn-ct-dump"];
    });
    return enabled;
}

static void CNLogLineTo(NSString *path, NSString *line) {
    // 总开关关闭时直接丢弃，不落盘、不建文件。
    if (!CNDebugLogEnabled()) return;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CNLogQueue = dispatch_queue_create("cn.cleanshot.log", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_async(CNLogQueue, ^{
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [@"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) return;
        @try {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        } @catch (__unused NSException *e) {
        }
        [fh closeFile];
    });
}

static void CNLogLine(NSString *line) {
    CNLogLineTo(@"/tmp/cleanshot-cn-menu.log", line);
}

// 记录「像界面文案但没翻到」的字符串，用于发现新版本新增的文案。
// 只记录看起来像自然语言的串，过滤掉 defaults key、代码片段等噪音。
static void CNLogCandidate(NSString *s) {
    if (s.length < 3 || s.length > 90) return;

    BOOL looksLikeLabel = [s containsString:@" "] ||
                          [s hasSuffix:@":"] ||
                          [s hasSuffix:@"…"] ||
                          [s hasSuffix:@"..."];
    if (!looksLikeLabel) return;

    unichar first = [s characterAtIndex:0];
    if (!((first >= 'A' && first <= 'Z') || (first >= 'a' && first <= 'z'))) return;

    // 排除明显是标识符 / 代码 / 路径的串
    if ([s containsString:@"_"] ||
        [s containsString:@"://"] ||
        [s containsString:@"%"] ||
        [s containsString:@"{"]) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CNLoggedUIStrings = [NSMutableSet set];
    });
    @synchronized (CNLoggedUIStrings) {
        if ([CNLoggedUIStrings containsObject:s]) return;
        [CNLoggedUIStrings addObject:s];
    }
    CNLogLineTo(@"/tmp/cleanshot-cn-ui.log",
                [NSString stringWithFormat:@"MISS\t%@\n", s]);
}

static void CNHandleMenuItem(NSMenuItem *item) {
    if (!item) return;
    NSString *title = item.title;
    if (title.length == 0) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CNLoggedTitles = [NSMutableSet set];
        // 收集全部译文，用于识别「已经翻好的」字符串，避免重复处理与误报
        CNTranslatedValues = [NSMutableSet set];
        for (NSString *v in CNTranslationTable().allValues) {
            [CNTranslatedValues addObject:v];
        }
    });

    // 已经是译文（本库自己翻过的），直接跳过
    @synchronized (CNTranslatedValues) {
        if ([CNTranslatedValues containsObject:title]) return;
    }

    NSString *translated = CNTranslate(title);
    BOOL changed = ![translated isEqualToString:title];

    @synchronized (CNLoggedTitles) {
        if (![CNLoggedTitles containsObject:title]) {
            [CNLoggedTitles addObject:title];
            CNLogLine([NSString stringWithFormat:@"%@\t%@\t->\t%@\n",
                       changed ? @"OK  " : @"MISS", title,
                       changed ? translated : @"(未翻译)"]);
        }
    }

    if (changed) item.title = translated;
}

@interface NSMenu (CleanShotCNPatch)
- (void)cn_insertItem:(NSMenuItem *)item atIndex:(NSInteger)index;
- (void)cn_addItem:(NSMenuItem *)item;
- (void)cn_setItems:(NSArray<NSMenuItem *> *)items;
- (BOOL)cn_popUpMenuPositioningItem:(NSMenuItem *)item
                         atLocation:(NSPoint)location
                             inView:(NSView *)view;
@end

// 状态栏图标挂的菜单：它既不属于 NSApp.mainMenu，也不在 NSApp.windows 里，
// 只能通过 NSStatusItem 的 setMenu: 抓到引用，之后持续跟进翻译。
static NSHashTable<NSMenu *> *CNStatusMenus;

static void CNRememberStatusMenu(NSMenu *menu) {
    if (!menu) return;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CNStatusMenus = [NSHashTable weakObjectsHashTable];
    });
    @synchronized (CNStatusMenus) {
        [CNStatusMenus addObject:menu];
    }
    for (NSMenuItem *mi in menu.itemArray) CNHandleMenuItem(mi);
}

static void CNTranslateStatusMenus(void) {
    if (!CNStatusMenus) return;
    @synchronized (CNStatusMenus) {
        for (NSMenu *menu in CNStatusMenus.allObjects) {
            for (NSMenuItem *mi in menu.itemArray) CNHandleMenuItem(mi);
        }
    }
}

// 调试辅助：把当前所有窗口的可见文案完整转储到日志（含已翻译项），
// 用于核对某个窗口到底有哪些文字。仅在标记文件存在时执行。
static NSMutableSet<NSString *> *CNDumpedStrings;

static void CNDumpView(NSView *view, NSString *windowTag) {
    if (!view) return;

    // 记录出现过的视图类名，用于判断界面是 AppKit 还是 SwiftUI 渲染
    {
        static NSMutableSet<NSString *> *seenClasses;
        static dispatch_once_t onceCls;
        dispatch_once(&onceCls, ^{ seenClasses = [NSMutableSet set]; });
        NSString *cls = NSStringFromClass(view.class);
        @synchronized (seenClasses) {
            if (![seenClasses containsObject:cls]) {
                [seenClasses addObject:cls];
                CNLogLineTo(@"/tmp/cleanshot-cn-ui.log",
                            [NSString stringWithFormat:@"CLASS\t%@\n", cls]);
            }
        }
    }

    void (^record)(NSString *, NSString *) = ^(NSString *kind, NSString *value) {
        if (value.length == 0) return;
        NSString *trimmed = [value stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length < 2 || trimmed.length > 120) return;
        @synchronized (CNDumpedStrings) {
            if ([CNDumpedStrings containsObject:trimmed]) return;
            [CNDumpedStrings addObject:trimmed];
        }
        NSString *tr = CNTranslate(trimmed);
        BOOL ok = ![tr isEqualToString:trimmed];
        CNLogLineTo(@"/tmp/cleanshot-cn-ui.log",
                    [NSString stringWithFormat:@"%@\t[%@]\t%@\t->\t%@\n",
                     ok ? @"OK  " : @"MISS", kind, trimmed, ok ? tr : @"(未翻译)"]);
    };

    if ([view isKindOfClass:[NSTextField class]]) {
        record(@"label", ((NSTextField *)view).stringValue);
    } else if ([view isKindOfClass:[NSButton class]]) {
        record(@"button", ((NSButton *)view).title);
    } else if ([view isKindOfClass:[NSPopUpButton class]]) {
        for (NSMenuItem *mi in ((NSPopUpButton *)view).itemArray) record(@"popup", mi.title);
    } else if ([view isKindOfClass:[NSTabView class]]) {
        for (NSTabViewItem *it in ((NSTabView *)view).tabViewItems) record(@"tab", it.label);
    } else if ([view isKindOfClass:[NSTableView class]]) {
        NSTableView *table = (NSTableView *)view;
        for (NSTableColumn *col in table.tableColumns) record(@"column", col.headerCell.stringValue);
    }

    for (NSView *sub in view.subviews) CNDumpView(sub, windowTag);
}

static void CNDumpAX(id element, NSInteger depth);

static void CNDebugDumpWindows(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CNDumpedStrings = [NSMutableSet set];
    });

    // 顺带自检：应用当前实际使用的本地化，以及 Localizable.strings 是否生效
    {
        NSBundle *b = [NSBundle mainBundle];
        CNLogLineTo(@"/tmp/cleanshot-cn-ui.log",
                    [NSString stringWithFormat:@"LOCALE\tpreferred=%@\tlocalizations=%@\n",
                     b.preferredLocalizations, b.localizations]);
        for (NSString *probe in @[@"Start at login", @"Show Quick Access Overlay", @"Screen Recording"]) {
            NSString *v = [b localizedStringForKey:probe value:@"(未命中)" table:nil];
            CNLogLineTo(@"/tmp/cleanshot-cn-ui.log",
                        [NSString stringWithFormat:@"LOCALE\t\"%@\" -> \"%@\"\n", probe, v]);
        }
    }

    NSArray<NSWindow *> *windows = NSApp.windows;
    CNLogLineTo(@"/tmp/cleanshot-cn-ui.log",
                [NSString stringWithFormat:@"---- 窗口快照：共 %lu 个 ----\n",
                 (unsigned long)windows.count]);

    for (NSWindow *w in windows) {
        CNLogLineTo(@"/tmp/cleanshot-cn-ui.log",
                    [NSString stringWithFormat:@"WINDOW\t%@\t%@\tvisible=%d\n",
                     NSStringFromClass(w.class), w.title ?: @"(无标题)", w.isVisible]);
        if (w.isVisible && w.contentView) CNDumpView(w.contentView, w.title ?: @"");
        if (w.isVisible) CNDumpAX(w, 0);
    }
}

// 在应用进程内查询「屏幕录制」权限的真实状态。
// 这是判定权限问题的唯一可靠依据：系统设置里显示的勾可能属于旧代码身份，
// 而 CGPreflightScreenCaptureAccess() 反映的是当前进程实际拿到的授权。
static void CNCheckScreenPermission(NSString *tag) {
    BOOL granted = CGPreflightScreenCaptureAccess();
    CNLogLineTo(@"/tmp/cleanshot-cn-perm.log",
                [NSString stringWithFormat:@"%@\t屏幕录制权限: %@\n",
                 tag, granted ? @"✅ 已授权" : @"❌ 未授权"]);

    // 标记文件存在时，主动触发系统授权请求（只触发一次）
    static BOOL alreadyRequested = NO;
    if (!alreadyRequested &&
        [[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/cleanshot-cn-request-screen"]) {
        alreadyRequested = YES;
        if (!granted) {
            CNLogLineTo(@"/tmp/cleanshot-cn-perm.log", @"已请求系统弹出授权对话框\n");
            CGRequestScreenCaptureAccess();
        }
    }
}

static void CNDebugProbeLocalization(void) {
    static BOOL done = NO;
    if (done) return;
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/cleanshot-cn-probe"]) return;
    done = YES;

    NSBundle *b = [NSBundle mainBundle];
    CNLogLineTo(@"/tmp/cleanshot-cn-probe.log",
                [NSString stringWithFormat:@"bundle=%@\npreferred=%@\nlocalizations=%@\n\n",
                 b.bundlePath, b.preferredLocalizations, b.localizations]);

    // 这些是截图里实际显示为英文的串 + 一个已知翻译成功的串作对照
    NSArray *probes = @[
        @"Launch at login",              // 截图里是英文
        @"Show menu bar icon",           // 截图里是英文
        @"Hide desktop icons while capturing", // 截图里是英文
        @"Desktop",                      // 翻译表里有，但截图里是英文 ← 关键对照
        @"Choose...",                    // 翻译表里有，但截图里是英文 ← 关键对照
        @"Play sounds",                  // 截图里已翻译成「播放声音」← 成功对照
        @"Sounds",                       // 截图里是英文（分组标题）
    ];
    for (NSString *p in probes) {
        NSString *viaBundle = [b localizedStringForKey:p value:@"__MISS__" table:nil];
        NSString *viaTable  = CNLookup(p);
        CNLogLineTo(@"/tmp/cleanshot-cn-probe.log",
                    [NSString stringWithFormat:
                     @"%@\n  Localizable.strings -> %@\n  翻译表(运行时)      -> %@\n\n",
                     p, viaBundle, viaTable ?: @"(无)"]);
    }
}

// 通过无障碍（Accessibility）树读取界面上「真实显示」的文字。
// SwiftUI 的 Text 不是 NSTextField，视图遍历读不到，
// 但 SwiftUI 会把文字暴露成无障碍元素，所以这是拿真实文案最可靠的办法。
static NSString *CNAXString(id v) {
    if (!v) return nil;
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [v stringValue];
    return nil;
}

static void CNDumpAX(id element, NSInteger depth) {
    if (!element || depth > 16) return;

    NSString *role = nil;
    @try {
        if ([element respondsToSelector:@selector(accessibilityRole)])
            role = CNAXString([element accessibilityRole]);
    } @catch (__unused NSException *e) {}

    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    @try {
        for (NSString *sel in @[@"accessibilityLabel", @"accessibilityTitle",
                                @"accessibilityValue", @"accessibilityDescription"]) {
            SEL s = NSSelectorFromString(sel);
            if (![element respondsToSelector:s]) continue;
            NSString *v = CNAXString([element performSelector:s]);
            if (v.length) [texts addObject:v];
        }
    } @catch (__unused NSException *e) {}

    for (NSString *t in texts) {
        if (t.length < 2 || t.length > 200) continue;
        NSString *trimmed = [t stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length < 2) continue;

        @synchronized (CNDumpedStrings) {
            if ([CNDumpedStrings containsObject:trimmed]) continue;
            [CNDumpedStrings addObject:trimmed];
        }
        NSString *tr = CNTranslate(trimmed);
        BOOL ok = ![tr isEqualToString:trimmed];
        CNLogLineTo(@"/tmp/cleanshot-cn-ui.log",
                    [NSString stringWithFormat:@"%@\t[%@ %@]\t%s\n",
                     ok ? @"OK  " : @"MISS", role ?: @"?", trimmed,
                     ok ? [tr UTF8String] : "(未翻译)"]);
    }

    NSArray *children = nil;
    @try {
        if ([element respondsToSelector:@selector(accessibilityChildren)])
            children = [element accessibilityChildren];
    } @catch (__unused NSException *e) {}
    if (!children.count) {
        @try {
            if ([element respondsToSelector:@selector(accessibilityVisibleChildren)])
                children = [element accessibilityVisibleChildren];
        } @catch (__unused NSException *e) {}
    }
    for (id c in children) CNDumpAX(c, depth + 1);
}

static void CNSwizzleInstanceMethod(Class cls, SEL original, SEL replacement);

// ── 抓取 SwiftUI 真正请求的本地化 key ────────────────────────
// SwiftUI 的 Text("字面量") 最终会走 NSBundle 的本地化查询。
// 把这条路径挂钩，就能拿到应用「真正想要翻译的 key」——
// 不管字符串是直接写的、还是运行时拼接的（比如带 Markdown 链接的描述），
// 都能原样捕获。这比反汇编猜字符串可靠得多。
static NSMutableSet<NSString *> *CNLoggedKeys;

@interface NSBundle (CleanShotCNKeys)
- (NSString *)cn_localizedStringForKey:(NSString *)key
                                 value:(NSString *)value
                                 table:(NSString *)tableName;
@end

@implementation NSBundle (CleanShotCNKeys)

- (NSString *)cn_localizedStringForKey:(NSString *)key
                                 value:(NSString *)value
                                 table:(NSString *)tableName {
    NSString *result = [self cn_localizedStringForKey:key value:value table:tableName];

    // 记录所有 bundle 的查询（含所属 bundle），
    // 用来判断 SwiftUI 文案到底走的是主 bundle 还是某个框架自己的 bundle。
    if (key.length > 1 && key.length < 300) {
        BOOL plausible = YES;
        for (NSUInteger i = 0; i < key.length; i++) {
            unichar c = [key characterAtIndex:i];
            if (c < 0x20 && c != '\n') { plausible = NO; break; }
        }
        if (plausible) {
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{ CNLoggedKeys = [NSMutableSet set]; });
            NSString *tag = [NSString stringWithFormat:@"%@|%@", self.bundlePath, key];
            BOOL isNew = NO;
            @synchronized (CNLoggedKeys) {
                if (![CNLoggedKeys containsObject:tag]) {
                    [CNLoggedKeys addObject:tag];
                    isNew = YES;
                }
            }
            if (isNew) {
                NSString *shortPath = self.bundlePath.lastPathComponent ?: @"(nil)";
                CNLogLineTo(@"/tmp/cleanshot-cn-keys.log",
                            [NSString stringWithFormat:@"%@\tbundle=%@\ttable=%@\tkey=[%@]\tresult=[%@]\n",
                             [key isEqualToString:result] ? @"MISS" : @"OK  ",
                             shortPath, tableName ?: @"(nil)", key, result ?: @"(nil)"]);
            }
        }
    }
    return result;
}

@end

static void CNInstallLocalizationHook(void) {
    CNSwizzleInstanceMethod([NSBundle class],
                            @selector(localizedStringForKey:value:table:),
                            @selector(cn_localizedStringForKey:value:table:));
}

// ── 拦截 CF 层本地化查询（SwiftUI 的真正通道）──────────────────
// 实测结论：把 zh-Hans.lproj/Localizable.strings 放进 bundle 后，
// SwiftUI 的 Text("字面量") 依然显示英文——说明它不走
// -[NSBundle localizedStringForKey:value:table:]，而是直接调用
// CoreFoundation 的 CFBundleCopyLocalizedString。
// 该函数在 CoreFoundation 里，调用点在 SwiftUI.framework 内，
// 所以对主可执行文件做 nm 是看不到引用的。
//
// 由于本 dylib 是被注入进目标进程的，可以用 Mach-O 的 __interpose 段
// 在进程内重绑定这个 C 函数，从而截获 SwiftUI 的每一次文案查询，
// 直接返回我们自己的译文——彻底绕开 bundle 的语言协商逻辑。
typedef CFStringRef (*CNCFLocalizedFn)(CFBundleRef, CFStringRef, CFStringRef, CFStringRef);
typedef CFStringRef (*CNCFLocalizedForLocFn)(CFBundleRef, CFStringRef, CFStringRef,
                                             CFStringRef, CFStringRef);

// 该符号存在于 CoreFoundation，但未必出现在当前 SDK 的公开头文件里，
// 因此自行声明，避免依赖 SDK 版本。
extern CFStringRef CFBundleCopyLocalizedStringForLocalization(CFBundleRef bundle,
                                                              CFStringRef key,
                                                              CFStringRef value,
                                                              CFStringRef tableName,
                                                              CFStringRef localizationName);

static CNCFLocalizedFn CNOrigCFLocalized = NULL;
static CNCFLocalizedForLocFn CNOrigCFLocalizedForLoc = NULL;
static void *CNCFHandle = NULL;

// 前置声明：自检时需要拿自己的地址做比较
static CFStringRef CNCFBundleCopyLocalizedString(CFBundleRef, CFStringRef, CFStringRef, CFStringRef);
static CFStringRef CNCFBundleCopyLocalizedStringForLocalization(CFBundleRef, CFStringRef,
                                                                CFStringRef, CFStringRef,
                                                                CFStringRef);

// 递归深度：本函数内部做日志/查表时会再次触发本地化查询，
// 必须防止自我重入（否则直接爆栈崩溃）。
static __thread NSInteger CNCFDepth = 0;

static void CNResolveOrigCFLocalized(void) {
    if (CNOrigCFLocalized && CNOrigCFLocalizedForLoc) return;

    if (!CNCFHandle) {
        // 直接从框架路径取原函数。
        // 注意：不能用 dlsym(RTLD_NEXT)，因为 __interpose 生效后
        // RTLD_NEXT 会解析回我们自己的替换函数，造成无限递归。
        const char *path = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";
        CNCFHandle = dlopen(path, RTLD_LAZY | RTLD_NOLOAD);
        if (!CNCFHandle) CNCFHandle = dlopen(path, RTLD_LAZY);
    }
    if (!CNCFHandle) return;

    if (!CNOrigCFLocalized) {
        CNOrigCFLocalized = (CNCFLocalizedFn)dlsym(CNCFHandle, "CFBundleCopyLocalizedString");
    }
    if (!CNOrigCFLocalizedForLoc) {
        CNOrigCFLocalizedForLoc =
            (CNCFLocalizedForLocFn)dlsym(CNCFHandle,
                                         "CFBundleCopyLocalizedStringForLocalization");
    }

    // 自检：万一还是解析到自己，必须弃用，否则递归
    if ((const void *)CNOrigCFLocalized == (const void *)CNCFBundleCopyLocalizedString) {
        CNOrigCFLocalized = NULL;
    }
    if ((const void *)CNOrigCFLocalizedForLoc ==
        (const void *)CNCFBundleCopyLocalizedStringForLocalization) {
        CNOrigCFLocalizedForLoc = NULL;
    }
}

// 命中翻译表就返回中文（+1 引用，与 CF 的 Copy 语义一致）
static CFStringRef CNTranslateCFString(CFStringRef key) {
    if (!key) return NULL;
    NSString *k = (__bridge NSString *)key;
    if (k.length < 2 || k.length > 300) return NULL;
    NSString *cn = CNTranslationTable()[k];
    if (!cn) return NULL;
    return (CFStringRef)CFBridgingRetain([cn copy]);
}

static void CNLogCFLookup(CFBundleRef bundle, CFStringRef key, CFStringRef result) {
    if (!key) return;
    NSString *k = (__bridge NSString *)key;
    if (k.length < 2 || k.length > 300) return;
    for (NSUInteger i = 0; i < k.length; i++) {
        unichar c = [k characterAtIndex:i];
        if (c < 0x20 && c != '\n') return;
    }

    NSString *bundlePath = @"(nil)";
    if (bundle) {
        CFURLRef url = CFBundleCopyBundleURL(bundle);
        if (url) {
            bundlePath = [(__bridge NSURL *)url lastPathComponent] ?: @"(nil)";
            CFRelease(url);
        }
    }

    static NSMutableSet<NSString *> *seen;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ seen = [NSMutableSet set]; });
    NSString *tag = [NSString stringWithFormat:@"%@|%@", bundlePath, k];
    @synchronized (seen) {
        if ([seen containsObject:tag]) return;
        [seen addObject:tag];
    }
    NSString *r = result ? (__bridge NSString *)result : @"(nil)";
    CNLogLineTo(@"/tmp/cleanshot-cn-cf.log",
                [NSString stringWithFormat:@"%@\tbundle=%@\tkey=[%@]\tresult=[%@]\n",
                 [k isEqualToString:r] ? @"MISS" : @"HIT ", bundlePath, k, r]);
}

// 统一的处理体：翻译 + 记录。返回非 NULL 表示已由我们接管。
static CFStringRef CNHandleCFLookup(CFBundleRef bundle, CFStringRef key, CFStringRef value,
                                    CFStringRef result) {
    if (CNCFDepth > 0) return NULL;           // 重入保护
    if (!key) return NULL;

    // 不再限制主 bundle：SwiftUI 的文案可能由框架自己的 bundle 承载，
    // 我们以「翻译表」为唯一事实来源，任何 bundle 的查询都按表翻译。
    CNCFDepth++;
    CFStringRef cn = CNTranslateCFString(key);
    CNLogCFLookup(bundle, key, result);
    CNCFDepth--;
    return cn;
}

static CFStringRef CNCFBundleCopyLocalizedString(CFBundleRef bundle,
                                                 CFStringRef key,
                                                 CFStringRef value,
                                                 CFStringRef tableName) {
    CNResolveOrigCFLocalized();

    // 重入时直接给出兜底值，避免在日志/查表过程中再次调用原实现
    if (CNCFDepth > 0) {
        if (value) return CFRetain(value);
        return key ? CFRetain(key) : NULL;
    }

    CFStringRef result = CNOrigCFLocalized ? CNOrigCFLocalized(bundle, key, value, tableName)
                                           : (value ? CFRetain(value) : (key ? CFRetain(key) : NULL));
    CFStringRef cn = CNHandleCFLookup(bundle, key, value, result);
    if (cn) {
        if (result) CFRelease(result);
        return cn;
    }
    return result;
}

static CFStringRef CNCFBundleCopyLocalizedStringForLocalization(CFBundleRef bundle,
                                                                CFStringRef key,
                                                                CFStringRef value,
                                                                CFStringRef tableName,
                                                                CFStringRef localization) {
    CNResolveOrigCFLocalized();

    if (CNCFDepth > 0) {
        if (value) return CFRetain(value);
        return key ? CFRetain(key) : NULL;
    }

    CFStringRef result = CNOrigCFLocalizedForLoc
        ? CNOrigCFLocalizedForLoc(bundle, key, value, tableName, localization)
        : (value ? CFRetain(value) : (key ? CFRetain(key) : NULL));
    CFStringRef cn = CNHandleCFLookup(bundle, key, value, result);
    if (cn) {
        if (result) CFRelease(result);
        return cn;
    }
    return result;
}

// __interpose 表：把 CF 函数在进程内重绑定到我们的实现
typedef struct { const void *replacement; const void *replacee; } CNInterposeEntry;

__attribute__((used))
static const CNInterposeEntry CNInterposeCFLocalized
    __attribute__((section("__DATA,__interpose"))) = {
        (const void *)CNCFBundleCopyLocalizedString,
        (const void *)CFBundleCopyLocalizedString
    };

__attribute__((used))
static const CNInterposeEntry CNInterposeCFLocalizedForLoc
    __attribute__((section("__DATA,__interpose"))) = {
        (const void *)CNCFBundleCopyLocalizedStringForLocalization,
        (const void *)CFBundleCopyLocalizedStringForLocalization
    };

static void CNInstallCFLocalizationHook(void) {
    // interpose 由 dyld 在加载时自动生效，这里只做一次自检记录
    CNResolveOrigCFLocalized();
    CNLogLineTo(@"/tmp/cleanshot-cn-cf.log",
                [NSString stringWithFormat:@"INIT\tCFBundleCopyLocalizedString=%@\t"
                                           @"CFBundleCopyLocalizedStringForLocalization=%@\n",
                 CNOrigCFLocalized ? @"已解析" : @"未解析(将只做兜底)",
                 CNOrigCFLocalizedForLoc ? @"已解析" : @"未解析(将只做兜底)"]);
}

// ── 拦截 CoreText 文本行创建（SwiftUI `Text(String)` 的通道）──────
// 有些 SwiftUI 文案是用「变量」而不是「字面量」构造的，
// 例如 Text(action.title)、Text(link.name)。
// 这种写法不产生 LocalizedStringKey，所以既不查 bundle、
// 也不经过任何本地化 API —— 上面两条通道都抓不到它。
//
// 但无论怎么渲染，最终都要交给 CoreText 生成文本行。
// 因此在 CTLineCreateWithAttributedString / CTTypesetterCreateWithAttributedString
// 上做拦截：命中翻译表就换成中文再交给原函数排版。
// 这样即使是运行时拼出来的字符串也能被翻译。
typedef CTLineRef (*CNCTLineFn)(CFAttributedStringRef);
typedef CTTypesetterRef (*CNCTTypesetterFn)(CFAttributedStringRef);

static CNCTLineFn CNOrigCTLine = NULL;
static CNCTTypesetterFn CNOrigCTTypesetter = NULL;
static void *CNCTHandle = NULL;

static CTLineRef CNCTLineCreateWithAttributedString(CFAttributedStringRef attrString);
static CTTypesetterRef CNCTTypesetterCreateWithAttributedString(CFAttributedStringRef attrString);

static void CNResolveCoreText(void) {
    if (CNOrigCTLine && CNOrigCTTypesetter) return;

    // 关键：不能用 dlsym(RTLD_NEXT / RTLD_DEFAULT / dlopen 句柄) 取原函数。
    // __interpose 生效后，这些途径都会解析回我们自己的替换函数（实测确认），
    // 直接调用会无限递归。
    //
    // 但「本镜像内的直接引用」不会被 interpose 改写：
    // dyld 不会替换定义 interpose 的那个镜像自身的绑定。
    // 实测 &CTLineCreateWithAttributedString 仍指向 CoreText 的真实实现，
    // 所以直接用函数名取地址即可。
    if (!CNOrigCTLine) {
        CNOrigCTLine = (CNCTLineFn)(const void *)CTLineCreateWithAttributedString;
    }
    if (!CNOrigCTTypesetter) {
        CNOrigCTTypesetter =
            (CNCTTypesetterFn)(const void *)CTTypesetterCreateWithAttributedString;
    }

    // 兜底自检：万一还是解析到自己，必须弃用，否则递归
    if ((const void *)CNOrigCTLine == (const void *)CNCTLineCreateWithAttributedString) {
        CNOrigCTLine = NULL;
    }
    if ((const void *)CNOrigCTTypesetter ==
        (const void *)CNCTTypesetterCreateWithAttributedString) {
        CNOrigCTTypesetter = NULL;
    }
}

static __thread NSInteger CNCTDepth = 0;
static __thread const char *CNCTTag = NULL;

// 诊断开关：只有存在 /tmp/cleanshot-cn-ct-dump 时才把渲染层文案写日志。
// 日常使用不写盘，避免无谓开销。总开关 /tmp/cleanshot-cn-debug 同样能打开它。
static BOOL CNCTLogEnabled(void) {
    static BOOL enabled = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        enabled = [fm fileExistsAtPath:@"/tmp/cleanshot-cn-ct-dump"] ||
                  CNDebugLogEnabled();
    });
    return enabled;
}

static void CNLogCTString(NSString *s) {
    if (!CNCTLogEnabled()) return;
    if (s.length < 2 || s.length > 2000) return;
    static NSMutableSet<NSString *> *seen;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ seen = [NSMutableSet set]; });
    BOOL isNew = NO;
    @synchronized (seen) {
        if (![seen containsObject:s]) {
            [seen addObject:s];
            isNew = YES;
        }
    }
    if (!isNew) return;
    NSString *cn = CNLookup(s);
    CNLogLineTo(@"/tmp/cleanshot-cn-ct.log",
                [NSString stringWithFormat:@"%@\t[%@]\t->\t%@\tvia=%s\n",
                 cn ? @"HIT " : @"MISS", s, cn ?: @"(未翻译)",
                 CNCTTag ? CNCTTag : "?"]);
}

// 命中翻译表时返回替换后的属性串（+1 引用，调用方负责释放）；未命中返回 NULL。
static CFAttributedStringRef CNTranslateAttributedString(CFAttributedStringRef attr) {
    if (!attr) return NULL;
    CFStringRef raw = CFAttributedStringGetString(attr);
    if (!raw) return NULL;
    NSString *s = (__bridge NSString *)raw;
    if (s.length < 2 || s.length > 300) return NULL;
    NSString *cn = CNLookup(s);
    if (!cn) return NULL;

    CFMutableAttributedStringRef mut = CFAttributedStringCreateMutableCopy(NULL, 0, attr);
    if (!mut) return NULL;
    CFAttributedStringReplaceString(mut, CFRangeMake(0, CFAttributedStringGetLength(mut)),
                                    (__bridge CFStringRef)cn);
    return mut;
}

static CTLineRef CNCTLineCreateWithAttributedString(CFAttributedStringRef attrString) {
    if (CNCTDepth > 0) {
        return CNOrigCTLine ? CNOrigCTLine(attrString) : NULL;
    }
    CNResolveCoreText();
    if (!CNOrigCTLine) return NULL;

    CNCTDepth++;
    if (attrString) {
        CFStringRef raw = CFAttributedStringGetString(attrString);
        if (raw) { CNCTTag = "CTLine"; CNLogCTString((__bridge NSString *)raw); }
    }
    CFAttributedStringRef replaced = CNTranslateAttributedString(attrString);
    CNCTDepth--;

    if (replaced) {
        CTLineRef line = CNOrigCTLine(replaced);
        CFRelease(replaced);
        if (line) return line;
    }
    return CNOrigCTLine(attrString);
}

static CTTypesetterRef CNCTTypesetterCreateWithAttributedString(CFAttributedStringRef attrString) {
    if (CNCTDepth > 0) {
        return CNOrigCTTypesetter ? CNOrigCTTypesetter(attrString) : NULL;
    }
    CNResolveCoreText();
    if (!CNOrigCTTypesetter) return NULL;

    CNCTDepth++;
    if (attrString) {
        CFStringRef raw = CFAttributedStringGetString(attrString);
        if (raw) { CNCTTag = "CTTypesetter"; CNLogCTString((__bridge NSString *)raw); }
    }
    CFAttributedStringRef replaced = CNTranslateAttributedString(attrString);
    CNCTDepth--;

    if (replaced) {
        CTTypesetterRef ts = CNOrigCTTypesetter(replaced);
        CFRelease(replaced);
        if (ts) return ts;
    }
    return CNOrigCTTypesetter(attrString);
}

// 带 options 的变体：SwiftUI 对富文本可能走这条
static CTTypesetterRef
CNCTTypesetterCreateWithAttributedStringAndOptions(CFAttributedStringRef attrString,
                                                   CFDictionaryRef options) {
    if (CNCTDepth > 0) {
        return CTTypesetterCreateWithAttributedStringAndOptions(attrString, options);
    }
    if (attrString) {
        CFStringRef raw = CFAttributedStringGetString(attrString);
        if (raw) { CNCTTag = "CTTypesetterOpt"; CNLogCTString((__bridge NSString *)raw); }
    }
    CNCTDepth++;
    CFAttributedStringRef replaced = CNTranslateAttributedString(attrString);
    CNCTDepth--;
    if (replaced) {
        CTTypesetterRef ts = CTTypesetterCreateWithAttributedStringAndOptions(replaced, options);
        CFRelease(replaced);
        if (ts) return ts;
    }
    return CTTypesetterCreateWithAttributedStringAndOptions(attrString, options);
}

__attribute__((used))
static const CNInterposeEntry CNInterposeCTTypesetterOpt
    __attribute__((section("__DATA,__interpose"))) = {
        (const void *)CNCTTypesetterCreateWithAttributedStringAndOptions,
        (const void *)CTTypesetterCreateWithAttributedStringAndOptions
    };

// ── 诊断：带 Markdown 链接的富文本到底在哪一层构造 ──
// SwiftUI 里 Text("... [链接](url) ...") 这类富文本既不经过 CTLine，
// 也不经过 CTFramesetter。这里挂钩属性串的构造点，找出真实通道。
static CFAttributedStringRef CNCFAttributedStringCreate(CFAllocatorRef allocator,
                                                        CFStringRef str,
                                                        CFDictionaryRef attributes) {
    if (CNCTDepth != 0 || !str) {
        return CFAttributedStringCreate(allocator, str, attributes);
    }

    CNCTDepth++;
    if (CNCTLogEnabled()) { CNCTTag = "CFAttrCreate"; CNLogCTString((__bridge NSString *)str); }
    NSString *cn = CNLookup((__bridge NSString *)str);
    CNCTDepth--;

    if (!cn) return CFAttributedStringCreate(allocator, str, attributes);

    CFStringRef translated = (CFStringRef)CFBridgingRetain([cn copy]);
    CFAttributedStringRef out = CFAttributedStringCreate(allocator, translated, attributes);
    CFRelease(translated);
    return out;
}

__attribute__((used))
static const CNInterposeEntry CNInterposeCFAttrStrCreate
    __attribute__((section("__DATA,__interpose"))) = {
        (const void *)CNCFAttributedStringCreate,
        (const void *)CFAttributedStringCreate
    };

@interface NSAttributedString (CleanShotCNDiag)
- (instancetype)cn_initWithString:(NSString *)str attributes:(NSDictionary *)attrs;
- (NSAttributedString *)cn_translatedForDrawing;
- (void)cn_drawAtPoint:(NSPoint)point;
- (void)cn_drawInRect:(NSRect)rect;
- (void)cn_drawWithRect:(NSRect)rect options:(NSStringDrawingOptions)options
                context:(NSStringDrawingContext *)context;
@end

@implementation NSAttributedString (CleanShotCNDiag)
- (instancetype)cn_initWithString:(NSString *)str attributes:(NSDictionary *)attrs {
    // 这里只记录、不翻译：属性串往往由多段拼装而成，
    // 逐段翻译会让链接文字先变中文，反而破坏整句的匹配。
    // 整句翻译统一放在绘制点（cn_translatedForDrawing）处理。
    if (CNCTDepth == 0 && str.length >= 2 && CNCTLogEnabled()) {
        CNCTDepth++;
        CNCTTag = "NSAttrInit"; CNLogCTString(str);
        CNCTDepth--;
    }
    return [self cn_initWithString:str attributes:attrs];
}
// 绘制点翻译：把整条属性串换成中文，同时尽量保留原有属性与链接范围。
// 之所以必须在这一层兜底：SwiftUI 里带 Markdown 链接的富文本，
// 既不在 CTLine 通道，也不走 initWithString:attributes:，
// 只有真正落笔绘制时才拿得到「解析后的完整句子」。
- (NSAttributedString *)cn_translatedForDrawing {
    if (self.length < 2 || self.length > 300) return nil;
    NSString *cn = CNLookup(self.string);
    if (!cn) return nil;

    NSMutableAttributedString *out =
        [[NSMutableAttributedString alloc] initWithString:cn];

    // 1) 把原文的非链接属性铺到整条译文上（字体、颜色、段落样式）
    NSRange full = NSMakeRange(0, self.length);
    [self enumerateAttributesInRange:full options:0
                          usingBlock:^(NSDictionary<NSAttributedStringKey, id> *attrs,
                                       NSRange range, BOOL *stop) {
        NSMutableDictionary *clean = [attrs mutableCopy];
        [clean removeObjectForKey:NSLinkAttributeName];
        if (clean.count) [out addAttributes:clean range:NSMakeRange(0, out.length)];
    }];

    // 2) 逐条链接：在译文里找到对应文字，把链接属性贴回去
    [self enumerateAttribute:NSLinkAttributeName inRange:full options:0
                  usingBlock:^(id value, NSRange range, BOOL *stop) {
        if (!value || range.location == NSNotFound) return;
        NSString *linkText = [self.string substringWithRange:range];
        NSString *linkCN = CNLookup(linkText) ?: linkText;
        NSRange found = [cn rangeOfString:linkCN];
        if (found.location != NSNotFound) {
            [out addAttribute:NSLinkAttributeName value:value range:found];
        }
    }];

    return out;
}

- (void)cn_drawAtPoint:(NSPoint)point {
    CNCTTag = "drawAtPoint"; CNLogCTString(self.string);
    NSAttributedString *t = [self cn_translatedForDrawing];
    if (t) { [t cn_drawAtPoint:point]; return; }
    [self cn_drawAtPoint:point];
}
- (void)cn_drawInRect:(NSRect)rect {
    CNCTTag = "drawInRect"; CNLogCTString(self.string);
    NSAttributedString *t = [self cn_translatedForDrawing];
    if (t) { [t cn_drawInRect:rect]; return; }
    [self cn_drawInRect:rect];
}
- (void)cn_drawWithRect:(NSRect)rect options:(NSStringDrawingOptions)options
                context:(NSStringDrawingContext *)context {
    CNCTTag = "drawWithRect"; CNLogCTString(self.string);
    NSAttributedString *t = [self cn_translatedForDrawing];
    if (t) { [t cn_drawWithRect:rect options:options context:context]; return; }
    [self cn_drawWithRect:rect options:options context:context];
}
@end

// Framesetter：多行 / 带链接的富文本走的是这条通道
static CTFramesetterRef CNCTFramesetterCreateWithAttributedString(CFAttributedStringRef attrString) {
    if (CNCTDepth > 0) {
        return CTFramesetterCreateWithAttributedString(attrString);
    }
    if (attrString) {
        CFStringRef raw = CFAttributedStringGetString(attrString);
        if (raw) { CNCTTag = "CTFramesetter"; CNLogCTString((__bridge NSString *)raw); }
    }
    CNCTDepth++;
    CFAttributedStringRef replaced = CNTranslateAttributedString(attrString);
    CNCTDepth--;
    if (replaced) {
        CTFramesetterRef fs = CTFramesetterCreateWithAttributedString(replaced);
        CFRelease(replaced);
        if (fs) return fs;
    }
    return CTFramesetterCreateWithAttributedString(attrString);
}

__attribute__((used))
static const CNInterposeEntry CNInterposeCTLine
    __attribute__((section("__DATA,__interpose"))) = {
        (const void *)CNCTLineCreateWithAttributedString,
        (const void *)CTLineCreateWithAttributedString
    };

__attribute__((used))
static const CNInterposeEntry CNInterposeCTTypesetter
    __attribute__((section("__DATA,__interpose"))) = {
        (const void *)CNCTTypesetterCreateWithAttributedString,
        (const void *)CTTypesetterCreateWithAttributedString
    };

__attribute__((used))
static const CNInterposeEntry CNInterposeCTFramesetter
    __attribute__((section("__DATA,__interpose"))) = {
        (const void *)CNCTFramesetterCreateWithAttributedString,
        (const void *)CTFramesetterCreateWithAttributedString
    };

// 诊断：搞清楚在 __interpose 生效的情况下，
// 各种取「原函数」的写法分别拿到什么地址。
static void CNDiagCoreTextAddresses(void) {
    const char *sym = "CTLineCreateWithAttributedString";
    void *self_ = (void *)CNCTLineCreateWithAttributedString;
    void *direct = (void *)CTLineCreateWithAttributedString;
    void *next = dlsym(RTLD_NEXT, sym);
    void *def = dlsym(RTLD_DEFAULT, sym);
    void *h1 = NULL, *h2 = NULL;
    void *handle = dlopen("/System/Library/Frameworks/CoreText.framework/CoreText",
                          RTLD_LAZY | RTLD_NOLOAD);
    if (handle) h1 = dlsym(handle, sym);
    void *handleFirst = dlopen("/System/Library/Frameworks/CoreText.framework/CoreText",
                               RTLD_LAZY | RTLD_FIRST);
    if (handleFirst) h2 = dlsym(handleFirst, sym);

    // 直接同步写文件：这一步可能在崩溃前完成，必须保证落盘
    FILE *fp = fopen("/tmp/cleanshot-cn-ct.log", "a");
    if (fp) {
        fprintf(fp,
                "DIAG\t我们的替换=%p\nDIAG\t直接引用&sym=%p\nDIAG\tRTLD_NEXT=%p\n"
                "DIAG\tRTLD_DEFAULT=%p\nDIAG\tdlopen(handle)=%p\nDIAG\tdlopen(FIRST)=%p\n",
                self_, direct, next, def, h1, h2);
        fclose(fp);
    }
}

static void CNInstallCoreTextHook(void) {
    if (CNCTLogEnabled()) CNDiagCoreTextAddresses();

    // 常驻：AppKit 侧构造属性串时顺带翻译。
    // SwiftUI 里带 Markdown 链接的富文本最终是在这一层构造出「解析后的纯文本」，
    // 而它的绘制不经过 CTLine，所以必须在构造点就把文案换掉。
    Class concrete = NSClassFromString(@"NSConcreteAttributedString");
    if (concrete) {
        CNSwizzleInstanceMethod(concrete, @selector(initWithString:attributes:),
                                @selector(cn_initWithString:attributes:));
    }

    {
        CNSwizzleInstanceMethod([NSAttributedString class], @selector(drawAtPoint:),
                                @selector(cn_drawAtPoint:));
        CNSwizzleInstanceMethod([NSAttributedString class], @selector(drawInRect:),
                                @selector(cn_drawInRect:));
        CNSwizzleInstanceMethod([NSAttributedString class],
                                @selector(drawWithRect:options:context:),
                                @selector(cn_drawWithRect:options:context:));
    }
    CNResolveCoreText();
    if (CNCTLogEnabled()) {
        CNLogLineTo(@"/tmp/cleanshot-cn-ct.log",
                    [NSString stringWithFormat:@"INIT\tCTLine=%@\tCTTypesetter=%@\n",
                     CNOrigCTLine ? @"已解析" : @"未解析(将只做兜底)",
                     CNOrigCTTypesetter ? @"已解析" : @"未解析(将只做兜底)"]);
    }
}

// ── 调试辅助 ──────────────────────────────────────────────
// 若存在标记文件 /tmp/cleanshot-cn-open-prefs，启动约 6 秒后自动触发
// 状态栏菜单里的「偏好设置 / 设置」项，把设置窗口打开。
// 目的：让界面文案日志能采集到设置窗口里的文本，无需人工点击。
// 标记文件不存在时完全不动作，不影响日常使用。
static void CNDebugMaybeOpenPreferences(void) {
    static BOOL alreadyTried = NO;
    if (alreadyTried) return;
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/cleanshot-cn-open-prefs"]) return;
    alreadyTried = YES;
    if (!CNStatusMenus) return;

    @synchronized (CNStatusMenus) {
        for (NSMenu *menu in CNStatusMenus.allObjects) {
            for (NSMenuItem *mi in menu.itemArray) {
                NSString *t = mi.title ?: @"";
                BOOL isPrefs = [t containsString:@"偏好设置"] || [t containsString:@"Preferences"] ||
                               [t containsString:@"设置"]     || [t containsString:@"Settings"];
                if (!isPrefs) continue;

                CNLogLineTo(@"/tmp/cleanshot-cn-ui.log",
                            [NSString stringWithFormat:@"DEBUG\t触发菜单项 [%@] action=%@\n",
                             t, mi.action ? NSStringFromSelector(mi.action) : @"(nil)"]);
                if (mi.action) {
                    [NSApp sendAction:mi.action to:mi.target from:mi];
                }
                return;
            }
        }
        CNLogLineTo(@"/tmp/cleanshot-cn-ui.log", @"DEBUG\t没找到偏好设置菜单项\n");
    }
}

@implementation NSMenu (CleanShotCNPatch)

- (void)cn_insertItem:(NSMenuItem *)item atIndex:(NSInteger)index {
    CNHandleMenuItem(item);
    // swizzle 之后，cn_ 前缀指向的是原始实现
    [self cn_insertItem:item atIndex:index];
}

- (void)cn_addItem:(NSMenuItem *)item {
    CNHandleMenuItem(item);
    [self cn_addItem:item];
}

- (void)cn_setItems:(NSArray<NSMenuItem *> *)items {
    for (NSMenuItem *mi in items) CNHandleMenuItem(mi);
    [self cn_setItems:items];
}

- (BOOL)cn_popUpMenuPositioningItem:(NSMenuItem *)item
                         atLocation:(NSPoint)location
                             inView:(NSView *)view {
    // 弹出前再兜一次，覆盖运行时动态改过标题的项
    for (NSMenuItem *mi in self.itemArray) CNHandleMenuItem(mi);
    return [self cn_popUpMenuPositioningItem:item atLocation:location inView:view];
}

@end

@interface NSStatusItem (CleanShotCNPatch)
- (void)cn_setMenu:(NSMenu *)menu;
@end

@implementation NSStatusItem (CleanShotCNPatch)

- (void)cn_setMenu:(NSMenu *)menu {
    CNRememberStatusMenu(menu);
    [self cn_setMenu:menu];
}

@end

static void CNSwizzleInstanceMethod(Class cls, SEL original, SEL replacement) {
    Method m1 = class_getInstanceMethod(cls, original);
    Method m2 = class_getInstanceMethod(cls, replacement);
    if (m1 && m2) method_exchangeImplementations(m1, m2);
}

static void CNInstallMenuHooks(void) {
    CNSwizzleInstanceMethod([NSMenu class],
                            @selector(insertItem:atIndex:),
                            @selector(cn_insertItem:atIndex:));
    CNSwizzleInstanceMethod([NSMenu class],
                            @selector(addItem:),
                            @selector(cn_addItem:));
    CNSwizzleInstanceMethod([NSMenu class],
                            @selector(setItems:),
                            @selector(cn_setItems:));
    CNSwizzleInstanceMethod([NSMenu class],
                            @selector(popUpMenuPositioningItem:atLocation:inView:),
                            @selector(cn_popUpMenuPositioningItem:atLocation:inView:));
    CNSwizzleInstanceMethod([NSStatusItem class],
                            @selector(setMenu:),
                            @selector(cn_setMenu:));
}

// ── 进程内设置页驱动器 ────────────────────────────────────
// 目的：自动把设置窗口的每个侧边栏页签点一遍，让 SwiftUI 重新渲染，
// 从而把应用真正查询的本地化 key 全部逼到 NSBundle 钩子的日志里。
// 仅当 /tmp/cleanshot-cn-cycle 标记文件存在时才动作。
// 只做声明，不实现：运行时用 respondsToSelector 保护后再调用，
// 避免为探测引入假的 NSView 子类。
@interface NSView (CNIntrospect)
- (NSString *)title;
- (NSString *)stringValue;
@end

static void CNCollectByClassFragment(NSView *view, NSString *frag, NSMutableArray<NSView *> *out) {
    if ([NSStringFromClass(view.class) containsString:frag]) [out addObject:view];
    for (NSView *sub in view.subviews) CNCollectByClassFragment(sub, frag, out);
}

static NSWindow *CNFindSettingsWindow(void) {
    for (NSWindow *w in NSApp.windows) {
        if (!w.isVisible) continue;
        if ([NSStringFromClass(w.class) containsString:@"SingleWindow"]) return w;
    }
    return nil;
}

// 在窗口内以坐标点合成一次左键点击（进程内投递，不需要辅助功能权限）
static void CNClickPointInWindow(NSWindow *window, NSPoint p) {
    NSTimeInterval t = [NSProcessInfo processInfo].systemUptime;
    NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                       location:p
                                  modifierFlags:0
                                      timestamp:t
                                   windowNumber:window.windowNumber
                                        context:nil
                                    eventNumber:0
                                     clickCount:1
                                       pressure:1.0];
    NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp
                                     location:p
                                modifierFlags:0
                                    timestamp:t + 0.06
                                 windowNumber:window.windowNumber
                                      context:nil
                                  eventNumber:1
                                   clickCount:1
                                     pressure:0.0];
    [window sendEvent:down];
    [window sendEvent:up];
}

static void CNClickViewCenter(NSView *view, NSWindow *window) {
    NSRect inWindow = [view convertRect:view.bounds toView:nil];
    NSPoint center = NSMakePoint(NSMidX(inWindow), NSMidY(inWindow));
    CNClickPointInWindow(window, center);
}

static NSString *CNViewText(NSView *v) {
    if ([v isKindOfClass:[NSTextField class]]) return [(NSTextField *)v stringValue] ?: @"";
    if ([v respondsToSelector:@selector(title)]) {
        NSString *t = [v title];
        if (t) return t;
    }
    return @"";
}

static void CNDebugDriveTabs(void) {
    static BOOL started = NO;
    if (started) return;
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/cleanshot-cn-cycle"]) return;

    NSWindow *win = CNFindSettingsWindow();
    if (!win) return;
    started = YES;

    NSString *log = @"/tmp/cleanshot-cn-cycle.log";
    CNLogLineTo(log, @"==== 开始遍历设置页签 ====\n");

    // 把窗口在屏幕上的位置换算成 screencapture -R 的参数写出去，
    // 方便外部脚本按节奏对每个页签截图核对。
    NSScreen *scr = win.screen ?: [NSScreen mainScreen];
    NSRect wf = win.frame;
    CGFloat topY = scr.frame.size.height - (wf.origin.y + wf.size.height);
    NSString *rect = [NSString stringWithFormat:@"%.0f,%.0f,%.0f,%.0f",
                      wf.origin.x, topY, wf.size.width, wf.size.height];
    [rect writeToFile:@"/tmp/cleanshot-cn-rect"
           atomically:YES
             encoding:NSUTF8StringEncoding
                error:nil];
    CNLogLineTo(log, [NSString stringWithFormat:@"WINDOW_RECT\t%@\n", rect]);

    NSMutableArray<NSView *> *controls = [NSMutableArray array];
    CNCollectByClassFragment(win.contentView, @"PRMenuControl", controls);
    CNLogLineTo(log, [NSString stringWithFormat:@"PRMenuControl 数量=%lu\n",
                      (unsigned long)controls.count]);

    // 侧边栏行 = PRMenuControl 内部的 NSTextField 标签
    NSMutableArray<NSView *> *rows = [NSMutableArray array];
    for (NSView *c in controls) CNCollectByClassFragment(c, @"NSTextField", rows);
    if (rows.count == 0) {
        // 兜底：整个窗口里类名带 SimpleLabel 的
        CNCollectByClassFragment(win.contentView, @"SimpleLabel", rows);
    }
    CNLogLineTo(log, [NSString stringWithFormat:@"候选行数量=%lu\n", (unsigned long)rows.count]);

    // 去重：同一位置会有 NSTextField 与 NSTextFieldSimpleLabel 两层
    NSMutableArray<NSView *> *uniqueRows = [NSMutableArray array];
    NSMutableSet<NSString *> *seenFrames = [NSMutableSet set];
    for (NSView *r in rows) {
        NSRect inWin = [r convertRect:r.bounds toView:nil];
        NSString *key = NSStringFromRect(inWin);
        if ([seenFrames containsObject:key]) continue;
        [seenFrames addObject:key];
        [uniqueRows addObject:r];
        CNLogLineTo(log, [NSString stringWithFormat:@"ROW\t[%@]\tframe=%@\ttext=[%@]\n",
                          NSStringFromClass(r.class), key, CNViewText(r)]);
    }

    // 依次点击每一行，中间留出渲染时间
    __block NSUInteger idx = 0;
    __block void (^next)(void);
    next = ^{
        if (idx >= uniqueRows.count) {
            CNLogLineTo(log, @"==== 遍历结束 ====\n");
            return;
        }
        NSView *r = uniqueRows[idx];
        NSRect inWin = [r convertRect:r.bounds toView:nil];
        CNLogLineTo(log, [NSString stringWithFormat:@"CLICK#%lu\ttext=[%@]\tpt=(%.0f,%.0f)\n",
                          (unsigned long)idx, CNViewText(r), NSMidX(inWin), NSMidY(inWin)]);
        CNClickViewCenter(r, win);
        idx++;
        // 停留久一点，方便外部按节奏截图
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            CNDebugDumpWindows();
            next();
        });
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), next);
}

__attribute__((constructor))
static void CleanShotCNInit(void) {
    @autoreleasepool {
        // 尽早装钩子：此时菜单还没被构建，状态栏菜单也在其列
        CNInstallMenuHooks();
        CNInstallLocalizationHook();
        CNInstallCFLocalizationHook();
        CNInstallCoreTextHook();

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidBecomeKeyNotification
                                                              object:nil
                                                               queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(__unused NSNotification *note) {
                if (CNMechanismAEnabled()) CNTranslateVisibleUI();
            }];

            [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidUpdateNotification
                                                              object:nil
                                                               queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(__unused NSNotification *note) {
                if (CNMechanismAEnabled()) CNTranslateVisibleUI();
            }];

            __block NSInteger cnTick = 0;
            [NSTimer scheduledTimerWithTimeInterval:0.5
                                            repeats:YES
                                              block:^(__unused NSTimer *timer) {
                if (CNMechanismAEnabled()) {
                    CNTranslateVisibleUI();
                    CNTranslateStatusMenus();
                }
                if (++cnTick == 12) CNDebugMaybeOpenPreferences();
                // 查询屏幕录制权限真实状态
                if (cnTick == 4 || cnTick % 40 == 0) CNCheckScreenPermission(@"定期检查");
                if (cnTick == 8) CNDebugProbeLocalization();
                // 设置窗口打开后，自动把侧边栏页签点一遍采集文案
                if (cnTick == 22) CNDebugDriveTabs();
                // 窗口打开后分几次抓取，最多 4 次（内容去重，重复抓不会刷屏）
                static NSInteger dumpCount = 0;
                if (cnTick > 18 && cnTick % 8 == 0 && dumpCount < 4 &&
                    [[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/cleanshot-cn-open-prefs"]) {
                    dumpCount++;
                    CNDebugDumpWindows();
                }
            }];

            if (CNDebugLogEnabled()) {
                [@"CleanShotCN runtime translator loaded\n" writeToFile:@"/tmp/cleanshot-cn.log"
                                                            atomically:YES
                                                              encoding:NSUTF8StringEncoding
                                                                 error:nil];
            }
        });
    }
}
