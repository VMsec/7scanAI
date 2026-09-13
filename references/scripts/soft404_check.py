#!/usr/bin/env python3
"""
软 404 基线校验 —— 备份文件扫描结果去伪

背景:
  ihoneyBakFileScan 的判定是"该路径返回了非空响应"。任何配了 catch-all /
  SPA fallback 的站点，对任意路径都返回 200 + 一小段文本，于是字典里
  每个路径都会被判为"命中"。

实测案例:
  某次扫描报出 17 条 .dump 命中，全部来自同一个 host，响应长度整齐都是
  21 字节。用随机不存在路径复测，返回完全相同的 21 字节 200 ⇒ 17 条全误报。

判定逻辑:
  对每个命中 host，请求一个随机不存在路径作为基线。
  基线是 200 且响应长度与命中项一致 ⇒ 判为软 404，剔除。

⚠️ 三条实现要点（都是从 dirsearch_filter.py 的踩坑中总结的，两边必须一致）:
  1. **基线与命中项都必须重试 3 次**。目标站常对扫描返回 RST/000，
     单次采样失败若默认判 clean，真软404 会漏进报告。
  2. **基线一致单条即定案**，不要要求"多条理由同时成立"。
  3. **取不到基线 ⇒ unverified，绝不允许默认判 clean**。
     这是最危险的默认值。

用法:
  python3 soft404_check.py <raw_backup_scan.txt> [--out-dir DIR]
产物:
  backup_scan_clean.txt      真实命中（报告可引用）
  backup_scan_soft404.txt    被判为软404的命中（报告禁止引用）
  backup_scan_unverified.txt 无法判定（必须人工确认）
"""
import argparse
import os
import random
import re
import ssl
import string
import sys
import time
import urllib.error
import urllib.request
from collections import defaultdict

CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE

LINE_RE = re.compile(r'^(?P<url>https?://[^\s]+)\s+size:(?P<size>\d+)')

RETRIES = 3


def rand_path():
    tail = "".join(random.choices(string.ascii_lowercase + string.digits, k=12))
    return f"scale-probe-{tail}.dump"


def fetch(url, timeout=10):
    """返回 (status_code, body_bytes)。失败返回 (None, b'')。"""
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=CTX) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        try:
            return e.code, e.read()
        except Exception:
            return e.code, b""
    except Exception:
        return None, b""


def fetch_retry(url, timeout, retries=RETRIES):
    """重试直到拿到响应。返回 (code, body)；全失败返回 (None, b'')。"""
    for i in range(retries):
        code, body = fetch(url, timeout)
        if code is not None:
            return code, body
        if i < retries - 1:
            time.sleep(2)
    return None, b""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("raw")
    ap.add_argument("--out-dir", default=None)
    ap.add_argument("--timeout", type=int, default=10)
    args = ap.parse_args()

    out_dir = args.out_dir or os.path.dirname(os.path.abspath(args.raw))
    clean_p = os.path.join(out_dir, "backup_scan_clean.txt")
    soft_p = os.path.join(out_dir, "backup_scan_soft404.txt")
    unver_p = os.path.join(out_dir, "backup_scan_unverified.txt")

    if not os.path.exists(args.raw) or os.path.getsize(args.raw) == 0:
        print("⏭️ 备份扫描无结果，跳过软404校验")
        for p in (clean_p, soft_p, unver_p):
            open(p, "w").close()
        return 0

    # 按 host 归组
    by_host = defaultdict(list)
    with open(args.raw, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            m = LINE_RE.match(line.strip())
            if not m:
                continue
            url = m.group("url")
            host = "/".join(url.split("/")[:3])  # scheme://host
            by_host[host].append((line, int(m.group("size"))))

    clean, soft, unverified = [], [], []

    for host, hits in sorted(by_host.items()):
        # ── 基线探测（重试）──
        bcode, bbody = fetch_retry(f"{host}/{rand_path()}", args.timeout)

        if bcode is None:
            # 要点 3: 拿不到基线绝不能默认判 clean
            for line, sz in hits:
                unverified.append(
                    f"[unverified] {host} — 基线探测失败({RETRIES}次)，无法判定软404，需人工确认")
            continue

        baseline_soft = bcode < 400
        baseline_len = len(bbody)

        if baseline_soft:
            # 要点 2: 基线一致单条即定案
            same = [h for h in hits if h[1] == baseline_len]
            if same and len(same) == len(hits):
                soft.append(f"[soft404] {host} 基线 {bcode} {baseline_len}B "
                            f"→ 该 host 全部 {len(hits)} 条命中判为误报")
                for line, sz in hits:
                    soft.append(f"  {line}")
                continue

        # 基线不一致时才逐条复测命中项（要点 1: 命中项也要重试）
        for line, sz in hits:
            if baseline_soft and sz == baseline_len:
                soft.append(f"[soft404] {host} 基线 {bcode} {baseline_len}B "
                            f"与命中 {sz}B 一致: {line}")
                continue

            url = re.match(LINE_RE, line.strip()).group("url")
            rcode, rbody = fetch_retry(url, args.timeout)
            if rcode is None:
                unverified.append(f"[unverified] {url} — 命中项 {RETRIES} 次请求均失败，"
                                  f"无法判定，需人工确认")
                continue
            if baseline_soft and len(rbody) == baseline_len:
                soft.append(f"[soft404] {url} — 与随机路径基线完全一致 "
                            f"({rcode} {baseline_len}B) ⇒ catch-all 路由")
            else:
                clean.append(line)

    for path, rows in ((clean_p, clean), (soft_p, soft), (unver_p, unverified)):
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(rows) + ("\n" if rows else ""))

    total = sum(len(v) for v in by_host.values())
    print(f"备份扫描: 原始 {total} 条 → 真实命中 {len(clean)} 条，"
          f"软404 {total - len(clean) - len(unverified)} 条，待人工确认 {len(unverified)} 条")
    print(f"  clean:      {clean_p}")
    print(f"  soft404:    {soft_p}")
    print(f"  unverified: {unver_p}")
    for line in soft[:10]:
        print("   ", line)
    for line in unverified[:10]:
        print("   ", line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
