#!/usr/bin/env python3
"""
dirsearch 结果软 404 过滤

背景:
  dirsearch 把"路径返回 200"当作命中。但 SPA / catch-all 站点对**任意路径**
  都返回 index.html + 200，于是字典里每个路径都"命中"。

实测案例:
  11 个高价值目标（后台/登录页）全部报 `200 - <N>B - /.env`，体积从 882B 到
  108539B 不等。体积不一致**看起来**像真实文件（每个站 config 不同），
  极具迷惑性。实际 curl 验证：Content-Type: text/html，body 以 <!DOCTYPE html>
  开头 ⇒ 全是各站 index.html 的 SPA fallback。

判定逻辑（两条**决定性**判据，任一成立即判软404）:
  1. **基线一致**: 随机不存在路径返回相同 status 且相同长度 ⇒ catch-all 路由
  2. **语义矛盾**: 数据文件路径（.env/.git/.sql/...）却返回 text/html 的 HTML 文档
     —— 真实配置文件绝不可能是 HTML

  ⚠️ 判据 1 单独成立即定案，**不要**要求"多条理由同时成立"：
     有的站 index.html 是 JS 壳、body 前 200 字节内没有 <!DOCTYPE html>，
     多条件与逻辑会把它误判为真实命中（实测踩过）。
     判据 2 不依赖基线，因此对**响应不稳定**的站点依然有效。

用法:
  python3 dirsearch_filter.py <dirsearch_result_dir_or_progress_log> [--out-dir DIR]
产物:
  dirsearch_clean.txt      真实命中（报告可引用）
  dirsearch_soft404.txt    判为软404的命中（报告禁止引用）
  dirsearch_unverified.txt 基线或命中项请求失败，无法判定（必须人工确认）
"""
import argparse
import os
import random
import re
import string
import ssl
import time
import sys
import urllib.error
import urllib.request
from collections import defaultdict

CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE

# 200 - 108539B - /.env
ROW_RE = re.compile(r'^(?P<code>\d{3})\s*-\s*(?P<size>\d+)B\s*-\s*(?P<path>\S+)\s*$')

# 这些路径语义上必须是"数据文件"，返回 text/html 基本可判为 fallback
DATAISH = re.compile(
    r'\.(env|git|svn|hg|bzr|sql|bak|zip|tar|gz|tgz|rar|7z|jar|war|dump|log|ini|conf|cfg|yml|yaml|json|xml|txt|csv|xls|xlsx|pdf)$'
    r'|/\.(git|svn|env)|actuator|swagger|phpinfo|heapdump|\.DS_Store',
    re.I,
)


def rand_path(host_path):
    tail = "".join(random.choices(string.ascii_lowercase + string.digits, k=14))
    # 保持与探测路径同后缀，避免后缀本身影响路由
    ext = os.path.splitext(host_path)[1] or ""
    return f"/scale-probe-{tail}{ext}"


def fetch(url, timeout=15):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=CTX) as r:
            return r.status, r.read(), (r.headers.get("Content-Type") or "")
    except urllib.error.HTTPError as e:
        try:
            return e.code, e.read(), (e.headers.get("Content-Type") or "")
        except Exception:
            return e.code, b"", ""
    except Exception:
        return None, b"", ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("target")
    ap.add_argument("--out-dir", default=None)
    ap.add_argument("--timeout", type=int, default=15)
    args = ap.parse_args()

    # 收集 (host, code, size, path)
    rows = []
    if os.path.isdir(args.target):
        for fn in sorted(os.listdir(args.target)):
            if not fn.startswith("smart_scan_") or not fn.endswith(".txt"):
                continue
            host = re.sub(r'^smart_scan_[\d-]+_', '', fn[:-4])
            with open(os.path.join(args.target, fn), encoding="utf-8", errors="replace") as f:
                for line in f:
                    m = ROW_RE.match(line.strip())
                    if m:
                        rows.append((host, int(m.group("code")), int(m.group("size")), m.group("path")))
    else:
        with open(args.target, encoding="utf-8", errors="replace") as f:
            for line in f:
                m = ROW_RE.match(line.strip())
                if m:
                    rows.append(("", int(m.group("code")), int(m.group("size")), m.group("path")))

    out_dir = args.out_dir or (args.target if os.path.isdir(args.target) else os.path.dirname(os.path.abspath(args.target)))
    clean_p = os.path.join(out_dir, "dirsearch_clean.txt")
    soft_p = os.path.join(out_dir, "dirsearch_soft404.txt")
    unver_p = os.path.join(out_dir, "dirsearch_unverified.txt")

    if not rows:
        print("⏭️ dirsearch 无结果，跳过软404校验")
        open(clean_p, "w").close(); open(soft_p, "w").close()
        return 0

    by_host = defaultdict(list)
    for host, code, size, path in rows:
        by_host[host].append((code, size, path))

    clean, soft, unverified = [], [], []

    for host, hits in sorted(by_host.items()):
        base_url = host if host.startswith("http") else f"https://{host}"
        sample_path = hits[0][2]

        # 基线探测必须重试。基线拿不到时**绝不允许**默认判为 clean ——
        # 实测踩过坑: uc.e.kuaishou.com 的基线请求瞬时失败，结果一条真软404
        # 被归入 clean，差点写进报告。拿不到基线 ⇒ 单独归入 unverified 待人工确认。
        bcode = bbody = None
        for _ in range(3):
            bcode, bbody, _ = fetch(base_url + rand_path(sample_path), args.timeout)
            if bcode is not None and bcode < 400:
                break
            time.sleep(2)

        baseline_ok = bcode is not None and bcode < 400
        baseline_len = len(bbody) if bbody is not None else 0

        if not baseline_ok:
            for code, size, path in hits:
                unverified.append(f"[unverified] {host}{path} — 基线探测失败(3次)，"
                                  f"无法判定软404，需人工确认")
            continue

        for code, size, path in hits:
            url = base_url + path
            # 命中项自身也要重试。取不到响应时**绝不能**默认判 clean ——
            # 实测 kdj.kuaishou.com 时而 000 时而 200，单次采样失败会让一条
            # 真软404 落进 clean。取不到 ⇒ unverified。
            rcode = rbody = rctype = None
            for _ in range(3):
                rcode, rbody, rctype = fetch(url, args.timeout)
                if rcode is not None:
                    break
                time.sleep(2)

            if rcode is None:
                unverified.append(f"[unverified] {host}{path} — 命中项 3 次请求均失败，"
                                  f"无法判定，需人工确认")
                continue

            reasons = []

            # ── 判据 1（决定性）: 随机路径基线一致 ──
            # 随机路径返回相同 status 且相同长度 ⇒ 该 host 是 catch-all，
            # 单这一条就足以判软404。不要要求"多条理由同时成立"——
            # 实测踩过坑: 有的站 index.html 是 JS 壳、body 前 200 字节内没有
            # <!DOCTYPE html>，导致"HTML 文档"这一条不成立，只剩 1 条理由而被误判为真实命中。
            if baseline_ok and bcode == code and baseline_len == len(rbody):
                soft.append(f"[soft404] {host}{path} — 与随机路径基线完全一致 "
                            f"({bcode} {baseline_len}B) ⇒ catch-all 路由")
                continue

            # ── 判据 2（决定性）: 数据文件路径返回 HTML 文档 ──
            # 真实 .env / .git/config / .sql 绝不可能是 text/html 的 HTML 文档。
            # 这一条不依赖基线，因此对**响应不稳定的站点**也有效——
            # 实测 kdj.kuaishou.com 时而返回 000、时而返回 SPA 页，
            # 基线比对会因采样到失败请求而失效，但 HTML 内容判定依然成立。
            is_html = (b"<!DOCTYPE html" in rbody[:500]) or (b"<html" in rbody[:500])
            if DATAISH.search(path) and is_html:
                soft.append(f"[soft404] {host}{path} — 数据文件路径却返回 HTML 文档 "
                            f"({rctype.split(';')[0] or 'unknown'}) ⇒ SPA fallback")
                continue

            # ── 判据 3: 辅助佐证（基线不一致时才看） ──
            if DATAISH.search(path) and "text/html" in rctype.lower():
                reasons.append(f"数据文件路径却返回 {rctype.split(';')[0]}")
            if is_html:
                reasons.append("响应体是 HTML 文档")

            if reasons:
                soft.append(f"[soft404] {host}{path} — {'; '.join(reasons)}")
            else:
                clean.append(f"{code} - {size}B - {url}" + (f" [{rctype.split(';')[0]}]" if rctype else ""))

    with open(clean_p, "w", encoding="utf-8") as f:
        f.write("\n".join(clean) + ("\n" if clean else ""))
    with open(soft_p, "w", encoding="utf-8") as f:
        f.write("\n".join(soft) + ("\n" if soft else ""))
    with open(unver_p, "w", encoding="utf-8") as f:
        f.write("\n".join(unverified) + ("\n" if unverified else ""))

    total = len(rows)
    print(f"dirsearch: 原始 {total} 条 → 真实命中 {len(clean)} 条，"
          f"软404 {len(soft)} 条，待人工确认 {len(unverified)} 条")
    print(f"  clean:      {clean_p}")
    print(f"  soft404:    {soft_p}")
    print(f"  unverified: {unver_p}")
    for line in soft[:20]:
        print("   ", line)
    for line in unverified[:20]:
        print("   ", line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
