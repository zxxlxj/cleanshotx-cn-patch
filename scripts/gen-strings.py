#!/usr/bin/env python3
"""从 src/translations.txt 生成：
   1) build/zh-Hans.lproj/Localizable.strings  —— 系统语言包
   2) src/GeneratedCNTable.h                   —— 运行时翻译表（供 dylib 编译）

translations.txt 每行格式：英文原文<TAB>简体中文
以 # 开头的行是注释，空行忽略。
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_TXT = os.path.join(ROOT, "src", "translations.txt")
OUT_STRINGS = os.path.join(ROOT, "build", "zh-Hans.lproj", "Localizable.strings")
OUT_HEADER = os.path.join(ROOT, "src", "GeneratedCNTable.h")


def load_pairs(path):
    pairs = {}
    order = []
    if not os.path.exists(path):
        return pairs, order
    with open(path, encoding="utf-8") as f:
        for lineno, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            if "\t" not in line:
                print(f"  [跳过] 第 {lineno} 行缺少制表符：{line[:60]}")
                continue
            key, val = line.split("\t", 1)
            key, val = key.strip(), val.strip()
            if not key or not val:
                print(f"  [跳过] 第 {lineno} 行键或值为空")
                continue
            if key in pairs:
                print(f"  [覆盖] 重复键：{key}")
            else:
                order.append(key)
            pairs[key] = val
    return pairs, order


def esc_objc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def main():
    pairs, order = load_pairs(SRC_TXT)
    print(f"读入词条：{len(pairs)} 条")

    # 1) Localizable.strings
    os.makedirs(os.path.dirname(OUT_STRINGS), exist_ok=True)
    with open(OUT_STRINGS, "w", encoding="utf-8") as f:
        f.write("/* 由 scripts/gen-strings.py 自动生成，请勿手改 */\n")
        f.write("/* 源：src/translations.txt */\n\n")
        for key in sorted(pairs):
            f.write(f'"{esc_objc(key)}" = "{esc_objc(pairs[key])}";\n')
    print(f"已生成：{OUT_STRINGS}")

    # 2) GeneratedCNTable.h
    with open(OUT_HEADER, "w", encoding="utf-8") as f:
        f.write("// 由 scripts/gen-strings.py 自动生成，请勿手改\n")
        f.write("// 源：src/translations.txt\n")
        f.write("#pragma once\n\n")
        f.write("static NSDictionary<NSString *, NSString *> *CNGeneratedTranslations(void) {\n")
        f.write("    static NSDictionary<NSString *, NSString *> *map;\n")
        f.write("    static dispatch_once_t onceToken;\n")
        f.write("    dispatch_once(&onceToken, ^{\n")
        f.write("        map = @{\n")
        for key in order:
            f.write(f'            @"{esc_objc(key)}": @"{esc_objc(pairs[key])}",\n')
        f.write("        };\n")
        f.write("    });\n")
        f.write("    return map;\n")
        f.write("}\n")
    print(f"已生成：{OUT_HEADER}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
