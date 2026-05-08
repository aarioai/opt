#!/bin/sh
set -eu

# https://github.com/aarioai/opt
if [ -x "./aa-posix-lib.sh" ]; then . ./aa-posix-lib.sh; else . /opt/aa/lib/aa-posix-lib.sh; fi

# 必须安装 yq v4+
UpgradeYq(){
  UpdateSUDO

  _installyq_os=$(uname -s | tr '[:upper:]' '[:lower:]')
  _installyq_arch=$(uname -m)
  case "$_installyq_arch" in
    x86_64) _installyq_arch="amd64" ;;
    aarch64|arm64) _installyq_arch="arm64" ;;
    armv7l) _installyq_arch="armv7" ;;
  esac

  _installyq_url="https://github.com/mikefarah/yq/releases/latest/download/yq_${_installyq_os}_${_installyq_arch}"

  g_temp_file=$(mktemp) || return 1
  trap 'rm -f "$g_temp_file" 2>/dev/null' EXIT
  trap 'rm -f "$g_temp_file" 2>/dev/null; return 1' INT TERM

  if ! Download "$_installyq_url" "$g_temp_file"; then
    PanicD "download $_installyq_url failed" "下载 $_installyq_url 失败"
  fi
  $SUDO chmod +x "$g_temp_file"
  $SUDO rm -f /bin/yq /usr/bin/yq /usr/local/bin/yq
  $SUDO mv "$g_temp_file" /usr/bin/yq
  which -a yq
  yq --version
}
export UpgradeYq
readonly UpgradeYq

YqGetFromFile(){
  Usage $# 2 4 'valueOf <key> <yaml> [default] [WITH_PANIC]'
  _yqgetfromfile_key="$1"
  _yqgetfromfile_yaml="$2"
  _yqgetfromfile_default="${3:-}"
  _yqgetfromfile_with_panic="${4:-}"

  if [ "$_yqgetfromfile_default" = WITH_PANIC ] && [ $# -eq 3 ]; then
    _yqgetfromfile_default=''
    _yqgetfromfile_with_panic=WITH_PANIC
  fi

  PanicIfNotFile "$_yqgetfromfile_yaml"

  _yqgetfromfile_value=$(yq -r "$_yqgetfromfile_key" "$_yqgetfromfile_yaml")
  if [ -z "$_yqgetfromfile_value" ] || [ "$_yqgetfromfile_value" = "null" ]; then
    if [ -z "$_yqgetfromfile_default" ] && [ "$_yqgetfromfile_with_panic" = WITH_PANIC ]; then
      PanicD "missing key $_yqgetfromfile_key in $_yqgetfromfile_yaml" "$_yqgetfromfile_yaml 缺少键值 $_yqgetfromfile_key"
    fi
    _yqgetfromfile_value="$_yqgetfromfile_default"
  fi
  printf '%s' "$_yqgetfromfile_value"
}
export YqGetFromFile
readonly YqGetFromFile

YqGetFromStr(){
  Usage $# 2 4 'valueOf <key> <str> [default] [WITH_PANIC]'
  _yqgetfromstr_key="$1"
  _yqgetfromstr_str="$2"
  _yqgetfromstr_default="${3:-}"
  _yqgetfromstr_with_panic="${4:-}"

  _yqgetfromstr_value=$(printf '%s\n' "$_yqgetfromstr_str" | yq -r "$_yqgetfromstr_key")
  if [ -z "$_yqgetfromstr_value" ] || [ "$_yqgetfromstr_value" = "null" ]; then
    if [ -z "$_yqgetfromstr_default" ] && [ "$_yqgetfromstr_with_panic" = WITH_PANIC ]; then
      PanicD "missing key $_yqgetfromstr_key" "缺少键值 $_yqgetfromstr_key"
    fi
    _yqgetfromstr_value="$_yqgetfromstr_default"
  fi
  printf '%s' "$_yqgetfromstr_value"
}
export YqGetFromStr
readonly YqGetFromStr

YqGet(){
  Usage $# 3 5 'valueOf <key> <-f|-s> <yaml> [default] [WITH_PANIC]'
  _yqget_key="$1"
  _yqget_type="$2"
  _yqget_yaml="$3"
  shift 3

  case "$_yqget_type" in
    -f) YqGetFromFile "$_yqget_key" "$_yqget_yaml" "$@" ;;
    -s) YqGetFromStr "$_yqget_key" "$_yqget_yaml" "$@" ;;
    *) PanicArg 2 "$_yqget_type" '-f:file|-s:string';;
  esac
}
export YqGet
readonly YqGet

init(){
  if ! command -v yq >/dev/null 2>&1; then
    UpgradeYq
    return $?
  fi
  _yq_version=$(yq --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  if [ -z "$_yq_version" ]; then
    UpgradeYq
    return $?
  fi

  _yq_major=$(echo "$_yq_version" | cut -d. -f1)
  if [ "$_yq_major" -lt 4 ] 2>/dev/null; then
    Info "yq version $_yq_version (< 4), upgrading yq..."
    UpgradeYq
    return $?
  fi
}

init