#!/usr/bin/env python3
"""
生成离线 HTML 扫描报告 — 替代 search_server.py。

用法:
  python3 generate_report.py -d example.com                    # 单域名
  python3 generate_report.py -d example.com -s screenshots/    # 带截图
  python3 generate_report.py -r 7scan_results/                 # 多域名汇总

输出: example.com/example.com_7scanAI_report.html (单域名) 或 7scan_results/7scanAI_report.html (多域名)
   直接用浏览器打开即可，无需服务器。
"""

import argparse
import json
import os
import sys
import glob
from datetime import datetime
from html import escape
from urllib.parse import quote

# ═══════════════════════════════════════════════════════════════
# CSS + JS (全部内联，离线可用)
# ═══════════════════════════════════════════════════════════════

CSS = """
*{margin:0;padding:0;box-sizing:border-box}
body{font:14px/1.5 -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#333;background:#f5f6fa;padding:20px}
.container{max-width:1400px;margin:0 auto}
h1{font-size:24px;margin-bottom:4px}
h2{font-size:18px;margin:24px 0 12px;padding-bottom:8px;border-bottom:2px solid #e0e0e0}
.meta{color:#888;margin-bottom:20px;font-size:13px}
/* 统计卡片 */
.stats{display:flex;flex-wrap:wrap;gap:12px;margin-bottom:24px}
.stat-card{background:#fff;border-radius:8px;padding:14px 20px;box-shadow:0 1px 3px rgba(0,0,0,.08);min-width:120px}
.stat-card .num{font-size:28px;font-weight:700}
.stat-card .label{font-size:12px;color:#888;margin-top:2px}
.stat-card.critical .num{color:#e74c3c}
.stat-card.high .num{color:#e67e22}
.stat-card.medium .num{color:#f39c12}
.stat-card.info .num{color:#3498db}
/* 搜索栏 */
.search-bar{display:flex;gap:8px;margin-bottom:16px;flex-wrap:wrap;align-items:center;background:#fff;padding:12px 16px;border-radius:8px;box-shadow:0 1px 3px rgba(0,0,0,.08)}
.search-bar input,.search-bar select{padding:8px 12px;border:1px solid #ddd;border-radius:6px;font-size:13px}
.search-bar input{flex:1;min-width:200px}
.search-bar select{min-width:120px}
.search-bar .count{color:#888;font-size:13px;white-space:nowrap}
/* 表格 */
.table-wrap{overflow-x:auto;background:#fff;border-radius:8px;box-shadow:0 1px 3px rgba(0,0,0,.08)}
table{width:100%;border-collapse:collapse;font-size:13px}
th{background:#f8f9fa;padding:10px 12px;text-align:left;font-weight:600;border-bottom:2px solid #e0e0e0;cursor:pointer;user-select:none;white-space:nowrap}
th:hover{background:#eef0f4}
th .sort-arrow{font-size:10px;margin-left:4px;opacity:.3}
th .sort-arrow.active{opacity:1}
td{padding:8px 12px;border-bottom:1px solid #f0f0f0;max-width:300px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
tr:hover{background:#fafbfc}
td.url{font-family:'SF Mono',Monaco,monospace;font-size:12px}
td a{color:#3498db;text-decoration:none}
td a:hover{text-decoration:underline}
td a:visited{color:#8e44ad}
/* 状态码色标 */
.status{display:inline-block;padding:2px 8px;border-radius:4px;font-weight:600;font-size:12px}
.status-2{background:#d4edda;color:#155724}
.status-3{background:#fff3cd;color:#856404}
.status-4{background:#f8d7da;color:#721c24}
.status-5{background:#f8d7da;color:#721c24}
/* 漏洞标签 */
.tag{display:inline-block;padding:2px 8px;border-radius:4px;font-size:11px;font-weight:600;margin:1px}
.tag-critical{background:#e74c3c;color:#fff}
.tag-high{background:#e67e22;color:#fff}
.tag-medium{background:#f39c12;color:#fff}
.tag-low{background:#95a5a6;color:#fff}
/* 截图预览 */
.screenshot-thumb{max-width:200px;max-height:120px;cursor:pointer;border-radius:4px;transition:transform .2s}
.screenshot-thumb:hover{transform:scale(4);z-index:999;position:relative}
/* 响应式 */
@media(max-width:768px){.stat-card{min-width:80px}.stat-card .num{font-size:20px}}
/* Tab 切换 */
.tabs{display:flex;gap:0;margin-bottom:0}
.tab{padding:10px 20px;background:#e8e8e8;border:none;cursor:pointer;font-size:14px;border-radius:8px 8px 0 0;margin-right:2px}
.tab.active{background:#fff;font-weight:600}
.tab-content{display:none}
.tab-content.active{display:block}
"""

JS = """
// ── 排序 ──
let sortCol = -1, sortAsc = true;
function sortTable(tbody, col, header) {
  const rows = Array.from(tbody.querySelectorAll('tr'));
  if (col === sortCol) { sortAsc = !sortAsc; } else { sortCol = col; sortAsc = true; }
  rows.sort((a, b) => {
    let va = (a.children[col]?.textContent || '').toLowerCase();
    let vb = (b.children[col]?.textContent || '').toLowerCase();
    let na = parseFloat(va), nb = parseFloat(vb);
    if (!isNaN(na) && !isNaN(nb)) { va = na; vb = nb; }
    return va < vb ? (sortAsc ? -1 : 1) : va > vb ? (sortAsc ? 1 : -1) : 0;
  });
  rows.forEach(r => tbody.appendChild(r));
  document.querySelectorAll('.sort-arrow').forEach(a => { a.classList.remove('active'); a.textContent = ' ⇅'; });
  const arrow = header.querySelector('.sort-arrow');
  if (arrow) { arrow.classList.add('active'); arrow.textContent = sortAsc ? ' ▲' : ' ▼'; }
}

// ── 搜索 ──
function doSearch(tableId) {
  const q = document.getElementById('search-' + tableId).value.toLowerCase();
  const col = parseInt(document.getElementById('search-col-' + tableId).value);
  const filter = document.getElementById('search-filter-' + tableId)?.value || 'include';
  const tbody = document.getElementById('tbody-' + tableId);
  const rows = tbody.querySelectorAll('tr');
  let c = 0;
  rows.forEach(row => {
    let text = col >= 0 ? (row.children[col]?.textContent || '') : row.textContent;
    text = text.toLowerCase();
    let show = filter === 'include' ? text.includes(q) : !text.includes(q);
    if (!q) show = true;
    row.style.display = show ? '' : 'none';
    if (show) c++;
  });
  document.getElementById('count-' + tableId).textContent = c + ' / ' + rows.length;
}

// ── Tab 切换 ──
function switchTab(name) {
  document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
  document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
  document.querySelector('.tab[data-tab="' + name + '"]').classList.add('active');
  document.getElementById('tab-' + name).classList.add('active');
}
"""

# ═══════════════════════════════════════════════════════════════
# 数据收集
# ═══════════════════════════════════════════════════════════════

def load_webfinger(domain_dir):
    """加载 webfinger 数据 (JSON 优先，CSV 退避)"""
    rows = []
    json_path = os.path.join(domain_dir, 'active_webs', 'active_websfinger.json')
    if os.path.exists(json_path):
        with open(json_path, errors='replace') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    d = json.loads(line)
                    rows.append({
                        'url': d.get('url', '-'),
                        'status': str(d.get('status_code', '-')),
                        'title': d.get('title', '-') or '-',
                        'length': str(d.get('content_length', '-')),
                        'ip': d.get('a', ['-'])[0] if d.get('a') else d.get('ip', '-'),
                        'server': d.get('webserver', '-') or '-',
                        'tech': ','.join(d.get('tech', [])) if d.get('tech') else '-',
                        'cname': d.get('cname', '-') or '-',
                    })
                except json.JSONDecodeError:
                    continue
    return rows


def load_vulns(domain_dir):
    """加载漏洞发现"""
    vulns = []

    # nuclei
    nuclei_path = os.path.join(domain_dir, 'nuclei_fuzzing_result', 'nuclei-templates_fuzzing.txt')
    if os.path.exists(nuclei_path):
        with open(nuclei_path, errors='replace') as f:
            for line in f:
                line = line.strip()
                if line:
                    vulns.append({'source': 'nuclei', 'detail': line[:300], 'severity': guess_severity(line)})

    # afrog
    afrog_dir = os.path.join(domain_dir, 'afrog_scan_results')
    if os.path.exists(afrog_dir):
        for f in glob.glob(os.path.join(afrog_dir, '*.json')):
            try:
                with open(f, 'r', errors='replace') as fh:
                    data = json.load(fh)
                if isinstance(data, list):
                    for item in data:
                        pocinfo = item.get('pocinfo', {})
                        severity = pocinfo.get('infoseg', 'unknown')
                        target = item.get('fulltarget') or item.get('target') or item.get('url') or '-'
                        name = pocinfo.get('infoname') or pocinfo.get('id') or 'afrog-detection'
                        vulns.append({
                            'source': 'afrog',
                            'detail': f'{name} -> {target}'[:300],
                            'severity': severity,
                            'url': target,
                        })
            except:
                pass

    # nuclei DAST fuzzing
    fuzz_path = os.path.join(domain_dir, 'nuclei_fuzzing_result', 'nuclei-DAST_fuzzing.txt')
    if os.path.exists(fuzz_path):
        with open(fuzz_path, errors='replace') as f:
            for line in f:
                line = line.strip()
                if line:
                    vulns.append({'source': 'nuclei-fuzz', 'detail': line[:300], 'severity': guess_severity(line)})

    # kscan weak passwords
    brute_path = os.path.join(domain_dir, 'brute_result', 'brute_success.txt')
    if os.path.exists(brute_path):
        with open(brute_path, errors='replace') as f:
            for line in f:
                line = line.strip()
                if line:
                    vulns.append({'source': 'kscan', 'detail': line[:300], 'severity': 'high'})

    # backup file scan
    backup_path = os.path.join(domain_dir, 'backup_result', 'backup_scan.txt')
    if os.path.exists(backup_path):
        with open(backup_path, errors='replace') as f:
            for line in f:
                line = line.strip()
                if line:
                    severity = 'high' if any(k in line.lower() for k in ['.git', '.env', '.sql', 'backup', 'dump']) else 'medium'
                    vulns.append({'source': 'backup-scan', 'detail': line[:300], 'severity': severity})

    return vulns


def load_exploits(domain_dir):
    """加载利用结果"""
    exploits = []
    base = domain_dir

    # exploit_success.txt — 成功利用记录
    success_path = os.path.join(base, 'exploit_result', 'exploit_success.txt')
    if os.path.exists(success_path):
        with open(success_path, 'r', errors='replace') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                parts = line.split('|')
                if len(parts) >= 3:
                    exploits.append({
                        'type': parts[0] if len(parts) > 0 else '-',
                        'target': parts[1] if len(parts) > 1 else '-',
                        'detail': '|'.join(parts[2:]) if len(parts) > 2 else '-',
                        'status': 'success',
                    })

    # harvested_credentials.txt — 收割的凭据
    creds_path = os.path.join(base, 'exploit_result', 'harvested_credentials.txt')
    if os.path.exists(creds_path):
        with open(creds_path, 'r', errors='replace') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                parts = line.split('|')
                if len(parts) >= 3:
                    exploits.append({
                        'type': parts[0] + '-cred' if len(parts) > 0 else '-',
                        'target': parts[1] if len(parts) > 1 else '-',
                        'detail': parts[2] if len(parts) > 2 else '-',
                        'status': 'credential',
                    })

    # exploit_log.txt — 尝试日志（仅统计计数，不逐条展示）
    log_path = os.path.join(base, 'exploit_result', 'exploit_log.txt')
    exploit_attempts = count_lines(log_path)

    return exploits, exploit_attempts


def guess_severity(text):
    """从文本推断严重度"""
    t = text.lower()
    if any(k in t for k in ['critical', 'rce', 'sqli', 'remote code', 'cve-']):
        return 'critical'
    if any(k in t for k in ['high', 'ssrf', 'ssti', 'xss', 'idor', 'upload', 'bypass']):
        return 'high'
    if any(k in t for k in ['medium', 'info-disclosure', 'traversal', 'misconfig']):
        return 'medium'
    if any(k in t for k in ['low', 'info', 'detect', 'version']):
        return 'low'
    return 'medium'


def count_lines(path):
    """安全计行数"""
    try:
        with open(path, 'r', errors='replace') as f:
            return sum(1 for _ in f)
    except:
        return 0


def collect_stats(domain_dir):
    """收集统计信息"""
    s = {}
    base = domain_dir
    s['subdomains'] = count_lines(os.path.join(base, 'collect_subdomains', 'collect_subdomains.txt'))
    s['resolved'] = count_lines(os.path.join(base, 'active_subdomains', 'active_subdomains.txt'))
    s['ips'] = count_lines(os.path.join(base, 'active_ips', 'active_ips.txt'))
    s['ports'] = count_lines(os.path.join(base, 'active_ports', 'active_ports.txt'))
    s['web'] = count_lines(os.path.join(base, 'active_webs', 'active_webs.txt'))
    s['nuclei'] = count_lines(os.path.join(base, 'nuclei_fuzzing_result', 'nuclei-templates_fuzzing.txt'))
    s['backup'] = count_lines(os.path.join(base, 'backup_result', 'backup_scan.txt'))
    s['brute'] = count_lines(os.path.join(base, 'brute_result', 'brute_success.txt'))
    s['exploit_success'] = count_lines(os.path.join(base, 'exploit_result', 'exploit_success.txt'))
    s['exploit_creds'] = count_lines(os.path.join(base, 'exploit_result', 'harvested_credentials.txt'))
    s['exploit_attempts'] = count_lines(os.path.join(base, 'exploit_result', 'exploit_log.txt'))
    # screenshots
    ss_dir = os.path.join(base, 'web_screenshots', 'screenshots')
    if os.path.exists(ss_dir):
        s['screenshots'] = len([f for f in os.listdir(ss_dir) if f.endswith(('.png', '.jpg', '.jpeg', '.gif'))])
    else:
        s['screenshots'] = 0
    return s


# ═══════════════════════════════════════════════════════════════
# HTML 生成
# ═══════════════════════════════════════════════════════════════

def status_class(status):
    try:
        s = int(status)
        if 200 <= s < 300: return 'status status-2'
        if 300 <= s < 400: return 'status status-3'
        if 400 <= s < 500: return 'status status-4'
        return 'status status-5'
    except:
        return ''

def severity_tag(sev):
    m = {'critical': 'tag-critical', 'high': 'tag-high', 'medium': 'tag-medium', 'low': 'tag-low'}
    return m.get(sev, 'tag-medium')


def generate_html(domain_dirs, output_path, screenshot_base=None):
    """生成自包含 HTML 报告"""

    # 收集所有数据
    all_web = []
    all_vulns = []
    all_stats = {}
    all_exploits = []
    total_exploit_attempts = 0
    domain_list = []

    # domain_paths maps bare domain name to full filesystem path
    domain_paths = {}
    for d in domain_dirs:
        domain = os.path.basename(d.rstrip('/'))
        domain_paths[domain] = d.rstrip('/')
        domain_list.append(domain)
        webs = load_webfinger(d)
        for w in webs:
            w['domain'] = domain
        all_web.extend(webs)
        vulns = load_vulns(d)
        for v in vulns:
            v['domain'] = domain
        all_vulns.extend(vulns)
        exploits, exploit_att = load_exploits(d)
        for e in exploits:
            e['domain'] = domain
        all_exploits.extend(exploits)
        total_exploit_attempts += exploit_att
        all_stats[domain] = collect_stats(d)

    if not domain_list:
        print("❌ 没有找到域名数据")
        sys.exit(1)

    now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    total_domains = len(domain_list)

    # ── 构建 HTML ──
    html_parts = [
        '<!DOCTYPE html>',
        '<html lang="zh-CN">',
        '<head>',
        '<meta charset="UTF-8">',
        '<meta name="viewport" content="width=device-width,initial-scale=1.0">',
        f'<title>7scan Report — {", ".join(domain_list[:3])}{"..." if total_domains > 3 else ""}</title>',
        f'<style>{CSS}</style>',
        '</head>',
        '<body>',
        '<div class="container">',
        f'<h1>🔍 7scan 扫描报告</h1>',
        f'<div class="meta">生成时间: {now} | 目标数: {total_domains} | {" ".join(domain_list[:5])}</div>',
    ]

    # ── 统计卡片 ──
    total_subdomains = sum(v['subdomains'] for v in all_stats.values())
    total_resolved = sum(v['resolved'] for v in all_stats.values())
    total_ips = sum(v['ips'] for v in all_stats.values())
    total_ports = sum(v['ports'] for v in all_stats.values())
    total_web = sum(v['web'] for v in all_stats.values())
    total_ss = sum(v['screenshots'] for v in all_stats.values())
    critical_vulns = sum(1 for v in all_vulns if v['severity'] == 'critical')
    high_vulns = sum(1 for v in all_vulns if v['severity'] == 'high')
    medium_vulns = sum(1 for v in all_vulns if v['severity'] == 'medium')

    html_parts.append('<div class="stats">')
    html_parts.append(f'<div class="stat-card"><div class="num">{total_subdomains}</div><div class="label">子域名</div></div>')
    html_parts.append(f'<div class="stat-card"><div class="num">{total_resolved}</div><div class="label">解析成功</div></div>')
    html_parts.append(f'<div class="stat-card"><div class="num">{total_ips}</div><div class="label">独立 IP</div></div>')
    html_parts.append(f'<div class="stat-card"><div class="num">{total_ports}</div><div class="label">开放端口</div></div>')
    html_parts.append(f'<div class="stat-card"><div class="num">{total_web}</div><div class="label">存活 Web</div></div>')
    html_parts.append(f'<div class="stat-card critical"><div class="num">{critical_vulns}</div><div class="label">🔴 Critical</div></div>')
    html_parts.append(f'<div class="stat-card high"><div class="num">{high_vulns}</div><div class="label">🟠 High</div></div>')
    html_parts.append(f'<div class="stat-card medium"><div class="num">{medium_vulns}</div><div class="label">🟡 Medium</div></div>')
    if total_ss > 0:
        html_parts.append(f'<div class="stat-card info"><div class="num">{total_ss}</div><div class="label">📸 截图</div></div>')
    exploit_success_count = sum(1 for e in all_exploits if e.get('status') == 'success')
    if exploit_success_count > 0:
        html_parts.append(f'<div class="stat-card critical"><div class="num">{exploit_success_count}</div><div class="label">💀 利用成功</div></div>')
    if total_exploit_attempts > 0:
        html_parts.append(f'<div class="stat-card high"><div class="num">{total_exploit_attempts}</div><div class="label">🔑 利用尝试</div></div>')
    html_parts.append('</div>')

    # ── Tab 导航 ──
    html_parts.append('<div class="tabs">')
    html_parts.append('<button class="tab active" data-tab="web" onclick="switchTab(\'web\')">🌐 Web 资产</button>')
    html_parts.append('<button class="tab" data-tab="vulns" onclick="switchTab(\'vulns\')">💣 漏洞发现</button>')
    html_parts.append('<button class="tab" data-tab="exploit" onclick="switchTab(\'exploit\')">💀 利用结果</button>')
    html_parts.append('<button class="tab" data-tab="summary" onclick="switchTab(\'summary\')">📊 摘要</button>')
    html_parts.append('</div>')

    # ── Tab 1: Web 资产 ──
    html_parts.append('<div id="tab-web" class="tab-content active">')
    html_parts.append('<h2>Web 资产列表</h2>')
    html_parts.append(f'''<div class="search-bar">
      <input id="search-web" placeholder="搜索..." oninput="doSearch('web')">
      <select id="search-col-web" onchange="doSearch('web')">
        <option value="-1">所有列</option>
        <option value="0">URL</option>
        <option value="1">状态码</option>
        <option value="2">标题</option>
        <option value="4">IP</option>
        <option value="5">Server</option>
        <option value="6">技术栈</option>
      </select>
      <select id="search-filter-web" onchange="doSearch('web')">
        <option value="include">包含</option>
        <option value="exclude">排除</option>
      </select>
      <span class="count" id="count-web">0</span>
    </div>''')

    html_parts.append('<div class="table-wrap"><table><thead><tr>')
    headers = ['URL', '状态码', '标题', '长度', 'IP', 'Server', '技术栈', '域名']
    for i, h in enumerate(headers):
        html_parts.append(f'<th onclick="sortTable(document.getElementById(\'tbody-web\'),{i},this)">{h}<span class="sort-arrow"> ⇅</span></th>')
    html_parts.append('</tr></thead><tbody id="tbody-web">')

    for row in all_web:
        sc = status_class(row['status'])
        html_parts.append('<tr>')
        html_parts.append(f'<td class="url"><a href="{escape(row["url"])}" target="_blank">{escape(row["url"][:80])}</a></td>')
        html_parts.append(f'<td><span class="{sc}">{escape(row["status"])}</span></td>')
        html_parts.append(f'<td>{escape(row["title"][:60])}</td>')
        html_parts.append(f'<td>{escape(row["length"])}</td>')
        html_parts.append(f'<td>{escape(row["ip"])}</td>')
        html_parts.append(f'<td>{escape(row["server"][:30])}</td>')
        html_parts.append(f'<td>{escape(row["tech"][:50])}</td>')
        html_parts.append(f'<td>{escape(row.get("domain","-"))}</td>')
        html_parts.append('</tr>')

    html_parts.append('</tbody></table></div>')
    html_parts.append('</div>')  # tab-web

    # ── Tab 2: 漏洞发现 ──
    html_parts.append('<div id="tab-vulns" class="tab-content">')
    html_parts.append('<h2>漏洞发现</h2>')
    html_parts.append(f'<div class="search-bar">'
      f'<input id="search-vulns" placeholder="搜索漏洞..." oninput="doSearch(\'vulns\')">'
      f'<select id="search-col-vulns" onchange="doSearch(\'vulns\')">'
      f'<option value="-1">所有列</option><option value="0">来源</option><option value="1">详情</option>'
      f'</select>'
      f'<span class="count" id="count-vulns">0</span></div>')

    # 按严重度分组
    sev_order = {'critical': 0, 'high': 1, 'medium': 2, 'low': 3, 'unknown': 4}
    sorted_vulns = sorted(all_vulns, key=lambda v: sev_order.get(v.get('severity', 'unknown'), 99))

    html_parts.append('<div class="table-wrap"><table><thead><tr>')
    for i, h in enumerate(['严重度', '来源', '详情', '域名']):
        html_parts.append(f'<th onclick="sortTable(document.getElementById(\'tbody-vulns\'),{i},this)">{h}<span class="sort-arrow"> ⇅</span></th>')
    html_parts.append('</tr></thead><tbody id="tbody-vulns">')

    for v in sorted_vulns:
        html_parts.append('<tr>')
        html_parts.append(f'<td><span class="tag {severity_tag(v["severity"])}">{v["severity"].upper()}</span></td>')
        html_parts.append(f'<td>{escape(v["source"])}</td>')
        html_parts.append(f'<td>{escape(v["detail"])}</td>')
        html_parts.append(f'<td>{escape(v.get("domain","-"))}</td>')
        html_parts.append('</tr>')

    html_parts.append('</tbody></table></div>')
    html_parts.append('</div>')  # tab-vulns

    # ── Tab 3: 利用结果 ──
    html_parts.append('<div id="tab-exploit" class="tab-content">')
    html_parts.append('<h2>自主利用结果</h2>')

    if all_exploits:
        sev_order = {'success': 0, 'credential': 1}
        sorted_exploits = sorted(all_exploits, key=lambda e: sev_order.get(e.get('status', ''), 99))

        html_parts.append('<div class="table-wrap"><table><thead><tr>')
        for i, h in enumerate(['状态', '类型', '目标', '详情', '域名']):
            html_parts.append(f'<th onclick="sortTable(document.getElementById(\'tbody-exploit\'),{i},this)">{h}<span class="sort-arrow"> ⇅</span></th>')
        html_parts.append('</tr></thead><tbody id="tbody-exploit">')

        for e in sorted_exploits:
            status_label = '✅ 成功' if e['status'] == 'success' else '🔑 凭据'
            status_cls = 'tag-high' if e['status'] == 'success' else 'tag-medium'
            html_parts.append('<tr>')
            html_parts.append(f'<td><span class="tag {status_cls}">{status_label}</span></td>')
            html_parts.append(f'<td>{escape(e["type"][:40])}</td>')
            html_parts.append(f'<td class="url">{escape(e["target"][:60])}</td>')
            html_parts.append(f'<td>{escape(e["detail"][:80])}</td>')
            html_parts.append(f'<td>{escape(e.get("domain","-"))}</td>')
            html_parts.append('</tr>')

        html_parts.append('</tbody></table></div>')
    else:
        html_parts.append('<p style="color:#888">无利用结果（无可利用漏洞或利用阶段未执行）</p>')

    html_parts.append('<p style="margin-top:12px;color:#888;font-size:12px">')
    html_parts.append(f'📋 利用尝试总数: {total_exploit_attempts} | ')
    html_parts.append(f'💀 成功: {exploit_success_count} | ')
    html_parts.append(f'🔑 收割凭据: {sum(1 for e in all_exploits if e.get("status") == "credential")}')
    html_parts.append('</p>')

    html_parts.append('</div>')  # tab-exploit

    # ── Tab 4: 摘要 ──
    html_parts.append('<div id="tab-summary" class="tab-content">')
    html_parts.append('<h2>各域名统计</h2>')
    html_parts.append('<div class="table-wrap"><table><thead><tr>')
    for h in ['域名', '子域名', '解析', 'IP', '端口', 'Web', 'Nuclei', '备份', '弱口令', '利用成功', '截图']:
        html_parts.append(f'<th>{h}</th>')
    html_parts.append('</tr></thead><tbody>')

    for domain, s in all_stats.items():
        html_parts.append('<tr>')
        html_parts.append(f'<td><strong>{escape(domain)}</strong></td>')
        html_parts.append(f'<td>{s["subdomains"]}</td>')
        html_parts.append(f'<td>{s["resolved"]}</td>')
        html_parts.append(f'<td>{s["ips"]}</td>')
        html_parts.append(f'<td>{s["ports"]}</td>')
        html_parts.append(f'<td>{s["web"]}</td>')
        html_parts.append(f'<td>{s["nuclei"]}</td>')
        html_parts.append(f'<td>{s["backup"]}</td>')
        html_parts.append(f'<td>{s["brute"]}</td>')
        html_parts.append(f'<td>{s.get("exploit_success", 0)}</td>')
        html_parts.append(f'<td>{s["screenshots"]}</td>')
        html_parts.append('</tr>')

    html_parts.append('</tbody></table></div>')

    # 截图区域
    if total_ss > 0:
        html_parts.append('<h2>页面截图</h2>')
        html_parts.append('<div style="display:flex;flex-wrap:wrap;gap:8px">')
        for domain, s in all_stats.items():
            ss_dir = os.path.join(domain_paths.get(domain, domain), 'web_screenshots', 'screenshots')
            if os.path.exists(ss_dir):
                for img in sorted(os.listdir(ss_dir)):
                    if img.endswith(('.png', '.jpg', '.jpeg', '.gif')):
                        img_path = os.path.join(ss_dir, img)
                        img_url = 'file://' + quote(os.path.abspath(img_path), safe='/:@')
                        html_parts.append(f'<div style="text-align:center">'
                          f'<a href="{img_url}" target="_blank">'
                          f'<img class="screenshot-thumb" src="{img_url}" title="{escape(img)}">'
                          f'</a>'
                          f'<div style="font-size:10px;color:#888">{escape(img[:30])}</div></div>')
        html_parts.append('</div>')

    html_parts.append('</div>')  # tab-summary

    # ── 脚本 + 结尾 ──
    html_parts.append(f'<script>{JS}</script>')
    html_parts.append('<script>doSearch("web");doSearch("vulns");</script>')
    html_parts.append('</div></body></html>')

    # 写入文件
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(html_parts))

    print(f'✅ 报告已生成: {output_path}')
    print(f'   Web 资产: {len(all_web)} 条')
    print(f'   漏洞发现: {len(all_vulns)} 条')
    print(f'   截图: {total_ss} 张')
    print(f'   直接用浏览器打开即可，无需服务器')


# ═══════════════════════════════════════════════════════════════
# 入口
# ═══════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(description='生成离线 HTML 扫描报告')
    parser.add_argument('-d', '--domain', help='单域名目录路径')
    parser.add_argument('-r', '--results-dir', help='多域名结果根目录 (7scan_results/)')
    parser.add_argument('-s', '--screenshots', help='截图目录（单域名模式）')
    parser.add_argument('-o', '--output', help='输出 HTML 路径（默认自动生成）')
    args = parser.parse_args()

    if args.domain:
        domain_dir = args.domain.rstrip('/')
        domain_name = os.path.basename(domain_dir)
        output = args.output or os.path.join(domain_dir, f'{domain_name}_7scanAI_report.html')
        generate_html([domain_dir], output)
    elif args.results_dir:
        root = args.results_dir.rstrip('/')
        domain_dirs = sorted([
            os.path.join(root, d) for d in os.listdir(root)
            if os.path.isdir(os.path.join(root, d)) and not d.startswith('.')
        ])
        if not domain_dirs:
            print(f"❌ {root}/ 下没有域名目录")
            sys.exit(1)
        output = args.output or os.path.join(root, '7scanAI_report.html')
        generate_html(domain_dirs, output)
    else:
        print("用法: python3 generate_report.py -d example.com")
        print("      python3 generate_report.py -r 7scan_results/")
        sys.exit(1)


if __name__ == '__main__':
    main()
