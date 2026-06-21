#!/bin/bash
# install.sh — sing-box 一键脚本安装器
# 用法: bash install.sh [-l] [-v <ver>] [-p <proxy>] [-f <core.tar.gz>]
#   -l  本地安装(使用当前目录的 sb.sh 与 lib/)
#   -v  指定 sing-box 版本, 如 -v 1.13.13
#   -p  使用代理下载, 如 -p http://127.0.0.1:7890
#   -f  使用本地核心压缩包

author=Cherrling
repo=$author/sing-box-1-click
core_repo=SagerNet/sing-box

# ---------- 基础(安装器自带的极简工具, 后续会 source lib 覆盖) ----------
red='\e[31m'; green='\e[92m'; yellow='\e[33m'; cyan='\e[96m'; none='\e[0m'
msg()  { echo -e "$*"; }
_green(){ echo -e "${green}$*${none}"; }
_yellow(){ echo -e "${yellow}$*${none}"; }
_cyan(){ echo -e "${cyan}$*${none}"; }
err()  { echo -e "\n\e[41m错误!${none} $*\n" >&2; exit 1; }
_wget() { [[ $proxy ]] && export https_proxy=$proxy http_proxy=$proxy; wget --no-check-certificate "$@"; }

[[ $EUID != 0 ]] && err "需要 ROOT 用户运行."

cmd=$(command -v apt-get || command -v yum || command -v dnf || command -v zypper)
[[ -z $cmd ]] && err "仅支持 apt/yum/dnf/zypper 系统 (systemd)."
[[ -z $(command -v systemctl) ]] && err "未找到 systemctl, 仅支持 systemd 系统."

case $(uname -m) in
x86_64 | amd64) arch=amd64 ;;
aarch64 | armv8*) arch=arm64 ;;
*) err "仅支持 64 位系统." ;;
esac

# ---------- 参数 ----------
local_install=; core_ver=; proxy=; core_file=
while [[ $# -gt 0 ]]; do
    case $1 in
    -l) local_install=1; shift ;;
    -v) core_ver=${2#v}; shift 2 ;;
    -p) proxy=$2; shift 2 ;;
    -f) core_file=$2; shift 2 ;;
    -h | --help)
        msg "用法: bash install.sh [-l] [-v <ver>] [-p <proxy>] [-f <core.tar.gz>]"; exit 0 ;;
    *) err "未知参数: $1" ;;
    esac
done

# ---------- 依赖 ----------
install_pkgs() {
    local need= p
    for p in "$@"; do [[ -z $(command -v "$p") ]] && need="$need $p"; done
    [[ -z $need ]] && return
    _yellow "安装依赖:$need\n"
    if [[ $cmd == *apt* ]]; then
        apt-get update -y >/dev/null 2>&1; apt-get install -y $need >/dev/null 2>&1
    elif [[ $cmd == *dnf* ]]; then
        dnf install -y $need >/dev/null 2>&1
    elif [[ $cmd == *yum* ]]; then
        yum install -y $need >/dev/null 2>&1
    elif [[ $cmd == *zypper* ]]; then
        zypper --non-interactive install $need >/dev/null 2>&1
    fi
}
install_pkgs wget tar jq qrencode

clear
echo
echo "........... sing-box 一键脚本 by $author .........."
echo
_yellow "开始安装...\n"

# ---------- 目录 ----------
mkdir -p /etc/sing-box/conf /var/lib/sing-box /var/log/sing-box /usr/local/lib/sing-box/lib /usr/local/bin

# ---------- 核心 ----------
SB_BIN=/usr/local/bin/sing-box
if [[ -n $core_file ]]; then
    _yellow "使用本地核心: $core_file\n"
    tar zxf "$core_file" --strip-components 1 -C /usr/local/bin 2>/dev/null || cp -f "$core_file" "$SB_BIN"
elif [[ -n $local_install && -x $SB_BIN ]]; then
    _yellow "已存在本地核心, 跳过下载.\n"
else
    [[ -z $core_ver ]] && core_ver=$(_wget --timeout=15 --tries=2 -qO- "https://api.github.com/repos/$core_repo/releases/latest?v=$RANDOM" 2>/dev/null |
        grep tag_name | grep -Eo 'v[0-9.]+' | head -1)
    core_ver=${core_ver#v}
    [[ -z $core_ver ]] && err "获取 sing-box 最新版本失败."
    _yellow "下载 sing-box v$core_ver ...\n"
    _wget --timeout=60 --tries=2 -qO /tmp/sbcore.tar.gz \
        "https://github.com/$core_repo/releases/download/v${core_ver}/sing-box-${core_ver}-linux-${arch}.tar.gz" || err "下载核心失败."
    tar zxf /tmp/sbcore.tar.gz --strip-components 1 -C /usr/local/bin
    rm -f /tmp/sbcore.tar.gz
fi
[[ -x $SB_BIN ]] || err "核心安装失败: $SB_BIN 不存在."
chmod +x "$SB_BIN"

# ---------- 脚本 ----------
if [[ -n $local_install ]]; then
    [[ -f $PWD/sb.sh && -d $PWD/lib ]] || err "当前目录非完整脚本目录: $PWD"
    cp -f "$PWD/sb.sh" /usr/local/lib/sing-box/
    cp -f "$PWD"/lib/*.sh /usr/local/lib/sing-box/lib/
    _yellow "本地安装脚本 > $PWD\n"
else
    _yellow "下载脚本...\n"
    tmp=$(mktemp -d)
    _wget --timeout=30 --tries=2 -qO "$tmp/sh.tar.gz" "https://codeload.github.com/$repo/tar.gz/refs/heads/main" || err "下载脚本失败."
    tar zxf "$tmp/sh.tar.gz" --strip-components 1 -C "$tmp"
    cp -f "$tmp/sb.sh" /usr/local/lib/sing-box/
    cp -f "$tmp"/lib/*.sh /usr/local/lib/sing-box/lib/
    rm -rf "$tmp"
fi
chmod +x /usr/local/lib/sing-box/sb.sh
ln -sf /usr/local/lib/sing-box/sb.sh /usr/local/bin/sb

# ---------- source lib, 完成初始化 ----------
export SB_LIB_DIR=/usr/local/lib/sing-box
for _f in common proto service share manage; do . "$SB_LIB_DIR/lib/$_f.sh"; done
unset _f

_green "生成自签证书与配置...\n"
ensure_tls_cert

# 主配置
jq -nc '{log:{output:"/var/log/sing-box/access.log",level:"info",timestamp:true},
         dns:{}, ntp:{enabled:true,server:"time.apple.com"},
         outbounds:[{tag:"direct",type:"direct"}]}' > "$SB_MAIN_CONF"

install_service
systemctl enable --now sing-box >/dev/null 2>&1

echo
_green "安装完成!\n"
msg "运行 $(_cyan sb) 进入菜单, 或 $(_cyan 'sb add r') 添加第一个配置."
msg "文档: https://github.com/$repo"
echo
