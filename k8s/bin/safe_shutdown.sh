#!/bin/bash
set -euo pipefail

. /opt/aa/lib/aa-posix-lib.sh
#  virtualbox 直接 shutdown 会导致 mysql/ redis 缓存数据丢失；docker stop 会通知内部程序（如mysqld，让其flush完成后，再停止）


declare cmd

usage() {
    cat << EOF
Usage: $0 [options]
Options:
    -r          systemctl reboot
    -h          systemctl poweroff
EOF
    exit 1
}


# 将原始 mv /usr/sbin/shutdown /usr/sbin/sys_shutdown
# 将本文件移动到 /usr/sbin/shutdown
exec_shutdown(){
    Info "Shutdown"
    if [ -x "/usr/sbin/sys_shutdown" ]; then
        /usr/sbin/system_shutdown "$@"  # 重新 ln -s
    else
        /usr/bin/systemctl "$cmd"
    fi
}

main(){
    if ! IAmRoot; then
        exec sudo "$BASH_SOURCE" "$@"
        return 0
    fi

    while getopts "rh:" opt; do
        case "$opt" in
            r) cmd="reboot" ;;
            h) cmd="poweroff" ;;
            *) usage ;;
        esac
    done

    Warn "$cmd"
    # 检查是否有 Docker
    if ! command -v docker >/dev/null 2>&1; then
        exec_shutdown "$@"
        exit 0
    fi

    local running_containers=$(docker ps -q)
    if [ -n "$running_containers" ]; then
        Info "Stopping docker containers..."
        if ! docker stop $(docker ps -aq); then
            Panic "Failed to stop docker container"
        fi
    fi

    Info "Sync"
    sync
    sleep 1
    sync
    exec_shutdown "$@"
}

main "$@"