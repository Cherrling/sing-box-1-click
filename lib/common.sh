#!/bin/bash
# common.sh — 颜色、工具、路径常量、基础生成/校验函数
# 仅定义,不执行;供 sb.sh 与 install.sh source

# ---------- 颜色 ----------
red='\e[31m'; yellow='\e[33m'; gray='\e[90m'; green='\e[92m'
blue='\e[94m'; magenta='\e[95m'; cyan='\e[96m'; none='\e[0m'
_red()   { echo -e "${red}$*${none}"; }
_blue()  { echo -e "${blue}$*${none}"; }
_cyan()  { echo -e "${cyan}$*${none}"; }
_green() { echo -e "${green}$*${none}"; }
_yellow(){ echo -e "${yellow}$*${none}"; }
_magenta(){ echo -e "${magenta}$*${none}"; }
_red_bg(){ echo -e "\e[41m$*${none}"; }

is_err=$(_red_bg 错误!)
is_warn=$(_red_bg 警告!)

# ---------- 输出 ----------
msg()    { echo -e "$*"; }
msg_ul() { echo -e "\e[4m$*\e[0m"; }
warn()   { echo -e "\n${is_warn} $*\n" >&2; }
err()    { echo -e "\n${is_err} $*\n" >&2; [[ $SB_NO_EXIT ]] && return 1; exit 1; }
pause()  { echo; echo -ne "按 $(_green Enter) 继续, 或按 $(_red Ctrl+C) 取消."; read -rs -d $'\n'; echo; }

# ---------- 路径常量 (FHS) ----------
SB_BIN=/usr/local/bin/sing-box             # 核心二进制
SB_ENTRY=/usr/local/bin/sb                 # 管理入口(软链)
SB_LIB_DIR=/usr/local/lib/sing-box         # 脚本模块
SB_CONF_DIR=/etc/sing-box                  # 配置根(仅配置)
SB_MAIN_CONF=/etc/sing-box/config.json     # 主配置: log/dns/ntp/outbounds
SB_INBOUND_DIR=/etc/sing-box/conf          # 每入站一个 JSON 片段
SB_VAR_DIR=/var/lib/sing-box               # 生成状态(自签证书)
SB_TLS_CER=/var/lib/sing-box/tls.cer
SB_TLS_KEY=/var/lib/sing-box/tls.key
SB_LOG_DIR=/var/log/sing-box
SB_SERVICE=/etc/systemd/system/sing-box.service
SB_CORE_REPO=SagerNet/sing-box
SB_REPO=Cherrling/sing-box-1-click
SB_SH_VER=v1.0

# ---------- 环境检测 ----------
sb_pkg_cmd() { command -v apt-get || command -v yum || command -v dnf || command -v zypper; }

sb_arch() {
    case $(uname -m) in
    x86_64 | amd64) echo amd64 ;;
    aarch64 | armv8*) echo arm64 ;;
    *) err "此脚本仅支持 64 位系统..." ;;
    esac
}

# ---------- 下载 ----------
_wget() { wget --no-check-certificate "$@"; }

# ---------- 版本 ----------
SB_CORE_VER=
sb_core_ver() {
    [[ $SB_CORE_VER ]] || SB_CORE_VER=$($SB_BIN version 2>/dev/null | head -n1 | awk '{print $3}')
    echo "$SB_CORE_VER"
}
# ver_ge <cur> <min> : cur >= min 时返回真
ver_ge() { [[ $(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1) == "$2" ]]; }

# ---------- 取值生成 ----------
get_ip() {
    [[ $SB_CACHED_IP ]] && { echo "$SB_CACHED_IP"; return; }
    local t
    t=$(_wget -4 -T 5 --tries=1 -qO- https://one.one.one.one/cdn-cgi/trace 2>/dev/null | grep '^ip=' | cut -d= -f2)
    [[ -z $t ]] && t=$(_wget -6 -T 5 --tries=1 -qO- https://one.one.one.one/cdn-cgi/trace 2>/dev/null | grep '^ip=' | cut -d= -f2)
    SB_CACHED_IP=$t
    echo "$t"
}

get_uuid() { cat /proc/sys/kernel/random/uuid; }

# 随机可用端口 (445-65535, 未占用)
get_port() {
    local p c=0
    while :; do
        ((c++)); [[ $c -ge 233 ]] && err "自动获取可用端口失败次数过多, 请检查端口占用."
        p=$((RANDOM % 65091 + 445))
        [[ -z $(is_port_used "$p") ]] && { echo "$p"; return; }
    done
}

# reality 密钥对: 输出 "PrivateKey PublicKey"
get_pbk() {
    local out
    out=$($SB_BIN generate reality-keypair 2>/dev/null)
    local priv pub
    priv=$(awk '/PrivateKey/{print $2}' <<<"$out")
    pub=$(awk '/PublicKey/{print $2}' <<<"$out")
    echo "$priv $pub"
}

# SS-2022 密码: aes-128 用 16 字节, 其余 32 字节
get_ss2022_password() {
    [[ $1 == *128* ]] && $SB_BIN generate rand 16 --base64 || $SB_BIN generate rand 32 --base64
}

# ---------- 端口占用 ----------
_SB_USED_PORTS=
is_port_used() {
    [[ $1 ]] || return
    [[ -z $_SB_USED_PORTS ]] && {
        if [[ $(command -v ss) ]]; then
            _SB_USED_PORTS=$(ss -tunlp 2>/dev/null | sed -n 's/.*:\([0-9]\+\).*/\1/p' | sort -nu)
        elif [[ $(command -v netstat) ]]; then
            _SB_USED_PORTS=$(netstat -tunlp 2>/dev/null | sed -n 's/.*:\([0-9]\+\).*/\1/p' | sort -nu)
        fi
    }
    [[ -n $_SB_USED_PORTS ]] && grep -qx "$1" <<<"$_SB_USED_PORTS" && echo ok
}

# ---------- 校验 ----------
is_test() {
    case $1 in
    number) echo "$2" | grep -Eq '^[1-9][0-9]*$' ;;
    port)   is_test number "$2" && [[ $2 -le 65535 ]] && echo ok ;;
    domain) echo "$2" | grep -Eqi '^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$' ;;
    path)   echo "$2" | grep -Eq '^/[A-Za-z0-9]([A-Za-z0-9_/-]*[A-Za-z0-9])?$' ;;
    uuid)   echo "$2" | grep -Eqi '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' ;;
    esac
}

# ---------- reality 伪装域名 ----------
SB_SERVERNAMES=(www.amazon.com www.ebay.com www.paypal.com www.cloudflare.com dash.cloudflare.com aws.amazon.com)
rand_servername() { echo "${SB_SERVERNAMES[$((RANDOM % ${#SB_SERVERNAMES[@]}))]}"; }

# ---------- 自签证书 ----------
ensure_tls_cert() {
    [[ -f $SB_TLS_CER && -f $SB_TLS_KEY ]] && return
    mkdir -p "$SB_VAR_DIR"
    local tmp=$SB_VAR_DIR/tls.tmp
    $SB_BIN generate tls-keypair tls -m 456 >"$tmp" 2>/dev/null || err "生成自签证书失败."
    awk '/BEGIN PRIVATE KEY/,/END PRIVATE KEY/' "$tmp" >"$SB_TLS_KEY"
    awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' "$tmp" >"$SB_TLS_CER"
    rm -f "$tmp"
}

# ---------- 证书 pin (SHA-256) ----------
# 用法: get_cert_pin [sb|mihomo] [cer_path]
#   sb    = base64(SHA256(SPKI DER))  → sing-box tls.certificate_public_key_sha256 (1.13.0+)
#   mihomo= hex(SHA256(cert DER))     → mihomo fingerprint (带冒号大写)
# 仅对自签证书有意义 (ACME 证书会更新, pin 不稳定)
get_cert_pin() {
    local fmt="${1:-sb}" cer="${2:-$SB_TLS_CER}"
    command -v openssl >/dev/null || { warn "openssl 未安装, 无法计算 pin."; return; }
    [[ -f $cer ]] || return
    case $fmt in
    sb)
        openssl x509 -in "$cer" -pubkey -noout 2>/dev/null |
            openssl pkey -pubin -outform der 2>/dev/null |
            openssl dgst -sha256 -binary | base64
        ;;
    mihomo)
        openssl x509 -noout -fingerprint -sha256 -inform pem -in "$cer" 2>/dev/null |
            sed 's/.*=//'
        ;;
    *) err "未知 pin 格式: $fmt (可用: sb mihomo)" ;;
    esac
}
