#!/bin/sh

set -eu


chgOwner(){
  user="${1:-}"
  group="${2:-}"
  if [ -z "$user" ]; then
    return
  fi
  if [ "$user" = "me" ]; then
    user="$(whoami)"
  fi

  if [ -z "$group" ]; then
    echo "chown -R $user /opt/aa"
    chown -R "$user" /opt/aa
    return
  fi

  echo "chown -R ${user}:${group} /opt/aa"
  chown -R "$user":"$group" /opt/aa
}


main(){
  if [ "$(id -u)" != '0' ]; then
    echo '[error] sudo ./init.sh [chg_owner] [chg_group]'
    exit 1
  fi
  chg_owner="${1:-}"
  chg_group="${2:-}"

  chgOwner "$chg_owner" "$chg_group"

  # 兼容软链接子目录
  find -L /opt -type d -name "bin" -exec chmod -R a+x {} \;
  find -L /opt -type f -name "*.sh" -exec chmod a+x {} \;
  echo ' >>> [done]'
}

main "$@"