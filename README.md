# 7scanAI — AI 驱动的自动化安全扫描 Pipeline

> 给 AI 一个根域名，自动完成：子域名发现 → DNS 解析 → 端口扫描 → Web 指纹 → 目录爆破 → 备份扫描 → 漏洞检测 → 结果研判 → HTML 报告 → 自主利用

## 设计理念

传统脚本是固定的编排流程，AI 无法介入决策。7scanAI 把同样的逻辑编码为 **AI 可理解的工作流**，让 AI 充当编排器：判断泛解析、处理重试、交叉验证结果、给出渗透方向。

**核心原则**：
- AI 严格按 SKILL.md 中的命令参数和顺序执行，不凭记忆拼命令
- 每个阶段有明确 checkpoint，通过才进入下一步
- 扫描前一次性确认（端口范围 + 域名变形 + 截图开关），扫描中零交互
- 任何步骤失败自动重试 3 次（Phase 2/3 间隔 2s/4s/8s；Phase 4/5/6 间隔 30s/60s/120s），anew 保证断点续跑不污染数据
- 所有 bash 代码块以 `set -o pipefail` 开头，防止管道中间态错误静默丢失
- Python 工具 git clone 后**必须** `pip3 install -r requirements.txt --break-system-packages`
- 默认进入自治执行模式：优先自动修依赖、切 fallback、局部重跑，再决定是否中止

---

## 工作流总览（8 个 Phase）

```
用户: "扫 baidu.com"
  │
  ├─ Phase 1  Intake         确认目标 + 端口范围 + 域名变形 + 截图开关，创建目录
  │
  ├─ Phase 2  Subdomain      7 个工具多源收集子域名
  │                           OneForAll → ksubdomain → subDomainsBrute
  │                           → subfinder → gau → jsubfinder
  │
  ├─ Phase 3  DNS            泛解析检测(3次重试) → dnsgen/alterx 排列(可选)
  │                          → dnsx 解析 → 内外网分离
  │
  ├─ Phase 4  Port           IP 提取 → CDN 过滤(nali+nocdn)
  │                          → naabu 端口扫描(用户选择范围)
  │
  ├─ Phase 5  Web            httpx 指纹 → 智能分类(高价值/泄露风险)
  │                          → gowitness 截图(可选)
  │
  ├─ Phase 6  Vuln           6 引擎串行扫描:
  │                          kscan指纹/弱口令 → afrog(分批) → 备份扫描
  │                          → dirsearch → nuclei → katana+fuzz
  │
  ├─ Phase 7  Report         统计汇总 → AI 逐条研判
  │                          → 渗透方向建议 → 生成 HTML 报告
  │
  └─ Phase 8  Exploit        AI 自主利用攻击 → 弱口令登录
                             → SQL注入/备份泄露 → 登录口爆破
                             → 注册越权 → OAuth滥用 → 凭据喷洒
                             → 生成利用报告
```

---

## 各 Phase 详细逻辑

### Phase 1 — Intake（初始化）

**触发**: 用户给出域名

**确认项（三项一次性确认，之后全程不再询问）**:

| 问题 | 选项 | 默认值 |
|------|------|--------|
| 端口扫描范围 | `[1] top-100` / `[2] top-1000` / `[3] 全端口` | top-1000 |
| 域名变形生成 (dnsgen/alterx) | `y` / `n` | n（不启用） |
| Web 截图 (gowitness) | `y` / `n` | n（不截图） |

**动作**:
1. 规范化域名（去除 `http://`、`https://`、路径、端口）
2. 验证 DOMAIN 不含 `../`、`/`、`\`、空格（防路径穿越）
3. 创建 23 个子目录到 `targets/<domain>/`

---

### Phase 2 — Subdomain Discovery（子域名发现）

**7 个工具，严格按顺序执行**:

| 步骤 | 工具 | 类型 | 输出文件 | 阈值截断 |
|------|------|------|---------|----------|
| 2.1 | whois | 信息查询 | `whois_info/<domain>.html` | — |
| 2.2 | OneForAll | 综合（被动+爆破） | `oneforall_subdomains/oneforall.txt` | >20000 清空 |
| 2.3 | ksubdomain | 主动爆破 (`--wild-filter-mode advanced --silent`) | `ksubdomain_subdomains/ksubdomain.txt` | >20000 清空 |
| 2.4 | subDomainsBrute | 主动爆破 (`-t 200 --full`) | `subdomainsbrute_subdomains/subdomainsbrute.txt` | >20000 清空 |
| 2.5 | subfinder | 被动（API 聚合） (`-all`) | `subfinder_subdomains/subfinder.txt` | >20000 清空 |
| 2.6 | gau | 被动（历史 URL） (`--subs`) | `gau_subdomains/gau.txt` | >20000 清空 |
| 2.7 | jsubfinder | JS 分析 (`grep -F` 精确匹配) | `jsubfinder_subdomains/jsubfinder.txt` | — |

**关键细节**:
- `OneForAll` 的 CSV 不能用 `awk -F ","` 直接拆列，必须按真正 CSV 规则解析；否则字段里的逗号会导致错位，出现类似 `,,,,,,,,RapidDNSQuery` 的异常记录
- `ksubdomain.yaml` 已存在时直接复用，避免多目标/多次运行反复改写共享配置
- 所有 `.txt` 写入使用 `anew`（去重追加），阈值触发时用 `truncate -s 0` 清空

---

### Phase 3 — DNS Resolution & Expansion（DNS 解析与扩展）

**3.1 泛解析检测（3 次重试）**:
- 生成 18 位随机子域名 → dig 解析（使用系统 DNS）
- ≥2 次解析成功 → 判为泛解析 → 跳过 dnsgen/alterx
- 每轮间隔 1 秒，不同随机子域名
- 如果用户在 Phase 1 关闭了域名变形，也跳过

**3.2 dnsgen 排列生成**（仅当非泛解析 **且** Phase 1 启用域名变形）:
- 输入: 6 工具 + jsubfinder 的合并子域名
- 输出: dnsgen 排列 → dnsx 解析验证
- 阈值: 本次新增 > 1000 条清空

**3.3 alterx 排列生成**（仅当非泛解析 **且** Phase 1 启用域名变形）:
- 输入: 上述 + dnsgen 结果
- 互补 dnsgen，生成不同模式的排列
- 阈值: 本次新增 > 1000 条清空

**3.4 合并所有子域名** → `collect_subdomains/collect_subdomains.txt`

**3.5 dnsx 解析 → 内外网分离**:
- `active_subdomains2ips.txt`: 子域名 → IP 完整映射
- `active_subdomains.txt`: 过滤局域网 IP 的外网子域名（grep -v '局域网'）
- `active_subdomains_intranet.txt`: 仅内网子域名

---

### Phase 4 — IP & Port Discovery（IP 提取与端口扫描）

**4.1 独立 IP + CDN 过滤（双层）**:
```
第 1 层 nali:  过滤 CloudFlare / Akamai / CDN / CloudFront / Fastly / GitHub
第 2 层 nocdn: CDN IP 段数据库二次过滤
```

**4.2 合并扫描目标**: 外网子域名 + 独立 IP → `active_all/active_all.txt`

**4.3 端口扫描（按 Phase 1 选择）**:
```
[1] top-100   → naabu -top-ports 100   (~3 分钟)
[2] top-1000  → naabu -top-ports 1000  (~15 分钟)
[3] 全端口     → naabu -p -             (~60 分钟)
```
- SYN 扫描（需 root），非 root 自动降级 TCP Connect
- 无结果自动重试 3 次（Phase 4/5/6 资源密集型引擎间隔 30s/60s/120s）
- 对解析成功但 `naabu` 未返回端口的域名，进入 Phase 5 前会用 `httpx` 再做默认协议/默认端口兜底探测

---

### Phase 5 — Web Service Probing（Web 探测）

**5.1 httpx 指纹识别 + 智能分类**:
- 第一遍 httpx（`-silent`）: 从端口列表和兜底域名列表过滤存活 HTTP 服务
- 第二遍 httpx: 获取状态码/标题/Server/技术栈/CNAME/IP → JSON
- jq 过滤 null url → `active_webs.txt`

**智能分类（两个维度）**:
```
高价值目标: 标题含 admin/管理/后台/登录/dashboard/console/api/debug/swagger
            → high_value_targets.txt

源码泄露风险: URL 含 .git/.svn/.env/heapdump/phpinfo/.DS_Store
            → leak_risks.txt
```

**5.2 Web 截图（按 Phase 1 选择）**:
- 开启: gowitness 截图（`-t 10 -T 40`）+ 3 次重试
- 未开启: 跳过

---

### Phase 6 — Vulnerability Scanning（漏洞扫描）

> **前置：6.0 规模守卫** —— 先按 24 小时阈值决定走【全量覆盖】还是【优化规则】，
> 详见「关键机制 → 规模守卫」。**必须先输出规模评估与所采用的规则**。

**6 个引擎**:

| 步骤 | 引擎 | 功能 | 输出 |
|------|------|------|------|
| 6.1 | kscan | 端口指纹 + Hydra 弱口令爆破 | `active_ports/*_portsfinger.txt` |
| 6.2 | afrog | POC 验证（高危+严重，分批 500/批） | `afrog_scan_results/part_*.json` |
| 6.3 | ihoneyBakFileScan | 备份文件扫描 | `backup_result/backup_scan.txt` → **须过软404过滤** |
| 6.4 | auto_dirsearch | 目录/文件爆破（1C1G 自适应） | `dirsearch_result/smart_scan_*.txt` → **须过软404过滤** |
| 6.5 | nuclei | YAML 模板扫描 (`~/nuclei-templates/`) | `nuclei_fuzzing_result/nuclei-templates_fuzzing.txt` |
| 6.6 | katana + nuclei DAST | 爬虫 (`-d 5`) + DAST Fuzz | `nuclei_fuzzing_result/*.txt` |

**关键细节**:
- kscan: 分离 IP:端口 和 域名:端口（`grep -E` 精确 IP 正则和域名正则）
- afrog: `split -l 500` 分批，每批后 `rm` 临时文件，自动归档 `json/html/err.log` 到 `afrog_scan_results/`
- nuclei 模板: 默认使用 `~/nuclei-templates/`（非 `/root/`），DAST 模板从 `/opt/fuzzing-templates` 软链
- dirsearch: 默认保留并重点研判 `200,401,403,301,302,307,308,405`，智能过滤无结果时回退标准模式，并补扫少量高价值敏感文件
- **6.3.1 / 6.4.1 软404过滤（MUST，不可跳过）**: 备份与 dirsearch 的原始输出
  必须经 `soft404_check.py` / `dirsearch_filter.py` 过滤；
  **报告与研判只能引用 `*_clean.txt`**，禁止引用 raw（详见「关键机制 → 软404治理」）

---

### Phase 7 — Report（报告与研判）

**7.1 统计报告（bash 自动生成）**:
- 子域名/DNS/IP端口/Web资产/漏洞发现 各维度行数统计
- `jq -s 'map(length) | add'` 正确计 afrog 总发现数
- 弱口令提取: `grep 'Success'` → `anew` 写入 `brute_success.txt`
- 完整文件索引: `find ... | while read -r f`

**7.2 AI 自动研判（核心价值）**:
- Step 1: 读入原始结果（优先级: brute > backup > afrog > nuclei > dirsearch）
- Step 2: 逐条研判 — 去重合并 / 真实性判定 / CVSS 危害分级 / dirsearch 专项
- Step 3: 渗透方向 — 每条含入口点 → 攻击手法 → 预期结果
- Step 4: 输出研判报告（按严重度分组 + 攻击链组合 + 推荐优先级）

**7.3 HTML 报告**:
```bash
# 单域名
python3 references/scripts/generate_report.py -d "targets/<domain>"
# → 生成 targets/<domain>/<domain>_7scanAI_report.html

# 多域名汇总
python3 references/scripts/generate_report.py -r targets/
# → 生成 targets/7scanAI_report.html
```
离线可用，无 CDN 依赖。含统计卡片、Web 资产表、漏洞发现表、截图预览。

### Phase 8 — Autonomous Exploitation（自主利用攻击）

Phase 7 研判完成后，AI 对确认有效的漏洞执行实际攻击，**不做建议而是直接利用**。

**12 条利用链路（按 tier 升序）**:

| 优先级 | 漏洞类型 | 攻击方式 | 预期成果 |
|--------|---------|---------|---------|
| Tier 0 | 弱口令 | SSH/MySQL/Redis/PG/Mongo/FTP 直接登录 | Shell / 数据库访问 |
| Tier 1 | RCE/命令注入 | 反弹 shell / webshell 部署 | 服务器控制权 |
| Tier 2 | SQL 注入 | sqlmap `--dbs` → `--dump` → 凭据提取 | 数据库数据（**禁止 `--os-shell`**） |
| Tier 2 | 备份/配置泄露 | 下载 → 解压 → grep 凭据 | 源码 / 数据库密码 |
| Tier 3 | 默认凭据 | 15 条常用弱口令尝试面板登录（上限 20 对） | 后台管理权限 |
| Tier 3 | 登录口爆破 | Basic Auth / ffuf 表单爆破 | 后台认证绕过 |
| Tier 3 | 文件上传 | PHP/JSP webshell 上传+验证 | 代码执行 |
| Tier 4 | LFI/路径穿越 | /etc/passwd → .env → 凭据链 | 配置信息 → RCE |
| Tier 4 | SSTI | Jinja2/Twig/Freemarker RCE payload | 命令执行 |
| Tier 4 | SSRF | 云元数据 + 内网端口探测 | 云凭据 / 内网拓扑 |
| Tier 4 | OAuth 滥用 | redirect_uri 绕过 / state 缺失 / scope 越权 | 账号接管 |
| Tier 5 | 注册接口利用 | 自动注册 → 登录 → 管理功能越权测试 | 越权访问 |

> ⚠️ **注册接口利用是 Tier 5 最低优先级**，排在 LFI/SSTI/SSRF/OAuth **之后**
> （注册流程通常有验证码/邮箱验证，投入产出比低）。

**凭据复用喷洒**: 所有收割的 user:pass 对所有 SSH 端口尝试。

**产物**: `targets/$DOMAIN/exploit_result/` — `exploit_plan.json`（Phase 8 入口）、
`exploit_log.txt`、`exploit_success.txt`、`harvested_credentials.txt`、`test_accounts.txt`、
`login_candidates.txt`、`register_candidates.txt`、`oauth_candidates.txt`、`all_targets.txt`、
`ssh_targets.txt`、`sqli_request.txt`、`admin_paths_to_test.txt`、`sqlmap/`、`evidence/`、
`<domain>_exploit_report.md`

---

## 关键机制

### anew 去重体系

所有 `.txt` 写入统一使用 `anew`（只追加不重复的行）。这是整个断点续跑机制的基石：

```
正常执行:   anew 写入 100 条 → 文件 100 行
中断重跑:   anew 再写入 → 同 100 条被去重 → 文件仍是 100 行
阈值判断:   wc -l 还是 100 → 不会误触发 >1000 清空逻辑
```

**例外**: 增量阈值触发清空时用 `truncate -s 0`（直接截断），不经过 anew。

### 泛解析检测（3 次重试）

单次 DNS 查询可能因网络抖动误判：
- 3 次独立查询，每次不同随机子域名
- ≥2 次解析成功才判为泛解析
- 使用系统 DNS 解析器

### 自动重试机制

每步命令失败或无结果时自动重试，间隔递增（2s / 4s / 8s）。3 次全失败 → 记录原因 → 继续下一步。保证网络抖动不中断全流程。

### 端口分离逻辑

naabu 输出的 `active_ports.txt` 包含两种格式：
```
192.168.1.1:80          → IP 正则 → active_ips_ports.txt (走 kscan --hydra)
admin.target.com:443    → 域名正则 → active_webs_ports.txt (走 kscan --check)
```

### 增量阈值截断

| 场景 | 阈值 | 原因 |
|------|------|------|
| 子域名工具 | > 20000 条 | 目标可能是泛解析或 CDN，结果无意义 |
| dnsgen/alterx | > 1000 条 | 排列爆炸，几乎全是垃圾 |

### 规模守卫（24 小时阈值）

重型引擎启动前必须用**实测吞吐**估算耗时，按 24 小时阈值二选一：

| 预计耗时 | 规则 | 目的 |
|---------|------|------|
| **≤ 24 小时** | **全量覆盖扫描** | 代价可接受 → 保证覆盖完整、不留盲区 |
| **> 24 小时** | **优化规则扫描**（Tier A/B/C 分级） | 实际不可完成 → 优先保证能出结果 |

**吞吐必须实测，不得凭经验估算** —— 实测发现同样 1496 个 POC，
混 403/302 的 500 目标集只有 **4.3 task/s**，纯 200 的 15 目标集达 **35 task/s**（8 倍差距）。

用户可双向覆盖：明确要求"不管多久都全量" ⇒ 全量；"启用分级" ⇒ 立即分级。

### 软 404 / SPA catch-all 误报治理

SPA 站点对**任意路径**都返回 `index.html` + 200，而扫描器把"非空 200"当命中，
会产生大量高危误报。**实测某次扫描 28 条"高危"全部是此类误报**，
其中 dirsearch 报出的 11 条 `.env` 体积从 882B 到 108539B 各不相同，
**极像真实配置泄露**，实为各站 index.html。

治理方式：对每个命中 host 取**随机不存在路径**做基线复测。

| 产物 | 含义 | 报告 |
|------|------|------|
| `*_clean.txt` | 真实命中 | ✅ 引用 |
| `*_soft404.txt` | 软 404 误报 | ❌ 禁止引用 |
| `*_unverified.txt` | 无法判定 | ⚠️ 人工确认 |

三条实现要点：**基线与命中项都要重试 3 次**；**基线一致单条即定案**；
**取不到基线 ⇒ unverified，绝不允许默认判 clean**。

### 长任务执行模型

AI Agent harness（Claude Code / Codex）的 bash 工具**每次调用是独立 shell**，
单次有硬性超时上限（通常 10 分钟）。因此**禁止**用阻塞式轮询跑长扫描——
超过 10 分钟的扫描会被 harness 强杀且成果丢失。

统一使用 `references/scripts/watchdog_lib.sh`：

| 函数 | 语义 |
|------|------|
| `wd_run` | **阻塞**，返回时任务已结束（后续步骤依赖产物时用） |
| `wd_start` | **非阻塞**，立即返回（边跑边做别的事时用） |
| `wd_poll` | 查状态，返回 **0=运行中 / 1=已结束**（返回值**不是**退出码） |
| `wd_exitcode` | 取已完成任务的退出码 |
| `wd_wait` / `wd_kill` | 受限等待 / TERM→15s→KILL |

**进度判定 = 输出字节增长 OR CPU 增长率 ≥ 20%**：
- 只看字节数会**误杀**缓冲输出的健康进程（实测 0 字节跑 40 分钟被误杀）
- 只看 CPU 增长会**漏杀**被目标 RST 拖住的僵尸进程（实测 0.04% CPU 缓慢增长）

### 跨调用变量恢复

同样是"每次调用独立 shell"的后果：`DOMAIN` / `SCRIPT_DIR` / `TARGET_DIR` 等变量
**不会跨调用保留**，而全流程 40+ 处依赖它们。

因此 Phase 1 会生成 `targets/<domain>/runtime/env.sh`（含全部变量 + 自动 source
`watchdog_lib.sh`），**之后每次 bash 调用的第一行必须 source 它**：

```bash
source targets/<domain>/runtime/env.sh
```

未生成或未 source 就直接跑后续步骤 = 违规，会得到空路径或 `unbound variable`。

---

## 结果目录结构

```
targets/<domain>/
├── whois_info/
│   └── <domain>.html
├── oneforall_subdomains/
│   └── oneforall.txt
├── ksubdomain_subdomains/
│   └── ksubdomain.txt
├── subdomainsbrute_subdomains/
│   └── subdomainsbrute.txt
├── subfinder_subdomains/
│   └── subfinder.txt
├── gau_subdomains/
│   ├── url.txt
│   └── gau.txt
├── jsubfinder_subdomains/
│   └── jsubfinder.txt
├── dnsgen_subdomains/
│   └── dnsgen.txt              # 仅非泛解析 + 用户启用时
├── alterx_subdomains/
│   └── alterx.txt              # 仅非泛解析 + 用户启用时
├── collect_subdomains/
│   └── collect_subdomains.txt
├── active_subdomains/
│   ├── active_subdomains2ips.txt
│   ├── active_subdomains.txt
│   └── active_subdomains_intranet.txt
├── active_ips/
│   └── active_ips.txt
├── active_all/
│   └── active_all.txt
├── active_ports/
│   ├── active_ports.txt
│   ├── active_ips_ports.txt
│   ├── active_webs_ports.txt
│   ├── active_webs_portsfinger.txt
│   └── active_ips_portsfinger.txt
├── active_webs/
│   ├── active_websfinger.json
│   ├── active_webs.txt
│   ├── high_value_targets.txt
│   ├── leak_risks.txt
│   ├── tier_a_highvalue.txt    # 仅启用分级扫描时生成
│   ├── tier_b_200.txt          # 仅启用分级扫描时生成
│   └── tier_c_other.txt        # 仅启用分级扫描时生成
├── afrog_scan_results/
│   ├── part_*.json
│   └── *.html
├── backup_result/
│   ├── backup_scan.txt              # 引擎原始输出（含软404误报，禁止写报告）
│   ├── backup_scan_clean.txt        # ✅ 过滤后真实命中（报告只引用这个）
│   ├── backup_scan_soft404.txt      # ❌ 软404误报
│   └── backup_scan_unverified.txt   # ⚠️ 无法判定，需人工确认
├── brute_result/
│   └── brute_success.txt
├── dirsearch_result/
│   ├── smart_scan_*.txt             # 引擎原始输出（含软404误报，禁止写报告）
│   ├── dirsearch_clean.txt          # ✅ 过滤后真实命中（报告只引用这个）
│   ├── dirsearch_soft404.txt        # ❌ 软404误报
│   └── dirsearch_unverified.txt     # ⚠️ 无法判定，需人工确认
├── nuclei_fuzzing_result/
│   ├── nuclei-templates_fuzzing.txt
│   ├── nuclei-DAST_fuzzing.txt
│   ├── katana_urls.txt
│   └── uro_urls.txt
├── web_screenshots/
│   ├── gowitness.sqlite3
│   └── screenshots/*.png
├── exploit_result/
│   ├── exploit_log.txt
│   ├── exploit_success.txt
│   ├── harvested_credentials.txt
│   └── evidence/
├── runtime/
│   ├── env.sh               # 跨调用变量恢复（每次 bash 调用先 source 它）
│   ├── <tool>.pid           # 长任务 PID
│   ├── <tool>.exitcode      # 长任务退出码
│   └── <tool>.status        # running / done / idle-timeout / killed
└── <domain>_7scanAI_report.html
```

---

## 依赖工具

### 核心（必须安装）
| 工具 | 安装 |
|------|------|
| subfinder | `go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest` |
| dnsx | `go install github.com/projectdiscovery/dnsx/cmd/dnsx@latest` |
| naabu | `go install github.com/projectdiscovery/naabu/v2/cmd/naabu@latest` |
| httpx | `go install github.com/projectdiscovery/httpx/cmd/httpx@latest` |
| nuclei | `go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest` |

### 扩展（推荐安装）
| 工具 | 安装 |
|------|------|
| OneForAll | `git clone https://github.com/shmilylty/OneForAll.git /opt/OneForAll && pip3 install -r /opt/OneForAll/requirements.txt --break-system-packages` |
| ksubdomain | `go install github.com/boy-hack/ksubdomain/v2/cmd/ksubdomain@latest` |
| subDomainsBrute | `git clone https://github.com/lijiejie/subDomainsBrute.git /opt/subDomainsBrute && pip3 install -r /opt/subDomainsBrute/requirements.txt --break-system-packages` |
| gau | `go install github.com/lc/gau/v2/cmd/gau@latest` |
| jsubfinder | `go install github.com/ThreatUnkown/jsubfinder@latest` |
| afrog | `go install github.com/zan8in/afrog/v3/cmd/afrog@latest` |
| katana | `go install github.com/projectdiscovery/katana/cmd/katana@latest` |
| gowitness | `go install github.com/sensepost/gowitness@latest` |
| kscan | `cd /opt && git clone https://github.com/lcvvvv/kscan && cd kscan && go build` |
| anew | `go install github.com/tomnomnom/anew@latest` |
| nali | `go install github.com/zu1k/nali@latest` |
| nocdn | `go install github.com/r00tSe7en/nocdn@latest` |
| alterx | `go install github.com/projectdiscovery/alterx/cmd/alterx@latest` |
| dnsgen | `pip3 install dnsgen --break-system-packages` |
| uro | `pip3 install uro --break-system-packages` |

### Python 工具（git clone 后必须 pip install requirements.txt）
| 工具 | 路径 | 安装 |
|------|------|------|
| dirsearch | `/opt/dirsearch` | `git clone https://github.com/maurosoria/dirsearch.git /opt/dirsearch && pip3 install -r /opt/dirsearch/requirements.txt --break-system-packages` |
| ihoneyBakFileScan | `/opt/ihoneyBakFileScan_Modify` | `git clone https://github.com/VMsec/ihoneyBakFileScan_Modify.git /opt/ihoneyBakFileScan_Modify && pip3 install -r /opt/ihoneyBakFileScan_Modify/requirements.txt --break-system-packages` |

### 一键安装 / 检测
```bash
# 仅检测（列出缺失项）
bash references/scripts/auto_install.sh check

# 检测失败后，再手动安装所有缺失工具
bash references/scripts/auto_install.sh
```

---

## 安装

### 通过 Claude Code 安装



本地让Claude自己安装后，`Claude Code` 会按官方插件规则读取 `.claude-plugin/plugin.json`。

如果你是把这个仓库直接作为当前项目使用，而不是安装插件，则 `Claude Code` 会按官方项目规则读取 `.claude/skills/7scanai/SKILL.md`。

### 通过 Codex 安装

将仓库作为本地插件目录接入，`Codex` 会按插件规则读取 [`.codex-plugin/plugin.json`](/opt/code/7scanAI/7scanAI/.codex-plugin/plugin.json:1) 和 [`skills/7scanai/SKILL.md`](/opt/code/7scanAI/7scanAI/skills/7scanai/SKILL.md:1)。

如果你的 `Codex` 使用个人插件市场目录，保持该仓库结构不变并把它放到对应插件路径下即可。

### 手动安装

```bash
git clone https://github.com/<your-username>/7scanAI.git /opt/code/7scanAI
```

---

## 使用

### 命令行调用
```
# Claude Code / Codex 插件模式
/7scanai:7scanai baidu.com

# Claude Code 项目模式（当前仓库）
/7scanai baidu.com
```

### 自然语言（AI 自动触发）
```
扫 baidu.com
```

### 指定参数
```
扫 baidu.com，端口扫全端口，需要截图
扫 qq.com，快速扫一下（top-100 端口，不截图，不开域名变形）
扫 target.com，有泛解析别开域名变形，端口 top-1000 不截图

# 我常用的设定目标模式
/goal 扫描vulnweb.com达到出完整报告的程度，运行中遇到的任何问题尝试解决，进程长时间挂住无反应主动kill，我需要扫top100端口,不做子域名变形，截图关闭
```

### 多域名（逐个独立扫描）
```
扫 baidu.com 和 qq.com 和 alibaba.com
```

默认串行执行。只有你明确要求并发，且机器高于 `4C/4G`，才会放开到 `2-3` 个目标并发；`Phase 6` 默认仍是单目标独占。

### 生成 HTML 报告
```
生成 baidu.com 的扫描报告
```

### 多域名汇总（需明确要求）
```
汇总 targets 下所有域名的结果
```

---

## 文件清单

```
7scanAI/
├── SKILL.md                       # 轻量主控 skill（触发条件、规则、phase 编排）
├── README.md                      # 本文件
├── .codex-plugin/
│   └── plugin.json                # Codex 插件描述
├── .claude-plugin/
│   └── plugin.json                # Claude Code 插件描述
├── .claude/
│   └── skills/
│       └── 7scanai/
│           └── SKILL.md           # Claude Code 项目级 skill 入口
├── skills/
│   └── 7scanai/
│       └── SKILL.md               # Codex 兼容层，指向根目录权威流程
└── references/
    ├── install.md                 # 详细安装指南
    ├── config.md                  # 配置说明
    ├── pipeline/
    │   ├── full-workflow.md       # 命令级原始长版流程
    │   ├── 02-subdomain-tools.md  # 子域名工具参数说明
    │   ├── 04-port-strategy.md    # 端口扫描策略
    │   ├── 06-vuln-engines.md     # 漏洞引擎参数说明
    │   └── 08-exploitation.md     # 漏洞利用 playbook
    └── scripts/
        ├── auto_install.sh        # 环境预检 + 缺失自动安装
        ├── auto_dirsearch.py      # 智能目录爆破（1C1G 自适应）
        ├── generate_report.py     # 生成离线 HTML 报告
        ├── watchdog_lib.sh        # 脱离式长任务执行库（双超时 + CPU/字节双进度信号）
        ├── soft404_check.py       # 备份扫描软404校验（三分类输出）
        └── dirsearch_filter.py    # dirsearch 软404过滤（三分类输出）
```

## 版本

**v2.0** — 2026-08-12
- 8 Phase 完整工作流
- 3 项 Phase 1 确认（端口 / 域名变形 / 截图）
- 16 个安全工具集成（7 子域名 + 3 排列/DNS + 6 漏洞引擎）
- DOMAIN 路径穿越校验
- pipefail 强制启用
- grep -F 精确匹配 / jq null 过滤 / IP 格式校验
- `~/nuclei-templates/` 替代硬编码 `/root/`
- anew 全流程去重 + truncate 阈值截断
- 3 次自动重试（递增间隔）
- AI 自动研判 → 渗透方向建议
- 离线 HTML 报告生成
