#!/bin/sh
set -eu

# https://github.com/aarioai/opt
if [ -x "./aa-posix-lib.sh" ]; then . ./aa-posix-lib.sh; else . /opt/aa/lib/aa-posix-lib.sh; fi

# 必须安装 yq v4+
UpgradeYq(){
  _installyq_os=$(uname -s | tr '[:upper:]' '[:lower:]')
  _installyq_arch=$(uname -m)
  case "$_installyq_arch" in
    x86_64) _installyq_arch="amd64" ;;
    aarch64|arm64) _installyq_arch="arm64" ;;
    armv7l) _installyq_arch="armv7" ;;
  esac

  _installyq_url="https://github.com/mikefarah/yq/releases/latest/download/yq_${_installyq_os}_${_installyq_arch}"

  g_temp_file=$(mktemp) || PanicMktemp
  trap 'rm -f "$g_temp_file" 2>/dev/null' EXIT
  trap 'rm -f "$g_temp_file" 2>/dev/null; return 1' INT TERM

  if ! Download "$_installyq_url" "$g_temp_file"; then
    PanicD "download $_installyq_url failed" "下载 $_installyq_url 失败"
  fi
  ChmodOrSudo +x "$g_temp_file"
  RemoveFilesOrSudo /bin/yq /usr/bin/yq /usr/local/bin/yq
  MoveOrSudo "$g_temp_file" /usr/bin/yq
  which -a yq
  yq --version
}
export UpgradeYq
readonly UpgradeYq

YqIsNotEmptyArray(){
  Usage $# -eq 3 'YqIsNotEmptyArray <key> <-f|-s> <file|str>'
  _yqisnotemptyarray_key="${1#.}"   # trim .
  _yqisnotemptyarray_type="$2"
  _yqisnotemptyarray="$3"

  _yqisnotemptyarray_key="${_yqisnotemptyarray_key%\[\]}"   # trim []
  _yqisnotemptyarray_qs=".$_yqisnotemptyarray_key | type == \"!!seq\" and length > 0"
  case "$_yqisnotemptyarray_type" in
    -f)
      yq -e "$_yqisnotemptyarray_qs" "$_yqisnotemptyarray" >/dev/null 2>&1
      return $?
      ;;
    -s)
      printf '%s\n' "$_yqisnotemptyarray" | yq -e "$_yqisnotemptyarray_qs" >/dev/null 2>&1
      return $?
      ;;
    *) PanicArg 2 "$_yqisnotemptyarray_type" '-f:file|-s:string';;
  esac
  return 1
}
export YqIsNotEmptyArray
readonly YqIsNotEmptyArray

YqHas(){
  Usage $# -eq 3 'YqHas <key> <-f|-s> <file|str>'
  _yqhas_key="${1#.}"   # trim .
  _yqhas_type="$2"
  _yqhas="$3"

  case "$_yqhas_key" in
    *'[]')
      YqIsNotEmptyArray "$_yqhas_key" "$_yqhas_type" "$_yqhas"
      return $?
      ;;
  esac

  _yqhas_qs=".${_yqhas_key} != null"
  case "$_yqhas_type" in
    -f)
      yq -e "$_yqhas_qs" "$_yqhas" >/dev/null 2>&1
      return $?
      ;;
    -s)
      printf '%s\n' "$_yqhas" | yq -e "$_yqhas_qs" >/dev/null 2>&1
      return $?
      ;;
    *) PanicArg 2 "$_yqhas_type" '-f:file|-s:string';;
  esac
  return 1
}
export YqHas
readonly YqHas

YqGetFromFile(){
  Usage $# 2 4 'YqGetFromFile <key> <yaml> [default] [WITH_PANIC]'
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
  Usage $# 2 4 'YqGetFromStr <key> <str> [default] [WITH_PANIC]'
  _yqgetfromstr_key="$1"
  _yqgetfromstr_str="$2"
  _yqgetfromstr_default="${3:-}"
  _yqgetfromstr_with_panic="${4:-}"

  if [ $# -eq 3 ] && [ "$_yqgetfromstr_default" = WITH_PANIC ]; then
    _yqgetfromstr_default=''
    _yqgetfromstr_with_panic=WITH_PANIC
  fi

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
  Usage $# 3 5 'YqGet <key> <-f|-s> <yaml> [default] [WITH_PANIC]'
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