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
        if [[ $anytls_domain ]]; then
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

# 交互菜单 (动作在子 shell 中执行, 避免 err 退出菜单)
menu() {
    while :; do
        _green "\n--- sb (sing-box 一键脚本) $SB_SH_VER ---\n"
        msg "  1) 添加配置    2) 更改配置    3) 查看配置"
        msg "  4) 删除配置    5) 列出配置    6) 服务管理"
        msg "  7) 测试运行    8) 更新        9) 卸载"
        msg "  h) 帮助        q) 退出"
        read -rp "选择: " c
        local n a
        case $c in
        1) (add) ;;
        2) read -rp "配置名: " n
           [[ $n ]] && { read -rp "更改项(port host path pass uuid method sni key): " o
                         read -rp "新值(auto=自动): " v; (change "$n" "$o" "$v"); } ;;
        3) read -rp "配置名(留空列全部): " n; [[ -z $n ]] && list || (info "$n") ;;
        4) read -rp "配置名: " n; [[ $n ]] && (del "$n") ;;
        5) list ;;
        6) read -rp "start|stop|restart|status: " a; [[ $a ]] && manage "$a" ;;
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
   start|stop|restart|status       服务管理
   test                            前台测试运行
   update [core|sh]                更新核心/脚本
   uninstall                       卸载

其他:
   version / ip / pbk / get-port / ss2022
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
