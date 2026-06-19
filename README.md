# sing-box-1-click

更简洁的 sing-box 一键安装 & 管理脚本。

参考 [233boy/sing-box](https://github.com/233boy/sing-box) 的核心理念(参数化 add/change/del/info + 多配置并存 + 一键 auto),剔除其复杂度来源:用 **sing-box 原生 ACME** 砍掉整个 Caddy 子系统、用 **jq 模板**生成 JSON(取代字符串拼接)、聚焦现代协议、模块化小文件、FHS 标准路径。

## 特点

- **无 Caddy**:域名协议用 sing-box 原生 ACME 自动签证书,无域名协议用自签证书
- **jq 模板生成 JSON**:每个协议一个 `jq -n` 模板,干净可审计,告别字符串拼接
- **聚焦现代协议**:VLESS-REALITY(默认)、Hysteria2、TUIC、Trojan、VMess-WS-TLS、Shadowsocks-2022、AnyTLS
- **多配置并存**:每个入站一个 JSON 片段,`-C` 目录合并,增删互不影响
- **FHS 路径**:二进制 `/usr/local/bin/sing-box`,`/etc/sing-box` 仅放配置,脚本 `/usr/local/lib/sing-box`,`sb` 直接进 PATH(无需 alias)
- **仅 systemd**,覆盖主流发行版(Ubuntu/Debian/CentOS/RHEL/Fedora/Arch)

## 安装

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Cherrling/sing-box-1-click/main/install.sh)
```

本地开发安装(使用当前目录脚本,跳过下载):

```bash
bash install.sh -l
```

安装参数:`-l` 本地安装 | `-v <ver>` 指定核心版本 | `-p <proxy>` 代理 | `-f <core.tar.gz>` 本地核心包

安装后默认创建一个 VLESS-REALITY 配置并启动服务。

## 用法

```
sb                       # 交互菜单
sb add [proto] [args|auto]   # 添加 (proto: reality hysteria2 tuic trojan vmess-ws-tls shadowsocks anytls)
sb change <name> <opt> [val|auto]  # 更改 (opt: port host path pass uuid method sni key)
sb del <name>            # 删除
sb info [name]           # 查看
sb list                  # 列出
sb url [name] | sb qr [name]   # 链接 / 二维码
sb start|stop|restart|status   # 服务管理
sb test                  # 前台测试运行(定位启动错误)
sb update [core|sh]      # 更新核心 / 脚本
sb uninstall             # 卸载
sb help                  # 帮助
```

`auto` 表示自动生成(端口/UUID/密钥/路径等)。

### 示例

```bash
sb add r                 # VLESS-REALITY,全自动,无需域名,开箱即用
sb add hy2               # Hysteria2
sb add tuic              # TUIC
sb add ss                # Shadowsocks-2022
sb add vws example.com   # VMess-WS-TLS(需域名,自动 ACME 证书,监听 443)
sb add anytls            # AnyTLS(自签)
sb add anytls auto auto example.com  # AnyTLS + 域名 ACME
sb info reality-12345
sb change reality-12345 sni auto      # 换 REALITY 伪装域名
sb change reality-12345 key auto      # 换 REALITY 密钥
sb change hy2-12345 port 20000        # 换端口
```

## 协议与 TLS

| 协议 | 需域名 | TLS | 端口 |
|---|---|---|---|
| VLESS-REALITY | 否 | Reality(无证书) | 随机 |
| Hysteria2 | 否 | 自签(客户端 insecure=1) | 随机 |
| TUIC | 否 | 自签(客户端 insecure=1) | 随机 |
| Trojan | 否 | 自签(客户端 insecure=1) | 随机 |
| VMess-WS-TLS | 是 | 原生 ACME | 443 |
| Shadowsocks-2022 | 否 | 无 | 随机 |
| AnyTLS | 可选 | 有域名→ACME;无→自签 | 443 / 随机 |

> 域名协议必须监听 443 且域名已解析到本机(ACME TLS-ALPN-01 挑战要求)。

## 文件布局(FHS)

```
/usr/local/bin/sing-box           # 核心二进制
/usr/local/bin/sb                 # 管理入口(→ sb.sh)
/usr/local/lib/sing-box/          # sb.sh + lib/*.sh
/etc/sing-box/config.json         # 主配置(log/dns/ntp/outbounds)
/etc/sing-box/conf/<name>.json    # 每入站一个片段
/var/lib/sing-box/tls.cer|.key    # 自签证书
/var/log/sing-box/                # 日志
```

## 项目结构

```
install.sh          # 安装器
sb.sh               # 入口(薄:source lib + 派发 main)
lib/common.sh       # 颜色/工具/路径/生成与校验
lib/proto.sh        # 协议归一 + jq 模板生成 + 反读
lib/service.sh      # systemd 服务 + manage + test_run
lib/manage.sh       # add/change/del/info/list + main 派发 + update/uninstall
lib/share.sh        # URL/QR/菜单/帮助
```

## 与 233boy 的区别

| | 233boy | 本项目 |
|---|---|---|
| 自动 TLS | Caddy 反代 | sing-box 原生 ACME(无 Caddy) |
| JSON 生成 | 字符串拼接 + jq 包装 | jq 模板(`-n --arg`) |
| 协议 | 20+ 变体(笛卡尔积) | 7 个现代协议 |
| 代码 | `core.sh` 单文件 1830 行 | 5 个小模块 |
| 路径 | 全堆 `/etc/sing-box` | FHS:二进制 `/usr/local/bin`、`/etc` 仅配置 |
| init | systemd + OpenRC | systemd |
| 导入/广告 | xray/v2ray 导入 + 推广链接 | 无 |

## 反馈

<https://github.com/Cherrling/sing-box-1-click/issues>
