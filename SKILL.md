---
name: 7scanai
description: 自动化安全侦察与漏洞扫描 pipeline。用户给根域名后，按 7scanAI 的七阶段流程完成子域名发现、DNS解析、端口扫描、Web探测、漏洞扫描与报告生成。
---

# 7scanAI

7scanAI 是一个低自由度扫描工作流。目标是让 AI 严格复用仓库内既有命令、脚本和目录约定，避免凭记忆重写扫描流程。

## 何时使用

- 用户要求扫描、挖洞、信息收集、资产发现、端口扫描、漏洞扫描、渗透测试
- 用户给出目标域名、URL 或一组域名，并希望自动完成完整流程
- 用户要求生成 `targets/<domain>/` 下的扫描结果或 HTML 报告

## 核心规则

1. 只使用仓库内定义过的命令参数和脚本，禁止凭记忆改写参数。
2. 扫描结果必须写入 `targets/<domain>/`，禁止直接写入 `targets/` 根目录。
2.1 **产物路径强制锁定（MUST）**: 所有产物必须写入以下固定路径，**禁止自创子目录、禁止用别名、禁止写回域名根目录**。任一文件不在此表中即为违规：

**Phase 2 产物**:
| 文件 | 强制路径 |
|------|---------|
| oneforall.txt | `targets/$DOMAIN/oneforall_subdomains/oneforall.txt` |
| ksubdomain.txt | `targets/$DOMAIN/ksubdomain_subdomains/ksubdomain.txt` |
| subdomainsbrute.txt | `targets/$DOMAIN/subdomainsbrute_subdomains/subdomainsbrute.txt` |
| subfinder.txt | `targets/$DOMAIN/subfinder_subdomains/subfinder.txt` |
| gau.txt | `targets/$DOMAIN/gau_subdomains/gau.txt` |
| jsubfinder.txt | `targets/$DOMAIN/jsubfinder_subdomains/jsubfinder.txt` |

**Phase 3 产物**:
| 文件 | 强制路径 |
|------|---------|
| collect_subdomains.txt | `targets/$DOMAIN/collect_subdomains/collect_subdomains.txt` |
| active_subdomains2ips.txt | `targets/$DOMAIN/active_subdomains/active_subdomains2ips.txt` |
| active_subdomains.txt | `targets/$DOMAIN/active_subdomains/active_subdomains.txt` |
| active_subdomains_intranet.txt | `targets/$DOMAIN/active_subdomains/active_subdomains_intranet.txt` |
| dnsgen.txt | `targets/$DOMAIN/dnsgen_subdomains/dnsgen.txt` |
| alterx.txt | `targets/$DOMAIN/alterx_subdomains/alterx.txt` |

**Phase 4 产物**:
| 文件 | 强制路径 |
|------|---------|
| active_ips.txt | `targets/$DOMAIN/active_ips/active_ips.txt` |
| active_all.txt | `targets/$DOMAIN/active_all/active_all.txt` |
| active_ports.txt | `targets/$DOMAIN/active_ports/active_ports.txt` |

**Phase 5 产物**:
| 文件 | 强制路径 |
|------|---------|
| active_webs.txt | `targets/$DOMAIN/active_webs/active_webs.txt` |
| active_websfinger.json | `targets/$DOMAIN/active_webs/active_websfinger.json` |
| high_value_targets.txt | `targets/$DOMAIN/active_webs/high_value_targets.txt` |
| leak_risks.txt | `targets/$DOMAIN/active_webs/leak_risks.txt` |

**Phase 6 产物**:
| 文件 | 强制路径 |
|------|---------|
| active_ips_portsfinger.txt | `targets/$DOMAIN/active_ports/active_ips_portsfinger.txt` |
| active_webs_portsfinger.txt | `targets/$DOMAIN/active_ports/active_webs_portsfinger.txt` |
| backup_scan.txt | `targets/$DOMAIN/backup_result/backup_scan.txt` |
| nuclei-templates_fuzzing.txt | `targets/$DOMAIN/nuclei_fuzzing_result/nuclei-templates_fuzzing.txt` |
| nuclei-DAST_fuzzing.txt | `targets/$DOMAIN/nuclei_fuzzing_result/nuclei-DAST_fuzzing.txt` |
| katana_urls.txt | `targets/$DOMAIN/nuclei_fuzzing_result/katana_urls.txt` |
| uro_urls.txt | `targets/$DOMAIN/nuclei_fuzzing_result/uro_urls.txt` |
| smart_scan_*.txt | `targets/$DOMAIN/dirsearch_result/smart_scan_*.txt` |

**Phase 7 产物**:
| 文件 | 强制路径 |
|------|---------|
| brute_success.txt | `targets/$DOMAIN/brute_result/brute_success.txt` |
| HTML 报告 | `targets/$DOMAIN/${DOMAIN}_7scanAI_report.html` |

**运行时文件** (`targets/$DOMAIN/runtime/`): `<tool>.pid`、`<tool>.exitcode`

**禁止的路径模式**:
- ❌ 直接写根目录: `targets/$DOMAIN/collect_subdomains.txt`
- ❌ 自创别名目录: `targets/$DOMAIN/parsed/`、`ph3/`、`merge/`、`subdomains/`、`scans/`、`httpx/`、`results/`、`raw/`、`ports/`、`phase3/`、`phase4/`、`phase5/`
- ✅ 唯一合法: `targets/$DOMAIN/<上表子目录>/<文件名>`

违反时必须回退修复: 从错误位置拷到强制路径后删除原文件。

3. 所有 `.txt` 结果文件统一使用 `anew` 写入；阈值清空只允许 `truncate -s 0`。
4. Phase 1 只允许问一次：端口范围、域名变形、截图开关。确认后全程自动执行，不再追问。
5. 每个阶段结束必须输出 checkpoint，并列出核心产物文件和行数。
6. 命令失败或超时必须自动重试最多 3 次；扫描类重试间隔长于轻量信息收集。
7. 输入文件为空时必须跳过对应步骤，不能空跑重量级工具。
8. Python 依赖必须走系统级安装：`pip3 install --break-system-packages`，禁止虚拟环境。
9. 所有 bash 代码块必须以 `set -o pipefail` 开头。
9.1 **pipefail + grep 安全规则**: 带 `pipefail` 时，`grep` 无匹配会返回 1 导致管道中断。以下场景**必须**在前面加 `grep ... || true` 或在 grep 后追加 `|| true`：
   - 用 `grep -Eo 'domain' ports.txt | anew` 拆分 IP/域名端口时
   - 用 `grep 'Success' finger.txt | anew` 提取弱口令成功记录时
   - 任何"可能找不到匹配"的 grep 管线
   或者改用临时方案：`set +o pipefail` 临时关闭 → 执行 grep 管线 → `set -o pipefail` 恢复。
10. 长任务必须记录 PID 到 `targets/<domain>/runtime/`，并同时设置总超时和“无进度超时”。
11. 无进度判定以 raw 产物或错误日志的字节数增长为准；超时后先发 `TERM`，等待 10-15 秒，再发 `KILL`。
12. 每一步执行都必须显式提示当前状态：开始、完成、跳过、失败重试，不能只在 phase 结束后汇总。

## 自治执行

默认进入 `autonomous mode`。

在不改变用户目标、端口范围、截图开关、域名变形开关的前提下，允许 AI 自动：

- 安装或修复缺失依赖后继续执行
- 切换到更稳妥的 fallback 路径
- 清洗脏输出、重建中间产物后继续执行
- 对明显异常或不合理结果做交叉验证
- 对受影响的单一步骤或单一 phase 做局部重跑
- 将确认过的流程缺陷同步修回 skill 项目

只有在以下情况才停止并询问用户：

- 需要改变用户已经确认的扫描意图
- 连续 3 次同类修复仍失败，且没有新的 fallback
- 继续执行会带来明显更高的外部风险或成本

## 多目标调度

多目标默认不是全并发。

- 无论机器配置如何，默认串行执行目标
- 只有用户明确要求并发时，且机器高于 `4C/4G`，才允许并发 `2-3` 个目标
- `Phase 6` 资源最重，默认按单目标独占执行；不要让多个目标同时跑漏洞阶段
- 任何时候都优先保证目标间产物隔离，其次才是吞吐量

## 执行模式

根 `SKILL.md` 只保留控制逻辑。真正执行某个阶段前，按需读取对应 reference：

- 完整命令级流程：`references/pipeline/full-workflow.md`
- 安装与环境：`references/install.md`
- 配置与 profile：`references/config.md`
- Phase 2 参数补充：`references/pipeline/02-subdomain-tools.md`
- Phase 4 参数补充：`references/pipeline/04-port-strategy.md`
- Phase 6 参数补充：`references/pipeline/06-vuln-engines.md`

如果你需要照着原始长版逐步执行，优先读取 `references/pipeline/full-workflow.md`。它是当前权威命令集。

## Phase 编排

### Phase 1 - Intake

先做四件事：

1. 规范化用户输入，只保留根域名。
2. 一次性确认：
   - 端口范围：`top-100` / `top-1000` / `1-65535`
   - 是否启用 `dnsgen` / `alterx`
   - 是否启用 `gowitness`
3. 定位 7scanAI 根目录并确定目标绝对工作目录。
4. 跑环境预检。
5. 创建 `targets/<domain>/` 目录树。

默认值：

- 端口范围默认 `top-1000`
- 域名变形默认 `n`
- 截图默认 `n`

Profile 规则：

- 用户明确指定 `quick` / `full` / `deep` 时，先读取 `references/config.md` 并按对应 profile 设默认扫描强度。
- 用户明确给出覆盖项时，以用户覆盖项为准，例如 `top-500`、`只做子域名发现`、`不做漏洞扫描`。
- 即使套用了 profile，Phase 1 仍然只能进行一次性确认；已被用户明确指定的项不再重复询问。
- 所有 profile 或覆盖项都必须记录在 Phase 1 checkpoint。

根目录定位逻辑必须满足：

- 优先从当前目录向上找同时包含 `SKILL.md` 和 `references/scripts/auto_install.sh` 的目录
- 找不到时，再全盘搜索 `*/references/scripts/auto_install.sh`
- 只要 `SCRIPT_DIR` 不含 `references/scripts/auto_install.sh`，立即中止

目标工作目录必须满足：

- 先在任何 `pushd "$SCRIPT_DIR"` 之前保存 `WORK_ROOT="$(pwd)"`
- 再定义 `TARGET_DIR="$WORK_ROOT/targets/$DOMAIN"`
- 只要某个步骤会切换工作目录，后续文件读写就必须改用 `"$TARGET_DIR"/...` 绝对路径

环境预检必须执行：

```bash
set -o pipefail

SCRIPT_DIR="<按规则探测出的 7scanAI 根目录>"
bash "$SCRIPT_DIR"/references/scripts/auto_install.sh check
```

如果 `check` 失败，优先提示用户手动运行：

```bash
bash "$SCRIPT_DIR"/references/scripts/auto_install.sh
```

手动安装完成后，再继续扫描流程。默认不要在主流程里直接安装依赖。

如需逐条执行初始化命令，读取 `references/pipeline/full-workflow.md` 的 Phase 1。

### Phase 2 - Subdomain Discovery

严格按原流程顺序执行：

1. `whois`
2. `OneForAll`
3. `ksubdomain`
4. `subDomainsBrute`
5. `subfinder`
6. `gau`
7. `jsubfinder`

必须遵守：

- 子域名工具本次新增超过 `20000` 条时清空对应结果文件
- `OneForAll` 必须排除 CSV 末列为 `Brute` 的结果
- `ksubdomain` 必须在项目根目录运行，并先校验本机出口 IP 再写 `ksubdomain.yaml`

执行命令前读取：

- `references/pipeline/full-workflow.md` 的 Phase 2
- `references/pipeline/02-subdomain-tools.md`

### Phase 3 - DNS Resolution And Expansion

顺序固定：

1. 泛解析检测，3 次独立重试
2. 非泛解析且用户启用变形时跑 `dnsgen`
3. 再跑 `alterx`
4. 合并全部子域名
5. 用 `dnsx` 做解析并分离内外网

必须遵守：

- 泛解析判定条件是 3 次中至少 2 次成功解析随机子域名
- `dnsgen` / `alterx` 本次新增超过 `1000` 条时清空
- `active_subdomains.txt` 只保留外网结果

执行命令前读取 `references/pipeline/full-workflow.md` 的 Phase 3。

### Phase 4 - IP And Port Discovery

顺序固定：

1. 抽取独立 IP
2. `nali` 第一层 CDN 过滤
3. `nocdn` 第二层 CDN 过滤
4. 合并外网子域名与独立 IP
5. 用 `naabu` 按用户选定范围扫端口

必须遵守：

- `top-100` / `top-1000` / `全端口` 三档策略不能混用
- 无结果时允许自动重试
- SYN 扫描需要 root，不满足时允许降级

执行命令前读取：

- `references/pipeline/full-workflow.md` 的 Phase 4
- `references/pipeline/04-port-strategy.md`

### Phase 5 - Web Probing

顺序固定：

1. 用 `httpx` 找存活 HTTP 服务
2. 再跑一遍 `httpx` 采集指纹 JSON
3. 生成 `active_webs.txt`
4. 分类高价值目标与泄露风险目标
5. 用户启用截图时跑 `gowitness`

必须遵守：

- 对 `active_subdomains.txt` 中解析成功但未出现在 `active_ports.txt` 的域名，必须做一次 `httpx` 兜底探测，避免把默认 80/443 Web 站点误判为无服务
- `jq` 过滤掉 `null url`
- 截图关闭时明确跳过，不要隐式执行

执行命令前读取 `references/pipeline/full-workflow.md` 的 Phase 5。

### Phase 6 - Vulnerability Scanning

固定顺序：

1. `kscan`
2. `afrog`
3. `ihoneyBakFileScan`
4. `auto_dirsearch.py`
5. `nuclei`
6. `katana + uro + nuclei DAST`

必须遵守：

- `kscan` 以 `active_ports.txt` 为输入，为空时只跳过 6.1
- `afrog` / `备份扫描` / `dirsearch` / `nuclei` / `katana + DAST` 以 `active_webs.txt` 为输入，为空时跳过 6.2-6.6
- `afrog` 必须分批
- `katana` / `nuclei DAST` 只在上游输入非空时运行

执行命令前读取：

- `references/pipeline/full-workflow.md` 的 Phase 6
- `references/pipeline/06-vuln-engines.md`

### Phase 7 - Report

固定顺序：

1. 统计各阶段产物
2. 提取弱口令成功结果
3. 汇总 `afrog` / `nuclei` / `dirsearch` / `backup` 等结果
4. 做 AI 研判
5. 需要 HTML 时执行 `generate_report.py`

必须遵守：

- AI 研判不能跳过
- 研判优先级：`brute` > `backup` > `afrog` > `nuclei` > `dirsearch`
- HTML 报告支持单域名和多域名汇总两种入口

执行命令前读取 `references/pipeline/full-workflow.md` 的 Phase 7。

## 决策点

- 用户未给域名：只追问域名，不进入扫描
- 用户未选端口范围：默认 `top-1000`
- 用户未选域名变形：默认 `n`
- 用户未选截图：默认 `n`
- 用户指定 `quick` / `full` / `deep` 或自定义覆盖项：先读 `references/config.md`，再把覆盖项压到最终执行参数
- 发现泛解析：跳过 `dnsgen` / `alterx`
- 任一步输入为空：跳过该步及其依赖步骤
- 多域名场景：逐个独立跑单域名流程，最终只在用户明确要求时生成汇总报告

## 输出要求

每个 phase 结束都输出：

- 当前 checkpoint 是否通过
- 本阶段新产物路径
- 每个核心 `.txt` 文件的行数
- 被跳过的步骤及原因

每个步骤执行时都输出：

- `▶ <步骤编号> <步骤名>` 开始
- `✅ <步骤编号> <步骤名>` 完成
- `⏭️ <步骤编号> <步骤名>` 跳过及原因
- `⚠️ <步骤编号> <步骤名>` 失败重试信息

## 维护约定

- 根 `SKILL.md` 只放触发条件、硬约束、phase 编排和决策点
- 命令级实现统一下沉到 `references/pipeline/full-workflow.md`
- 参数解释和工具差异继续放在 `references/` 下的分文件中
- 修改扫描逻辑时，先改 `references/pipeline/full-workflow.md`，再同步这里的摘要
