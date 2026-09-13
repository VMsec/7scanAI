#!/usr/bin/env bash
# 7scanAI 依赖检测与安装
# 用法: bash auto_install.sh          # 检测并安装全部缺失工具
#       bash auto_install.sh check    # 仅检测，不安装
set -e

# ⚠️ INSTALL_ONLY 必须最先赋值，后续所有判断依赖此变量
INSTALL_ONLY="${1:-install}"

# 自动探测项目根目录（无论从哪个路径执行此脚本）
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
echo "📍 7scanAI 项目路径: $SCRIPT_DIR"

# 预清理：删除会干扰 Go 版 httpx 判断的 Python 包装器（仅在 install 模式执行）
if [ "$INSTALL_ONLY" != "check" ]; then
  if [ -f /usr/local/bin/httpx ] && grep -q "from httpx import main" /usr/local/bin/httpx 2>/dev/null; then
      echo "🧹 检测到 Python 版 /usr/local/bin/httpx，已删除，优先使用 Go 版 httpx"
      rm -f /usr/local/bin/httpx
  fi
fi

promote_go_httpx() {
    local go_bin httpx_bin
    go_bin="$(go env GOBIN 2>/dev/null)"
    if [ -z "$go_bin" ]; then
        go_bin="$(go env GOPATH 2>/dev/null)/bin"
    fi
    httpx_bin="$go_bin/httpx"

    if [ -x "$httpx_bin" ]; then
        mkdir -p /usr/local/bin
        cp -f "$httpx_bin" /usr/local/bin/httpx
        chmod +x /usr/local/bin/httpx
        echo "🔗 已将 Go 版 httpx 覆盖到 /usr/local/bin/httpx"
    fi
}

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
MISSING=()
# 可选依赖：缺失只警告，**不影响 check 退出码**。
# 为什么必须分开：check 非 0 会让 full-workflow Phase 1 直接 exit 1 终止整个扫描。
# 若把可选依赖（如 chrome）计入必需缺失，一个用不到的可选工具就能卡死全流程。
OPTIONAL_MISSING=()

check_system_pkg() {
    local name=$1 pkg=${2:-$1}
    if dpkg -s "$pkg" &>/dev/null || rpm -q "$pkg" &>/dev/null; then
        echo -e "  ${GREEN}✅${NC} $name"
    else
        echo -e "  ${RED}❌${NC} $name"
        MISSING+=("apt:$pkg")
    fi
}

check_command() {
    local name=$1
    if command -v "$name" &>/dev/null; then
        echo -e "  ${GREEN}✅${NC} $name"
    else
        echo -e "  ${RED}❌${NC} $name"
        MISSING+=("apt:$name")
    fi
}

check_go_tool() {
    local name=$1 pkg=${2:-$1}
    if command -v "$name" &>/dev/null; then
        echo -e "  ${GREEN}✅${NC} $name"
    else
        echo -e "  ${RED}❌${NC} $name"
        MISSING+=("go:$pkg")
    fi
}

# 可选 Go 工具：缺失只警告，不计入必需缺失
check_go_tool_optional() {
    local name=$1 pkg=${2:-$1} reason=${3:-可选}
    if command -v "$name" &>/dev/null; then
        echo -e "  ${GREEN}✅${NC} $name"
    else
        echo -e "  ${YELLOW}⚠️${NC} $name ($reason)"
        OPTIONAL_MISSING+=("go:$pkg")
    fi
}

check_python_tool() {
    local name=$1 dir=$2 repo=$3 entrypoint=${4:-$dir/${name}.py} validator=${5:-}
    if [ -n "$validator" ]; then
        if [ -d "$dir" ] && eval "$validator" >/dev/null 2>&1; then
            echo -e "  ${GREEN}✅${NC} $name (依赖完整)"
        elif [ -d "$dir" ]; then
            echo -e "  ${RED}❌${NC} $name (目录存在但依赖缺失，需 pip install)"
            MISSING+=("python_tool:$repo:$dir")
        else
            echo -e "  ${RED}❌${NC} $name"
            MISSING+=("python_tool:$repo:$dir")
        fi
        return
    fi

    if [ -d "$dir" ] && python3 "$entrypoint" -h >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅${NC} $name (依赖完整)"
    elif [ -d "$dir" ]; then
        echo -e "  ${RED}❌${NC} $name (目录存在但依赖缺失，需 pip install)"
        MISSING+=("python_tool:$repo:$dir")
    else
        echo -e "  ${RED}❌${NC} $name"
        MISSING+=("python_tool:$repo:$dir")
    fi
}

check_pip() {
    # 必须分两行赋值：同一 local 命令内引用刚赋的变量，bash 5.2 下会取到空值，
    # 导致 pkg 为空 → `import ` 语法错误 → 永远误报缺失
    local name="$1"
    local pkg="${2:-$name}"
    if python3 -c "import $pkg" 2>/dev/null; then
        echo -e "  ${GREEN}✅${NC} $name (pip)"
    else
        echo -e "  ${RED}❌${NC} $name (pip)"
        MISSING+=("pip:$pkg")
    fi
}

check_dir() {
    local name=$1 path=$2
    if [ -d "$path" ]; then
        echo -e "  ${GREEN}✅${NC} $name ($path)"
    else
        echo -e "  ${RED}❌${NC} $name"
        MISSING+=("dir:$name:$path")
    fi
}

echo ""
echo "=========================================="
echo "  7scanAI 依赖检测"
echo "=========================================="
echo ""

echo "── 系统工具 ──"
check_system_pkg curl
check_system_pkg wget
check_system_pkg git
check_system_pkg jq
check_system_pkg dig "dnsutils"
check_system_pkg python3
check_system_pkg pip3 "python3-pip"
check_system_pkg gcc
check_system_pkg libpcap "libpcap-dev"
check_command lsof
check_command tmux
check_command iotop
check_command telnet
check_command axel
check_command unzip
command -v ag &>/dev/null && echo -e "  ${GREEN}✅${NC} silversearcher-ag" || { echo -e "  ${RED}❌${NC} silversearcher-ag"; MISSING+=("apt:silversearcher-ag"); }
# chrome 仅用于：① gowitness 截图（Phase 1 默认关闭）② katana headless（有非 headless 兜底）
# ⇒ 可选。缺失不影响 Phase 1-8 主流程
command -v google-chrome &>/dev/null && echo -e "  ${GREEN}✅${NC} chrome" || { echo -e "  ${YELLOW}⚠️${NC} chrome (可选: 截图/katana headless，均有兜底)"; OPTIONAL_MISSING+=("chrome"); }

echo ""
echo "── Go 环境 ──"
# Go 环境
if command -v go &>/dev/null; then
    echo -e "  ${GREEN}✅${NC} go ($(go version 2>/dev/null | head -1))"
else
    echo -e "  ${RED}❌${NC} go"
    MISSING+=("goenv")
fi

echo ""
echo "── Go 工具链 ──"
check_go_tool subfinder   "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
check_go_tool dnsx        "github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
check_go_tool naabu       "github.com/projectdiscovery/naabu/v2/cmd/naabu@latest"
check_go_tool httpx       "github.com/projectdiscovery/httpx/cmd/httpx@latest"
check_go_tool nuclei      "github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
check_go_tool katana      "github.com/projectdiscovery/katana/cmd/katana@latest"
check_go_tool gau         "github.com/lc/gau/v2/cmd/gau@latest"
check_go_tool ksubdomain  "github.com/boy-hack/ksubdomain/v2/cmd/ksubdomain@latest"
check_go_tool afrog       "github.com/zan8in/afrog/v3/cmd/afrog@latest"
# gowitness 仅用于 Phase 5.2 截图（Phase 1 默认关闭）⇒ 可选
check_go_tool_optional gowitness "github.com/sensepost/gowitness@latest" "截图用，Phase 1 默认关闭"
check_go_tool anew        "github.com/tomnomnom/anew@latest"
check_go_tool nali        "github.com/zu1k/nali@latest"
check_go_tool nocdn       "github.com/r00tSe7en/nocdn@latest"
check_go_tool alterx      "github.com/projectdiscovery/alterx/cmd/alterx@latest"
check_go_tool jsubfinder  "github.com/ThreatUnkown/jsubfinder@latest"
check_go_tool ffuf        "github.com/ffuf/ffuf@latest"
check_pip uro
command -v kscan &>/dev/null && echo -e "  ${GREEN}✅${NC} kscan" || { echo -e "  ${RED}❌${NC} kscan"; MISSING+=("kscan"); }
command -v csvquote &>/dev/null && echo -e "  ${GREEN}✅${NC} csvquote" || { echo -e "  ${RED}❌${NC} csvquote"; MISSING+=("csvquote"); }

echo ""
echo "── 渗透利用工具 ──"
command -v sqlmap &>/dev/null && echo -e "  ${GREEN}✅${NC} sqlmap" || { echo -e "  ${RED}❌${NC} sqlmap"; MISSING+=("sqlmap"); }
command -v redis-cli &>/dev/null && echo -e "  ${GREEN}✅${NC} redis-cli" || { echo -e "  ${RED}❌${NC} redis-cli"; MISSING+=("apt:redis-tools"); }
command -v mysql &>/dev/null && echo -e "  ${GREEN}✅${NC} mysql-client" || { echo -e "  ${RED}❌${NC} mysql-client"; MISSING+=("apt:default-mysql-client"); }
command -v git-dumper &>/dev/null && echo -e "  ${GREEN}✅${NC} git-dumper" || { echo -e "  ${RED}❌${NC} git-dumper"; MISSING+=("pip:git-dumper"); }
command -v sshpass &>/dev/null && echo -e "  ${GREEN}✅${NC} sshpass" || { echo -e "  ${RED}❌${NC} sshpass"; MISSING+=("apt:sshpass"); }

echo ""
echo "── Python 工具 ──"
check_python_tool OneForAll       /opt/OneForAll       shmilylty/OneForAll          /opt/OneForAll/oneforall.py        "cd /opt/OneForAll && mkdir -p results && python3 oneforall.py --help"
check_python_tool subDomainsBrute /opt/subDomainsBrute  lijiejie/subDomainsBrute    /opt/subDomainsBrute/subDomainsBrute.py
check_python_tool dirsearch       /opt/dirsearch        maurosoria/dirsearch         /opt/dirsearch/dirsearch.py        "python3 -c 'import requests_ntlm, httpx_ntlm'"
check_python_tool ihoneyBakFileScan_Modify /opt/ihoneyBakFileScan_Modify VMsec/ihoneyBakFileScan_Modify /opt/ihoneyBakFileScan_Modify/ihoneyBakFileScan_Modify.py
check_pip dnsgen

echo ""
echo "── 模板库 ──"
# nuclei-templates installed via nuclei -ut, not git clone
# fuzzing-templates handled by dedicated installer below

echo ""
echo "=========================================="
echo "  必需缺失: ${#MISSING[@]} 项 | 可选缺失: ${#OPTIONAL_MISSING[@]} 项"
echo "=========================================="

# 可选缺失单独列出，但不影响退出码
if [ ${#OPTIONAL_MISSING[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠️ 可选依赖缺失（不影响主流程）:${NC}"
    for item in "${OPTIONAL_MISSING[@]}"; do echo "  - $item"; done
fi

if [ ${#MISSING[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ 必需依赖已就绪${NC}"
    if [ "$INSTALL_ONLY" = "check" ]; then
        # 必需齐全即视为通过：可选缺失不应阻塞 Phase 1
        exit 0
    fi
else
    for item in "${MISSING[@]}"; do echo "  - $item"; done

    if [ "$INSTALL_ONLY" = "check" ]; then
        echo ""
        echo "运行 'bash auto_install.sh' 自动安装"
        exit 1
    fi

    echo ""
    echo "开始安装 ${#MISSING[@]} 项..."
fi

# 安装模式下把可选缺失并入安装队列：
# check 模式不动它们（避免可选依赖阻塞 Phase 1），
# 但用户显式跑 install 说明期望装齐，此时把可选的也装上。
if [ "$INSTALL_ONLY" != "check" ] && [ ${#OPTIONAL_MISSING[@]} -gt 0 ]; then
    echo ""
    echo "  ℹ️ 安装模式：可选依赖也一并安装（${#OPTIONAL_MISSING[@]} 项）"
    MISSING+=("${OPTIONAL_MISSING[@]}")
fi

# ── 安装阶段 (仅当有缺失项时执行) ──
if [ ${#MISSING[@]} -gt 0 ]; then
    # 确保 apt update 先执行一次
    # ⚠️ 必须检查更新结果：若系统存在坏源（如未签名的第三方源），
    # apt update 会整体失败 → 后续所有 apt install 只能拿到过期索引 → 404，
    # 而 install 侧的 `|| echo 失败` 只会给出含糊提示，根因被掩盖。
    # 实测踩过：一个未签名的 chrome 源导致 apt update 全挂，mysql-client 反复装上又 404。
    echo "  📦 apt update ..."
    APT_LOG="$(mktemp)"
    apt-get update >"$APT_LOG" 2>&1
    APT_RC=$?
    # 判定要同时看退出码和日志：实测 apt-get update 在有 Err: 行时**仍可能返回 0**，
    # 只有 `E:` 开头才是硬错误（如源未签名）。两者任一出现都要告警。
    #
    # ⚠️ 不要写成 $(grep -c ... || echo 0)：grep -c 无匹配时输出 "0" 且返回 1，
    #    会再 echo 一个 0 → 变量变成两行 "0\n0" → 整数比较直接报错。
    APT_HARD_ERR=0
    grep -qE '^E:' "$APT_LOG" 2>/dev/null && APT_HARD_ERR=1
    if [ "$APT_RC" -ne 0 ] || [ "$APT_HARD_ERR" -ne 0 ]; then
        echo -e "    ${RED}⚠️ apt update 异常 (exit=$APT_RC, 存在硬错误=$APT_HARD_ERR)，后续 apt 安装可能因索引过期而 404${NC}"
        echo "    失败原因（前 5 行）:"
        grep -iE '^(E:|Err:)' "$APT_LOG" | head -5 | sed 's/^/      /'
        echo "    💡 常见原因：某个第三方源未签名或不可达。"
        echo "       可执行 'apt-get update' 查看完整报错，"
        echo "       或临时移出有问题的源文件（/etc/apt/sources.list.d/*.list|*.sources）后重试。"
    else
        echo -e "    ${GREEN}✅ apt update 成功${NC}"
    fi
    rm -f "$APT_LOG"

    # 优先安装 Go 环境，因为后续 Go 工具依赖它
    for item in "${MISSING[@]}"; do
        IFS=':' read -r type arg1 arg2 <<< "$item"
        if [ "$type" = "goenv" ]; then
            echo "  🔧 安装 Go 环境 (严格遵循 autoinstallooo.sh) ..."
            sh -c "$(curl -L https://raw.githubusercontent.com/canha/golang-tools-install-script/master/goinstall.sh | bash)" >/dev/null 2>&1
            # goinstall.sh 只往 shell profile 写 PATH，当前 shell 不会自动生效。
            # 这里主动把 go 加进当前进程的 PATH，否则后续 go install 全部落空。
            if ! command -v go >/dev/null 2>&1; then
                for candidate in /usr/local/go/bin /usr/lib/go/bin "$HOME/go/bin"; do
                    if [ -x "$candidate/go" ]; then
                        export PATH="$candidate:$PATH"
                        break
                    fi
                done
            fi
            if command -v go >/dev/null 2>&1; then
                echo -e "    ${GREEN}✅${NC} Go 安装成功: $(go version 2>/dev/null | head -1)"
            else
                echo -e "    ${RED}❌${NC} Go 安装后仍不可用"
                echo "    请手动执行 'source /root/.bashrc' 后重新运行 'bash auto_install.sh'"
                exit 1
            fi
        fi
    done

    # 安装其余所有缺失项
    for item in "${MISSING[@]}"; do
        IFS=':' read -r type arg1 arg2 <<< "$item"
        case "$type" in
            apt)
                echo "  📦 apt install $arg1 ..."
                APT_I_LOG="$(mktemp)"
                if apt-get install -y "$arg1" >"$APT_I_LOG" 2>&1; then
                    echo -e "    ${GREEN}✅ 已安装${NC}"
                else
                    echo -e "    ${RED}❌ 安装失败${NC}"
                    grep -iE '^(E:|Err:|Package .* has no installation candidate|Unable to locate)' "$APT_I_LOG" \
                        | head -3 | sed 's/^/      /'
                    # 404 最常见的根因是索引过期（apt update 失败），给出可操作提示
                    if grep -q '404' "$APT_I_LOG"; then
                        echo "      💡 404 = 索引里的版本在镜像上不存在。先确认 'apt-get update' 是否成功；"
                        echo "         若某版本被撤包，可指定可用版本：apt-cache madison $arg1"
                    fi
                fi
                rm -f "$APT_I_LOG"
                ;;
            go)
                echo "  🔧 go install $arg1 ..."
                go install "$arg1" >/dev/null 2>&1 || echo "    ⚠️ 失败"
                ;;
            git)
                echo "  📥 git clone → $arg2 ..."
                repo="https://github.com/${arg1}.git"
                git clone "$repo" "$arg2" >/dev/null 2>&1 || echo "    ⚠️ 失败"
                [ -f "$arg2/requirements.txt" ] && python3 -m pip install -r "$arg2/requirements.txt" --break-system-packages >/dev/null 2>&1 || true
                ;;
            pip)
                echo "  🐍 pip3 install $arg1 ..."
                python3 -m pip install "$arg1" --break-system-packages >/dev/null 2>&1 || echo "    ⚠️ 失败"
                ;;
            # pipx 分支已移除：项目硬规则禁止虚拟环境，
            # 所有 Python 包一律走系统级 pip --break-system-packages

            dir)
                echo "  📥 git clone → $arg2 ..."
                git clone "https://github.com/${arg1}.git" "$arg2" >/dev/null 2>&1 || echo "    ⚠️ 失败"
                [ -f "$arg2/requirements.txt" ] && python3 -m pip install -r "$arg2/requirements.txt" --break-system-packages >/dev/null 2>&1 || true
                ;;
            python_tool)
                echo "  🐍 Python 工具: $arg1 → $arg2 ..."
                if [ ! -d "$arg2" ]; then
                    git clone "https://github.com/${arg1}.git" "$arg2" >/dev/null 2>&1 || echo "    ⚠️ git clone 失败"
                fi
                if [ -f "$arg2/requirements.txt" ]; then
                    echo "     python3 -m pip install -r requirements.txt --break-system-packages ..."
                    python3 -m pip install -r "$arg2/requirements.txt" --break-system-packages >/dev/null 2>&1 || echo "    ⚠️ pip install 失败"
                fi
                ;;

            goenv)
                # 已在前面处理，跳过
                ;;
            chrome)
                echo "  🌐 安装 google-chrome ..."
                if ! grep -q 'dl.google.com/linux/chrome/deb/' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
                    wget -q -O /tmp/google-chrome.gpg https://dl.google.com/linux/linux_signing_key.pub
                    mkdir -p /etc/apt/keyrings 2>/dev/null
                    gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg /tmp/google-chrome.gpg 2>/dev/null || true
                    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
                    rm -f /tmp/google-chrome.gpg
                fi
                apt update >/dev/null 2>&1 || true
                apt install -y google-chrome-stable >/dev/null 2>&1 || echo "    ⚠️ 失败"
                ;;
            csvquote)
                echo "  🔨 编译 csvquote ..."
                if [ ! -d /opt/csvquote ]; then
                    cd /opt && git clone https://github.com/adamgordonbell/csvquote.git >/dev/null 2>&1 || echo "    ⚠️ git clone 失败"
                fi
                # 必须显式判断目录存在：set -e 下裸 `cd` 失败会静默终止整个脚本，
                # 后面的工具全部装不上且不报错
                if [ -d /opt/csvquote ]; then
                    cd /opt/csvquote && go build -o csvquote cmd/csvquote/main.go >/dev/null 2>&1 && cp csvquote /usr/local/bin/ || echo "    ⚠️ 编译失败"
                else
                    echo "    ⚠️ 跳过：/opt/csvquote 不存在（clone 失败）"
                fi
                ;;
            kscan)
                echo "  🔨 编译 kscan ..."
                if [ ! -d /opt/kscan ]; then
                    cd /opt && git clone https://github.com/lcvvvv/kscan >/dev/null 2>&1 || echo "    ⚠️ git clone 失败"
                fi
                if [ -d /opt/kscan ]; then
                    cd /opt/kscan && go mod tidy >/dev/null 2>&1 && go build -o kscan . >/dev/null 2>&1 && cp kscan ~/go/bin/ || echo "    ⚠️ 编译失败"
                else
                    echo "    ⚠️ 跳过：/opt/kscan 不存在（clone 失败）"
                fi
                ;;
            sqlmap)
                echo "  📥 git clone sqlmap → /opt/sqlmap ..."
                if [ ! -d /opt/sqlmap ]; then
                    git clone --depth 1 https://github.com/sqlmapproject/sqlmap.git /opt/sqlmap >/dev/null 2>&1 || echo "    ⚠️ git clone 失败"
                fi
                [ -f /opt/sqlmap/sqlmap.py ] && ln -sf /opt/sqlmap/sqlmap.py /usr/local/bin/sqlmap 2>/dev/null
                ;;
        esac
    done
fi

# ── 以下操作仅在 install 模式执行，check 模式跳过 ──
if [ "$INSTALL_ONLY" != "check" ]; then

  # 优先提升 Go 版 httpx 到 /usr/local/bin/httpx
  promote_go_httpx

  # 初始化 nuclei 模板
  echo "  📥 nuclei -ut ..."
  nuclei -ut >/dev/null 2>&1 || true

  # afrog POC 下载
  echo "  📥 afrog -up ..."
  afrog -up >/dev/null 2>&1 || true

  # fuzzing-templates 软链
  if [ ! -d ~/nuclei-templates/dast ] && [ -d /opt/fuzzing-templates ]; then
      ln -s /opt/fuzzing-templates ~/nuclei-templates/dast 2>/dev/null || true
  elif [ ! -d ~/nuclei-templates/dast ] && [ ! -d /opt/fuzzing-templates ]; then
      echo "  📥 下载 fuzzing-templates ..."
      git clone https://github.com/projectdiscovery/fuzzing-templates.git /opt/fuzzing-templates >/dev/null 2>&1 || true
      ln -s /opt/fuzzing-templates ~/nuclei-templates/dast 2>/dev/null || true
  fi

  # 创建 swap (2GB)
  if [ ! -f /swap ]; then
      echo "  📀 创建 swap (2GB) ..."
      dd if=/dev/zero of=/swap bs=1M count=2048 2>/dev/null
      mkswap -f /swap >/dev/null 2>&1
      swapon /swap >/dev/null 2>&1
  fi

  # 配置 locale（检查避免重复追加）
  if ! grep -q 'LC_ALL=C.UTF-8' /etc/profile 2>/dev/null; then
      echo "export LC_ALL=C.UTF-8" >> /etc/profile
  fi
  if ! grep -q 'LANG=C.UTF-8' /etc/profile 2>/dev/null; then
      echo "export LANG=C.UTF-8" >> /etc/profile
  fi

fi  # end install-only block

echo ""
echo "=========================================="
echo "  最终验证：确认关键工具可正常调用"
echo "=========================================="

VERIFY_FAILED=0

smoke() {
    local name=$1 test_cmd=$2
    if eval "$test_cmd" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅${NC} $name 调用正常"
    else
        echo -e "  ${RED}❌${NC} $name 调用失败"
        VERIFY_FAILED=1
    fi
}

# 可选工具的 smoke：失败只警告，不置 VERIFY_FAILED
smoke_optional() {
    local name=$1 test_cmd=$2
    if eval "$test_cmd" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅${NC} $name 调用正常"
    else
        echo -e "  ${YELLOW}⚠️${NC} $name 不可用（可选，不影响主流程）"
    fi
}

smoke "go"           "go version"
smoke "python3"      "python3 --version"
smoke "subfinder"    "subfinder -version 2>&1"
smoke "dnsx"         "dnsx -version 2>&1"
smoke "naabu"        "naabu -version 2>&1"
smoke "httpx"        "httpx -version 2>&1"
smoke "nuclei"       "nuclei -version 2>&1"
smoke "katana"       "katana -version 2>&1"
smoke "anew"         "ANEW_TMP=\$(mktemp); echo test | anew \$ANEW_TMP >/dev/null 2>&1; rm -f \$ANEW_TMP"
smoke "ksubdomain"   "ksubdomain -version 2>&1"
smoke "afrog"        "afrog -version 2>&1"
smoke_optional "gowitness"    "gowitness version 2>&1"
smoke "gau"          "gau --version 2>&1"
smoke "ffuf"         "ffuf -V 2>&1"
smoke "nali"         "nali --version 2>&1"
smoke "kscan"        "kscan --help 2>&1"
smoke "dnsgen"       "dnsgen --help 2>&1"
smoke "csvquote"     "csvquote --help 2>&1"
smoke "uro"          "uro --help 2>&1"
smoke "alterx"       "alterx -version 2>&1"
smoke "sqlmap"       "python3 /opt/sqlmap/sqlmap.py --version 2>&1"
smoke "redis-cli"    "redis-cli --version 2>&1"
smoke "mysql"        "mysql --version 2>&1"
smoke "sshpass"      "sshpass -V 2>&1"
smoke "git-dumper"   "git-dumper --help 2>&1"
smoke "OneForAll"           "cd /opt/OneForAll && mkdir -p results && python3 oneforall.py --help 2>&1"
smoke "subDomainsBrute"     "python3 /opt/subDomainsBrute/subDomainsBrute.py -h 2>&1"
smoke "dirsearch"           "python3 /opt/dirsearch/dirsearch.py -h 2>&1"
smoke "ihoneyBakFileScan"   "python3 /opt/ihoneyBakFileScan_Modify/ihoneyBakFileScan_Modify.py -h 2>&1"

if [ "$VERIFY_FAILED" -eq 1 ]; then
    echo ""
    echo -e "${RED}============================================${NC}"
    echo -e "${RED}  ❌ 部分工具调用失败，请检查环境后重试${NC}"
    echo -e "${RED}============================================${NC}"
    exit 1
fi

echo ""
echo "=========================================="
echo -e "  ${GREEN}✅ 环境就绪，所有工具通过验证${NC}"
echo "=========================================="
