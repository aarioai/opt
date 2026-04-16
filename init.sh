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
  echo ' >>> no change owner. or Usage: ./init.sh [chg_owner] [chg_group]'
  chg_owner="${1:-}"
  chg_group="${2:-}"

  chgOwner "$chg_owner" "$chg_group"

  find "/opt" -type d -name "bin" -exec chmod a+x {} \; 2>/dev/null
  find "/opt" -type f -name "*.sh" -exec chmod a+x {} \; 2>/dev/null
  echo ' >>> [done]'
}

main "$@"