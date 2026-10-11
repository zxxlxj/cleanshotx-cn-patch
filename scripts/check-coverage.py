#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""统计汉化补丁的翻译表在本机 CleanShot X 上的实际命中率。

注意：编译后的 nib 是二进制格式，字符串不是按行分隔的，
所以必须用「整块字节流子串匹配」，不能按 token 精确比对。
"""
import re, subprocess, pathlib

APP = pathlib.Path("/Applications/CleanShot X.app")
TRANS_FILE = pathlib.Path(__file__).resolve().parent.parent / "src" / "translations.txt"

# 1. 解析翻译表（唯一数据源：src/translations.txt，由 gen-strings.py 生成 C 头文件）
keys = []
for line in TRANS_FILE.read_text(encoding="utf-8").splitlines():
    if not line.strip() or line.lstrip().startswith("#") or "\t" not in line:
        continue
    keys.append(line.split("\t", 1)[0])
print(f"翻译表条目数：{len(keys)}")

# 2. 把应用里所有可能承载界面文本的字节拼成一个大 blob
blob = bytearray()

def feed(p: pathlib.Path):
    try:
        blob.extend(p.read_bytes())
    except Exception:
        pass

for p in APP.rglob("*"):
    if p.is_file():
        feed(p)   # 资源 + nib + 所有 framework，全量扫

# 主程序与可执行文件走 strings（Mach-O 里字符串以 \0 分隔，直接读原字节同样有效）
for p in APP.rglob("*"):
    if p.is_file() and p.stat().st_mode & 0o111:
        feed(p)

haystack = bytes(blob)
print(f"扫描字节总量：{len(haystack)/1024/1024:.1f} MB")

# 3. 子串匹配统计
hit, miss = [], []
for k in keys:
    (hit if k.encode("utf-8") in haystack else miss).append(k)

print(f"在本机应用中能找到原文：{len(hit)}  ({len(hit)*100//len(keys)}%)")
print(f"找不到原文（该版本无此串，不会被替换）：{len(miss)}")
print()
print("--- 找不到原文的条目 ---")
for k in miss:
    print("  ", k)
