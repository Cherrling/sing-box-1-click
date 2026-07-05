#!/bin/bash
# service.sh — systemd 服务安装、运行管理、前台测试

# 安装 systemd 服务单元
install_service() {
    cat >"$SB_SERVICE" <<EOF
[Unit]
Description=sing-box Service
Documentation=https://sing-box.sagernet.org/
After=network.target nss-lookup.target

[Service]
User=root
NoNewPrivileges=true
ExecStart=$SB_BIN run -c $SB_MAIN_CONF -C $SB_INBOUND_DIR
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1048576
PrivateTmp=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable sing-box >/dev/null 2>&1
    systemctl daemon-reload
}

# manage <start|stop|restart|status|enable|disable> [sing-box]
manage() {
    local action=$1 svc=${2:-sing-box}
    case $action in s) action=status ;; r) action=restart ;; esac
    case $action in
    start | stop | restart | status | enable | disable)
        systemctl "$action" "$svc"
        ;;
    *) err "未知管理操作: $action" ;;
    esac
}

# 内部: 重启并校验是否起来, 失败给提示
sb_restart() {
    [[ $SB_NO_RESTART ]] && return
    systemctl restart sing-box 2>/dev/null
    sleep 1
    if pgrep -f "$SB_BIN" >/dev/null; then
        _green "sing-box 已重启.\n"
    else
        warn "sing-box 启动失败, 配置可能有误."
        msg "运行 $(_green sb test) 前台查看错误信息."
    fi
}

is_running() { pgrep -f "$SB_BIN" >/dev/null && echo ok; }

# 前台测试运行, 暴露启动错误
test_run() {
    if pgrep -f "$SB_BIN" >/dev/null; then
        _green "\nsing-box 正在运行, 跳过测试.\n"
        return
    fi
    _yellow "\n前台测试运行 sing-box (Ctrl+C 退出)...\n"
    $SB_BIN run -c "$SB_MAIN_CONF" -C "$SB_INBOUND_DIR"
}
