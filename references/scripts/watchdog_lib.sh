#!/usr/bin/env bash
# 7scanAI watchdog library — 脱离式(detached)后台执行 + 双超时保护
#
# 背景: AI Agent harness(Claude Code / Codex)的 bash 工具每次调用都是**独立 shell**，
# 且单次调用有硬性超时上限(通常 10 分钟)。原 full-workflow.md 里的 run_with_watchdog
# 是"阻塞式"实现 —— 在当前 shell 里 sleep 轮询直到命令结束。这在交互式终端可行，
# 但在 Agent harness 下会导致:
#   1. 超过 10 分钟的扫描(nuclei/afrog/katana)被 harness 强杀，扫描成果丢失
#   2. shell 状态不跨调用保留，函数定义下一次调用就没了
#   3. 无法在等待期间做任何其他事情
#
# 本库把 watchdog 改成**脱离式**: 启动后立即返回，扫描在独立 session 中继续运行，
# 进度/退出码写入 runtime/ 下的状态文件，后续调用只需 poll 即可。
#
# 用法:
#   source watchdog_lib.sh
#   wd_start <name> <total_timeout_s> <idle_timeout_s> <progress_file> <err_file> -- <cmd...>
#   wd_poll  <name>            # 打印 running/done + exitcode
#   wd_wait  <name> [max_s]    # 阻塞等待(受限时长), 返回 exitcode; 124=仍在运行
#   wd_kill  <name>            # TERM -> 15s -> KILL
#
# 状态文件 (均在 $WD_RUNTIME 下):
#   <name>.pid     扫描进程 PID(timeout 包装进程)
#   <name>.exitcode  完成后的退出码
#   <name>.status    running | done | idle-timeout | killed

# ── 环境变量 ──
: "${WD_RUNTIME:=runtime}"
: "${WD_POLL_INTERVAL:=10}"
# CPU 进度信号的最低速率门槛(百分比)。低于此值视为"未推进"，防止僵尸进程
# 靠极缓慢的 CPU 增长无限复位 idle 计时器。
: "${WD_MIN_CPU_PCT:=20}"

wd_start() {
  local name="$1" total="$2" idle="$3" prog="$4" err="$5"
  shift 5
  [ "$1" = "--" ] && shift

  if [ -z "$name" ] || [ -z "$total" ]; then
    echo "wd_start: 用法 wd_start <name> <total> <idle> <progress> <err> -- <cmd...>" >&2
    return 2
  fi

  mkdir -p "$WD_RUNTIME"
  [ -f "$err" ] || : > "$err"
  [ -z "$prog" ] || [ -f "$prog" ] || : > "$prog"

  # 清理上一次运行的状态
  rm -f "$WD_RUNTIME/${name}.exitcode"
  echo "running" > "$WD_RUNTIME/${name}.status"

  # setsid 脱离当前 session，nohup 忽略 SIGHUP → harness 杀掉 bash 调用后扫描仍存活
  nohup setsid bash -c '
    name="$1"; total="$2"; idle="$3"; prog="$4"; err="$5"; runtime="$6"; interval="$7"; min_pct="$8"
    shift 8

    # ── 进度信号 1: 输出字节数 ──
    bytes_signal() {
      echo $(( $(wc -c < "$prog" 2>/dev/null || echo 0) + $(wc -c < "$err" 2>/dev/null || echo 0) ))
    }

    # ── 进度信号 2: 进程组累计 CPU ticks ──
    # 必要性: subDomainsBrute / afrog / ihoneyBakFileScan 等工具会把结果缓冲到结束时
    # 才落盘，扫描期间输出字节数恒为 0。只看字节数会把"正在正常干活"误判成"卡死"并杀掉。
    # CPU 时间持续增长 ⇒ 进程确实在推进，即使一个字节都没写。
    # /proc/<pid>/stat 的 comm 字段可能含空格和括号，先用 sed 剥离再做字段定位。
    cpu_signal() {
      local pgid
      pgid=$(awk "{print \$5}" "/proc/$1/stat" 2>/dev/null)
      [ -z "$pgid" ] && { echo 0; return; }
      sed "s/^[0-9]* (.*) //" /proc/[0-9]*/stat 2>/dev/null | \
        awk -v t="$pgid" "{ if (\$3 == t) s += \$12 + \$13 } END { print s+0 }"
    }

    # timeout 会把子进程放进独立进程组，超时时整组收到信号
    timeout --kill-after=30 "$total" "$@" 2>>"$err" &
    cpid=$!
    echo "$cpid" > "$runtime/${name}.pid"

    last_ts=$(date +%s)
    last_bytes=0
    last_cpu=0
    start_ts=$(date +%s)
    while kill -0 "$cpid" 2>/dev/null; do
      # 前 30s 用 2s 短间隔轮询: 让 whois / subfinder 这类秒级任务尽快被判定完成。
      # 否则完成检测延迟高达一个 interval(默认 10s)，wd_run 的每个快步骤都白等 10s。
      # 30s 后回到 interval，避免长任务频繁读 /proc 造成额外开销。
      if [ $(( $(date +%s) - start_ts )) -lt 30 ]; then
        sleep 2
      else
        sleep "$interval"
      fi
      cur=$(bytes_signal)
      cur_cpu=$(cpu_signal "$cpid")
      now=$(date +%s)

      # CPU 增长必须达到最低速率才算"有进度"。
      # 反例: 被目标 RST 拖住的工具(jsubfinder)CPU 以 0.04% 缓慢增长，
      # 若只判断 "cur_cpu > last_cpu"，计时器会被无限复位，idle 超时永不触发。
      # min_cpu = interval 秒内至少消耗的 tick 数 (1 tick = 10ms)。
      # 默认 20% ⇒ interval=10s 时需 20 ticks(200ms)，可滤掉僵尸态；
      # 真正的 CPU 密集任务(subDomainsBrute 约 700+ ticks/10s)远高于此。
      min_cpu=$(( interval * min_pct / 100 ))
      [ "$min_cpu" -lt 1 ] && min_cpu=1
      cpu_delta=$(( cur_cpu - last_cpu ))

      if [ "$cur" -gt "$last_bytes" ] || [ "$cpu_delta" -ge "$min_cpu" ]; then
        last_bytes="$cur"
        last_cpu="$cur_cpu"
        last_ts="$now"
      elif [ $((now - last_ts)) -ge "$idle" ]; then
        echo "" >> "$err"
        echo "[watchdog] ${name}: ${idle}s 无进度增长 (bytes=${cur} cpu_ticks=${cur_cpu})，终止 PID $cpid" >> "$err"
        kill "$cpid" 2>/dev/null || true
        sleep 15
        if kill -0 "$cpid" 2>/dev/null; then
          kill -9 "$cpid" 2>/dev/null || true
        fi
        echo "idle-timeout" > "$runtime/${name}.status"
        break
      fi
    done

    wait "$cpid"
    rc=$?
    echo "$rc" > "$runtime/${name}.exitcode"
    if [ "$(cat "$runtime/${name}.status" 2>/dev/null)" = "running" ]; then
      echo "done" > "$runtime/${name}.status"
    fi
  ' _ "$name" "$total" "$idle" "$prog" "$err" "$WD_RUNTIME" "$WD_POLL_INTERVAL" "$WD_MIN_CPU_PCT" "$@" \
    >/dev/null 2>&1 &

  disown 2>/dev/null || true
  echo "🚀 ${name} 已启动 (total=${total}s idle=${idle}s) → $WD_RUNTIME/${name}.pid"
}

# 阻塞式执行 —— 语义等价于旧版 run_with_watchdog，供文档中"跑完才能用产物"的步骤使用。
# 内部 = wd_start + 循环 wd_wait。
#
# ⚠️ 为什么需要它: 文档里大量步骤形如
#     run_with_watchdog "whois" ... -- wget ...
#     cat <产物> | ...        ← 依赖上一步已产出文件
# 若直接把这些改成非阻塞的 wd_start，后续步骤会在**文件还没生成**时继续执行，
# 静默产生空结果。这个 wrapper 保证"调用返回时任务确实已结束"。
#
# 返回: 扫描退出码；124 = 超过 max_s 仍在后台运行（此时必须改用 wd_poll 续等）
wd_run() {
  local name="$1" max_s="${WD_RUN_MAX_S:-540}"
  shift
  wd_start "$name" "$@" || return $?

  local rc
  wd_wait "$name" "$max_s" >/dev/null 2>&1
  rc=$?

  if [ "$rc" -eq 124 ] && wd_poll "$name" >/dev/null 2>&1; then
    echo "⚠️ ${name} 超过 ${max_s}s 仍未结束，已转入后台继续运行。" >&2
    echo "   后续步骤若依赖其产物，必须先 wd_poll $name 直到 done。" >&2
    return 124
  fi

  wd_poll "$name"        # 打印最终状态行
  return "$rc"
}

# 查询状态并打印。
# 返回: 0 = 任务**仍在运行**; 1 = 任务**已结束**（退出码请用 wd_exitcode 取）
#
# ⚠️ 为什么不用"返回退出码"这种设计: 退出码 0 与"仍在运行"无法区分，
# 调用方写 `if ! wd_poll` 时会把**成功完成**的任务误判成"还在跑"，
# 一路等到超时（实测踩过：wd_run 对 exit 0 的任务空等 540s）。
# 状态判定与退出码获取必须是两个独立的接口。
wd_poll() {
  local name="$1"
  local status
  status="$(cat "$WD_RUNTIME/${name}.status" 2>/dev/null || echo unknown)"
  if [ "$status" = "running" ]; then
    local pid
    pid="$(cat "$WD_RUNTIME/${name}.pid" 2>/dev/null || echo '?')"
    echo "⏳ ${name}: running (pid=$pid)"
    return 0
  fi
  local rc
  rc="$(cat "$WD_RUNTIME/${name}.exitcode" 2>/dev/null || echo 255)"
  echo "🏁 ${name}: $status (exitcode=$rc)"
  return 1
}

# 取已完成任务的退出码；未完成或不存在则返回 255
wd_exitcode() {
  local name="$1"
  cat "$WD_RUNTIME/${name}.exitcode" 2>/dev/null || echo 255
}

# 阻塞等待, 最多 max_s 秒(默认 540, 留出 harness 10min 上限余量)
# 返回: 任务退出码；124 = 等待超时(仍在后台运行)
#
# ⚠️ 返回 124 有歧义: 任务自身超时(timeout 命令)也是 124。
#    需要区分时请用 `wd_poll` 的布尔结果判断是否仍在运行。
wd_wait() {
  local name="$1" max_s="${2:-540}"
  local waited=0
  while [ "$waited" -lt "$max_s" ]; do
    if ! wd_poll "$name" >/dev/null 2>&1; then
      wd_poll "$name"                      # 打印最终状态行
      local rc
      rc="$(wd_exitcode "$name")"
      return "$(( rc > 255 ? 255 : rc ))"
    fi
    sleep 5
    waited=$((waited + 5))
  done
  echo "⏳ ${name}: 等待 ${max_s}s 后仍在运行 (继续在后台跑)"
  return 124
}

wd_kill() {
  local name="$1"
  local pid
  pid="$(cat "$WD_RUNTIME/${name}.pid" 2>/dev/null || true)"
  [ -z "$pid" ] && { echo "wd_kill: 无 PID 记录"; return 1; }
  echo "🛑 终止 ${name} (pid=$pid)"
  kill "$pid" 2>/dev/null || true
  sleep 15
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true
  fi
  echo "killed" > "$WD_RUNTIME/${name}.status"
}

# 清理 err log 的 ANSI/回车噪音；成功且无异常关键字时清空
wd_finalize_err_log() {
  local err_file="$1" exit_code="$2" clean_file
  [ -f "$err_file" ] || return 0
  clean_file="${err_file}.clean"
  perl -pe 's/\r/\n/g; s/\x1b\[[0-9;?]*[ -\/]*[@-~]//g' "$err_file" | \
    sed '/^[[:space:]]*$/d' > "$clean_file" 2>/dev/null || { rm -f "$clean_file"; return 0; }
  mv "$clean_file" "$err_file"
  if [ "$exit_code" -eq 0 ] && \
     ! grep -qiE 'error|warn|failed|timeout|exception|panic|traceback|forbidden|denied|429|500|502|503' "$err_file"; then
    truncate -s 0 "$err_file"
  fi
}

safe_line_count() {
  local f="$1"
  [ -f "$f" ] && wc -l < "$f" || echo 0
}
