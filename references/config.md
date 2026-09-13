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
| nuclei 模板 | critical | critical,high,medium | critical,high,medium |
| afrog | - | critical,high | critical,high |
| kscan 指纹 | - | ✅ | ✅ |
| kscan hydra | ✅ | ✅ | ✅ |
| 目录爆破 | - | ✅(智能) | ✅(全量) |
| 备份文件扫描 | - | ✅ | ✅ |
| Katana 爬虫 | - | - | ✅ |
| DAST Fuzzing | - | - | ✅ |
| 自主利用 | - | ✅(60min预算) | ✅(120min预算) |
| 预计耗时 | 5-10min | 1-2h | 6-12h |

## 自定义 Profile

用户可以在对话中覆盖任何参数:
- "用 quick 模式但加上目录爆破"
- "扫 top-500 端口而不是 top-1000"
- "只做子域名发现，不做漏洞扫描"

AI 收到这类指令后，在 Phase 1 checkpoint 中记录覆盖项，并按覆盖项执行。

约束:
- 不增加额外交互轮次。profile 只用于预填默认值或直接覆盖执行参数。
- 如果用户已经明确给出端口范围、截图或域名变形，Phase 1 不再重复询问这些项。
- profile 与用户显式覆盖冲突时，始终以用户显式覆盖为准。

## 扫描范围自适应

> ⚠️ **本节已废弃旧的"按子域名数自动降级"规则**。
> 扫描范围的自动调整**统一由规模守卫（Scale Guard）决定**，
> 唯一自动切换条件是**预计耗时 24 小时阈值**（见 `full-workflow.md` 6.0 / `SKILL.md` Phase 6）：
>
> | 预计耗时 | 规则 |
> |---------|------|
> | ≤ 24 小时 | **全量覆盖扫描** |
> | > 24 小时 | **优化规则扫描**（Tier A/B/C 分级） |
>
> **不得**再按子域名数量、机器配置或 profile 自行缩小扫描范围——
> 那属于改扫描意图，必须由用户决定或由 24h 阈值客观触发。
>
> profile（quick / full / deep）只影响**用户主动选择**时的默认强度，
> 不构成自动降级依据。

## 多目标并发策略

- 无论机器配置如何，默认串行跑目标
- **只有用户明确要求并发，且机器高于 `4C/4G`，才允许并发 `2-3` 个目标**
- `Phase 6` 默认单目标独占，避免多个目标同时做重型漏洞扫描
- 多目标场景优先做目录隔离和资源隔离，不追求满并发
- 所有写 CWD 文件的工具必须先 `pushd "$TARGET_DIR"`；
  共享配置（如 `ksubdomain.yaml`）每目标独立副本到 `$TARGET_DIR/runtime/`

## Nuclei 模板排除

以下模板噪音大，默认排除:
```
http-missing-security-headers,nginx-status,apache-detect,ssl-dns-names,
waf-detect,expired-ssl,HTTP-TRACE,tech-detect,tomcat-exposed-docs,
tls-version,default-openresty,nginx-version,old-copyright,default-nginx-page,
deprecated-tls
```
