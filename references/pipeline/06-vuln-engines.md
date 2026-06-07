# Phase 6 速查表

本文件只解释漏洞阶段各引擎的定位和差异。  
真正执行命令、watchdog、fallback 和归档逻辑，以 `references/pipeline/full-workflow.md` 为准。

## kscan
- 定位：端口服务指纹 + 弱口令爆破
- 输入分流：
  - 域名:端口 → `--check`
  - IP:端口 → `--check --hydra`
- 风险：多目标并发时资源开销高，建议保持单目标独占

## afrog
- 定位：高危/严重 POC 快速验证
- 规则：按批次拆分，结果归档到 `afrog_scan_results/`
- 产物：`json`、`html`、`err.log`
- 价值：适合作为高危快速确认器

## ihoneyBakFileScan
- 定位：备份泄露和敏感文件暴露
- 价值：对 `db.sql`、`.env`、源码压缩包这类高价值泄露点非常有效

## auto_dirsearch
- 定位：目录/文件爆破 + 敏感文件补扫
- 关键机制：
  - 先尝试智能过滤
  - 无结果时回退标准模式
  - 再补一层少量高价值敏感文件直探
- 结果保留策略：重点保留 `200,401,403,301,302,307,308,405`

## nuclei
- 定位：模板化漏洞扫描
- 适合：已确认的 Web 目标快速批量验证
- 结果：更适合做“命中提示”和多源交叉验证

## Katana + Nuclei DAST
- 定位：URL 扩展 + 参数面 DAST 验证
- 关键点：
  - `katana` 把可访问路径尽量展开
  - `uro` 负责去重和压缩输入
  - `nuclei DAST` 对参数化入口做更深探测
- 价值：容易发现 LFI、参数型文件读取、部分注入线索
