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
- ⚠️ **必须做软404过滤（MUST，见 full-workflow 6.3.1）**：
  该工具判定命中的依据是「该路径返回了非空响应」，
  任何配了 catch-all / SPA fallback 的站点会把字典里**每个**路径都判为命中。
  - 实测：某次扫描 17 条 `.dump` 命中全部来自同一 host、响应整齐 21 字节，
    用随机路径复测返回**完全相同**的响应 ⇒ 全是误报
  - 过滤：`python3 references/scripts/soft404_check.py <raw> --out-dir DIR`
  - 产物三分类：`backup_scan_clean.txt` / `_soft404.txt` / `_unverified.txt`
  - **报告与研判只能引用 `backup_scan_clean.txt`，禁止引用 raw**

## auto_dirsearch
- 定位：目录/文件爆破 + 敏感文件补扫
- 关键机制：
  - 先尝试智能过滤
  - 无结果时回退标准模式
  - 再补一层少量高价值敏感文件直探
- 结果保留策略：重点保留 `200,401,403,301,302,307,308,405`
- ⚠️ **必须做软404过滤（MUST，见 full-workflow 6.4.1）**：
  dirsearch 判定命中的依据是「路径返回 200」，
  SPA 站点对**任意路径**都返回 `index.html` + 200，导致字典里每条路径都"命中"。
  - 实测（**最具迷惑性**）：11 个高价值目标全部报 `200 - <N>B - /.env`，
    体积 **882B ~ 108539B 各不相同**，极易被当成真实的配置泄露，
    实际全是各站 `index.html` 的 SPA fallback
  - 过滤：`python3 references/scripts/dirsearch_filter.py <dirsearch_result/> --out-dir DIR`
  - 产物三分类：`dirsearch_clean.txt` / `_soft404.txt` / `_unverified.txt`
  - **报告与研判只能引用 `dirsearch_clean.txt`，禁止引用 raw `smart_scan_*.txt`**
  - 注意 clean 文件行格式与 raw 不同：
    `200 - 1234B - https://host/path [text/html]`（含完整 URL 与 Content-Type），
    直接套用 raw 的 `grep -oE '/[^ ]+'` 路径提取会失效

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
