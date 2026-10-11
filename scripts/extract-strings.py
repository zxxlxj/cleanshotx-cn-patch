#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从 CleanShot X 主可执行文件中提取「可能出现在界面上的英文文案」。

两条来源：
  1. __TEXT,__cstring / __const 段里的 C 字符串（长文案、说明文字、分组标题）
  2. __TEXT,__text 指令流里的 Swift 内联小字符串（≤15 字节，
     布局为 movabs 成对出现，第 16 字节 = 0xE0 | 长度）

输出：每行一条候选英文文案，已按启发式规则过滤掉代码符号与系统噪声。
"""

import json
import os
import re
import subprocess
import sys

APP = os.environ.get("CSX_APP", "/Applications/CleanShot X.app")
BIN = os.path.join(APP, "Contents/MacOS/CleanShot X")
CACHE = "/tmp/csx-sections.json"


def load_sections():
    if os.path.exists(CACHE):
        try:
            return json.load(open(CACHE))
        except Exception:
            pass
    out = subprocess.run(["otool", "-l", BIN], capture_output=True, text=True).stdout
    sections = {}
    for block in out.split("Section"):
        m_sect = re.search(r"sectname (\S+)", block)
        m_seg = re.search(r"segname (\S+)", block)
        m_off = re.search(r"offset (\d+)", block)
        m_size = re.search(r"size (0x[0-9a-f]+)", block)
        if m_sect and m_seg and m_off and m_size:
            sections["%s|%s" % (m_seg.group(1), m_sect.group(1))] = (
                int(m_off.group(1)),
                int(m_size.group(1), 16),
            )
    json.dump(sections, open(CACHE, "w"))
    return sections


def cstrings(data, sections):
    out = []
    for key in ("__TEXT|__cstring", "__TEXT|__const"):
        if key not in sections:
            continue
        off, size = sections[key]
        blob = data[off:off + size]
        for raw in blob.split(b"\x00"):
            if len(raw) < 3:
                continue
            try:
                out.append(raw.decode("utf-8"))
            except UnicodeDecodeError:
                pass
    return out


MOVABS = set(range(0xB8, 0xC0))  # 48 B8 .. 48 BF = movabs r64, imm64


def swift_small_strings(data, sections):
    """扫描指令流，还原 Swift 内联小字符串（≤15 字节 ASCII）。"""
    key = "__TEXT|__text"
    if key not in sections:
        return []
    off, size = sections[key]
    text = data[off:off + size]
    out = []
    i = 0
    n = len(text)
    while i < n - 20:
        if text[i] == 0x48 and text[i + 1] in MOVABS \
                and text[i + 10] == 0x48 and text[i + 11] in MOVABS:
            lo = int.from_bytes(text[i + 2:i + 10], "little")
            hi = int.from_bytes(text[i + 12:i + 20], "little")
            raw = lo.to_bytes(8, "little") + hi.to_bytes(8, "little")
            if raw[15] & 0xE0 == 0xE0:
                cnt = raw[15] & 0x0F
                body = raw[:cnt]
                if 0 < cnt <= 15 and all(0x20 <= b <= 0x7E for b in body):
                    out.append(body.decode("ascii"))
            i += 20
        else:
            i += 1
    return out


# 明显的代码/系统噪声特征
NOISE_SUBSTR = (
    "://", ".swift", ".framework", "()", "=>", "::", "->", "%@", "%s", "%d",
    "%lu", "%zu", "%p", "%f", "NULL", "!=", "==", "CF", "Sec", "SSL", "CSSM",
    "DER", "XPC", "Mach", "Kernel", "CoreFoundation", "MobileMe", "keychain",
    "Module Directory", "Sentry", "VP8", "VP9", "YUV", "Luma", "Chroma",
    "NSData", "NSFileManager", "URLSession", "ServerTrust", "superview",
    "OCSP", "CRL", "kext", "assert", "exception", "attribute",
)

ALLOWED = re.compile(r"^[A-Za-z0-9 ,\.'\"“”‘’\-–—:;!?\(\)\[\]/&%\+\*=@#\$°…~]+$")


def looks_like_ui(s):
    if not (3 <= len(s) <= 200):
        return False
    if not s[0].isupper():
        return False
    if " " not in s:            # 单词片段基本都是符号/键名
        return False
    if "_" in s:
        return False
    if any(t in s for t in NOISE_SUBSTR):
        return False
    if not ALLOWED.match(s):
        return False
    return True


def main():
    data = open(BIN, "rb").read()
    sections = load_sections()
    pool = cstrings(data, sections) + swift_small_strings(data, sections)
    seen, res = set(), []
    for s in pool:
        if s in seen or not looks_like_ui(s):
            continue
        seen.add(s)
        res.append(s)
    print("\n".join(sorted(res)))


if __name__ == "__main__":
    main()
