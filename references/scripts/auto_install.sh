#!/usr/bin/env bash
# 7scanAI 依赖检测与安装
# 用法: bash auto_install.sh          # 检测并安装全部缺失工具
#       bash auto_install.sh check    # 仅检测，不安装
set -e

# 自动探测项目根目录（无论从哪个路径执行此脚本）
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
echo "📍 7scanAI 项目路径: $SCRIPT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
MISSING=()
INSTALL_ONLY="${1:-install}"

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
    local name=$1 pkg=${2:-$name}
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
check_system_pkg pipx
check_system_pkg gcc
check_system_pkg libpcap "libpcap-dev"
check_command lsof
check_command tmux
check_command iotop
check_command telnet
check_command axel
check_command unzip
command -v ag &>/dev/null && echo -e "  ${GREEN}✅${NC} silversearcher-ag" || { echo -e "  ${RED}❌${NC} silversearcher-ag"; MISSING+=("apt:silversearcher-ag"); }
command -v google-chrome &>/dev/null && echo -e "  ${GREEN}✅${NC} chrome" || { echo -e "  ${YELLOW}⚠️${NC} chrome (katana headless 需要)"; MISSING+=("chrome"); }

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
check_go_tool gowitness   "github.com/sensepost/gowitness@latest"
check_go_tool anew        "github.com/tomnomnom/anew@latest"
check_go_tool nali        "github.com/zu1k/nali@latest"
check_go_tool nocdn       "github.com/r00tSe7en/nocdn@latest"
check_go_tool alterx      "github.com/projectdiscovery/alterx/cmd/alterx@latest"
check_go_tool jsubfinder  "github.com/ThreatUnkown/jsubfinder@latest"
check_go_tool ffuf        "github.com/ffuf/ffuf@latest"
command -v uro &>/dev/null && echo -e "  ${GREEN}✅${NC} uro" || { echo -e "  ${RED}❌${NC} uro (pipx)"; MISSING+=("pipx:uro"); }
command -v kscan &>/dev/null && echo -e "  ${GREEN}✅${NC} kscan" || { echo -e "  ${RED}❌${NC} kscan"; MISSING+=("kscan"); }
command -v csvquote &>/dev/null && echo -e "  ${GREEN}✅${NC} csvquote" || { echo -e "  ${RED}❌${NC} csvquote"; MISSING+=("csvquote"); }

echo ""
echo "── Python 工具 ──"
check_python_tool OneForAll       /opt/OneForAll       shmilylty/OneForAll          /opt/OneForAll/oneforall.py        "cd /opt/OneForAll && mkdir -p results && python3 oneforall.py --help"
check_python_tool subDomainsBrute /opt/subDomainsBrute  lijiejie/subDomainsBrute    /opt/subDomainsBrute/subDomainsBrute.py
check_python_tool dirsearch       /opt/dirsearch        maurosoria/dirsearch         /opt/dirsearch/dirsearch.py        "python3 -c 'import requests_ntlm, httpx_ntlm'"
check_python_tool ihoneyBakFileScan_Modify /opt/ihoneyBakFileScan_Modify VMsec/ihoneyBakFileScan_Modify /opt/ihoneyBakFileScan_Modify/ihoneyBakFileScan_Modify.py
command -v dnsgen &>/dev/null && echo -e "  ${GREEN}✅${NC} dnsgen" || { echo -e "  ${RED}❌${NC} dnsgen"; MISSING+=("pip:dnsgen"); }

echo ""
echo "── 模板库 ──"
# nuclei-templates installed via nuclei -ut, not git clone
# fuzzing-templates handled by dedicated installer below

echo ""
echo "=========================================="
echo "  缺失: ${#MISSING[@]} 项"
echo "=========================================="

if [ ${#MISSING[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ 所有依赖已就绪，跳过安装${NC}"
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

# ── 安装阶段 (仅当有缺失项时执行) ──
if [ ${#MISSING[@]} -gt 0 ]; then
    # 确保 apt update 先执行一次
    echo "  📦 apt update ..."
    apt update >/dev/null 2>&1 || true

    # 优先安装 Go 环境，因为后续 Go 工具依赖它
    for item in "${MISSING[@]}"; do
        IFS=':' read -r type arg1 arg2 <<< "$item"
        if [ "$type" = "goenv" ]; then
            echo "  🔧 安装 Go 环境 (严格遵循 autoinstallooo.sh) ..."
            sh -c "$(curl -L https://raw.githubusercontent.com/canha/golang-tools-install-script/master/goinstall.sh | bash -s -- --version 1.26.3)" >/dev/null 2>&1
            if command -v go >/dev/null 2>&1; then
                echo -e "    ${GREEN}✅${NC} Go 安装成功!"
            else
                echo -e "    ${RED}❌${NC} Go 安装失败!"
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
                apt-get install -y "$arg1" >/dev/null 2>&1 || echo "    ⚠️ 失败"
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
            pipx)
                echo "  🐍 pipx install $arg1 ..."
                pipx install "$arg1" >/dev/null 2>&1 || echo "    ⚠️ 失败"
                ;;
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
                echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list
                apt install -y gnupg2 >/dev/null 2>&1 || true
                wget https://dl.google.com/linux/linux_signing_key.pub >/dev/null 2>&1 || true
                apt-key add linux_signing_key.pub >/dev/null 2>&1 || true
                apt update >/dev/null 2>&1 || true
                apt install -y google-chrome-stable >/dev/null 2>&1 || echo "    ⚠️ 失败"
                ;;
            csvquote)
                echo "  🔨 编译 csvquote ..."
                cd /opt && git clone https://github.com/adamgordonbell/csvquote.git >/dev/null 2>&1 || true
                cd /opt/csvquote && go build -o csvquote cmd/csvquote/main.go >/dev/null 2>&1 && cp csvquote /usr/local/bin/ || echo "    ⚠️ 失败"
                ;;
            kscan)
                echo "  🔨 编译 kscan ..."
                cd /opt && git clone https://github.com/lcvvvv/kscan >/dev/null 2>&1 || true
                cd /opt/kscan && go mod tidy >/dev/null 2>&1 && go build -o kscan . >/dev/null 2>&1 && cp kscan ~/go/bin/ || echo "    ⚠️ 失败"
                ;;
        esac
    done
fi

# 初始化 nuclei 模板
echo "  📥 nuclei -ut ..."
nuclei -ut >/dev/null 2>&1 || true

# fuzzing-templates 软链
if [ ! -d ~/nuclei-templates/dast ] && [ -d /opt/fuzzing-templates ]; then
    ln -s /opt/fuzzing-templates ~/nuclei-templates/dast 2>/dev/null || true
elif [ ! -d ~/nuclei-templates/dast ] && [ ! -d /opt/fuzzing-templates ]; then
    echo "  📥 下载 fuzzing-templates ..."
    git clone https://github.com/projectdiscovery/fuzzing-templates.git /opt/fuzzing-templates >/dev/null 2>&1 || true
    ln -s /opt/fuzzing-templates ~/nuclei-templates/dast 2>/dev/null || true
fi

# 创建 swap (2GB) — 严格遵循 autoinstallooo.sh
if [ ! -f /swap ]; then
    echo "  📀 创建 swap (2GB) ..."
    dd if=/dev/zero of=/swap bs=1M count=2048 2>/dev/null
    mkswap -f /swap >/dev/null 2>&1
    swapon /swap >/dev/null 2>&1
fi

# 配置 locale — 严格遵循 autoinstallooo.sh
if [ "$(locale 2>/dev/null | head -n 1)" != 'LANG=C.UTF-8' ]; then
    echo "export LC_ALL=C.UTF-8" >> /etc/profile
    echo "export LANG=C.UTF-8" >> /etc/profile
fi

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

smoke "go"           "go version"
smoke "python3"      "python3 --version"
smoke "subfinder"    "subfinder -version 2>&1"
smoke "dnsx"         "dnsx -version 2>&1"
smoke "naabu"        "naabu -version 2>&1"
smoke "httpx"        "httpx -version 2>&1"
smoke "nuclei"       "nuclei -version 2>&1"
smoke "katana"       "katana -version 2>&1"
smoke "anew"         "echo test | anew /tmp/anew_smoke_test 2>&1; rm -f /tmp/anew_smoke_test"
smoke "ksubdomain"   "ksubdomain -version 2>&1"
smoke "afrog"        "afrog -version 2>&1"
smoke "gowitness"    "gowitness version 2>&1"
smoke "gau"          "gau --version 2>&1"
smoke "ffuf"         "ffuf -V 2>&1"
smoke "nali"         "nali --version 2>&1"
smoke "kscan"        "kscan --help 2>&1"
smoke "dnsgen"       "dnsgen --help 2>&1"
smoke "csvquote"     "csvquote --help 2>&1"
smoke "uro"          "uro --help 2>&1"
smoke "alterx"       "alterx -version 2>&1"
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
