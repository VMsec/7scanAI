# 工具安装

## 一键安装

```bash
# 在项目根目录下执行（脚本会自动探测路径）
bash references/scripts/auto_install.sh

# 仅检测不安装
bash references/scripts/auto_install.sh check
```

## 依赖清单

### Python 工具
| 工具 | 路径 | 安装 |
|------|------|------|
| OneForAll | `/opt/OneForAll` | `git clone https://github.com/shmilylty/OneForAll.git /opt/OneForAll && pip3 install -r /opt/OneForAll/requirements.txt --break-system-packages` |
| subDomainsBrute | `/opt/subDomainsBrute` | `git clone https://github.com/lijiejie/subDomainsBrute.git /opt/subDomainsBrute && pip3 install -r /opt/subDomainsBrute/requirements.txt --break-system-packages` |
| dirsearch | `/opt/dirsearch` | `git clone https://github.com/maurosoria/dirsearch.git /opt/dirsearch && pip3 install -r /opt/dirsearch/requirements.txt --break-system-packages` |
| ihoneyBakFileScan_Modify | `/opt/ihoneyBakFileScan_Modify` | `git clone https://github.com/VMsec/ihoneyBakFileScan_Modify.git /opt/ihoneyBakFileScan_Modify && pip3 install -r /opt/ihoneyBakFileScan_Modify/requirements.txt --break-system-packages` |

> ⚠️ **Python 工具安装硬规则**: 每个 Python 工具 git clone 后**必须**立即执行 `pip3 install -r requirements.txt --break-system-packages`，不可跳过。`--break-system-packages` 强制安装，避免 PEP 668 环境报错。

### Go 工具
```bash
# ProjectDiscovery 套件
go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install github.com/projectdiscovery/dnsx/cmd/dnsx@latest
go install github.com/projectdiscovery/naabu/v2/cmd/naabu@latest
go install github.com/projectdiscovery/httpx/cmd/httpx@latest
go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
go install github.com/projectdiscovery/katana/cmd/katana@latest
go install github.com/projectdiscovery/alterx/cmd/alterx@latest

# 其他
go install github.com/lc/gau/v2/cmd/gau@latest
go install github.com/boy-hack/ksubdomain/v2/cmd/ksubdomain@latest
go install github.com/ThreatUnkown/jsubfinder@latest
go install github.com/sensepost/gowitness@latest
go install github.com/tomnomnom/anew@latest
go install github.com/zu1k/nali@latest
go install github.com/zan8in/afrog/v3/cmd/afrog@latest
go install github.com/r00tSe7en/nocdn@latest

# kscan (需编译)
cd /opt && git clone https://github.com/lcvvvv/kscan
cd /opt/kscan && go mod tidy && go build -o kscan . && cp kscan ~/go/bin/

# csvquote (需编译)
cd /opt && git clone https://github.com/adamgordonbell/csvquote.git
cd /opt/csvquote && go build -o csvquote cmd/csvquote/main.go && cp csvquote /usr/local/bin
```

### 系统工具
```bash
apt install -y nmap masscan wfuzz libpcap-dev
pip3 install dnsgen --break-system-packages
pipx install uro
```

### Nuclei 模板
```bash
nuclei -ut
git clone https://github.com/projectdiscovery/fuzzing-templates.git ~/nuclei-templates/dast/
```
