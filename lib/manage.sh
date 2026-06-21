#!/bin/bash
# manage.sh — add/change/del/info/list + main 派发 + update/uninstall

SB_SS_METHODS=(aes-128-gcm aes-256-gcm chacha20-ietf-poly1305 xchacha20-ietf-poly1305
    2022-blake3-aes-128-gcm 2022-blake3-aes-256-gcm 2022-blake3-chacha20-poly1305)
SB_PROTO_LIST=(reality vless-ws hysteria2 tuic trojan vmess-ws-tls vmess-ws shadowsocks anytls)

# ---------- 域名解析校验 (ACME 需要) ----------
_get_dns_a() {
    local name=$1 ip=$2 type=a
    [[ $ip == *:* ]] && type=aaaa
    _wget -T 5 --tries=1 -qO- --header="accept: application/dns-json" \
        "https://one.one.one.one/dns-query?name=$name&type=$type" 2>/dev/null
}

test_host_dns() {
    [[ $SB_NO_HOST_TEST ]] && return
    local ip; ip=$(get_ip)
    [[ -z $ip ]] && { warn "无法获取服务器 IP, 跳过域名解析检查."; return; }
    local dns; dns=$(_get_dns_a "$host" "$ip")
    if ! grep -q "$ip" <<<"$dns"; then
        warn "域名 ($host) 未解析到本机 ($ip)."
        msg "ACME 签证书需要域名正确解析到本机 (Cloudflare 请关代理/DNS only)."
        read -rp "我已确认解析 [y]: " y
        [[ $y != [yY] ]] && err "已取消."
    fi
}

_valid_ss_method() {
    local m
    for m in "${SB_SS_METHODS[@]}"; do [[ $m == "$1" ]] && return 0; done
    return 1
}

# ---------- 添加 ----------
add() {
    local proto
    if [[ -z $1 ]]; then
        _green "\n可选协议:\n"
        local i=1 p
        for p in "${SB_PROTO_LIST[@]}"; do msg "  $i) $p"; ((i++)); done
        read -rp "选择协议 [1]: " n
        proto=${SB_PROTO_LIST[${n:-1}-1]}
    else
        # 支持 "vless ws" / "vmess ws" 两词写法
        if [[ ($1 == vless || $1 == vmess) && $2 == ws ]]; then
            set -- "$1-$2" "${@:3}"
        fi
        proto=$(normalize_protocol "$1") || exit 1
        shift
    fi
    [[ $proto == anytls ]] && require_core 1.12
    # notls 修饰: vws → vmess-ws (无 TLS, 用于自有反代后端)
    [[ $SB_NOTLS == 1 && $proto == vmess-ws-tls ]] && proto=vmess-ws

    # 重置字段
    port= uuid= password= servername= priv_key= pub_key= host= path=
    ss_method= ss_password= anytls_domain=

    case $proto in
    reality)
        port=$1;     [[ -z $port || $port == auto ]] && port=$(get_port)
        uuid=$2;     [[ -z $uuid || $uuid == auto ]] && uuid=$(get_uuid)
        servername=$3; [[ -z $servername || $servername == auto ]] && servername=$(rand_servername)
        read priv_key pub_key <<<"$(get_pbk)"
        ;;
    vless-ws)
        port=$1; [[ -z $port || $port == auto ]] && port=$(get_port)
        uuid=$2; [[ -z $uuid || $uuid == auto ]] && uuid=$(get_uuid)
        path=$3; [[ -z $path || $path == auto ]] && path=/$uuid
        ;;
    hysteria2 | trojan)
        port=$1;     [[ -z $port || $port == auto ]] && port=$(get_port)
        password=$2; [[ -z $password || $password == auto ]] && password=$(get_uuid)
        ;;
    tuic)
        port=$1; [[ -z $port || $port == auto ]] && port=$(get_port)
        uuid=$2; [[ -z $uuid || $uuid == auto ]] && uuid=$(get_uuid)
        password=$uuid
        ;;
    vmess-ws-tls)
        host=$1
        [[ -z $host ]] && read -rp "请输入域名: " host
        [[ $host == auto ]] && err "vmess-ws-tls 需要域名: sb add vws <domain> [uuid] [/path]"
        uuid=$2; [[ -z $uuid || $uuid == auto ]] && uuid=$(get_uuid)
        path=$3; [[ -z $path || $path == auto ]] && path=/$uuid
        test_host_dns
        ;;
    vmess-ws)
        port=$1; [[ -z $port || $port == auto ]] && port=$(get_port)
        uuid=$2; [[ -z $uuid || $uuid == auto ]] && uuid=$(get_uuid)
        path=$3; [[ -z $path || $path == auto ]] && path=/$uuid
        ;;
    shadowsocks)
        port=$1;        [[ -z $port || $port == auto ]] && port=$(get_port)
        ss_password=$2; [[ -z $ss_password || $ss_password == auto ]] && ss_password=
        ss_method=$3;   [[ -z $ss_method || $ss_method == auto ]] && ss_method=2022-blake3-chacha20-poly1305
        _valid_ss_method "$ss_method" || err "不支持的加密方式: $ss_method"
        if [[ -z $ss_password ]]; then
            if [[ $ss_method == 2022-* ]]; then ss_password=$(get_ss2022_password "$ss_method")
            else ss_password=$(get_uuid); fi
        fi
        ;;
    anytls)
        anytls_domain=$3; [[ $anytls_domain == auto ]] && anytls_domain=
        password=$2; [[ -z $password || $password == auto ]] && password=$(get_uuid)
        if [[ $anytls_domain ]]; then
            port=443; test_host_dns
        else
            port=$1; [[ -z $port || $port == auto ]] && port=$(get_port)
        fi
        ;;
    esac

    # 校验
    [[ $port ]] && { is_test port "$port" || err "无效端口: $port"; }
    [[ $port && $port != 443 && $(is_port_used "$port") ]] && err "端口 $port 已被占用."
    [[ $uuid ]] && { is_test uuid "$uuid" || err "无效 UUID: $uuid"; }
    [[ $path ]] && { is_test path "$path" || err "无效路径: $path (例: /abc)"; }
    [[ $host ]] && { is_test domain "$host" || err "无效域名: $host"; }

    local name tag ib extra=
    name=$(inbound_name "$proto"); tag=${name%.json}
    ib=$(gen_inbound "$proto" "$tag")
    [[ $proto == reality ]] && extra=$(jq -nc --arg pk "$pub_key" '[{type:"direct",tag:("pk-"+$pk)}]')
    write_inbound "$name" "$ib" "$extra"

    _green "\n已添加: $name\n"
    sb_restart
    info "$name"
}

# ---------- 更改 ----------
change() {
    local name; name=$(resolve_name "$1") || exit 1; shift
    local opt=${1,,} val=$2
    [[ -z $opt ]] && err "用法: sb change <name> <port|host|path|pass|uuid|method|sni|key> [val|auto]"
    parse_inbound "$name"

    case $opt in
    port)
        [[ $has_acme == 1 ]] && err "域名协议端口固定 443, 不能更改."
        [[ -z $val || $val == auto ]] && val=$(get_port)
        is_test port "$val" || err "无效端口: $val"
        [[ $val != 443 && $(is_port_used "$val") ]] && err "端口 $val 已占用."
        port=$val
        ;;
    pass | passwd | password)
        if [[ $proto_name == shadowsocks ]]; then
            [[ -z $val || $val == auto ]] && val=$(get_ss2022_password "$ss_method")
            ss_password=$val
        else
            [[ -z $val || $val == auto ]] && val=$(get_uuid)
            password=$val
        fi
        ;;
    uuid)
        [[ -z $val || $val == auto ]] && val=$(get_uuid)
        is_test uuid "$val" || err "无效 UUID: $val"
        uuid=$val
        ;;
    method)
        [[ $proto_name != shadowsocks ]] && err "仅 Shadowsocks 支持更改加密方式."
        [[ -z $val || $val == auto ]] && val=2022-blake3-chacha20-poly1305
        _valid_ss_method "$val" || err "不支持的加密方式: $val"
        ss_method=$val
        ;;
    sni | servername)
        [[ $proto_name != reality ]] && err "仅 REALITY 支持更改 serverName."
        [[ -z $val || $val == auto ]] && val=$(rand_servername)
        servername=$val
        ;;
    key)
        [[ $proto_name != reality ]] && err "仅 REALITY 支持更改密钥."
        read priv_key pub_key <<<"$(get_pbk)"
        ;;
    path)
        [[ -z $path ]] && err "此协议无路径."
        [[ -z $val || $val == auto ]] && val=/$uuid
        is_test path "$val" || err "无效路径: $val"
        path=$val
        ;;
    host | domain)
        [[ -z $host ]] && err "此协议无域名."
        [[ -z $val || $val == auto ]] && err "更改域名需指定新域名."
        is_test domain "$val" || err "无效域名: $val"
        host=$val; anytls_domain=$val; test_host_dns
        ;;
    *) err "不支持的更改项: $opt. 可用: port host path pass uuid method sni key" ;;
    esac

    local newname tag ib extra=
    newname=$(inbound_name "$proto_name"); tag=${newname%.json}
    ib=$(gen_inbound "$proto_name" "$tag")
    [[ $proto_name == reality ]] && extra=$(jq -nc --arg pk "$pub_key" '[{type:"direct",tag:("pk-"+$pk)}]')
    write_inbound "$newname" "$ib" "$extra"
    [[ $newname != "$name" ]] && rm -f "$SB_INBOUND_DIR/$name"

    _green "\n已更改 $opt: $newname\n"
    sb_restart
    info "$newname"
}

# ---------- 删除 ----------
del() {
    local name; name=$(resolve_name "$1")
    [[ -z $name ]] && return
    rm -f "$SB_INBOUND_DIR/$name"
    _green "\n已删除: $name\n"
    sb_restart
}

# ---------- 列表 ----------
list() {
    [[ -d $SB_INBOUND_DIR ]] || { msg "无配置."; return; }
    local f n t any=0
    for f in "$SB_INBOUND_DIR"/*.json; do
        [[ -f $f ]] || continue
        any=1
        n=$(basename "$f")
        t=$(jq -r '.inbounds[0].type // "?"' "$f" 2>/dev/null)
        msg "  $n  ($t)"
    done
    [[ $any == 0 ]] && msg "无配置."
}

# ---------- 详情 ----------
info() {
    local name=$1 cnt
    if [[ -z $name ]]; then
        cnt=$(ls "$SB_INBOUND_DIR"/*.json 2>/dev/null | wc -l)
        case $cnt in
        0) msg "无配置."; return ;;
        1) name=$(basename "$SB_INBOUND_DIR"/*.json) ;;
        *) list; return ;;
        esac
    else
        name=$(resolve_name "$name") || exit 1
    fi
    parse_inbound "$name"
    local ip; ip=$(get_ip)
    local addr=${ip:-"<本机IP>"}
    [[ $ip == *:* ]] && addr="[$ip]"
    # 域名协议客户端连域名:443
    if [[ $host ]]; then addr=$host
    elif [[ $anytls_domain ]]; then addr=$anytls_domain; fi

    _green "\n--- $name ---\n"
    case $proto_name in
    reality)
        msg "协议     : VLESS-REALITY"
        msg "地址     : $addr"
        msg "端口     : $port"
        msg "UUID     : $uuid"
        msg "Flow     : ${flow:-xtls-rprx-vision}"
        msg "SNI      : $servername"
        msg "公钥     : $pub_key"
        ;;
    vless-ws)
        msg "协议     : VLESS-WS (无 TLS)"; msg "地址: $addr"; msg "端口: $port"; msg "UUID: $uuid"; msg "路径: $path"; msg "TLS: 无 (用于自有反代后端)"
        ;;
    hysteria2)
        msg "协议     : Hysteria2"; msg "地址: $addr"; msg "端口: $port"; msg "密码: $password"; msg "TLS: 自签 (客户端需 insecure=1)"
        ;;
    tuic)
        msg "协议     : TUIC"; msg "地址: $addr"; msg "端口: $port"; msg "UUID: $uuid"; msg "密码: $password"; msg "TLS: 自签 (客户端需 insecure=1)"
        ;;
    trojan)
        msg "协议     : Trojan"; msg "地址: $addr"; msg "端口: $port"; msg "密码: $password"; msg "TLS: 自签 (客户端需 insecure=1)"
        ;;
    vmess-ws-tls)
        msg "协议     : VMess-WS-TLS"; msg "地址: $addr"; msg "端口: $port"; msg "UUID: $uuid"; msg "路径: $path"; msg "TLS: ACME 自动证书"
        ;;
    vmess-ws)
        msg "协议     : VMess-WS (无 TLS)"; msg "地址: $addr"; msg "端口: $port"; msg "UUID: $uuid"; msg "路径: $path"; msg "TLS: 无 (用于自有反代后端)"
        ;;
    shadowsocks)
        msg "协议     : Shadowsocks"; msg "地址: $addr"; msg "端口: $port"; msg "加密: $ss_method"; msg "密码: $ss_password"
        ;;
    anytls)
        msg "协议     : AnyTLS"; msg "地址: $addr"; msg "端口: $port"; msg "密码: $password"
        [[ $anytls_domain ]] && msg "TLS: ACME 自动证书 ($anytls_domain)" || msg "TLS: 自签 (客户端需 insecure=1)"
        ;;
    esac

    local url; url=$(gen_url)
    if [[ $url ]]; then
        msg "链接     :"
        _cyan "$url"
    fi
    footer
}

footer() {
    [[ $(is_running) ]] || warn "sing-box 当前未运行 (sb start 启动)."
    msg "----------- END -----------"
    msg "文档: $(msg_ul https://github.com/$SB_REPO)"
}

# ---------- 更新 ----------
download_core() {
    local ver=$1 arch; arch=$(sb_arch)
    local tmp; tmp=$(mktemp -d)
    _wget -qO- "https://github.com/$SB_CORE_REPO/releases/download/v${ver}/sing-box-${ver}-linux-${arch}.tar.gz" \
        -O "$tmp/core.tar.gz" || err "下载核心失败."
    tar zxf "$tmp/core.tar.gz" --strip-components 1 -C "$tmp"
    cp -f "$tmp/sing-box" "$SB_BIN"; chmod +x "$SB_BIN"
    rm -rf "$tmp"
}

update() {
    local what=${1:-core}
    case $what in
    core)
        local cur latest; cur=$(sb_core_ver)
        latest=$(_wget -qO- "https://api.github.com/repos/$SB_CORE_REPO/releases/latest?v=$RANDOM" 2>/dev/null |
            grep tag_name | grep -Eo 'v[0-9.]+')
        [[ -z $latest ]] && err "获取最新版本失败."
        latest=${latest#v}
        [[ $cur == "$latest" ]] && { msg "已是最新版本: $cur"; return; }
        msg "更新 sing-box: $cur -> $latest"
        download_core "$latest"
        SB_CORE_VER=
        sb_restart
        _green "更新完成: $(sb_core_ver)\n"
        ;;
    sh)
        local tmp; tmp=$(mktemp -d)
        _wget -qO- "https://github.com/$SB_REPO/archive/refs/heads/main.tar.gz" -O "$tmp/sh.tar.gz" || err "下载脚本失败."
        tar zxf "$tmp/sh.tar.gz" --strip-components 1 -C "$tmp"
        cp -f "$tmp/sb.sh" "$SB_LIB_DIR/" 2>/dev/null
        cp -rf "$tmp"/lib/* "$SB_LIB_DIR/lib/" 2>/dev/null
        rm -rf "$tmp"
        _green "脚本已更新至最新.\n"
        ;;
    *) err "用法: sb update [core|sh]" ;;
    esac
}

# ---------- 卸载 ----------
uninstall() {
    read -rp "确认卸载 sing-box 及本脚本? [y/N]: " y
    [[ $y != [yY] ]] && { msg "已取消."; return; }
    systemctl stop sing-box 2>/dev/null
    systemctl disable sing-box 2>/dev/null
    rm -rf "$SB_CONF_DIR" "$SB_VAR_DIR" "$SB_LOG_DIR" "$SB_LIB_DIR" "$SB_BIN" "$SB_ENTRY" "$SB_SERVICE"
    _green "\n卸载完成.\n"
}

show_version() {
    msg "$(_green sing-box) $(sb_core_ver)  /  $(_cyan sb script) $SB_SH_VER"
}

# ---------- 主派发 ----------
main() {
    case $1 in
    notls | no-tls | no-auto-tls)
        export SB_NOTLS=1; shift; add "$@" ;;
    add | a) shift; add "$@" ;;
    change | c) shift; change "$@" ;;
    del | d | rm) del "$2" ;;
    info | i) info "$2" ;;
    list | ls) list ;;
    url) name=$(resolve_name "$2") || exit 1; parse_inbound "$name"; _cyan "\n$(gen_url)\n" ;;
    qr) name=$(resolve_name "$2") || exit 1; parse_inbound "$name"; show_qr ;;
    start | stop | restart | status) manage "$1" ;;
    test | t) test_run ;;
    update | u) shift; update "$@" ;;
    uninstall | un) uninstall ;;
    version | v | ver) show_version ;;
    help | h | --help) show_help ;;
    "") menu ;;
    ip) msg "$(get_ip)" ;;
    pbk) "$SB_BIN" generate reality-keypair ;;
    get-port) msg "$(get_port)" ;;
    ss2022) msg "$(get_ss2022_password 2022-blake3-chacha20-poly1305)" ;;
    generate | format | check | geoip | geosite | rule-set | tools | completion)
        "$SB_BIN" "$@" ;;
    *) err "无法识别 ($1). 用法: sb help" ;;
    esac
}
