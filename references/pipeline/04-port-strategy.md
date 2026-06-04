# Phase 4 — 端口扫描策略

## naabu 参数

```bash
naabu -l targets.txt \
  -exclude-cdn \       # 排除 CDN IP
  -Pn \                # 跳过 ping 探活
  -scan-type s \       # SYN 扫描（需 root）
  -c 50 \              # 并发 50
  -pts 50 \            # 每端口超时 50ms
  -iv 4 \              # 重试间隔 4s
  -rate 10000 \        # 发包速率 10000 pps
  -p -                 # 全端口 1-65535
```

非 root 时 `-scan-type s` 自动降级为 TCP Connect。

## CDN 过滤

双层过滤:
1. **nali**: 地理标签 → 过滤 CloudFlare/Akamai/CDN/CloudFront/Fastly/GitHub
2. **nocdn**: CDN IP 段数据库，二次过滤

```bash
cat ips.txt | nali | grep -iEv '(本机地址|局域网|CloudFlare|Akamai|CDN|CloudFront|Fastly|GitHub)' | awk '{print $1}' | nocdn | sort -u
```

## 内外网分离

```bash
# 外网
cat subdomain2ips.txt | nali | grep -v '局域网' | awk '{print $1}' > external.txt
# 内网
cat subdomain2ips.txt | nali | grep '局域网' | awk '{print $1}' | dnsx -silent -a -resp > intranet.txt
```
