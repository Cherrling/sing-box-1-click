#!/bin/bash
# sb — sing-box 一键脚本入口
export SB_LIB_DIR=/usr/local/lib/sing-box
for _f in common proto service share manage; do
    . "$SB_LIB_DIR/lib/$_f.sh"
done
unset _f
main "$@"
