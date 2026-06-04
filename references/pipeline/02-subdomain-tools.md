# Phase 2 — 子域名工具参数说明

## OneForAll
- 路径: `/opt/OneForAll/oneforall.py`
- 输出 CSV 第 6 列为子域名
- `--req False` 禁用请求以加速
- 耗时: 5-30min

## ksubdomain
- 需先 `ksubdomain test` 生成配置文件
- 配置文件第一行为 `src_ip`，需设为本机出口 IP
- `--wild-filter-mode advanced` 高级泛解析过滤模式
- 结果 > 20000 行时清空

## subDomainsBrute
- `-t 200` 200 线程
- `--full` 全量爆破
- 结果取第一列（域名部分）

## subfinder
- `-all` 使用所有 API 源
- 纯被动，不发包到目标

## gau (Get All URLs)
- `--subs` 提取子域名
- `--blacklist` 排除静态资源后缀
- `timeout 20m` 限制 20 分钟

## jsubfinder
- 从 JavaScript 文件中提取子域名/endpoint
- 需先用 httpx 过滤存活目标
- 排除 `GetResults content type JS` 噪音行

## dnsgen
- 基于已知子域名生成排列变体
- 结果 > 1000 行时清空

## alterx
- ProjectDiscovery 的排列生成工具
- dnsgen 的补充
- 结果 > 1000 行时清空
