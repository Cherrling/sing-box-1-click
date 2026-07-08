#!/bin/bash
# proto.sh — 协议归一、JSON 生成(jq 模板)、写入、反读
# 生成器读取 add() 预设的全局变量: port uuid password servername
#   priv_key pub_key host path ss_method ss_password anytls_domain

# ---------- 协议归一 ----------
normalize_protocol() {
    case "${1,,}" in
    r | reality | vless-reality)    echo reality ;;
    vless-ws)                       echo vless-ws ;;
    hy | hy2 | hysteria2 | hysteria*) echo hysteria2 ;;
    tuic)                           echo tuic ;;
    trojan)                         echo trojan ;;
    vws | vmess-ws-tls)          echo vmess-ws-tls ;;
    vmess-ws)                    echo vmess-ws ;;
    ss | shadowsocks | ss2022)   echo shadowsocks ;;
    anytls)                      echo anytls ;;
    *) err "无法识别协议 ($1). 可用: reality vless-ws hysteria2 tuic trojan vmess-ws-tls vmess-ws shadowsocks anytls" ;;
    esac
}

# 协议默认参数提示
proto_args_hint() {
    case "$1" in
    reality)        echo "[port] [uuid] [sni]" ;;
    vless-ws)       echo "[port] [uuid] [/path]" ;;
    hysteria2)      echo "[port] [password]" ;;
    tuic)           echo "[port] [uuid]" ;;
    trojan)         echo "[port] [password]" ;;
    vmess-ws-tls)   echo "[domain] [uuid] [/path]" ;;
    vmess-ws)       echo "[port] [uuid] [/path]" ;;
    shadowsocks)    echo "[port] [password] [method]" ;;
    anytls)         echo "[port] [password] [domain]  (domain 无端口→ACME 443; domain+端口→自签自定义SNI)" ;;
    esac
}

# ---------- 版本要求 ----------
require_core() {
    ver_ge "$(sb_core_ver)" "$1" || err "当前 sing-box ($(sb_core_ver)) 版本过低, 需要 >= $1. 请运行: sb update core"
}

# ---------- TLS 辅助 (输出 JSON 对象) ----------
# 自签证书 (无域名协议: hy2/tuic/trojan/anytls-无域名)
gen_selfsigned_tls() {
    local alpn="$1"
    jq -nc --arg k "$SB_TLS_KEY" --arg c "$SB_TLS_CER" --arg alpn "$alpn" '
        {enabled:true, key_path:$k, certificate_path:$c}
        + (if $alpn != "" then {alpn:[$alpn]} else {} end)'
}

# 原生 ACME (域名协议: vmess-ws-tls / anytls-有域名). 版本感知 schema
gen_acme_tls() {
    local domain="$1"
    if ver_ge "$(sb_core_ver)" 1.14; then
        jq -nc --arg d "$domain" '{enabled:true,certificate_provider:{type:"acme",domain:[$d]}}'
    else
        jq -nc --arg d "$domain" '{enabled:true,acme:{domain:[$d]}}'
    fi
}

# ---------- 入站生成器 (各输出一个入站对象) ----------
gen_inbound_reality() {
    jq -n --arg tag "$1" --argjson port "$port" --arg uuid "$uuid" \
          --arg sni "$servername" --arg pk "$priv_key" '
    {tag:$tag, type:"vless", listen:"::", listen_port:$port,
     users:[{uuid:$uuid, flow:"xtls-rprx-vision"}],
     tls:{enabled:true, server_name:$sni,
          reality:{enabled:true, handshake:{server:$sni, server_port:443},
                   private_key:$pk, short_id:[""]}}}'
}

gen_inbound_hysteria2() {
    local tls; tls=$(gen_selfsigned_tls h3)
    jq -n --arg tag "$1" --argjson port "$port" --arg pass "$password" --argjson tls "$tls" '
    {tag:$tag, type:"hysteria2", listen:"::", listen_port:$port,
     users:[{password:$pass}], tls:$tls}'
}

gen_inbound_tuic() {
    local tls; tls=$(gen_selfsigned_tls h3)
    jq -n --arg tag "$1" --argjson port "$port" --arg uuid "$uuid" \
          --arg pass "$password" --argjson tls "$tls" '
    {tag:$tag, type:"tuic", listen:"::", listen_port:$port,
     users:[{uuid:$uuid, password:$pass}], congestion_control:"bbr", tls:$tls}'
}

gen_inbound_trojan() {
    local tls; tls=$(gen_selfsigned_tls)
    jq -n --arg tag "$1" --argjson port "$port" --arg pass "$password" --argjson tls "$tls" '
    {tag:$tag, type:"trojan", listen:"::", listen_port:$port,
     users:[{password:$pass}], tls:$tls}'
}

gen_inbound_vmess_ws_tls() {
    # 域名协议: ACME 需监听 443
    port=443
    local tls; tls=$(gen_acme_tls "$host")
    jq -n --arg tag "$1" --argjson port "$port" --arg uuid "$uuid" \
          --arg host "$host" --arg path "$path" --argjson tls "$tls" '
    {tag:$tag, type:"vmess", listen:"::", listen_port:$port,
     users:[{uuid:$uuid}], tls:$tls,
     transport:{type:"ws", path:$path, headers:{host:$host}}}'
}

gen_inbound_vless_ws() {
    # 无 TLS (notls): VLESS over WS, 用于自有反代后端, 不需要域名/证书
    jq -n --arg tag "$1" --argjson port "$port" --arg uuid "$uuid" --arg path "$path" '
    {tag:$tag, type:"vless", listen:"::", listen_port:$port,
     users:[{uuid:$uuid}], transport:{type:"ws", path:$path}}'
}

gen_inbound_vmess_ws() {
    # 无 TLS (notls): 用于自有反代(nginx/caddy)后端, 不需要域名/证书
    jq -n --arg tag "$1" --argjson port "$port" --arg uuid "$uuid" --arg path "$path" '
    {tag:$tag, type:"vmess", listen:"::", listen_port:$port,
     users:[{uuid:$uuid}], transport:{type:"ws", path:$path}}'
}

gen_inbound_shadowsocks() {
    jq -n --arg tag "$1" --argjson port "$port" --arg method "$ss_method" --arg pass "$ss_password" '
    {tag:$tag, type:"shadowsocks", listen:"::", listen_port:$port,
     method:$method, password:$pass}'
}

gen_inbound_anytls() {
    local tls
    if [[ $has_acme == 1 ]]; then
        tls=$(gen_acme_tls "$anytls_domain")
    else
        tls=$(gen_selfsigned_tls)
        # 自签 + 指定 SNI 域名: 写入 server_name (端口可自定义, 客户端 insecure=1)
        [[ $anytls_domain ]] && tls=$(jq --arg d "$anytls_domain" '. + {server_name:$d}' <<<"$tls")
    fi
    jq -n --arg tag "$1" --argjson port "$port" --arg pass "$password" --argjson tls "$tls" '
    {tag:$tag, type:"anytls", listen:"::", listen_port:$port,
     users:[{password:$pass}], tls:$tls}'
}

# 统一派发: gen_inbound <proto> <name>
gen_inbound() {
    case "$1" in
    reality)       gen_inbound_reality "$2" ;;
    vless-ws)      gen_inbound_vless_ws "$2" ;;
    hysteria2)     gen_inbound_hysteria2 "$2" ;;
    tuic)          gen_inbound_tuic "$2" ;;
    trojan)        gen_inbound_trojan "$2" ;;
    vmess-ws-tls)  gen_inbound_vmess_ws_tls "$2" ;;
    vmess-ws)      gen_inbound_vmess_ws "$2" ;;
    shadowsocks)   gen_inbound_shadowsocks "$2" ;;
    anytls)        gen_inbound_anytls "$2" ;;
    *) err "未知协议: $1" ;;
    esac
}

# ---------- 写入 ----------
# write_inbound <name> <inbound_json> [extra_outbounds_json]
write_inbound() {
    local name="$1" inbound="$2" extra="$3"
    mkdir -p "$SB_INBOUND_DIR"
    if [[ $extra ]]; then
        jq -nc --argjson ib "$inbound" --argjson ob "$extra" \
            '{inbounds:[$ib], outbounds:$ob}' >"$SB_INBOUND_DIR/$name"
    else
        jq -nc --argjson ib "$inbound" '{inbounds:[$ib]}' >"$SB_INBOUND_DIR/$name"
    fi
}

# 派生配置文件名: 有域名用 proto-host, 否则 proto-port
inbound_name() {
    local proto="$1"
    if [[ $host || $anytls_domain ]]; then
        echo "${proto}-${host}${anytls_domain}.json"
    else
        echo "${proto}-${port}.json"
    fi
}

# ---------- 反读 ----------
# parse_inbound <name> : 把字段读入全局, 并设置 proto_name
parse_inbound() {
    local f="$SB_INBOUND_DIR/$1"
    [[ -f $f ]] || err "找不到配置: $1"
    local ib
    ib=$(jq '.inbounds[0]' "$f") || err "无法读取配置: $1"

    proto=$(jq -r '.type' <<<"$ib")
    port=$(jq -r '.listen_port' <<<"$ib")
    uuid=$(jq -r '.users[0].uuid // empty' <<<"$ib")
    password=$(jq -r '.users[0].password // empty' <<<"$ib")
    flow=$(jq -r '.users[0].flow // empty' <<<"$ib")
    ss_method=$(jq -r '.method // empty' <<<"$ib")
    ss_password=$(jq -r '.password // empty' <<<"$ib")
    net=$(jq -r '.transport.type // empty' <<<"$ib")
    path=$(jq -r '.transport.path // empty' <<<"$ib")
    host=$(jq -r '.transport.headers.host // empty' <<<"$ib")
    servername=$(jq -r '.tls.server_name // empty' <<<"$ib")
    priv_key=$(jq -r '.tls.reality.private_key // empty' <<<"$ib")
    pub_key=$(jq -r '.outbounds[]?.tag | select(type=="string" and (startswith("pk-") or startswith("public_key_"))) | sub("^pk-|^public_key_"; "")' <<<"$(cat "$f")")
    # reality 的 server_name 是伪装 SNI (非连接域名), 不应落入 anytls_domain;
    # 仅 anytls 自签自定义 SNI 时 server_name 才是真正的连接域名
    anytls_domain=$(jq -r 'if .tls.reality then empty
                          else (.tls.acme.domain[0] // .tls.certificate_provider.domain[0] // .tls.server_name // empty) end' <<<"$ib")
    has_acme=$(jq -r 'if (.tls.acme // .tls.certificate_provider) then 1 else 0 end' <<<"$ib")

    case "$proto" in
    vless)
        if [[ $priv_key ]]; then proto_name=reality
        else proto_name=vless-ws; fi
        ;;
    vmess)
        if [[ $has_acme == 1 ]]; then proto_name=vmess-ws-tls
        else proto_name=vmess-ws; fi
        ;;
    *)     proto_name=$proto ;;
    esac
    SB_PARSED_NAME="$1"
}

# ---------- 名称解析 ----------
# resolve_name [user_input] : 无输入且仅一配置时自动选用; 返回文件名(含.json)
resolve_name() {
    local n="$1"
    [[ -d $SB_INBOUND_DIR ]] || err "配置目录不存在, 请先安装: bash install.sh"
    if [[ -z $n ]]; then
        local files cnt
        files=$(ls "$SB_INBOUND_DIR"/*.json 2>/dev/null)
        cnt=$(grep -c . <<<"$files")
        [[ $cnt -eq 1 ]] && { basename "$files"; return; }
        err "请指定配置名; 查看: sb list"
    fi
    [[ $n == *.json ]] || n="$n.json"
    [[ -f $SB_INBOUND_DIR/$n ]] && { echo "$n"; return; }
    err "找不到配置: $1 (查看: sb list)"
}
