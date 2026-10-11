#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
整理 src/translations.txt：
  - 去掉重复键（保留第一次出现的译文）
  - 去掉行尾多余空白、压缩连续空行
  - 保留注释行，并把注释归拢到它所属的分组前

用法：
  python3 scripts/dedupe-translations.py            # 预览
  python3 scripts/dedupe-translations.py --write    # 实际写回
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TRANS = os.path.join(ROOT, "src", "translations.txt")


def main():
    write = "--write" in sys.argv

    out_lines = []
    seen = {}
    dropped = []

    for raw in open(TRANS, encoding="utf-8"):
        line = raw.rstrip("\n").rstrip()
        if not line:
            if out_lines and out_lines[-1] != "":
                out_lines.append("")
            continue
        if line.lstrip().startswith("#") or "\t" not in line:
            out_lines.append(line)
            continue

        key, value = line.split("\t", 1)
        key = key.strip()
        value = value.strip()
        if key in seen:
            dropped.append((key, seen[key], value))
            continue
        seen[key] = value
        out_lines.append("%s\t%s" % (key, value))

    while out_lines and out_lines[-1] == "":
        out_lines.pop()

    print("保留词条：%d 条，丢弃重复：%d 条" % (len(seen), len(dropped)))
    for k, first, later in dropped:
        print("  重复键 %r：保留 %r，丢弃 %r" % (k, first, later))

    if write:
        with open(TRANS, "w", encoding="utf-8") as f:
            f.write("\n".join(out_lines) + "\n")
        print("已写回 %s" % TRANS)
    else:
        print("（预览模式，未改动文件；加 --write 生效）")


if __name__ == "__main__":
    main()
