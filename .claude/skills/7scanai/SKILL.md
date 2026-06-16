---
name: 7scanai
description: 自动化安全侦察与漏洞扫描 pipeline。用户给根域名后，按 7scanAI 的七阶段流程完成子域名发现、DNS解析、端口扫描、Web探测、漏洞扫描与报告生成。
---

# 7scanAI for Claude Code

仓库根目录的 `../../../SKILL.md` 是本项目唯一的权威工作流定义。

当用户要求扫描、挖洞、信息收集、资产发现、端口扫描、漏洞扫描，并给出目标域名或 URL 时：

1. 先读取 `../../../SKILL.md`，严格按其中的阶段顺序、命令参数、输出目录约束执行。
2. 不要凭记忆改写命令参数，优先复用 `references/scripts/` 下已有脚本。
3. 所有扫描结果继续写入 `targets/<domain>/`，不要改动目录约定。
4. **产物路径强制**: 核心产物必须写入固定绝对路径（见根 SKILL.md 规则2.1），禁止自创子目录。

仅在需要安装依赖、查看工具说明或生成报告时，再按需读取这些参考文件：

- `../../../references/install.md`
- `../../../references/config.md`
- `../../../references/pipeline/02-subdomain-tools.md`
- `../../../references/pipeline/04-port-strategy.md`
- `../../../references/pipeline/06-vuln-engines.md`
