# 工具安装

## 客户端兼容性

- `Claude Code` 插件模式读取 `.claude-plugin/plugin.json`
- `Claude Code` 项目模式读取 `.claude/skills/7scanai/SKILL.md`
- `Codex` 插件模式读取 `.codex-plugin/plugin.json` 和 `skills/7scanai/SKILL.md`
- 两端共用同一份扫描流程定义，不需要维护两套脚本

## 一键安装

```bash
# 在项目根目录下先检测
bash references/scripts/auto_install.sh check

# 检测失败后，再手动安装
bash references/scripts/auto_install.sh
```

## 依赖清单

### Python 工具
| 工具 | 路径 | 安装 |
|------|------|------|
| OneForAll | `/opt/OneForAll` | `git clone https://github.com/shmilylty/OneForAll.git /opt/OneForAll && pip3 install -r /opt/OneForAll/requirements.txt --break-system-packages` |
| subDomainsBrute | `/opt/subDomainsBrute` | `git clone https://github.com/lijiejie/subDomainsBrute.git /opt/subDomainsBrute && pip3 install -r /opt/subDomainsBrute/requirements.txt --break-system-packages` |
| dirsearch | `/opt/dirsearch` | `git clone https://github.com/maurosoria/dirsearch.git /opt/dirsearch && pip3 install -r /opt/dirsearch/requirements.txt --break-system-packages` |
| ihoneyBakFileScan_Modify | `/opt/ihoneyBakFileScan_Modify` | `git clone https://github.com/VMsec/ihoneyBakFileScan_Modify.git /opt/ihoneyBakFileScan_Modify && pip3 install -r /opt/ihoneyBakFileScan_Modify/requirements.txt --break-system-packages` |

> ⚠️ **Python 工具安装硬规则**: 所有 Python 依赖必须系统级安装，统一使用 `pip3 install --break-system-packages`。每个 Python 工具 git clone 后**必须**立即执行 `pip3 install -r requirements.txt --break-system-packages`，不可跳过。

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
# 说明: nmap / masscan / wfuzz 不参与本流程（端口扫描用 naabu、爆破用 ffuf），故不安装
apt install -y libpcap-dev
pip3 install dnsgen --break-system-packages
pip3 install uro --break-system-packages
```

### 渗透利用工具（Phase 8 必需）

Phase 8 的 playbook 依赖以下工具，缺任一项都会导致对应 playbook 无法执行：

```bash
apt install -y sshpass default-mysql-client        # A.1/A.2/J.2 SSH、MySQL
pip3 install git-dumper --break-system-packages     # D.3 .git 源码泄露
# sqlmap（B.1/B.2 SQLi）与 ffuf（K.3/K.4 登录爆破）由 auto_install.sh 安装到 /opt 并加入 PATH
bash references/scripts/auto_install.sh check       # 核对是否齐全
```

| 工具 | 用途 | 对应 playbook |
|------|------|--------------|
| `sshpass` | SSH 弱口令登录验证、凭据复用喷洒 | A.1 / J.2 |
| `mysql` | MySQL 弱口令验证 | A.2 |
| `redis-cli` | Redis 弱口令验证 | A.3 |
| `sqlmap` | SQLi 自动化（**禁止 `--os-shell`**） | B.1 / B.2 |
| `ffuf` | 登录口表单爆破 | K.3 / K.4 |
| `git-dumper` | `.git` 源码泄露提取 | D.3 |

### Nuclei 模板
```bash
nuclei -ut
# ⚠️ fuzzing-templates 必须克隆到 /opt 再软链到 ~/nuclei-templates/dast
# （与 auto_install.sh 一致）。直接 clone 进 ~/nuclei-templates/dast/ 会与软链冲突。
git clone https://github.com/projectdiscovery/fuzzing-templates.git /opt/fuzzing-templates
ln -sfn /opt/fuzzing-templates ~/nuclei-templates/dast
```
