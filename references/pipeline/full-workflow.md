# 7scanAI Full Workflow

本文件保存 7scanAI 的命令级原始长版流程。已同步当前兼容修正，供根目录 `SKILL.md` 在执行具体阶段时按需读取。

## 原始长版流程

# 7scanAI — AI 驱动的自动化安全扫描 Pipeline

**核心理念**:你给域名，AI 执行全流程。严格按照 7scanAI 原生脚本逻辑编排工具链，AI 自主判断泛解析等分支逻辑。

**反幻觉硬约束**:
1. 所有工具命令来自原生脚本（7scan.py / SandS.sh / auto_dirsearch.py），不准凭记忆拼参数
2. 每个阶段结束必须输出 checkpoint + 产物文件列表
3. 扫描结果实时展示，不攒到最后

---

## 触发条件

- 用户给域名/IP/URL 说 "扫描 / 挖洞 / 信息收集 / 资产发现"
- "扫一下 example.com"
- "对 target.com 做安全扫描"

---

## 全局规则

1. **目录约定 (MUST)**: 所有结果**必须**输出到 `./targets/<domain>/` 下，**禁止**直接写入 `./targets/`。每个命令的 `-o` / 输出路径必须包含以用户根域名命名的子目录（如 `targets/example.com/xxx/xxx.txt`）。targets/ 不存在则自动创建。Phase 1 结束后必须 `ls -d targets/$DOMAIN` 验证目录已创建
2. **所有 .txt 写入强制用 anew**:全流程所有 `.txt` 文件写入统一用 `anew`，禁止 `tee` / `>` / `>>`。`anew` 是断点续跑的基石——保证无论重跑多少次，文件内容去重、行数稳定，阈值判断（>20000 / >1000）不会被重复数据污染。工具自身的输出参数（`-o` / `--json` / `-json`）不受此限制。**例外**: 增量阈值触发清空时用 `truncate -s 0`（直接截断，不经过 anew，否则 anew 去重后清空不彻底）
3. **增量阈值**:子域名工具本次新增 > 20000 条时清空，dnsgen/alterx 本次新增 > 1000 条时清空（BEFORE/AFTER 取差值，防 anew 累积误判）
4. **扫描前确认，扫描中不问**:Phase 1 一次性确认端口范围、域名变形、截图三个选项，之后全程自动执行，不再询问
5. **每阶段结束列出产物 .txt 文件及其行数**
6. **断点续跑 + 自动重试**:每步命令失败或超时，自动重试最多 3 次。Phase 2/3 轻量命令重试间隔 2s/4s/8s；Phase 4 端口扫描和 Phase 6 漏洞扫描重试间隔 30s/60s/120s（扫描工具为资源密集型，短间隔无意义）。3 次都失败则记录失败原因并继续下一步。anew 保证重试不会污染已有结果
7. **Python 工具安装硬规则**: 所有 Python 依赖**必须**安装为系统级包，使用 `pip3 install --break-system-packages`，**禁止**使用 pyenv / virtualenv / pipx 等虚拟环境。每个 Python 工具 git clone 后**必须**立即执行 `pip3 install -r requirements.txt --break-system-packages`，不可跳过。工具检测时通过 `python3 <entrypoint> -h` 验证依赖是否完整安装
8. **所有 bash 代码块必须以 `set -o pipefail` 开头**:管道中任何命令失败都会传递退出码，防止中间态错误被静默吞掉
9. **超时设置**: Bash 工具的 timeout 参数必须根据扫描阶段设置足够长，禁止一刀切 10 分钟：
   - Phase 2/3 信息收集工具（whois/OneForAll/ksubdomain/subDomainsBrute/subfinder/gau/jsubfinder/dnsgen/alterx/dnsx）: 默认 20min
   - Phase 4 naabu 端口扫描: top-100 → 60min, top-1000 → 120min, 全端口 → 240min
   - Phase 6 afrog: 每批 60min
   - Phase 6 nuclei: 120min
   - Phase 6 katana: 60min
   - Phase 6 dirsearch: 120min
   - Phase 6 其他工具 (kscan/backup scan): 120min
10. **watchdog 硬规则**:
    - 所有长任务必须把 PID 写入 `targets/$DOMAIN/runtime/<tool>.pid`
    - 同时设置总超时和无进度超时，不能只靠其中一种
    - 无进度判定以 raw 结果文件和对应 `_err.log` 的字节数是否增长为准
    - 超时 kill 顺序固定为 `TERM -> 等待 15s -> KILL`
    - kill 后必须记录原因、PID、退出码
11. **步骤提示硬规则**:
    - 每个步骤开始前输出 `▶ <步骤编号> <步骤名>`
    - 每个步骤成功结束后输出 `✅ <步骤编号> <步骤名>`
    - 跳过时输出 `⏭️ <步骤编号> <步骤名>: <原因>`
    - 重试时输出 `⚠️ <步骤编号> <步骤名>: 第 N 次重试`
12. **自治执行硬规则**:
    - 默认不因单步失败而中止整个扫描
    - 发现环境问题时先自动修复，再重试当前步骤
    - 发现结果明显异常时先做交叉验证，再决定是否重跑
    - 发现工具策略不适配时先切 fallback，再继续主流程
    - 确认是 skill 项目缺陷时，允许先修项目再局部重跑受影响步骤
    - 同类问题连续 3 次修复仍失败，才允许中止并上报
13. **多目标调度硬规则**:
    - 无论机器配置如何，默认串行跑目标
    - 只有用户明确要求并发时，且机器高于 `4C/4G`，才允许 `2-3` 个目标并发
    - `Phase 6` 默认单目标独占执行
    - 不允许为了吞吐量牺牲目标间产物隔离
14. **空输入跳过 (MUST)**: 任何扫描步骤的输入文件为空（0 行），**必须跳过**该步骤及其依赖步骤。空输入运行扫描工具不仅无意义，还会导致：
    - katana `-headless` 启动无用的 Chrome 实例消耗内存
    - nuclei 加载大量模板后无目标可扫，浪费 CPU 或被 OOM kill
    - afrog 空批次无意义消耗 POC 加载时间
    - 跳过规则：
      - `active_webs.txt` 为 0 → 跳过 6.1-6.6 全部
      - katana_urls.txt 为 0 → 跳过 uro + nuclei DAST (6.6 后续步骤)
      - afrog 批次文件为 0 → 跳过该批次
      - uro_urls.txt 为 0 → 跳过 nuclei DAST
    - 跳过时输出 `⏭️ <步骤名>: 输入为空，跳过`

---

## Phase 1 · Intake（初始化）

**目的**:确认目标、端口策略、域名变形开关、截图开关、创建输出目录

**流程**:

1. 如果用户没给域名 → 反问 "请提供目标域名"
2. 用户给了域名后，**必须一次性确认下面三项**（一选一问题+两个布尔问题，一次问完）：

> **⚠️ 三项必须都在 Phase 1 确认，确认后整个扫描过程不再询问。**

**问题 1 — 端口扫描范围**:
```
选择端口扫描范围：
  [1] top-100   (~3 分钟)
  [2] top-1000  (~15 分钟)
  [3] 全端口 1-65535 (~60 分钟)
```
用户未选择时默认 **top-1000**。

**问题 2 — 域名变形生成（dnsgen / alterx）**:
```
是否启用子域名排列变形生成？(y/n)
  → dnsgen + alterx 基于已知子域名生成排列变体，可发现隐藏子域名
  → 若目标有泛解析（wildcard DNS），排列生成会产生海量垃圾结果（会被阈值自动截断）
  → 已知目标有泛解析时建议关闭，节省扫描时间
```
用户未选择时默认 **否**（关闭）。

**问题 3 — Web 截图**:
```
是否对存活 Web 进行截图？(y/n)
  → 截图可直观预览页面，但会增加扫描时间
  → gowitness 截图，每个 URL ~5-10 秒
```
用户未选择时默认 **否**。

4. 从用户输入提取根域名并设置变量，然后创建目录:
```bash
set -o pipefail

# ⚠️ MUST: 从用户输入提取纯根域名（去掉 http://、https://、路径、端口等）
# 示例: "https://www.example.com:8080/path" → DOMAIN="example.com"
DOMAIN="<用户给的根域名>"   # AI 必须替换为实际域名，仅保留 example.com 部分

# ⚠️ MUST: 验证 DOMAIN 不含路径遍历字符，防止写入 ../ 逃逸 targets/
if echo "$DOMAIN" | grep -qE '(\.\./|/|\\|\s)'; then
  echo "❌ DOMAIN 包含非法字符（../、/、\\、空格），中止"
  exit 1
fi

# 自动探测 skill 安装路径（兼容 Codex / Claude Code）
# 只认包含 references/scripts/auto_install.sh 的目录，避免误命中兼容层 wrapper
SCRIPT_DIR=""
SEARCH_DIR="$(pwd)"
while [ "$SEARCH_DIR" != "/" ]; do
  if [ -f "$SEARCH_DIR/references/scripts/auto_install.sh" ] && [ -f "$SEARCH_DIR/SKILL.md" ]; then
    SCRIPT_DIR="$SEARCH_DIR"
    break
  fi
  SEARCH_DIR="$(dirname "$SEARCH_DIR")"
done

if [ -z "$SCRIPT_DIR" ]; then
  SCRIPT_DIR="$(find / -maxdepth 5 -type f -path '*/references/scripts/auto_install.sh' 2>/dev/null | head -1 | xargs -r dirname | xargs -r dirname | xargs -r dirname)"
fi

if [ -z "$SCRIPT_DIR" ] || [ ! -f "$SCRIPT_DIR/references/scripts/auto_install.sh" ]; then
  echo "❌ 无法定位 7scanAI 安装目录（缺少 references/scripts/auto_install.sh）"
  exit 1
fi
echo "📍 7scanAI 安装路径: $SCRIPT_DIR"
WORK_ROOT="$(pwd)"

# ── 环境预检 (MUST — 不可跳过) ──
# Phase 2-6 依赖大量 CLI 工具，缺任何一个都会导致扫描中断。
# AI 必须先跑 auto_install.sh check 检测依赖。
# 如果检测失败，优先提示用户手动运行 auto_install.sh，避免在主流程中边装边扫。
	echo ""
	echo "🔧 检查依赖环境..."
	if ! bash "$SCRIPT_DIR"/references/scripts/auto_install.sh check; then
	    echo ""
	    echo "❌ 环境检查失败，优先请用户手动运行依赖安装脚本"
	    echo "   bash \"$SCRIPT_DIR\"/references/scripts/auto_install.sh"
	    exit 1
	fi
	echo ""

# 根据 Phase 1 用户选择设置（AI 根据用户回答填入）
PORT_RANGE=2          # 1=top-100, 2=top-1000, 3=全端口
PERMUTATION="n"       # "y" 或 "n" — 是否启用 dnsgen + alterx 域名变形
SCREENSHOT="n"        # "y" 或 "n"
TARGET_DIR="$WORK_ROOT/targets/$DOMAIN"

mkdir -p targets
mkdir -p "targets/$DOMAIN"/{whois_info,oneforall_subdomains,ksubdomain_subdomains,subdomainsbrute_subdomains,subfinder_subdomains,gau_subdomains,jsubfinder_subdomains,dnsgen_subdomains,alterx_subdomains,collect_subdomains,active_subdomains,active_ips,active_all,active_ports,active_webs,web_screenshots/screenshots,afrog_scan_results,dirsearch_result,nuclei_fuzzing_result,brute_result,backup_result,runtime}

# ⚠️ 验证目录已创建 — 失败则中止
if [ ! -d "targets/$DOMAIN" ]; then
  echo "❌ 目录 targets/$DOMAIN 创建失败，中止"
  exit 1
fi
echo "✅ 输出目录: targets/$DOMAIN/"
ls -d targets/$DOMAIN/*/

# 统一 watchdog:
#   run_with_watchdog <name> <total_timeout_s> <idle_timeout_s> <progress_file> <err_file> -- <command...>
safe_line_count() {
  local target_file="$1"
  [ -f "$target_file" ] && wc -l < "$target_file" || echo 0
}

finalize_err_log() {
  local err_file="$1"
  local exit_code="$2"
  local clean_file

  [ -f "$err_file" ] || return 0
  clean_file="${err_file}.clean"

  perl -pe 's/\r/\n/g; s/\x1b\[[0-9;?]*[ -\/]*[@-~]//g' "$err_file" | \
    sed '/^[[:space:]]*$/d' > "$clean_file"
  mv "$clean_file" "$err_file"

  if [ "$exit_code" -eq 0 ] && ! grep -qiE 'error|warn|failed|timeout|exception|panic|traceback|forbidden|denied|429|500|502|503' "$err_file"; then
    truncate -s 0 "$err_file"
  fi
}

run_with_watchdog() {
  local tool_name="$1"
  local total_timeout="$2"
  local idle_timeout="$3"
  local progress_file="$4"
  local err_file="$5"
  shift 5
  [ "$1" = "--" ] && shift

  mkdir -p "$TARGET_DIR/runtime"
  : > "$err_file"
  [ -n "$progress_file" ] && : > "$progress_file"

  (
    timeout --kill-after=30 "$total_timeout" "$@" 2>>"$err_file"
  ) &
  local scan_pid=$!
  echo "$scan_pid" > "$TARGET_DIR/runtime/${tool_name}.pid"

  local last_progress_ts
  local last_bytes
  local cur_bytes
  local now_ts
  last_progress_ts=$(date +%s)
  last_bytes=0

  while kill -0 "$scan_pid" 2>/dev/null; do
    sleep 30
    cur_bytes=$(( $(wc -c < "$progress_file" 2>/dev/null || echo 0) + $(wc -c < "$err_file" 2>/dev/null || echo 0) ))
    now_ts=$(date +%s)
    if [ "$cur_bytes" -gt "$last_bytes" ]; then
      last_bytes="$cur_bytes"
      last_progress_ts="$now_ts"
    elif [ $((now_ts - last_progress_ts)) -ge "$idle_timeout" ]; then
      echo "⚠️ ${tool_name} ${idle_timeout}s 无进度，终止 PID $scan_pid" | tee -a "$err_file"
      kill "$scan_pid" 2>/dev/null || true
      sleep 15
      kill -9 "$scan_pid" 2>/dev/null || true
      break
    fi
  done

  wait "$scan_pid"
  local scan_rc=$?
  echo "$scan_rc" > "$TARGET_DIR/runtime/${tool_name}.exitcode"
  finalize_err_log "$err_file" "$scan_rc"
  return "$scan_rc"
}
```

**MUST 输出 checkpoint**:
- [ ] 目标域名确认
- [ ] 端口范围已选择: top-100 / top-1000 / 全端口
- [ ] 域名变形生成: 是 / 否
- [ ] Web 截图: 是 / 否
- [ ] 目录结构已创建

**Phase 1 通过即进入 Phase 2，全程自动执行不再询问。**

---

## Phase 2 · Subdomain Discovery（子域名发现）

**目的**:从多源收集子域名。严格按照 7scan.py 的 run_command 顺序执行。

### 2.1 whois 信息
```bash
run_with_watchdog "whois" 1200 300 \
  "targets/$DOMAIN/whois_info/$DOMAIN.html" \
  "targets/$DOMAIN/whois_info/$DOMAIN.err.log" -- \
  wget --timeout=30 "https://whois.aite.xyz/?ajax&domain=$DOMAIN" -O "targets/$DOMAIN"/whois_info/"$DOMAIN".html -nv
```

### 2.2 OneForAll
```bash
run_with_watchdog "oneforall" 1200 300 \
  "targets/$DOMAIN/oneforall_subdomains/$DOMAIN.csv" \
  "targets/$DOMAIN/oneforall_subdomains/oneforall.err.log" -- \
  python3 /opt/OneForAll/oneforall.py --target "$DOMAIN" --path="targets/$DOMAIN/oneforall_subdomains/" --req False run

# ⚠️ CSV 解析硬规则 (v1.0.1 修复):
#   1. tr -d '\r' — 去除 CRLF 行尾, 否则 $NF 匹配 "Brute\r" 而非 "Brute"
#   2. $NF != "Brute" — 排除 wildcard DNS brute 结果 (泛解析下量产 95k+ 垃圾)
#   3. 当本次新增 >20000 时清空 (与其他子域名工具阈值对齐)
BEFORE=$(safe_line_count "targets/$DOMAIN/oneforall_subdomains/oneforall.txt")
cat "targets/$DOMAIN"/oneforall_subdomains/"$DOMAIN".csv | tr -d '\r' | awk -F "," 'NR>1 && $NF != "Brute" {print $6}' | sed '/^$/d' | sort | uniq | anew "targets/$DOMAIN"/oneforall_subdomains/oneforall.txt
AFTER=$(safe_line_count "targets/$DOMAIN/oneforall_subdomains/oneforall.txt")
NEW=$((AFTER - BEFORE))
echo "OneForAll: $AFTER lines (new: $NEW) [Brute excluded]"

if [ "$NEW" -gt 20000 ]; then
  echo "⚠️ New entries exceed threshold ($NEW > 20000), clearing"
  truncate -s 0 "targets/$DOMAIN"/oneforall_subdomains/oneforall.txt
fi
```

### 2.3 ksubdomain
```bash
# ksubdomain 必须在项目根目录运行（读/写 ksubdomain.yaml）
pushd "$SCRIPT_DIR" >/dev/null || { echo "❌ 无法进入 $SCRIPT_DIR"; exit 1; }
# ksubdomain.yaml 已存在则直接复用，避免多目标/多次运行反复改写共享配置
if [ ! -f "$SCRIPT_DIR/ksubdomain.yaml" ]; then
  run_with_watchdog "ksubdomain_test" 300 120 \
    "$SCRIPT_DIR/ksubdomain.yaml" \
    "$TARGET_DIR/ksubdomain_subdomains/ksubdomain_test.err.log" -- \
    ksubdomain test
  # 动态获取本机 IP 写入配置（必须校验 IP 格式）
  IP=$(curl -s --fail --connect-timeout 10 --max-time 15 https://api.ipify.org 2>/dev/null || true)
  if echo "$IP" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
    sed -i "1s/.*/src_ip: $IP/" "$SCRIPT_DIR"/ksubdomain.yaml
  else
    echo "⚠️ 获取/校验本机 IP 失败，保持 ksubdomain.yaml 现有配置"
  fi
else
  echo "ℹ️ 复用现有 ksubdomain.yaml，不重复生成/改写"
fi
BEFORE=$(safe_line_count "$TARGET_DIR/ksubdomain_subdomains/ksubdomain.txt")
# ksubdomain 输出含 "域名=>CNAME ...=>IP" 链，用 sed 去掉 => 及之后内容，仅保留纯域名
: > "$TARGET_DIR"/ksubdomain_subdomains/ksubdomain_raw.txt
run_with_watchdog "ksubdomain_enum" 1200 300 \
  "$TARGET_DIR/ksubdomain_subdomains/ksubdomain_raw.txt" \
  "$TARGET_DIR/ksubdomain_subdomains/ksubdomain.err.log" -- \
  sh -c 'ksubdomain e -d "$1" --wild-filter-mode advanced --silent > "$2"' _ "$DOMAIN" "$TARGET_DIR/ksubdomain_subdomains/ksubdomain_raw.txt"
cat "$TARGET_DIR"/ksubdomain_subdomains/ksubdomain_raw.txt | tr -d '\r' | sed 's/=>.*//' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed '/^$/d' | sort | uniq | anew "$TARGET_DIR"/ksubdomain_subdomains/ksubdomain.txt
AFTER=$(safe_line_count "$TARGET_DIR/ksubdomain_subdomains/ksubdomain.txt")
NEW=$((AFTER - BEFORE))
echo "ksubdomain: $AFTER 条 (本次新增 $NEW)"

if [ "$NEW" -gt 20000 ]; then
  echo "⚠️ 增量过大 ($NEW > 20000)，清空"
  truncate -s 0 "$TARGET_DIR/ksubdomain_subdomains/ksubdomain.txt"
fi
popd >/dev/null
```

### 2.4 subDomainsBrute
```bash
BEFORE=$(safe_line_count "targets/$DOMAIN/subdomainsbrute_subdomains/subdomainsbrute.txt")
# subDomainsBrute 依赖 ./dict/ 目录，需在其安装目录下运行；输出用绝对路径
ORIG_DIR="$(pwd)"
run_with_watchdog "subdomainsbrute" 1200 300 \
  "$ORIG_DIR/targets/$DOMAIN/subdomainsbrute_subdomains/$DOMAIN.txt" \
  "$ORIG_DIR/targets/$DOMAIN/subdomainsbrute_subdomains/subdomainsbrute.err.log" -- \
  bash -lc 'cd /opt/subDomainsBrute && python3 subDomainsBrute.py --full "$0" -t 200 -o "$1"' "$DOMAIN" "$ORIG_DIR/targets/$DOMAIN/subdomainsbrute_subdomains/$DOMAIN.txt"
cat "targets/$DOMAIN"/subdomainsbrute_subdomains/"$DOMAIN".txt | awk '{print $1}' | sort | uniq | anew "targets/$DOMAIN"/subdomainsbrute_subdomains/subdomainsbrute.txt
AFTER=$(safe_line_count "targets/$DOMAIN/subdomainsbrute_subdomains/subdomainsbrute.txt")
NEW=$((AFTER - BEFORE))
echo "subDomainsBrute: $AFTER 条 (本次新增 $NEW)"

if [ "$NEW" -gt 20000 ]; then
  echo "⚠️ 增量过大 ($NEW > 20000)，清空"
  truncate -s 0 "targets/$DOMAIN"/subdomainsbrute_subdomains/subdomainsbrute.txt
fi
```

### 2.5 subfinder
```bash
BEFORE=$(safe_line_count "targets/$DOMAIN/subfinder_subdomains/subfinder.txt")
run_with_watchdog "subfinder" 1200 300 \
  "targets/$DOMAIN/subfinder_subdomains/subfinder.txt" \
  "targets/$DOMAIN/subfinder_subdomains/subfinder.err.log" -- \
  subfinder -d "$DOMAIN" -all -o "targets/$DOMAIN"/subfinder_subdomains/subfinder.txt
AFTER=$(safe_line_count "targets/$DOMAIN/subfinder_subdomains/subfinder.txt")
NEW=$((AFTER - BEFORE))
echo "subfinder: $AFTER 条 (本次新增 $NEW)"

if [ "$NEW" -gt 20000 ]; then
  echo "⚠️ 增量过大 ($NEW > 20000)，清空"
  truncate -s 0 "targets/$DOMAIN"/subfinder_subdomains/subfinder.txt
fi
```

### 2.6 gau (历史URL提取子域名)
```bash
BEFORE=$(safe_line_count "targets/$DOMAIN/gau_subdomains/gau.txt")
: > "targets/$DOMAIN"/gau_subdomains/url_raw.txt
run_with_watchdog "gau" 1200 300 \
  "targets/$DOMAIN/gau_subdomains/url_raw.txt" \
  "targets/$DOMAIN/gau_subdomains/gau.err.log" -- \
  sh -c 'gau "$1" --subs --blacklist eot,jpg,jpeg,gif,css,tif,tiff,png,ttf,otf,woff,woff2,ico,svg,zip,rar,tar.gz,tgz,tar.bz2,tar,jar,war,7z,bak,sql,gz,sql.gz,tar.tgz --threads 50 > "$2"' _ "$DOMAIN" "targets/$DOMAIN/gau_subdomains/url_raw.txt"
cat "targets/$DOMAIN"/gau_subdomains/url_raw.txt | anew "targets/$DOMAIN"/gau_subdomains/url.txt
: > "targets/$DOMAIN"/gau_subdomains/gau_raw.txt
run_with_watchdog "gau_dnsx" 1200 300 \
  "targets/$DOMAIN/gau_subdomains/gau_raw.txt" \
  "targets/$DOMAIN/gau_subdomains/gau_dnsx.err.log" -- \
  sh -c 'cat "$1" | awk -F "/" "{print \$3}" | awk -F ":" "{print \$1}" | sort | uniq | dnsx > "$2"' _ "targets/$DOMAIN/gau_subdomains/url.txt" "targets/$DOMAIN/gau_subdomains/gau_raw.txt"
cat "targets/$DOMAIN"/gau_subdomains/gau_raw.txt | anew "targets/$DOMAIN"/gau_subdomains/gau.txt
AFTER=$(safe_line_count "targets/$DOMAIN/gau_subdomains/gau.txt")
NEW=$((AFTER - BEFORE))
echo "gau: $AFTER 条 (本次新增 $NEW)"

if [ "$NEW" -gt 20000 ]; then
  echo "⚠️ 增量过大 ($NEW > 20000)，清空"
  truncate -s 0 "targets/$DOMAIN"/gau_subdomains/gau.txt
fi
```

### 2.7 jsubfinder (JS子域名)
```bash
cat "targets/$DOMAIN"/oneforall_subdomains/oneforall.txt \
    "targets/$DOMAIN"/ksubdomain_subdomains/ksubdomain.txt \
    "targets/$DOMAIN"/subdomainsbrute_subdomains/subdomainsbrute.txt \
    "targets/$DOMAIN"/subfinder_subdomains/subfinder.txt \
    "targets/$DOMAIN"/gau_subdomains/gau.txt | sort | uniq > "targets/$DOMAIN"/jsubfinder_subdomains/jsubfinder_input.txt
: > "targets/$DOMAIN"/jsubfinder_subdomains/jsubfinder_raw.txt
run_with_watchdog "jsubfinder" 1200 300 \
  "targets/$DOMAIN/jsubfinder_subdomains/jsubfinder_raw.txt" \
  "targets/$DOMAIN/jsubfinder_subdomains/jsubfinder.err.log" -- \
  sh -c 'cat "$1" | httpx --silent | jsubfinder search | grep -v "GetResults content type JS" | grep -F "$2" > "$3"' _ "targets/$DOMAIN/jsubfinder_subdomains/jsubfinder_input.txt" "$DOMAIN" "targets/$DOMAIN/jsubfinder_subdomains/jsubfinder_raw.txt"
cat "targets/$DOMAIN"/jsubfinder_subdomains/jsubfinder_raw.txt | sort | uniq | anew "targets/$DOMAIN"/jsubfinder_subdomains/jsubfinder.txt
```

**MUST 输出 checkpoint**:
- [ ] 7 个工具全部执行完成
- [ ] 报告每个工具的产出行数

**产物清单**:
```
targets/$DOMAIN/whois_info/$DOMAIN.html
targets/$DOMAIN/oneforall_subdomains/oneforall.txt
targets/$DOMAIN/ksubdomain_subdomains/ksubdomain.txt
targets/$DOMAIN/subdomainsbrute_subdomains/subdomainsbrute.txt
targets/$DOMAIN/subfinder_subdomains/subfinder.txt
targets/$DOMAIN/gau_subdomains/gau.txt
targets/$DOMAIN/jsubfinder_subdomains/jsubfinder.txt
```

---

## Phase 3 · DNS Resolution & Expansion（泛解析检测 + 排列生成 + DNS解析）

**目的**:检测泛解析、生成子域名排列变体、DNS 解析、分离内外网

### 3.1 泛解析检测（带重试）

> DNS 查询可能因网络抖动失败。3 次重试均解析成功才判为泛解析，避免误判跳过 dnsgen/alterx。

```bash
WILDCARD=false
WILDCARD_CONFIRM=0

for i in 1 2 3; do
  RANDOM_STR=$(cat /dev/urandom | tr -dc 'a-z0-9' | head -c 18)
  RANDOM_SUB="$RANDOM_STR.$DOMAIN"

  echo "[尝试 $i/3] 解析 $RANDOM_SUB ..."
  if dig +short "$RANDOM_SUB" +time=5 2>/dev/null | grep -q '[0-9]'; then
    WILDCARD_CONFIRM=$((WILDCARD_CONFIRM + 1))
    echo "  ⚠️ 解析成功 (命中 $WILDCARD_CONFIRM/3)"
  else
    echo "  ✅ 解析失败 (NXDOMAIN)"
  fi
  sleep 1
done

if [ "$WILDCARD_CONFIRM" -ge 2 ]; then
  echo ""
  echo "⚠️⚠️ WILDCARD CONFIRMED: $DOMAIN 是泛解析域名"
  echo "   跳过 dnsgen 和 alterx（排列生成无意义）"
  WILDCARD=true
elif [ "$PERMUTATION" != "y" ]; then
  echo ""
  echo "⏭️ 跳过域名变形生成 (Phase 1 用户选择关闭)"
  WILDCARD=true
else
  echo ""
  echo "✅ NO WILDCARD: $DOMAIN 无泛解析，继续子域名排列生成"
  WILDCARD=false
fi
```

### 3.2 dnsgen 排列生成（仅当非泛解析且 Phase 1 启用域名变形）
```bash
if [ "$WILDCARD" = false ]; then
  BEFORE=$(safe_line_count "targets/$DOMAIN/dnsgen_subdomains/dnsgen.txt")
  cat "targets/$DOMAIN"/oneforall_subdomains/oneforall.txt \
      "targets/$DOMAIN"/ksubdomain_subdomains/ksubdomain.txt \
      "targets/$DOMAIN"/subdomainsbrute_subdomains/subdomainsbrute.txt \
      "targets/$DOMAIN"/subfinder_subdomains/subfinder.txt \
      "targets/$DOMAIN"/gau_subdomains/gau.txt \
      "targets/$DOMAIN"/jsubfinder_subdomains/jsubfinder.txt | sort | uniq > "targets/$DOMAIN"/dnsgen_subdomains/dnsgen_input.txt
  : > "targets/$DOMAIN"/dnsgen_subdomains/dnsgen_raw.txt
  run_with_watchdog "dnsgen" 1200 300 \
    "targets/$DOMAIN/dnsgen_subdomains/dnsgen_raw.txt" \
    "targets/$DOMAIN/dnsgen_subdomains/dnsgen.err.log" -- \
    sh -c 'cat "$1" | dnsgen - | dnsx -silent -a -resp | awk "{print \$1}" > "$2"' _ "targets/$DOMAIN/dnsgen_subdomains/dnsgen_input.txt" "targets/$DOMAIN/dnsgen_subdomains/dnsgen_raw.txt"
  cat "targets/$DOMAIN"/dnsgen_subdomains/dnsgen_raw.txt | anew "targets/$DOMAIN"/dnsgen_subdomains/dnsgen.txt
  AFTER=$(safe_line_count "targets/$DOMAIN/dnsgen_subdomains/dnsgen.txt")
  NEW=$((AFTER - BEFORE))
  echo "dnsgen: +$NEW 条新增 ($BEFORE → $AFTER)"

  # 仅本次新增 > 1000 才清空（不是累计总数）
  if [ "$NEW" -gt 1000 ]; then
    echo "⚠️ 排列增量过大 ($NEW > 1000)，清空 dnsgen 结果"
    truncate -s 0 "targets/$DOMAIN"/dnsgen_subdomains/dnsgen.txt
  fi
fi
```

### 3.3 alterx 排列生成（仅当非泛解析且 Phase 1 启用域名变形）
```bash
if [ "$WILDCARD" = false ]; then
  BEFORE=$(safe_line_count "targets/$DOMAIN/alterx_subdomains/alterx.txt")
  cat "targets/$DOMAIN"/oneforall_subdomains/oneforall.txt \
      "targets/$DOMAIN"/ksubdomain_subdomains/ksubdomain.txt \
      "targets/$DOMAIN"/subdomainsbrute_subdomains/subdomainsbrute.txt \
      "targets/$DOMAIN"/subfinder_subdomains/subfinder.txt \
      "targets/$DOMAIN"/gau_subdomains/gau.txt \
      "targets/$DOMAIN"/jsubfinder_subdomains/jsubfinder.txt \
      "targets/$DOMAIN"/dnsgen_subdomains/dnsgen.txt | sort | uniq > "targets/$DOMAIN"/alterx_subdomains/alterx_input.txt
  : > "targets/$DOMAIN"/alterx_subdomains/alterx_raw.txt
  run_with_watchdog "alterx" 1200 300 \
    "targets/$DOMAIN/alterx_subdomains/alterx_raw.txt" \
    "targets/$DOMAIN/alterx_subdomains/alterx.err.log" -- \
    sh -c 'cat "$1" | alterx | dnsx -silent -a -resp | awk "{print \$1}" > "$2"' _ "targets/$DOMAIN/alterx_subdomains/alterx_input.txt" "targets/$DOMAIN/alterx_subdomains/alterx_raw.txt"
  cat "targets/$DOMAIN"/alterx_subdomains/alterx_raw.txt | anew "targets/$DOMAIN"/alterx_subdomains/alterx.txt
  AFTER=$(safe_line_count "targets/$DOMAIN/alterx_subdomains/alterx.txt")
  NEW=$((AFTER - BEFORE))
  echo "alterx: +$NEW 条新增 ($BEFORE → $AFTER)"

  if [ "$NEW" -gt 1000 ]; then
    echo "⚠️ 排列增量过大 ($NEW > 1000)，清空 alterx 结果"
    truncate -s 0 "targets/$DOMAIN"/alterx_subdomains/alterx.txt
  fi
fi
```

### 3.4 合并所有子域名
```bash
cat "targets/$DOMAIN"/oneforall_subdomains/oneforall.txt \
    "targets/$DOMAIN"/ksubdomain_subdomains/ksubdomain.txt \
    "targets/$DOMAIN"/subdomainsbrute_subdomains/subdomainsbrute.txt \
    "targets/$DOMAIN"/subfinder_subdomains/subfinder.txt \
    "targets/$DOMAIN"/gau_subdomains/gau.txt \
    "targets/$DOMAIN"/jsubfinder_subdomains/jsubfinder.txt \
    "targets/$DOMAIN"/dnsgen_subdomains/dnsgen.txt \
    "targets/$DOMAIN"/alterx_subdomains/alterx.txt | sort | uniq | anew "targets/$DOMAIN"/collect_subdomains/collect_subdomains.txt
```

### 3.5 dnsx 解析 → 内外网分离

> **v1.0.2 修复**: dnsx 不经管道直写文件防止断点续跑丢失；增加 `-t` 线程和 `-timeout` 提速；用 `cat|wc -l` 代替 `wc -l <` 避免文件不存在时的 stderr 噪音。

```bash
# 子域名→IP 映射 (直写文件 + 后处理，防止管道中断丢失)
echo "  正在 dnsx 解析 $(cat targets/$DOMAIN/collect_subdomains/collect_subdomains.txt 2>/dev/null | wc -l) 个子域名 ..."
run_with_watchdog "dnsx_collect" 1200 300 \
  "targets/$DOMAIN/active_subdomains/active_subdomains2ips_raw.txt" \
  "targets/$DOMAIN/active_subdomains/dnsx_collect.err.log" -- \
  dnsx -l "targets/$DOMAIN"/collect_subdomains/collect_subdomains.txt -silent -a -resp -nc -t 200 -timeout 2 -retry 1 -o "targets/$DOMAIN"/active_subdomains/active_subdomains2ips_raw.txt

# 后处理: 格式化 IP
cat "targets/$DOMAIN"/active_subdomains/active_subdomains2ips_raw.txt 2>/dev/null | \
  sed 's/\[//g' | sed 's/\]//g' | sed -E 's/\s+A\s+/ /' | anew "targets/$DOMAIN"/active_subdomains/active_subdomains2ips.txt
echo "  子域名→IP: $(cat targets/$DOMAIN/active_subdomains/active_subdomains2ips.txt 2>/dev/null | wc -l) 条"

# 外网子域名 (过滤局域网IP)
: > "targets/$DOMAIN"/active_subdomains/active_subdomains_public_raw.txt
if cat "targets/$DOMAIN"/active_subdomains/active_subdomains2ips.txt 2>/dev/null | nali 2>"targets/$DOMAIN"/active_subdomains/nali_public.err.log | \
  grep -v '局域网' | awk '{print $1}' | sort | uniq > "targets/$DOMAIN"/active_subdomains/active_subdomains_public_raw.txt; then
  true
fi
if [ ! -s "targets/$DOMAIN"/active_subdomains/active_subdomains_public_raw.txt ]; then
  echo "⚠️ nali 输出异常或为空，回退到 RFC1918/loopback 规则做公网筛选"
  cat "targets/$DOMAIN"/active_subdomains/active_subdomains2ips.txt 2>/dev/null | \
    awk '$2 !~ /^(127\\.|10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[0-1])\\.)/ {print $1}' | \
    sort | uniq > "targets/$DOMAIN"/active_subdomains/active_subdomains_public_raw.txt
fi
cat "targets/$DOMAIN"/active_subdomains/active_subdomains_public_raw.txt | \
  anew "targets/$DOMAIN"/active_subdomains/active_subdomains.txt
echo "  外网子域名: $(cat targets/$DOMAIN/active_subdomains/active_subdomains.txt 2>/dev/null | wc -l) 条"

# 内网子域名 (仅局域网IP)
: > "targets/$DOMAIN"/active_subdomains/active_subdomains_intranet_raw.txt
if cat "targets/$DOMAIN"/active_subdomains/active_subdomains2ips.txt 2>/dev/null | nali 2>"targets/$DOMAIN"/active_subdomains/nali_intranet.err.log | \
  grep '局域网' | awk '{print $1}' > "targets/$DOMAIN"/active_subdomains/active_subdomains_intranet_input.txt; then
  true
fi
if [ ! -s "targets/$DOMAIN"/active_subdomains/active_subdomains_intranet_input.txt ]; then
  cat "targets/$DOMAIN"/active_subdomains/active_subdomains2ips.txt 2>/dev/null | \
    awk '$2 ~ /^(127\\.|10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[0-1])\\.)/ {print $1}' | \
    sort | uniq > "targets/$DOMAIN"/active_subdomains/active_subdomains_intranet_input.txt
fi
cat "targets/$DOMAIN"/active_subdomains/active_subdomains_intranet_input.txt | \
  sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed '/^$/d' | sort | uniq > "targets/$DOMAIN"/active_subdomains/active_subdomains_intranet_raw.txt
cat "targets/$DOMAIN"/active_subdomains/active_subdomains_intranet_raw.txt | \
  anew "targets/$DOMAIN"/active_subdomains/active_subdomains_intranet.txt
echo "  内网子域名: $(cat targets/$DOMAIN/active_subdomains/active_subdomains_intranet.txt 2>/dev/null | wc -l) 条"
```

**MUST 输出 checkpoint**:
- [ ] 泛解析检测结果
- [ ] 排列生成（如执行）
- [ ] DNS 解析完成
- [ ] 内外网子域名分离完成

**产物清单**:
```
targets/$DOMAIN/dnsgen_subdomains/dnsgen.txt           (非泛解析时)
targets/$DOMAIN/alterx_subdomains/alterx.txt           (非泛解析时)
targets/$DOMAIN/collect_subdomains/collect_subdomains.txt
targets/$DOMAIN/active_subdomains/active_subdomains2ips.txt
targets/$DOMAIN/active_subdomains/active_subdomains_public_raw.txt
targets/$DOMAIN/active_subdomains/active_subdomains.txt
targets/$DOMAIN/active_subdomains/active_subdomains_intranet_raw.txt
targets/$DOMAIN/active_subdomains/active_subdomains_intranet.txt
```

---

## Phase 4 · IP & Port Discovery（IP 提取、CDN 过滤、端口扫描）

**目的**:提取独立 IP、过滤 CDN、全端口扫描

### 4.1 独立 IP 提取 + CDN 过滤
```bash
: > "targets/$DOMAIN"/active_ips/active_ips_raw.txt
if cat "targets/$DOMAIN"/active_subdomains/active_subdomains2ips.txt | awk '{print $2}' | sort | uniq | \
  nali 2>"targets/$DOMAIN"/active_ips/nali_ips.err.log | grep -iEv '(本机地址|局域网|CloudFlare|Akamai|CDN|CloudFront|Fastly|GitHub)' | \
  awk '{print $1}' | nocdn > "targets/$DOMAIN"/active_ips/active_ips_raw.txt; then
  true
fi
if [ ! -s "targets/$DOMAIN"/active_ips/active_ips_raw.txt ]; then
  echo "⚠️ nali/nocdn 输出异常或为空，回退到 RFC1918/loopback 规则做 IP 筛选"
  cat "targets/$DOMAIN"/active_subdomains/active_subdomains2ips.txt | awk '{print $2}' | \
    grep -Ev '^(127\\.|10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[0-1])\\.)' | \
    sort | uniq > "targets/$DOMAIN"/active_ips/active_ips_raw.txt
fi
cat "targets/$DOMAIN"/active_ips/active_ips_raw.txt | \
  anew "targets/$DOMAIN"/active_ips/active_ips.txt
```

### 4.2 合并扫描目标（子域名 + IP）
```bash
cat "targets/$DOMAIN"/active_subdomains/active_subdomains.txt "targets/$DOMAIN"/active_ips/active_ips.txt | \
  sort | uniq | anew "targets/$DOMAIN"/active_all/active_all.txt
```

### 4.3 端口扫描

> 端口范围已在 Phase 1 由用户选定（top-100 / top-1000 / 全端口）。
> 
> **Web 兜底规则**: 对解析成功但 `naabu` 未返回端口的域名，不要直接判定“无 Web 服务”。进入 Phase 5 前，必须用 `httpx` 对 `active_subdomains.txt` 做一次基于默认协议/默认端口的兜底探测；命中者补入 `active_webs`，即使 `active_ports.txt` 为空也不能丢掉这类候选 Web 资产。

```bash
case "$PORT_RANGE" in
  1|top100)   PORT_ARG="-top-ports 100" ;;
  2|top1000)  PORT_ARG="-top-ports 1000" ;;
  3|full)     PORT_ARG="-p -" ;;
  *)         PORT_ARG="-top-ports 1000" ;;  # 默认
esac

# 带重试的端口扫描
for attempt in 1 2 3; do
  echo "[端口扫描 尝试 $attempt/3]"
  : > "targets/$DOMAIN"/active_ports/active_ports_raw.txt
  run_with_watchdog "naabu" 7200 900 \
    "targets/$DOMAIN/active_ports/active_ports_raw.txt" \
    "targets/$DOMAIN/active_ports/naabu_err.log" -- \
    naabu -l "targets/$DOMAIN"/active_all/active_all.txt -exclude-cdn -Pn -scan-type s -iv 4 \
      -c 50 -pts 50 -rate 10000 $PORT_ARG -o "targets/$DOMAIN"/active_ports/active_ports_raw.txt
  cat "targets/$DOMAIN"/active_ports/active_ports_raw.txt | \
    anew "targets/$DOMAIN"/active_ports/active_ports.txt

  if [ $(wc -l < "targets/$DOMAIN"/active_ports/active_ports.txt) -gt 0 ]; then
    echo "✅ 端口扫描完成: $(wc -l < "targets/$DOMAIN"/active_ports/active_ports.txt) 个开放端口"
    break
  else
    echo "⚠️ 端口扫描无结果，等待重试..."
    sleep $((2 ** attempt))  # 2s / 4s / 8s 递增
  fi
done
```

**MUST 输出 checkpoint**:
- [ ] 独立 IP 数、合并目标数、开放端口数
- [ ] 端口范围: top-100 / top-1000 / 全端口

**产物清单**:
```
targets/$DOMAIN/active_ips/active_ips_raw.txt
targets/$DOMAIN/active_ips/active_ips.txt
targets/$DOMAIN/active_all/active_all.txt
targets/$DOMAIN/active_ports/active_ports_raw.txt
targets/$DOMAIN/active_ports/active_ports.txt
```

---

## Phase 5 · Web Service Probing（Web 探测、指纹、截图）

**目的**:HTTP 服务识别、指纹获取、页面截图

### 5.1 httpx 探测 + 指纹 + 智能分类

```bash
# 第一遍 httpx：过滤可访问 HTTP 目标
: > "targets/$DOMAIN"/active_webs/httpx_alive_raw.txt
run_with_watchdog "httpx_alive" 3600 600 \
  "targets/$DOMAIN/active_webs/httpx_alive_raw.txt" \
  "targets/$DOMAIN/active_webs/httpx_alive.err.log" -- \
  sh -c 'httpx -l "$1" -silent | sort | uniq > "$2"' _ "targets/$DOMAIN/active_ports/active_ports.txt" "targets/$DOMAIN/active_webs/httpx_alive_raw.txt"

# 第二遍 httpx：采集 JSON 指纹
run_with_watchdog "httpx_fingerprint" 3600 600 \
  "targets/$DOMAIN/active_webs/active_websfinger.json" \
  "targets/$DOMAIN/active_webs/httpx_fingerprint.err.log" -- \
  httpx -l "targets/$DOMAIN"/active_webs/httpx_alive_raw.txt \
    -location -cdn -td -title -status-code -probe -cname --fc 0 -server -ip --threads 20 \
    -json -o "targets/$DOMAIN"/active_webs/active_websfinger.json

# JSON → 存活 URL 列表
cat "targets/$DOMAIN"/active_webs/active_websfinger.json | jq -r '.url | select(. != null)' | grep -v 'null$' | \
  anew "targets/$DOMAIN"/active_webs/active_webs.txt

echo "存活 Web: $(wc -l < "targets/$DOMAIN"/active_webs/active_webs.txt) 个"

# 智能分类: 高价值目标（管理后台/API/登录口）
cat "targets/$DOMAIN"/active_webs/active_websfinger.json | \
  jq -r 'select(.title != null and (.title | test("admin|管理|后台|登录|dashboard|console|\\bapi\\b|debug|swagger"; "i"))) | "\(.url) [\(.status_code)] \(.title)"' 2>/dev/null | \
  anew "targets/$DOMAIN"/active_webs/high_value_targets.txt
echo "高价值目标: $(wc -l < "targets/$DOMAIN"/active_webs/high_value_targets.txt) 个"

# 智能分类: 源码泄露风险
cat "targets/$DOMAIN"/active_webs/active_websfinger.json | \
  jq -r 'select(.url != null and (.url | test("\\.git|\\.svn|\\.env|heapdump|phpinfo|\\.DS_Store|\\.hg|\\.bzr"; "i"))) | "\(.url) [\(.status_code)]"' 2>/dev/null | \
  anew "targets/$DOMAIN"/active_webs/leak_risks.txt
echo "源码泄露风险: $(wc -l < "targets/$DOMAIN"/active_webs/leak_risks.txt) 个"
```

### 5.2 Web 截图（按 Phase 1 选择执行）

```bash
if [ "$SCREENSHOT" = "yes" ] || [ "$SCREENSHOT" = "y" ]; then
  echo "📸 开始 Web 截图..."
  for attempt in 1 2 3; do
    echo "[截图 尝试 $attempt/3]"
    run_with_watchdog "gowitness" 7200 600 \
      "targets/$DOMAIN/web_screenshots/gowitness.sqlite3" \
      "targets/$DOMAIN/web_screenshots/gowitness.err.log" -- \
      gowitness scan file -f "targets/$DOMAIN"/active_webs/active_webs.txt \
        --write-db -s "targets/$DOMAIN"/web_screenshots/screenshots -t 10 -T 40
    mv gowitness.sqlite3 "targets/$DOMAIN"/web_screenshots/gowitness.sqlite3 2>/dev/null

    SCREEN_COUNT=$(ls "targets/$DOMAIN"/web_screenshots/screenshots/ 2>/dev/null | wc -l)
    if [ "$SCREEN_COUNT" -gt 0 ]; then
      echo "✅ 截图完成: $SCREEN_COUNT 张"
      break
    else
      echo "⚠️ 截图失败或无结果，等待重试..."
      sleep $((2 ** attempt))
    fi
  done
else
  echo "⏭️ 跳过 Web 截图 (Phase 1 选择了否)"
fi
```

**MUST 输出 checkpoint**:
- [ ] 存活 Web 服务数 + 高价值目标数 + 源码泄露风险数
- [ ] 截图完成数（如开启）

**产物清单**:
```
targets/$DOMAIN/active_webs/httpx_alive_raw.txt
targets/$DOMAIN/active_webs/active_websfinger.json
targets/$DOMAIN/active_webs/active_webs.txt
targets/$DOMAIN/active_webs/high_value_targets.txt
targets/$DOMAIN/active_webs/leak_risks.txt
targets/$DOMAIN/web_screenshots/gowitness.sqlite3
targets/$DOMAIN/web_screenshots/screenshots/*.png
```

---

## Phase 6 · Vulnerability Scanning（漏洞扫描）

**目的**:多引擎漏洞检测。

⚠️ **串行执行硬规则**: 6 个扫描模块**必须逐个串行执行**，上一模块完全结束后才能开始下一模块。禁止并行启动多个扫描——每个模块都是资源密集型（CPU/内存/带宽），并行会互相抢占导致超时、误报、漏报。AI 必须等待每个命令块完整返回后再执行下一个，不准批量提交。

⚠️ **防管道阻塞硬规则**: 漏洞扫描工具输出量大、运行时间长，必须防止管道缓冲区满导致进程卡死：
- 工具自身的 `-o` / `--json` / `--output` 参数直写文件，不经过管道
- 必须用 shell 管道时加 `stdbuf -oL`（行缓冲）或 `unbuffer`
- stderr 重定向到日志文件 `2>/path/to/error.log`，防止 stderr 缓冲区阻塞 stdout
- 扫描前 `ulimit -n 50000` 提高文件描述符上限
- 禁止在长时间扫描命令后直接跟 `| grep` / `| awk` / `| anew`——先写文件，完成后再后处理

### 6.1 kscan 端口指纹 + 弱口令爆破
```bash
set -o pipefail
ulimit -n 50000

# 空输入检查
if [ ! -s "targets/$DOMAIN"/active_ports/active_ports.txt ]; then
  echo "⏭️ kscan: active_ports.txt 为空，跳过"
else
  # 分离 IP:端口 和 Web:端口
  cat "targets/$DOMAIN"/active_ports/active_ports.txt | \
    grep -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]{1,5}' | \
    anew "targets/$DOMAIN"/active_ports/active_ips_ports.txt

  cat "targets/$DOMAIN"/active_ports/active_ports.txt | \
    grep -Eo '[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}:[0-9]{1,5}' | \
    anew "targets/$DOMAIN"/active_ports/active_webs_ports.txt

  # Web 端口指纹
  if [ -s "targets/$DOMAIN"/active_ports/active_webs_ports.txt ]; then
    run_with_watchdog "kscan_web" 7200 900 \
      "targets/$DOMAIN/active_ports/active_webs_portsfinger.txt" \
      "targets/$DOMAIN/active_ports/kscan_webs_err.log" -- \
      kscan -t "targets/$DOMAIN"/active_ports/active_webs_ports.txt --check -Pn -Cn -Dn --threads 50 \
        -o "targets/$DOMAIN"/active_ports/active_webs_portsfinger.txt
  else
    echo "⏭️ kscan Web 指纹: active_webs_ports.txt 为空，跳过"
  fi

  # IP 端口指纹 + Hydra 弱口令
  if [ -s "targets/$DOMAIN"/active_ports/active_ips_ports.txt ]; then
    run_with_watchdog "kscan_ip" 7200 900 \
      "targets/$DOMAIN/active_ports/active_ips_portsfinger.txt" \
      "targets/$DOMAIN/active_ports/kscan_ips_err.log" -- \
      kscan -t "targets/$DOMAIN"/active_ports/active_ips_ports.txt --check -Pn -Cn -Dn --threads 50 --hydra \
        -o "targets/$DOMAIN"/active_ports/active_ips_portsfinger.txt
  else
    echo "⏭️ kscan IP 指纹: active_ips_ports.txt 为空，跳过"
  fi
fi
```

### 6.2 afrog 高危漏洞扫描（分批模式）

> **注意**: afrog 无漏洞时 `-json` 不产生文件（正常行为）。afrog 还会在 CWD 生成 `afrog-resume-*.afg` 文件，扫描完移动到结果目录。stderr 输出进度条，重定向到 `_err.log` 防止阻塞。

```bash
set -o pipefail
ulimit -n 50000

# 空输入检查
if [ ! -s "targets/$DOMAIN"/active_webs/active_webs.txt ]; then
  echo "⏭️ afrog: active_webs.txt 为空，跳过"
else
  mkdir -p "targets/$DOMAIN"/afrog_scan_results /tmp/afrog_work_$$
  REPORTS_TS="$(date +%s)"
  split -l 500 -d -a 4 "targets/$DOMAIN"/active_webs/active_webs.txt /tmp/afrog_work_$$/part_

  for file in /tmp/afrog_work_$$/part_*; do
    batch_name=$(basename "$file")
    echo "🔍 afrog 批次: $batch_name ($(wc -l < "$file") 目标)"
    run_with_watchdog "afrog_${batch_name}" 3600 900 \
      "targets/$DOMAIN/afrog_scan_results/${batch_name}.json" \
      "targets/$DOMAIN/afrog_scan_results/${batch_name}_err.log" -- \
      afrog -T "$file" -c 50 -rl 100 -S high,critical --task-smart-timeout \
        -json "targets/$DOMAIN"/afrog_scan_results/"$batch_name".json
    # 移动 afrog 自动生成的 resume 文件到结果目录
    find . -maxdepth 1 -name "afrog-resume-*.afg" -newer /tmp/afrog_work_$$ \
      -exec mv {} "targets/$DOMAIN"/afrog_scan_results/ \; 2>/dev/null || true
    rm -f "$file"
    sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    sleep 3
  done
  rm -rf /tmp/afrog_work_$$
  # 归档 afrog 自动生成的 HTML 报告目录
  if [ -d reports ]; then
    find reports -maxdepth 1 -type f -name '*.html' -newermt "@$REPORTS_TS" \
      -exec mv {} "targets/$DOMAIN"/afrog_scan_results/ \; 2>/dev/null || true
    rmdir reports 2>/dev/null || true
  fi
  # 清理 afrog 自动生成的 resume 文件（扫描已完成，无需断点续跑）
  find . -maxdepth 1 -name "afrog-resume-*.afg" -delete 2>/dev/null || true
  find "targets/$DOMAIN"/afrog_scan_results/ -name "afrog-resume-*.afg" -delete 2>/dev/null || true
fi
```

### 6.3 备份文件扫描
```bash
set -o pipefail

# 空输入检查
if [ ! -s "targets/$DOMAIN"/active_webs/active_webs.txt ]; then
  echo "⏭️ 备份扫描: active_webs.txt 为空，跳过"
else
  run_with_watchdog "backup_scan" 7200 900 \
    "targets/$DOMAIN/backup_result/backup_scan.txt" \
    "targets/$DOMAIN/backup_result/backup_scan_err.log" -- \
    python3 /opt/ihoneyBakFileScan_Modify/ihoneyBakFileScan_Modify.py \
      -t 200 -f "targets/$DOMAIN"/active_webs/active_webs.txt \
      -o "targets/$DOMAIN"/backup_result/backup_scan.txt
fi
```

### 6.4 目录/文件爆破

> auto_dirsearch.py 输出到 CWD 下的 `dirsearch_result/`，需先 cd 到域名目录。

```bash
set -o pipefail

# 空输入检查
if [ ! -s "targets/$DOMAIN"/active_webs/active_webs.txt ]; then
  echo "⏭️ dirsearch: active_webs.txt 为空，跳过"
else
  pushd "$TARGET_DIR" >/dev/null || { echo "❌ 无法进入 $TARGET_DIR，跳过 dirsearch"; exit 1; }
  if [ -f "active_webs/active_webs.txt" ]; then
    : > "dirsearch_result/dirsearch_progress.log"
    run_with_watchdog "dirsearch" 7200 900 \
      "$TARGET_DIR/dirsearch_result/dirsearch_progress.log" \
      "$TARGET_DIR/dirsearch_result/dirsearch.err.log" -- \
      sh -c 'python3 "$1" active_webs/active_webs.txt && find dirsearch_result -maxdepth 1 -type f -name "smart_scan_*.txt" -exec cat {} + > dirsearch_result/dirsearch_progress.log' _ "$SCRIPT_DIR/references/scripts/auto_dirsearch.py"
  else
    echo "❌ dirsearch 输入文件缺失: active_webs/active_webs.txt"
  fi
  popd >/dev/null
fi
```

### 6.5 Nuclei 模板扫描
```bash
set -o pipefail
ulimit -n 50000

# 空输入检查
if [ ! -s "targets/$DOMAIN"/active_webs/active_webs.txt ]; then
  echo "⏭️ Nuclei 模板扫描: active_webs.txt 为空，跳过"
else
  : > "targets/$DOMAIN"/nuclei_fuzzing_result/nuclei-templates_raw.txt
  run_with_watchdog "nuclei_templates" 7200 1200 \
    "targets/$DOMAIN/nuclei_fuzzing_result/nuclei-templates_raw.txt" \
    "targets/$DOMAIN/nuclei_fuzzing_result/nuclei-templates_err.log" -- \
    nuclei -t ~/nuclei-templates/ -severity critical,high,medium \
      -l "targets/$DOMAIN"/active_webs/active_webs.txt -bs 50 -c 50 -rl 50 -nc \
      -o "targets/$DOMAIN"/nuclei_fuzzing_result/nuclei-templates_raw.txt
  cat "targets/$DOMAIN"/nuclei_fuzzing_result/nuclei-templates_raw.txt | \
    anew "targets/$DOMAIN"/nuclei_fuzzing_result/nuclei-templates_fuzzing.txt
fi
```

### 6.6 Katana 爬虫 + Nuclei DAST Fuzzing

> **注意**: 引用 `~/nuclei-templates/dast/`，但 auto_install.sh 将 fuzzing-templates 克隆到 `/opt/fuzzing-templates`。执行前确认路径：
> ```bash
> # 如果 ~/nuclei-templates/dast/ 不存在，创建软链
> [ ! -d ~/nuclei-templates/dast/ ] && ln -s /opt/fuzzing-templates ~/nuclei-templates/dast/
> ```

> **headless 模式**: katana `-headless` 需要 Chrome/Chromium。若浏览器不可用或 katana > 2 分钟无输出，改用非 headless 模式（仅 HTTP 抓取，无法执行 JS 渲染的 SPA 页面）。

```bash
set -o pipefail
ulimit -n 50000

# 空输入检查 — 无存活 Web 则跳过全部
if [ ! -s "targets/$DOMAIN"/active_webs/active_webs.txt ]; then
  echo "⏭️ Katana+DAST: active_webs.txt 为空，跳过"
else
  # 确保 dast 模板路径存在
  [ ! -d ~/nuclei-templates/dast/ ] && ln -s /opt/fuzzing-templates ~/nuclei-templates/dast/ 2>/dev/null

  # ── Step 1: Katana 爬虫 ──
  # 检测 headless 浏览器可用性
  HEADLESS_FLAG=""
  if command -v chromium >/dev/null 2>&1 || command -v google-chrome >/dev/null 2>&1; then
    HEADLESS_FLAG="-headless"
    echo "🔍 Katana: headless 模式 (Chrome 可用)"
  else
    echo "⚠️ Katana: 非 headless 模式 (Chrome 不可用)"
  fi

  # katana 超时保护: 20min 总超时 + 30s SIGKILL 兜底
  : > "targets/$DOMAIN"/nuclei_fuzzing_result/katana_urls_raw.txt
  mkdir -p "targets/$DOMAIN"/runtime/katana_tmp
  run_with_watchdog "katana" 1200 600 \
    "targets/$DOMAIN/nuclei_fuzzing_result/katana_urls_raw.txt" \
    "targets/$DOMAIN/nuclei_fuzzing_result/katana_err.log" -- \
    sh -c 'TMPDIR="$4" katana -list "$1" $2 -no-sandbox -nc -d 5 -output-template "{{url}}" -silent -fs rdn -rl 50 -dr > "$3"' _ "targets/$DOMAIN/active_webs/active_webs.txt" "$HEADLESS_FLAG" "targets/$DOMAIN/nuclei_fuzzing_result/katana_urls_raw.txt" "targets/$DOMAIN/runtime/katana_tmp"
  cat "targets/$DOMAIN"/nuclei_fuzzing_result/katana_urls_raw.txt | \
    anew "targets/$DOMAIN"/nuclei_fuzzing_result/katana_urls.txt

  KATANA_COUNT=$(wc -l < "targets/$DOMAIN"/nuclei_fuzzing_result/katana_urls.txt 2>/dev/null || echo 0)
  echo "katana_urls: $KATANA_COUNT 条"

  # ── Step 2: URL 去重 ──
  if [ "$KATANA_COUNT" -eq 0 ]; then
    echo "⏭️ uro + Nuclei DAST: katana 无输出，跳过"
  else
    # uro 可用性检测
    if ! command -v uro >/dev/null 2>&1; then
      echo "⚠️ uro 未安装，跳过 URL 去重，直接用 katana 输出做 DAST"
      # 例外: katana_urls 已经过 anew 去重，此处直接复制不脏数据
      cat "targets/$DOMAIN"/nuclei_fuzzing_result/katana_urls.txt | \
        anew "targets/$DOMAIN"/nuclei_fuzzing_result/uro_urls.txt
    else
      cat "targets/$DOMAIN"/nuclei_fuzzing_result/katana_urls.txt | \
        uro -b js,eot,jpg,jpeg,gif,css,tif,tiff,png,ttf,otf,woff,woff2,ico,svg,zip,rar,tar.gz,tgz,tar.bz2,tar,jar,war,7z,bak,sql,gz,sql.gz,tar.tgz | \
        anew "targets/$DOMAIN"/nuclei_fuzzing_result/uro_urls.txt
    fi

    URO_COUNT=$(wc -l < "targets/$DOMAIN"/nuclei_fuzzing_result/uro_urls.txt 2>/dev/null || echo 0)
    echo "uro_urls: $URO_COUNT 条"

    # ── Step 3: Nuclei DAST Fuzzing ──
    if [ "$URO_COUNT" -eq 0 ]; then
      echo "⏭️ Nuclei DAST: uro_urls 为空，跳过"
    else
      : > "targets/$DOMAIN"/nuclei_fuzzing_result/nuclei-DAST_raw.txt
      run_with_watchdog "nuclei_dast" 7200 1200 \
        "targets/$DOMAIN/nuclei_fuzzing_result/nuclei-DAST_raw.txt" \
        "targets/$DOMAIN/nuclei_fuzzing_result/nuclei-DAST_err.log" -- \
        nuclei -l "targets/$DOMAIN"/nuclei_fuzzing_result/uro_urls.txt \
          -t ~/nuclei-templates/dast/ -dast -rl 20 -nc \
          -o "targets/$DOMAIN"/nuclei_fuzzing_result/nuclei-DAST_raw.txt
      cat "targets/$DOMAIN"/nuclei_fuzzing_result/nuclei-DAST_raw.txt | \
        anew "targets/$DOMAIN"/nuclei_fuzzing_result/nuclei-DAST_fuzzing.txt
      echo "DAST 发现: $(wc -l < targets/$DOMAIN/nuclei_fuzzing_result/nuclei-DAST_fuzzing.txt 2>/dev/null || echo 0) 条"
    fi
  fi
fi
```

**MUST 输出 checkpoint**:
- [ ] 6 个扫描模块全部完成
- [ ] 列出每个模块的发现数量
- [ ] 弱口令成功的高亮提醒
- [ ] 备份文件发现的高亮提醒

**产物清单**:
```
targets/$DOMAIN/active_ports/active_webs_portsfinger.txt
targets/$DOMAIN/active_ports/active_ips_portsfinger.txt
targets/$DOMAIN/active_ports/kscan_webs_err.log
targets/$DOMAIN/active_ports/kscan_ips_err.log
targets/$DOMAIN/backup_result/backup_scan.txt
targets/$DOMAIN/backup_result/backup_scan_err.log
targets/$DOMAIN/nuclei_fuzzing_result/nuclei-templates_fuzzing.txt
targets/$DOMAIN/nuclei_fuzzing_result/nuclei-templates_raw.txt
targets/$DOMAIN/nuclei_fuzzing_result/nuclei-templates_err.log
targets/$DOMAIN/nuclei_fuzzing_result/katana_urls.txt
targets/$DOMAIN/nuclei_fuzzing_result/katana_urls_raw.txt
targets/$DOMAIN/nuclei_fuzzing_result/katana_err.log
targets/$DOMAIN/nuclei_fuzzing_result/uro_urls.txt
targets/$DOMAIN/nuclei_fuzzing_result/nuclei-DAST_fuzzing.txt
targets/$DOMAIN/nuclei_fuzzing_result/nuclei-DAST_raw.txt
targets/$DOMAIN/nuclei_fuzzing_result/nuclei-DAST_err.log
targets/$DOMAIN/dirsearch_result/smart_scan_*.txt
targets/$DOMAIN/afrog_scan_results/*.json
targets/$DOMAIN/afrog_scan_results/*.html
targets/$DOMAIN/afrog_scan_results/*_err.log
```
> ⚠️ afrog 的 `afrog-resume-*.afg` 在扫描完成后自动清理，不作为持久产物。

---

## Phase 7 · Report（结果聚合与统计）

**目的**:汇总所有产物，输出结构化统计报告

### 7.1 全面统计

```bash
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         7scanAI Report — $DOMAIN                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo "扫描时间: $(date)"
echo ""
echo "──────────── 子域名发现 ────────────"
for f in "targets/$DOMAIN"/*_subdomains/*.txt "targets/$DOMAIN"/collect_subdomains/*.txt; do
  [ -f "$f" ] && printf "  %-45s %s 条\n" "$(basename "$(dirname "$f")")/$(basename "$f")" "$(wc -l < "$f")"
done
echo ""
echo "──────────── DNS 解析 ────────────"
for f in "targets/$DOMAIN"/active_subdomains/*.txt; do
  [ -f "$f" ] && printf "  %-45s %s 条\n" "$f" "$(wc -l < "$f")"
done
echo ""
echo "──────────── IP & 端口 ────────────"
for f in "targets/$DOMAIN"/active_ips/*.txt "targets/$DOMAIN"/active_all/*.txt "targets/$DOMAIN"/active_ports/active_ports.txt; do
  [ -f "$f" ] && printf "  %-45s %s 条\n" "$f" "$(wc -l < "$f")"
done
echo ""
echo "──────────── Web 资产 ────────────"
printf "  %-45s %s 条\n" "active_webs.txt" "$(wc -l < "targets/$DOMAIN"/active_webs/active_webs.txt 2>/dev/null || echo 0)"
printf "  %-45s %s 张\n" "screenshots" "$(ls "targets/$DOMAIN"/web_screenshots/screenshots/ 2>/dev/null | wc -l)"
echo ""
echo "──────────── 漏洞发现 ────────────"
printf "  %-45s %s 条\n" "nuclei" "$(wc -l < "targets/$DOMAIN"/nuclei_fuzzing_result/nuclei-templates_fuzzing.txt 2>/dev/null || echo 0)"
printf "  %-45s %s 条\n" "nuclei_DAST" "$(wc -l < "targets/$DOMAIN"/nuclei_fuzzing_result/nuclei-DAST_fuzzing.txt 2>/dev/null || echo 0)"
printf "  %-45s %s 条\n" "afrog" "$(find "targets/$DOMAIN"/afrog_scan_results/ -name "*.json" -exec cat {} + 2>/dev/null | jq -s 'map(length) | add' 2>/dev/null || echo 0)"
printf "  %-45s %s 条\n" "backup_scan" "$(wc -l < "targets/$DOMAIN"/backup_result/backup_scan.txt 2>/dev/null || echo 0)"
printf "  %-45s %s 条\n" "kscan_web_finger" "$(wc -l < "targets/$DOMAIN"/active_ports/active_webs_portsfinger.txt 2>/dev/null || echo 0)"
printf "  %-45s %s 条\n" "kscan_ip_brute" "$(wc -l < "targets/$DOMAIN"/active_ports/active_ips_portsfinger.txt 2>/dev/null || echo 0)"
# 弱口令成功提取
grep 'Success' "targets/$DOMAIN"/active_ports/active_ips_portsfinger.txt 2>/dev/null | sort | uniq | anew "targets/$DOMAIN"/brute_result/brute_success.txt
printf "  %-45s %s 条\n" "brute_success" "$(wc -l < "targets/$DOMAIN"/brute_result/brute_success.txt 2>/dev/null || echo 0)"
# dirsearch 结果统计
DIRSEARCH_COUNT=$(find "targets/$DOMAIN"/dirsearch_result -maxdepth 1 -type f -name 'smart_scan_*.txt' -exec cat {} + 2>/dev/null | wc -l)
printf "  %-45s %s 条\n" "dirsearch" "$DIRSEARCH_COUNT"
echo ""
echo "──────────── 完整文件索引 ────────────"
find "targets/$DOMAIN" -type f \( -name "*.txt" -o -name "*.json" -o -name "*.html" -o -name "*.csv" \) | sort | while read -r f; do
  printf "  %-60s %s 行\n" "$f" "$(wc -l < "$f" 2>/dev/null || echo '-')"
done
```

**Phase 7 产物**:
```
targets/$DOMAIN/brute_result/brute_success.txt    (从 kscan 结果提取)
targets/$DOMAIN/${DOMAIN}_7scanAI_report.html     (Phase 7.3 生成)
```

### 7.2 🔍 AI 自动研判（MUST — 不可跳过）

> **此步骤是 AI 的核心价值。统计数字没有意义，AI 必须读入实际结果文件，逐条分析，给出可操作的渗透方向。**

**强制流程**:

#### Step 1 — 读入原始结果

AI 必须 Read 以下文件（至少读完，内容多时分批读）：

| 优先级 | 文件 | 读多少 |
|--------|------|--------|
| 🔴 最高 | `brute_result/brute_success.txt` | 全读 |
| 🔴 最高 | `backup_result/backup_scan.txt` | 全读 |
| 🔴 最高 | `afrog_scan_results/*.json` | 逐个全读 |
| 🟡 高 | `nuclei_fuzzing_result/nuclei-templates_fuzzing.txt` | 全读 |
| 🟡 高 | `nuclei_fuzzing_result/nuclei-DAST_fuzzing.txt` | 全读 |
| 🟡 高 | `dirsearch_result/smart_scan_*.txt` | 逐个全读 |
| 🟢 中 | `active_ports/active_webs_portsfinger.txt` | 全读 |
| 🟢 中 | `active_ports/active_ips_portsfinger.txt` | 全读 |
| ⚪ 参考 | `active_webs/active_websfinger.json` | 按需 |
| ⚪ 参考 | `active_webs/high_value_targets.txt` | 全读 |
| ⚪ 参考 | `active_webs/leak_risks.txt` | 全读 |

#### Step 2 — 逐条研判

对每条发现做三件事：

**2a. 去重合并**:同一个漏洞被 nuclei 和 afrog 同时检出的，合并为一条，标注"双引擎确认"

**2b. 真实性判定**:
```
✅ 确认有效 — POC 已验证 / 双引擎命中 / 有 HTTP 响应佐证
⚠️ 待验证   — 单引擎检出 / 需要手动确认 / 可能是 WAF 误报
❌ 疑似误报 — 与目标技术栈不匹配 / 已知的泛匹配 / 无实际影响
```

**2c. 危害分级**（CVSS 对齐）:
```
🔴 Critical (9.0+) — RCE / SQLi / 任意文件读取 / 未授权访问核心系统
🟠 High     (7.0+) — 弱口令 / 备份泄露 / SSRF / SSTI / 越权
🟡 Medium   (4.0+) — 信息泄露 / 目录遍历 / 配置缺陷 / 未授权访问非核心
🟢 Low      (<4.0)  — 版本号暴露 / 默认页面 / 低危配置
```

**2d. dirsearch 专项研判**:

dirsearch 输出格式: `状态码  路径  大小  跳转URL`，AI 需逐条判断：

**结果保留策略**:
```
默认保留并重点研判: 200,401,403,301,302,307,308,405
默认排除: 400,404,410,429,500,502,503,504
```

**重点关注（Medium+）**:
```
✅ 200 + 含敏感关键词 → 标记为信息泄露
   .git/config / .env / .svn/entries / phpinfo.php / dump.sql / backup.zip
   → 类似备份文件扫描，可能直接获取源码/凭据

✅ 200 + 后台/管理路径 → 标记为未授权访问风险
   /admin/ /manager/ /console/ /api/ /swagger-ui.html /actuator
   → 如果无认证即可访问，这是直接的攻击入口

✅ 401/403 + 管理路径 → 标记为待爆破目标
   /admin/login /manager/login /api/admin
   → 值得尝试弱口令爆破
```

**降级处理（Low/Info）**:
```
❌ 301/302 跳转到首页 → 目录不存在，跳转回首页
❌ 404 页面但返回 200 → dirsearch 智能过滤已排除，但仍有漏网
❌ /images/ /css/ /js/ 等静态目录 → 已在排除列表中
```

**dirsearch 与 backup_scan 交叉验证**:
```
dirsearch 命中 .git/config + backup_scan 命中 .git/HEAD
→ 交叉确认，判为"双源确认 → ✅ 确认有效"
```

#### Step 3 — 渗透方向建议

AI 必须结合**资产特征**和**漏洞类型**，给出具体攻击链，不准泛泛而谈：

**不准这样写**:
> "可以尝试 SQL 注入、XSS 等漏洞利用"

**必须这样写**（每条建议含：入口点 → 攻击手法 → 预期结果）:
```
🟠 弱口令 → 直接登录
  入口: 10.0.0.1:22 (SSH), root:admin123
  攻击: ssh root@10.0.0.1
  预期: 获取服务器 shell，进而横向移动

🔴 备份文件 → 源码审计
  入口: https://target.com/wwwroot.zip
  攻击: 下载 → 解压 → grep 搜索 password/secret/key/conn
  预期: 获取数据库凭据、API key、加密密钥

🟡 信息泄露 → 组合利用
  入口: https://target.com/.git/config
  攻击: git-dumper 下载源码 → 审计业务逻辑 → 找越权/注入点
  预期: 发现未授权访问路径

🟡 dirsearch 敏感路径 → 未授权访问
  入口: https://target.com/swagger-ui.html (200 OK)
  攻击: 访问 Swagger → 列出所有 API → 逐一测试未授权调用
  预期: 发现可未授权调用的敏感 API（用户管理/数据导出/配置修改）

🟡 dirsearch 后台入口 → 弱口令爆破
  入口: https://target.com/admin/login (401)
  攻击: 整理常见后台弱口令字典 → ffuf/hydra 爆破
  预期: 突破后台认证，进入管理界面
```

**攻击链组合**:发现多个漏洞时，给出最优攻击路径，例如：
```
最优攻击链:
  ① 备份文件获取数据库凭据
  ② 数据库凭据尝试登录后台 (凭证复用)
  ③ 后台文件上传 getshell
```

#### Step 4 — 输出研判报告

```
┌─────────────────────────────────────────────────────────────┐
│                   🔍 AI 研判报告 — $DOMAIN                    │
├─────────────────────────────────────────────────────────────┤
│ 扫描时间: 2026-06-03 14:30                                   │
│ 原始发现: N 条 → 去重后: N 条 → 确认有效: N 条               │
├─────────────────────────────────────────────────────────────┤

🔴 Critical (N 条)
────────────────────────────────────────────────
1. [漏洞类型] 端点/URL
   来源: nuclei ✓ | afrog ✓ (双引擎确认)
   判定: ✅ 确认有效
   渗透:
     → 入口: https://target.com/api/v1/users?id=1
     → 手法: IDOR — 遍历 id 参数 1-1000
     → 预期: 获取所有用户数据
     → 工具: curl + bash 循环 / Burp Intruder

🟠 High (N 条)
────────────────────────────────────────────────
2. [弱口令] 服务:端口
   来源: kscan hydra
   判定: ✅ 确认有效
   渗透:
     → 入口: 10.0.0.2:3306 (MySQL), root:root
     → 手法: mysql -h 10.0.0.2 -u root -proot
     → 预期: 数据库直接读写，可能拿到所有业务数据

🟡 Medium (N 条)
────────────────────────────────────────────────
3. [dirsearch 敏感路径] /swagger-ui.html (200)
   来源: dirsearch
   判定: ✅ 确认有效 — Swagger 可未授权访问
   渗透:
     → 入口: https://target.com/swagger-ui.html
     → 手法: 访问 → 解析 API 文档 → 测试未授权接口调用
     → 预期: 发现可越权调用的数据接口

4. [dirsearch 后台入口] /admin/login (401)
   来源: dirsearch
   判定: ⚠️ 待验证 — 需爆破或寻找认证绕过
   渗透:
     → 入口: https://target.com/admin/login
     → 手法: 指纹识别后台框架 → 寻找已知漏洞或默认口令
     → 预期: 突破认证进入后台

...

🟢 Low / ❌ 误报 (N 条)
────────────────────────────────────────────────
[dirsearch 降级项]
- /images/xxx (301→首页) → ❌ 目录不存在
- /css/style.css (404但200码) → ❌ 伪200页面
...

┌─────────────────────────────────────────────────────────────┐
│                     🎯 推荐攻击优先级                         │
├─────────────────────────────────────────────────────────────┤
│ 1. [最易利用+最高影响] ...                                   │
│ 2. [需要条件但影响大] ...                                    │
│ 3. [低优先级但可组合] ...                                    │
├─────────────────────────────────────────────────────────────┤
│ ⚠️ 下一步建议:                                              │
│ - 对发现的 N 个登录口进行弱口令爆破 (补充字典)               │
│ - 对 .git 泄露进行源码审计                                   │
│ - 对 API 端点进行越权测试                                    │
└─────────────────────────────────────────────────────────────┘
```

### 7.3 📄 生成离线 HTML 报告

> 替代 search_server.py，生成一个自包含的 HTML 文件，浏览器直接打开即可，无需 Flask。

```bash
# 单域名
python3 "$SCRIPT_DIR"/references/scripts/generate_report.py -d "targets/$DOMAIN"
# → 生成 targets/$DOMAIN/${DOMAIN}_7scanAI_report.html

# 多域名汇总
python3 "$SCRIPT_DIR"/references/scripts/generate_report.py -r targets/
# → 生成 targets/7scanAI_report.html
```

HTML 报告包含：
- 📊 统计卡片（子域名/IP/端口/Web/漏洞数）
- 🌐 Web 资产表（支持搜索/排序/过滤，点击 URL 跳转）
- 💣 漏洞发现表（按严重度色标分组）
- 📸 页面截图预览（如果启用了截图）
- 全部离线可用，无 CDN 依赖

---

## 多域名汇总（按需触发）

**默认不做多域名汇总**。仅当用户明确说"汇总 / 合并 / 聚合 / 对比 / 生成汇总报告"时，才执行汇总：

1. 读取各域名目录下的统计结果
2. 输出对比表（每个域名的关键指标）
3. 可选: `python3 "$SCRIPT_DIR"/references/scripts/generate_report.py -r targets/` 生成汇总 HTML

---

## AI 决策点总结

| 决策点 | 条件 | 行动 |
|--------|------|------|
| 端口范围 | Phase 1 用户选择 | top-100 / top-1000 / 全端口 |
| 域名变形生成 | Phase 1 用户选择 | 是: 运行 dnsgen + alterx / 否: 跳过 |
| Web 截图 | Phase 1 用户选择 | 是: gowitness 截图 / 否: 跳过 |
| 泛解析检测 | 3 次随机子域名 ≥2 次解析成功 | 跳过 dnsgen + alterx（即使用户启用） |
| 命令失败 | 非零退出 / 无结果 | 自动重试 3 次（Phase 2/3 间隔 2s/4s/8s，Phase 4/6 间隔 30s/60s/120s），3 次全失败记录并继续 |
| 断点续跑 | 某阶段中断后重跑 | anew 保证去重，阈值判断不受影响 |
| 子域名增量截断 | 本次新增 > 20000 条 | 清空该工具结果（去噪） |
| 排列增量截断 | dnsgen/alterx 本次新增 > 1000 条 | 清空该工具结果（去噪） |
| CDN 过滤 | IP 含 CDN/云标签 | 自动剔除 |
| 内网分离 | IP 含局域网标签 | 分离到 intranet 文件 |
