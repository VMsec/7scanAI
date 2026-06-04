# 扫描配置与 Profile 定制

## 内置 Profile 参数表

| 参数 | quick | full | deep |
|------|-------|------|------|
| 子域名被动 | ✅ | ✅ | ✅ |
| 子域名爆破 | - | ✅ | ✅ |
| JS 子域名 | - | ✅ | ✅ |
| 子域名排列 | - | 条件(非泛解析) | ✅(非泛解析) |
| DNS 解析 | ✅ | ✅ | ✅ |
| CDN 过滤 | ✅ | ✅ | ✅ |
| 端口扫描 | top-100 | top-1000 | 全端口 |
| HTTP 指纹 | ✅ | ✅ | ✅ |
| Web 截图 | - | ✅ | ✅ |
| nuclei 模板 | critical | critical,high,medium | 全部 |
| afrog | - | critical,high | 全部 |
| kscan 指纹 | - | ✅ | ✅ |
| kscan hydra | - | - | ✅ |
| 目录爆破 | - | ✅(智能) | ✅(全量) |
| 备份文件扫描 | - | ✅ | ✅ |
| Katana 爬虫 | - | - | ✅ |
| DAST Fuzzing | - | - | ✅ |
| 预计耗时 | 5-10min | 1-2h | 6-12h |

## 自定义 Profile

用户可以在对话中覆盖任何参数:
- "用 quick 模式但加上目录爆破"
- "扫 top-500 端口而不是 top-1000"
- "只做子域名发现，不做漏洞扫描"

AI 收到这类指令后，在 Phase 1 checkpoint 中记录覆盖项，并按覆盖项执行。

## 目标规模自适应

| 子域名数 | 自动调整 |
|----------|---------|
| < 100 | 维持原 profile |
| 100 - 1000 | 目录爆破降为仅重点目标 |
| 1000 - 5000 | nuclei 只跑 critical,high |
| > 5000 | 自动降级为 quick + 告知用户 |

## Nuclei 模板排除

以下模板噪音大，默认排除:
```
http-missing-security-headers,nginx-status,apache-detect,ssl-dns-names,
waf-detect,expired-ssl,HTTP-TRACE,tech-detect,tomcat-exposed-docs,
tls-version,default-openresty,nginx-version,old-copyright,default-nginx-page,
deprecated-tls
```
