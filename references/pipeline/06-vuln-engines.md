# Phase 6 — 漏洞扫描引擎

## kscan — 端口指纹 + 弱口令

```bash
# Web 端口（域名:端口格式）
kscan -t web_ports.txt --check -Pn -Cn -Dn --threads 50 -o web_finger.txt

# IP 端口（IP:端口格式）+ Hydra 弱口令爆破
kscan -t ip_ports.txt --check -Pn -Cn -Dn --threads 50 --hydra -o ip_brute.txt
```

提取成功凭据:
```bash
grep 'Success' ip_brute.txt | sort | uniq > brute_success.txt
```

## afrog — POC 漏洞验证

分批扫描（每批 500 个目标）:
```bash
split -l 500 targets.txt part_
for file in part_*; do
  afrog -T "$file" -c 80 -rl 200 -S high,critical --task-smart-timeout -json "$file".json
  rm -f "$file"
  sync && echo 3 > /proc/sys/vm/drop_caches
  sleep 3
done
```

## ihoneyBakFileScan — 备份文件扫描

检测类型:
- 源码包: `.zip` `.tar.gz` `.rar` `.war` `.jar`
- 数据库: `.sql` `.sql.gz` `.bak` `.mdb`
- 配置文件: `.env` `.config` `.yml` `.xml`
- 编辑器临时文件: `~` `.swp` `.swo` `.save`
- 版本控制: `.git/config` `.svn/entries` `.DS_Store`

## auto_dirsearch — 智能目录爆破

核心机制:
1. curl 随机不存在的路径 → 采集 404 参考页
2. dirsearch 扫描时排除与参考页内容相似的响应
3. 解决 CDN/WAF 的伪 200 页面干扰
4. 参考页采集失败时自动退化为标准模式

排除的子目录:
```
js,css,fonts,images,image,img,static,assets,media,dist,build,
node_modules,vendor,lib,lang,locale,cache,wp-content,wp-includes
```

## nuclei — YAML 模板扫描

```bash
# 模板目录: /root/nuclei-templates/
nuclei -t /root/nuclei-templates/ -severity critical,high,medium \
  -l urls.txt -bs 50 -c 50 -rl 50 -nc
```

## Katana + Nuclei DAST Fuzzing

```bash
# 1. 爬虫收集 URL (depth=5, 过滤静态资源)
katana -list urls.txt -headless -no-sandbox -nc -d 5 -f qurl -silent -fs rdn -rl 50 -dr

# 2. uro 去重 + 过滤静态资源后缀
uro -b js,eot,jpg,jpeg,gif,css,tif,tiff,png,ttf,otf,woff,woff2,ico,svg,zip,rar,tar.gz,tgz,tar.bz2,tar,jar,war,7z,bak,sql,gz,sql.gz,tar.tgz

# 3. DAST 模板 fuzzing
nuclei -l uro_urls.txt -t ~/nuclei-templates/dast/ -dast -rl 20 -nc
```
