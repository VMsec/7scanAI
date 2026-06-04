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

check_go_tool() {
    local name=$1 pkg=${2:-$1}
    if command -v "$name" &>/dev/null; then
        echo -e "  ${GREEN}✅${NC} $name"
    else
        echo -e "  ${RED}❌${NC} $name"
        MISSING+=("go:$pkg")
    fi
}

check_python_dir() {
    local name=$1 path=${2:-/opt/$name}
    if [ -d "$path" ]; then
        echo -e "  ${GREEN}✅${NC} $name ($path)"
    else
        echo -e "  ${RED}❌${NC} $name"
        MISSING+=("git:$name:$path")
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
check_system_pkg nmap
check_system_pkg python3
check_system_pkg pip3 "python3-pip"
check_system_pkg pipx
check_system_pkg libpcap "libpcap-dev"
command -v google-chrome &>/dev/null && echo -e "  ${GREEN}✅${NC} chrome" || { echo -e "  ${YELLOW}⚠️${NC} chrome (katana headless 需要)"; }

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
command -v uro &>/dev/null && echo -e "  ${GREEN}✅${NC} uro" || { echo -e "  ${RED}❌${NC} uro (pipx)"; MISSING+=("pipx:uro"); }
command -v kscan &>/dev/null && echo -e "  ${GREEN}✅${NC} kscan" || { echo -e "  ${RED}❌${NC} kscan"; MISSING+=("kscan"); }
command -v csvquote &>/dev/null && echo -e "  ${GREEN}✅${NC} csvquote" || { echo -e "  ${RED}❌${NC} csvquote"; MISSING+=("csvquote"); }

echo ""
echo "── Python 工具 ──"
check_python_dir OneForAll       /opt/OneForAll
check_python_dir subDomainsBrute /opt/subDomainsBrute
check_python_dir dirsearch       /opt/dirsearch
check_python_dir ihoneyBakFileScan_Modify /opt/ihoneyBakFileScan_Modify
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
    echo -e "${GREEN}✅ 所有依赖已就绪${NC}"
    exit 0
fi

for item in "${MISSING[@]}"; do echo "  - $item"; done

if [ "$INSTALL_ONLY" = "check" ]; then
    echo ""
    echo "运行 'bash auto_install.sh' 自动安装"
    exit 1
fi

echo ""
echo "开始安装 ${#MISSING[@]} 项..."

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
            repo="https://github.com/${arg1}.git"
            echo "  📥 git clone → $arg2 ..."
            git clone "$repo" "$arg2" >/dev/null 2>&1 || echo "    ⚠️ 失败"
            [ -f "$arg2/requirements.txt" ] && pip3 install -r "$arg2/requirements.txt" --break-system-packages >/dev/null 2>&1 || true
            ;;
        pip)
            echo "  🐍 pip3 install $arg1 ..."
            pip3 install "$arg1" --break-system-packages >/dev/null 2>&1 || echo "    ⚠️ 失败"
            ;;
	        pipx)
	            echo "  🐍 pipx install $arg1 ..."
	            pipx install "$arg1" >/dev/null 2>&1 || echo "    ⚠️ 失败"
	            ;;
        dir)
            echo "  📥 git clone → $arg2 ..."
            git clone "https://github.com/${arg1}.git" "$arg2" >/dev/null 2>&1 || echo "    ⚠️ 失败"
            [ -f "$arg2/requirements.txt" ] && pip3 install -r "$arg2/requirements.txt" --break-system-packages >/dev/null 2>&1 || true
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

echo ""
echo "=========================================="
echo -e "  ${GREEN}✅ 安装完成${NC}"
echo "  bash auto_install.sh check   # 验证"
echo "=========================================="
