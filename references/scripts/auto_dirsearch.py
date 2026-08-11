#!/usr/bin/env python3
"""
Smart batch dirsearch — 1C1G 友好版。

特点:
- 自动检测机器资源，自适应 worker 数和线程数
- 1C1G 自动降为 sequential 模式（1 worker × 5 threads）
- 硬超时 SIGKILL，不会 zombie 进程卡死
- 内存监控，低内存时暂停等 GC
- 支持 --low 模式使用更小字典 + ffuf 降级
"""

import concurrent.futures
import subprocess
import os
import sys
import logging
import argparse
import tempfile
import secrets
import shutil
import time
import signal
import resource
from datetime import datetime

# ── 机器资源探测 ───────────────────────────────────────────
CPU_COUNT = os.cpu_count() or 1
try:
    import psutil
    MEM_GB = psutil.virtual_memory().total / (1024**3)
except ImportError:
    MEM_GB = 1.0  # 保守假设 1G

def is_low_resource():
    """判断是否为低配机器"""
    return CPU_COUNT <= 2 and MEM_GB <= 2.0

LOW_RESOURCE = is_low_resource()

# ── 自适应配置 ─────────────────────────────────────────────
if LOW_RESOURCE:
    DEFAULT_WORKERS = 1
    DEFAULT_THREADS = 5
    DEFAULT_TIMEOUT = 600       # 每个 URL 最多 10 分钟
    HARD_KILL_TIMEOUT = 720     # 硬杀阈值 12 分钟
    WORDLIST = None             # 使用 dirsearch 默认小字典
else:
    DEFAULT_WORKERS = min(4, CPU_COUNT)
    DEFAULT_THREADS = 10
    DEFAULT_TIMEOUT = 1200
    HARD_KILL_TIMEOUT = 1500
    WORDLIST = None

# ── 日志 ───────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)

# ── 配置常量 ───────────────────────────────────────────────
DEFAULT_EXCLUDED_STATUS = '500,502,400,404,410,429,503,504'
DEFAULT_EXCLUDED_SUBDIRS = (
    'js,css,fonts,images,image,img,pictures,pic,icons,icon,svg,webp,gallery,'
    'video,videos,audio,cdn,assets,static,media,dist,build,bin,node_modules,'
    'bower_components,vendors,vendor,lib,libraries,style,theme,themes,layout,'
    'layouts,lang,locale,i18n,l10n,cache,local,error,'
    'wp-content,wp-includes,moodle,joomla,help,guide,events,event,tag,tags,sessions'
)
DEFAULT_EXCLUDE_TEXTS = (
    "Not Found,Page Not Found,Forbidden,Access Denied,blocked,"
    "Cloudflare,F5,Akamai,Sorry,captcha,has been blocked,Error 404"
)

SENSITIVE_PATHS = [
    "db.sql",
    "index.bak",
    "wp-config.bak",
    ".env",
    ".git/config",
    ".svn/entries",
    "phpinfo.php",
    "database.sql",
    "dump.sql",
    "backup.zip",
]

# ── 内存监控 ───────────────────────────────────────────────
def check_memory(min_free_mb=150):
    """低内存时等待，避免 OOM"""
    try:
        import psutil
        mem = psutil.virtual_memory()
        free_mb = mem.available / (1024**2)
        if free_mb < min_free_mb:
            logging.warning(f"⚠️ 可用内存仅 {free_mb:.0f}MB，暂停 5s 等 GC...")
            time.sleep(5)
            return False
        return True
    except ImportError:
        return True

# ── 核心逻辑 ───────────────────────────────────────────────
def build_filename(url):
    clean = url.replace('https://', '').replace('http://', '').rstrip('/')
    return ''.join(c if c.isalnum() or c in ('.', '-', '_') else '_' for c in clean)

# ── 参考页面缓存（按 hostname，避免同域名重复采集 404 页） ────
_REF_CACHE: dict = {}

def get_fake_reference(url, temp_dir):
    """采集 404 参考页面，失败返回 None。同 hostname 只采集一次。"""
    # 提取 hostname
    try:
        hostname = url.split('://', 1)[1].split('/')[0].split(':')[0]
    except IndexError:
        hostname = url

    if hostname in _REF_CACHE:
        return _REF_CACHE[hostname]

    random_str = secrets.token_hex(8)
    fake_path = f"non-exist-{random_str}-ref"
    fake_url = f"{url.rstrip('/')}/{fake_path}"
    ref_file = os.path.join(temp_dir, f"ref_{build_filename(url)}.html")

    try:
        cmd = [
            'curl', '-s', '-k', '-L', '--max-time', '5', '--retry', '0',
            '-o', ref_file,
            '-A', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            fake_url
        ]
        subprocess.run(cmd, check=True, timeout=8)
        if os.path.exists(ref_file) and os.path.getsize(ref_file) > 64:
            _REF_CACHE[hostname] = ref_file
            return ref_file
    except Exception:
        pass

    _REF_CACHE[hostname] = None
    return None

def run_dirsearch_safe(cmd, timeout, hard_timeout):
    """
    安全执行 dirsearch:
    - 进程组隔离 (os.setpgrp)
    - timeout 后先 SIGTERM，再等 10s → SIGKILL
    - 返回值: (success: bool, output: str)
    """
    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            preexec_fn=os.setpgrp  # 进程组隔离，防止僵尸子进程
        )
        try:
            stdout, _ = proc.communicate(timeout=timeout)
            return proc.returncode == 0, stdout.decode(errors='replace')
        except subprocess.TimeoutExpired:
            logging.warning(f"⏰ 超时 {timeout}s，发送 SIGTERM...")
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                logging.warning(f"💀 SIGTERM 无效，发送 SIGKILL...")
                try:
                    os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
                    proc.wait(timeout=5)
                except:
                    pass
            return False, "TIMEOUT_KILLED"
    except Exception as e:
        return False, str(e)

def probe_sensitive_paths(url, output_file):
    """补扫少量高价值敏感文件，弥补字典/过滤策略漏报"""
    found = []
    for path in SENSITIVE_PATHS:
        target = f"{url.rstrip('/')}/{path}"
        body_fd, body_path = tempfile.mkstemp(prefix='dirsearch_sensitive_', suffix='.tmp')
        try:
            cmd = [
                'curl', '-s', '-k', '-L', '--max-time', '8', '--retry', '0',
                '-o', body_path,
                '-w', '%{http_code} %{size_download}',
                '-A', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                target
            ]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            if result.returncode != 0:
                continue
            parts = result.stdout.strip().split()
            if len(parts) != 2:
                continue
            status_code, size_download = parts
            if status_code == '200' and size_download.isdigit() and int(size_download) > 0:
                # 对齐 dirsearch -O simple 格式: "200 - 12345B - /.env"
                found.append(f"{status_code} - {size_download:>5}B - /{path}")
        except Exception:
            continue
        finally:
            os.close(body_fd)
            try:
                os.unlink(body_path)
            except OSError:
                pass

    if found:
        with open(output_file, 'a', encoding='utf-8', errors='replace') as f:
            for line in sorted(set(found)):
                f.write(line + '\n')
        return len(found)
    return 0

def process_url(url, output_dir, temp_dir, timeout, force, use_ffuf=False, threads=5):
    """处理单个 URL"""
    ref_file = None
    try:
        # 低内存时等待，最多尝试 6 次（30s），避免在 OOM 边缘强行启动
        for _ in range(6):
            if check_memory():
                break

        target_name = build_filename(url)
        today = datetime.now().strftime('%Y-%m-%d')
        ext = 'txt'
        output_file = os.path.join(output_dir, f'smart_scan_{today}_{target_name}.{ext}')

        # 断点续跑
        if not force and os.path.exists(output_file) and os.path.getsize(output_file) > 64:
            logging.info(f'  ⏭️ Skip {url} (已有结果)')
            return True

        logging.info(f'  🔍 {url}')

        # 参考页面
        ref_file = get_fake_reference(url, temp_dir)

        if use_ffuf:
            # ffuf 模式：更轻量，适合极低配机器
            cmd = [
                'ffuf', '-u', f'{url.rstrip("/")}/FUZZ',
                '-w', '/usr/share/wordlists/dirb/common.txt',
                '-t', str(max(3, DEFAULT_THREADS)),
                '-fc', '500,502,400,404,410,429,503,504',
                '-r', '-maxtime', str(timeout),
                '-of', 'plain', '-o', output_file,
            ]
            if ref_file:
                with open(ref_file, 'r', errors='replace') as rf:
                    cmd += ['-fr', rf.read(200)]
        else:
            # dirsearch 模式（默认）
            cmd = [
                'python3', '/opt/dirsearch/dirsearch.py',
                '-u', url,
                '-x', DEFAULT_EXCLUDED_STATUS,
                '--random-agent',
                '-t', str(max(3, threads)),
                '--retries', '1',
                '--full-url',
                '--follow-redirects',
                '--exclude-subdirs', DEFAULT_EXCLUDED_SUBDIRS,
                '--exclude-texts', DEFAULT_EXCLUDE_TEXTS,
                '--no-color',
                '-o', output_file,
                '-O', 'simple'
            ]
            if ref_file:
                cmd += ['--exclude-response', ref_file]
            if WORDLIST:
                cmd += ['-w', WORDLIST]

        success, output = run_dirsearch_safe(cmd, timeout, HARD_KILL_TIMEOUT)

        # 如果智能过滤模式没有产物，回退到不带 exclude-response 的标准模式，
        # 避免参考页策略与目标响应过于相似时把真实结果全部过滤掉。
        # 注意：不依赖 success 判断 —— 进程超时被杀但已写出部分结果时，保留产物不覆盖。
        output_ok = os.path.exists(output_file) and os.path.getsize(output_file) > 0
        if not output_ok and not use_ffuf:
            fallback_cmd = [
                'python3', '/opt/dirsearch/dirsearch.py',
                '-u', url,
                '-x', DEFAULT_EXCLUDED_STATUS,
                '--random-agent',
                '-t', str(max(3, threads)),
                '--retries', '1',
                '--full-url',
                '--follow-redirects',
                '--exclude-subdirs', DEFAULT_EXCLUDED_SUBDIRS,
                '--exclude-texts', DEFAULT_EXCLUDE_TEXTS,
                '--no-color',
                '-o', output_file,
                '-O', 'simple'
            ]
            if WORDLIST:
                fallback_cmd += ['-w', WORDLIST]
            logging.info(f'    ↩️ {url} 智能过滤无结果，回退标准模式')
            success, _ = run_dirsearch_safe(fallback_cmd, timeout, HARD_KILL_TIMEOUT)

        sensitive_hits = probe_sensitive_paths(url, output_file)
        if sensitive_hits:
            logging.info(f'    🎯 {url} 敏感文件补扫命中 {sensitive_hits} 条')

        # 检查产出
        if os.path.exists(output_file) and os.path.getsize(output_file) > 0:
            with open(output_file, 'r', errors='replace') as f:
                lines = sum(1 for _ in f)
            logging.info(f'    ✅ {url} → {lines} 条')
            return True
        else:
            logging.warning(f'    ⚠️ {url} → 无结果')
            return False

    except Exception as e:
        logging.error(f'  ❌ {url}: {e}')
        return False

# ── 参数解析 ───────────────────────────────────────────────
def parse_args():
    parser = argparse.ArgumentParser(
        description='Batch smart dirsearch — 自动适配机器资源'
    )
    parser.add_argument('targets_file', help='目标 URL 文件（每行一个）')
    parser.add_argument('--workers', type=int, default=DEFAULT_WORKERS,
                        help=f'并发 URL 数（默认 {DEFAULT_WORKERS}）')
    parser.add_argument('--threads', type=int, default=DEFAULT_THREADS,
                        help=f'每个目标的 dirsearch 线程数（默认 {DEFAULT_THREADS}）')
    parser.add_argument('--timeout', type=int, default=DEFAULT_TIMEOUT,
                        help=f'每个 URL 超时秒数（默认 {DEFAULT_TIMEOUT}）')
    parser.add_argument('--force', action='store_true', help='强制重扫已有结果')
    parser.add_argument('--ffuf', action='store_true', help='使用 ffuf 代替 dirsearch（更轻量）')
    return parser.parse_args()

def load_urls(targets_file):
    seen = set()
    urls = []
    if not os.path.exists(targets_file):
        return []
    with open(targets_file, 'r', encoding='utf-8') as f:
        for line in f:
            url = line.strip()
            if url and url.startswith('http') and url not in seen:
                seen.add(url)
                urls.append(url)
    return urls

# ── 主入口 ─────────────────────────────────────────────────
def main():
    args = parse_args()

    # 结果目录
    result_dir = 'dirsearch_result'
    os.makedirs(result_dir, exist_ok=True)

    temp_dir = tempfile.mkdtemp(prefix='dir_ref_')

    urls = load_urls(args.targets_file)
    if not urls:
        logging.error(f"没有有效 URL: {args.targets_file}")
        # 不要 sys.exit，直接返回
        return

    # 机器信息
    logging.info(f"🖥️  机器: {CPU_COUNT}核 / {MEM_GB:.1f}G | "
                 f"{'🔴 低配模式' if LOW_RESOURCE else '🟢 正常模式'}")
    logging.info(f"📋 目标: {len(urls)} URL | "
                 f"Workers: {args.workers} | Threads/目标: {args.threads} | "
                 f"超时: {args.timeout}s | 引擎: {'ffuf' if args.ffuf else 'dirsearch'}")

    if LOW_RESOURCE and len(urls) > 50:
        logging.warning("⚠️ 低配机器 + 超过 50 个目标，建议只扫核心目标或使用 --ffuf")

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = {
            executor.submit(
                process_url, url, result_dir, temp_dir,
                args.timeout, args.force, args.ffuf, args.threads
            ): url
            for url in urls
        }

        completed = 0
        for future in concurrent.futures.as_completed(futures):
            url = futures[future]
            completed += 1
            try:
                success = future.result()
                status = "✅" if success else "❌"
            except Exception as e:
                status = f"💥{e}"
            if completed % 10 == 0 or completed == len(urls):
                logging.info(f"[{completed}/{len(urls)}] {status}")

    try:
        shutil.rmtree(temp_dir)
    except:
        pass

    # 汇总
    total_findings = 0
    for f in os.listdir(result_dir):
        if f.startswith('smart_scan_'):
            fpath = os.path.join(result_dir, f)
            with open(fpath, 'r', errors='replace') as fh:
                total_findings += sum(1 for _ in fh)
    logging.info(f"🏁 完成: {len(urls)} 目标 → {total_findings} 条路径发现")

if __name__ == '__main__':
    main()
