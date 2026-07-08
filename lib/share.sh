#!/bin/bash
# share.sh — 分享链接、二维码、交互菜单、帮助

# 生成分享链接 (使用 parse_inbound 设置的全局)
gen_url() {
    local addr ip
    if [[ $host ]]; then addr=$host
    elif [[ $anytls_domain ]]; then addr=$anytls_domain
    else
        ip=$(get_ip); addr=${ip:-"<IP>"}
        [[ $ip == *:* ]] && addr="[$ip]"
    fi
    local p=$port
    case $proto_name in
    reality)
        echo "vless://$uuid@$addr:$p?encryption=none&security=reality&flow=${flow:-xtls-rprx-vision}&type=tcp&sni=$servername&pbk=$pub_key&fp=chrome#sb-reality"
        ;;
    vless-ws)
        echo "vless://$uuid@$addr:$p?encryption=none&type=ws&path=$path#sb-vless-ws"
        ;;
    hysteria2)
        echo "hysteria2://$password@$addr:$p?insecure=1&alpn=h3#sb-hy2"
        ;;
    tuic)
        echo "tuic://$uuid:$password@$addr:$p?congestion_control=bbr&alpn=h3&insecure=1#sb-tuic"
        ;;
    trojan)
        echo "trojan://$password@$addr:$p?security=tls&insecure=1&type=tcp#sb-trojan"
        ;;
    vmess-ws-tls)
        local j; j=$(jq -nc --arg ps "sb-vmess-$host" --arg add "$host" --argjson port "$p" \
            --arg id "$uuid" --arg host "$host" --arg path "$path" \
            '{v:2,ps:$ps,add:$add,port:$port,id:$id,aid:"0",net:"ws",host:$host,path:$path,tls:"tls"}')
        echo "vmess://$(echo -n "$j" | base64 -w 0)"
        ;;
    vmess-ws)
        local j; j=$(jq -nc --arg ps "sb-vmess-$addr" --arg add "$addr" --argjson port "$p" \
            --arg id "$uuid" --arg path "$path" \
            '{v:2,ps:$ps,add:$add,port:$port,id:$id,aid:"0",net:"ws",path:$path}')
        echo "vmess://$(echo -n "$j" | base64 -w 0)"
        ;;
    shadowsocks)
        echo "ss://$(echo -n "$ss_method:$ss_password" | base64 -w 0)@$addr:$p#sb-ss"
        ;;
    anytls)
        # 自签 (has_acme!=1) 需 insecure=1; ACME 不需要. 有 domain 时 addr=domain (作 SNI)
        if [[ $has_acme == 1 ]]; then
            echo "anytls://$password@$addr:$p#sb-anytls"
        else
            echo "anytls://$password@$addr:$p?insecure=1#sb-anytls"
        fi
        ;;
    esac
}

show_qr() {
    local url; url=$(gen_url)
    [[ -z $url ]] && { warn "无法生成二维码."; return; }
    msg "\n--- 二维码 ---\n"
    if [[ $(command -v qrencode) ]]; then
        qrencode -t ANSI "$url"
    else
        msg "未安装 qrencode, 请用上方链接."
    fi
    msg "\n链接: $url\n"
}

# ---------- 交互选择 ----------
# read_pick <count> : 读取 1..count 的选择并回显(1-based); 取消/无效返回非0
read_pick() {
    local cnt=$1 sel
    read -rp "选择 [1-$cnt] (0=取消): " sel
    [[ $sel =~ ^[0-9]+$ ]] && (( 10#$sel >= 1 && 10#$sel <= cnt )) && echo "$((10#$sel))"
}

# pick_inbound : 列出所有配置供选择, 回显文件名(含.json); 取消返回非0
# 菜单展示走 stderr, 仅文件名走 stdout (供 $(...) 捕获)
pick_inbound() {
    [[ -d $SB_INBOUND_DIR ]] || { warn "配置目录不存在, 请先安装: bash install.sh"; return 1; }
    local files=() f t i=0
    for f in "$SB_INBOUND_DIR"/*.json; do
        [[ -f $f ]] || continue
        files+=("$(basename "$f")")
    done
    local cnt=${#files[@]}
    [[ $cnt -eq 0 ]] && { warn "无配置, 请先添加: sb add"; return 1; }
    {
        _green "\n当前配置:\n"
        for f in "${files[@]}"; do
            t=$(jq -r '.inbounds[0].type // "?"' "$SB_INBOUND_DIR/$f" 2>/dev/null)
            ((i++))
            msg "  $i) $f  ($t)"
        done
        echo
    } >&2
    local sel; sel=$(read_pick "$cnt") || { msg "已取消." >&2; return 1; }
    echo "${files[$((sel-1))]}"
}

# pick_change_opt <name> : 列出该配置可更改的项, 回显选项名; 取消返回非0
# 可改项随协议不同 (依据 parse_inbound 解析出的字段推导)
pick_change_opt() {
    parse_inbound "$1"
    local opts=() labels=()
    [[ $has_acme != 1 ]]                          && { opts+=(port);   labels+=("端口 port"); }
    [[ $host || $anytls_domain ]]                 && { opts+=(host);   labels+=("域名 host"); }
    [[ $path ]]                                   && { opts+=(path);   labels+=("路径 path"); }
    [[ $password || $proto_name == shadowsocks ]] && { opts+=(pass);   labels+=("密码 pass"); }
    [[ $uuid ]]                                   && { opts+=(uuid);   labels+=("UUID"); }
    [[ $proto_name == shadowsocks ]]              && { opts+=(method); labels+=("加密方式 method"); }
    [[ $proto_name == reality ]]                  && { opts+=(sni);    labels+=("伪装域名 sni"); }
    [[ $proto_name == reality ]]                  && { opts+=(key);    labels+=("密钥 key (重新生成)"); }
    local cnt=${#opts[@]}
    [[ $cnt -eq 0 ]] && { warn "此配置无可更改项."; return 1; }
    {
        _green "\n可更改项:\n"
        local i
        for ((i=0; i<cnt; i++)); do msg "  $((i+1))) ${labels[i]}"; done
        echo
    } >&2
    local sel; sel=$(read_pick "$cnt") || { msg "已取消." >&2; return 1; }
    echo "${opts[$((sel-1))]}"
}

# prompt_change_val <opt> : 依选项提示输入新值, 回显值(可空=auto); 取消返回非0
prompt_change_val() {
    local opt=$1 sel val items i
    case $opt in
    key)
        msg "\n将重新生成 REALITY 密钥对." >&2
        echo ""
        ;;
    method)
        items=("${SB_SS_METHODS[@]}")
        {
            _green "\n可选加密方式:\n"
            for i in "${!items[@]}"; do msg "  $((i+1))) ${items[i]}"; done
            echo
        } >&2
        sel=$(read_pick "${#items[@]}") || { msg "已取消." >&2; return 1; }
        echo "${items[$((sel-1))]}"
        ;;
    sni)
        items=("${SB_SERVERNAMES[@]}" "随机 auto")
        {
            _green "\n可选伪装域名:\n"
            for i in "${!items[@]}"; do msg "  $((i+1))) ${items[i]}"; done
            echo
        } >&2
        sel=$(read_pick "${#items[@]}") || { msg "已取消." >&2; return 1; }
        [[ ${items[$((sel-1))]} == "随机 auto" ]] && echo auto || echo "${items[$((sel-1))]}"
        ;;
    *)
        read -rp "新值 (留空=自动生成): " val
        echo "$val"
        ;;
    esac
}

# pick_service_action : 列出服务操作供选择, 回显动作名; 取消返回非0
pick_service_action() {
    local actions=(start stop restart status)
    local labels=("启动 start" "停止 stop" "重启 restart" "状态 status")
    {
        _green "\n服务管理:\n"
        local i
        for ((i=0; i<${#actions[@]}; i++)); do msg "  $((i+1))) ${labels[i]}"; done
        echo
    } >&2
    local sel; sel=$(read_pick "${#actions[@]}") || { msg "已取消." >&2; return 1; }
    echo "${actions[$((sel-1))]}"
}

# 交互菜单 (动作在子 shell 中执行, 避免 err 退出菜单)
menu() {
    while :; do
        _green "\n--- sb (sing-box 一键脚本) $SB_SH_VER ---\n"
        msg "  1) 添加配置    2) 更改配置    3) 查看配置"
        msg "  4) 删除配置    5) 列出配置    6) 服务管理"
        msg "  7) 测试运行    8) 更新        9) 卸载"
        msg "  h) 帮助        q) 退出"
        read -rp "选择: " c
        local n a o v y
        case $c in
        1) (add) ;;
        2) n=$(pick_inbound) || { echo; continue; }
           o=$(pick_change_opt "$n") || { echo; continue; }
           v=$(prompt_change_val "$o") || { echo; continue; }
           (change "$n" "$o" "$v") ;;
        3) n=$(pick_inbound) || { echo; continue; }
           (info "$n") ;;
        4) n=$(pick_inbound) || { echo; continue; }
           read -rp "确认删除 $n ? [y/N]: " y
           if [[ $y == [yY] ]]; then (del "$n"); else msg "已取消."; fi ;;
        5) list ;;
        6) a=$(pick_service_action) || { echo; continue; }
           manage "$a" ;;
        7) (test_run) ;;
        8) (update) ;;
        9) (uninstall) ;;
        h | H) show_help ;;
        q | Q | '') return ;;
        *) msg "无效选择" ;;
        esac
    done
}

show_help() {
    cat <<EOF
sb (sing-box 一键脚本) $SB_SH_VER

用法: sb <命令> [参数]

配置:
   add [proto] [args|auto]         添加配置
   change <name> <opt> [val|auto]  更改 (opt: port host path pass uuid method sni key)
   del <name>                      删除配置
   info [name]                     查看配置
   list                            列出配置
   url [name]                      显示分享链接
   qr [name]                       显示二维码

管理:
   start|stop|restart|status       服务管理 (别名: s=status, r=restart)
   test                            前台测试运行
   update [core|sh]                更新核心/脚本
   uninstall                       卸载

其他:
   version / ip / pbk / get-port / ss2022
   pin [name] [sb|mihomo]         证书 SHA-256 pin (自签协议)
   generate ...                    透传 sing-box 命令
   help                            此帮助

协议: reality(默认) hysteria2 tuic trojan vmess-ws-tls(需域名) shadowsocks anytls

示例:
   sb add r                    添加 VLESS-REALITY (全自动)
   sb add hy2                  添加 Hysteria2
   sb add vws example.com      添加 VMess-WS-TLS
   sb add ss                   添加 Shadowsocks-2022
   sb info reality-12345       查看配置
   sb change reality-12345 sni auto   更换 REALITY 伪装域名
EOF
}
