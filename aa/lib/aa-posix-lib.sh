#!/bin/sh
# [WARN] shell 脚本必须全部是 LF 格式，如果是 CRLF 等就会无法执行，报错 not found

#   -e 遇到非零状态码，立即终止
#   -u 遇到未定义变量，立即终止
#   -x 执行每条命令前，打印命令（方便docker编译调试），但是日志太多，应限制使用
set -eu

# Requires:
#   printf, date, sed id, uname, dirname, basename, pwd
# Optional:
#   dpkg, awk/apk/rpm/yum/apt-get, openssl(auto install)

# 要求兼容 Debian, Alpine, Redhat 等。
# /bin/sh 是Unix标准默认shell，而alphin等没有默认安装bash。nginx/mysql等docker都使用 /bin/sh
# @warn POSIX for s in "$@"; 是不会拆分空格的，需要使用兼容性更好的方法，先分割空格为换行，然后IFS读取
# @warn POSIX 不支持local变量，变量没有作用域，都是全局变量，这里统一加 _前后缀。本页内如果互相调用，也会导致相同变量名冲突，因此必须要带函数前缀
#   本身shell脚本就很小，因此不要过度优化通用包，这里只保留少量全局变量

# mktemp 依赖 $TMPDIR 文件夹
export TMPDIR="${TMPDIR:-/tmp}"
export QUITE_LOGS="${QUITE_LOGS:-0}"
export LIB_LOG_FILE="${LIB_LOG_FILE:-}"
export IN_CHINESE=0         # 如果将此设置为 -1，则强制输出英文；设为 1，强制输出中文；否则自动判断系统是否是中文
AA_LOG_NO_COLOR="${AA_LOG_NO_COLOR:-0}"  # 是否不输出颜色

# 换行符
# printf/echo 都会移除掉尾部的空行。试了很多办法，只有这样写才可以
export LF
readonly LF="
"
export TAB
readonly TAB='	'     # tab=tab符号
export TAB2
readonly TAB2='  '    # tab=2个空格
export TAB4
readonly TAB4='    '  # tab=4个空格
# 黑、白没有存在的必要（黑、白背景面板难以区分）
export _NC_
readonly _NC_='\033[0m' # No Color
export _RED_
readonly _RED_='\033[0;31m'             # 红
export _LIGHT_RED_
readonly _LIGHT_RED_='\033[0;91m'
export _GREEN_
readonly _GREEN_='\033[0;32m'           # 绿
export _LIGHT_GREEN_
readonly _LIGHT_GREEN_='\033[0;92m'
export _YELLOW_
readonly _YELLOW_='\033[1;33m'          # 黄
export _LIGHT_YELLOW_
readonly _LIGHT_YELLOW_='\033[1;93m'
export _BLUE_
readonly _BLUE_='\033[1;34m'            # 蓝
export _LIGHT_BLUE_
readonly _LIGHT_BLUE_='\033[1;94m'
export _MAGENTA_
readonly _MAGENTA_='\033[1;35m'         # 品红
export _LIGHT_MAGENTA_
readonly _LIGHT_MAGENTA_='\033[1;95m'
export _CYAN_
readonly _CYAN_='\033[1;36m'            # 青
export _LIGHT_CYAN_
readonly _LIGHT_CYAN_='\033[1;96m'
export _GRAY_
readonly _GRAY_='\033[0;90m'            # 灰

DetectPkgManager(){
  if command -v apk >/dev/null 2>&1; then
    printf '%s' 'apk'           # alpine
  elif command -v apt-get >/dev/null 2>&1; then
    printf '%s' 'apt-get'       # debian/ubuntu. apt 被视为不稳定的，因此脚本使用 apt-get
  elif command -v dnf >/dev/null 2>&1; then
    printf '%s' 'dnf'       # UBI, Fedora/CentOS 8+, better than yum
  elif command -v microdnf >/dev/null 2>&1; then
    printf '%s' 'microdnf'      # UBI-minimal, oraclelinux
  elif command -v opkg >/dev/null 2>&1; then
    printf '%s' 'opkg'
  elif command -v pacman >/dev/null 2>&1; then
    printf '%s' 'pacman'
  elif command -v yum >/dev/null 2>&1; then
    printf '%s' 'yum'           # CentOS 8-
  elif command -v zypper >/dev/null 2>&1; then
    printf '%s' 'zypper'
  else
    printf '%s' ''
  fi
}
export DetectPkgManager
readonly DetectPkgManager

# Usage 函数依赖 grep，因此 _install_ 函数不要引用 Usage，否则当 grep 没安装时，_install_ 将无法使用
_install_(){
  _install_pkg="$1"
  _install_sudo="${2:-}"
  _install_quite="${3:-}"

  # handle Install <sudo> -q <app>
  if [ "$_install_pkg" = '-q' ]; then
    _install_pkg="$3"
    _install_quite="$2"
  fi
  _install_cmd=''
  case "$_install_pkg" in
    'procps')
      _install_cmd='ps'
      ;;
    'ps')
      _install_cmd='ps'
      _install_pkg='procps'
      ;;
    *)
      _install_cmd="$_install_pkg"
  esac

  if command -v "$_install_cmd" >/dev/null 2>&1; then
    return 0
  fi

  _install_manager="$(DetectPkgManager)"

  case "$_install_manager" in
    'apk')
      echo ">>> $_install_sudo apk update --no-cache $_install_quite"
      # shellcheck disable=SC2086    # 不要加引号
      $_install_sudo apk update --no-cache $_install_quite
      echo ">>> $_install_sudo apk add --no-cache $_install_quite $_install_pkg"
      # shellcheck disable=SC2086    # 不要加引号
      $_install_sudo apk add --no-cache $_install_quite "$_install_pkg"
      ;;
    'apt-get')
      # -y auto confirm
      # -q quit only output important information
      # --no-install-recommends 只安装依赖包，不安扩展的推荐包
      echo ">>> $_install_sudo $_install_manager update -y $_install_quite"
      # shellcheck disable=SC2086    # 不要加引号
      $_install_sudo $_install_manager update -y $_install_quite
      echo ">>> $_install_sudo $_install_manager update -y $_install_quite"
      # shellcheck disable=SC2086    # 不要加引号
      $_install_sudo $_install_manager install -y $_install_quite --no-install-recommends "$_install_pkg"
      ;;
    'dnf'|'microdnf')
      echo ">>> $_install_sudo $_install_manager update -y $_install_quite"
      # shellcheck disable=SC2086    # 不要加引号
      $_install_sudo $_install_manager update -y $_install_quite
      echo ">>> $_install_sudo $_install_manager install -y --nodocs --setopt=tsflags=nodocs $_install_quite $_install_pkg"
      # shellcheck disable=SC2086    # 不要加引号
      $_install_sudo $_install_manager install -y --nodocs --setopt=tsflags=nodocs $_install_quite "$_install_pkg"
      ;;
    'yum')
      echo ">>> $_install_sudo $_install_manager update -y $_install_quite"
      # shellcheck disable=SC2086    # 不要加引号
      $_install_sudo $_install_manager update -y $_install_quite
      echo ">>> $_install_sudo $_install_manager install -y $_install_quite $_install_pkg"
      # shellcheck disable=SC2086    # 不要加引号
      $_install_sudo $_install_manager install -y $_install_quite "$_install_pkg"
      ;;
    'opkg')
      echo ">>> $_install_sudo opkg update $_install_quite"
      # shellcheck disable=SC2086    # 不要加引号
      $_install_sudo opkg update $_install_quite
      echo ">>> $_install_sudo opkg install $_install_quite $_install_pkg"
      # shellcheck disable=SC2086    # 不要加引号
      $_install_sudo opkg install $_install_quite "$_install_pkg"
      ;;
    'pacman')
      echo ">>> $_install_sudo pacman -Syu --noconfirm --needed"
      $_install_sudo pacman -Syu --noconfirm --needed
      echo ">>> $_install_sudo pacman -S --noconfirm --needed $_install_pkg"
      $_install_sudo pacman -S --noconfirm --needed "$_install_pkg"
      ;;
    'zypper')
      echo ">>> $_install_sudo zypper --non-interactive refresh"
      $_install_sudo zypper --non-interactive refresh
      echo ">>> $_install_sudo zypper --non-interactive install $_install_pkg"
      $_install_sudo zypper --non-interactive install "$_install_pkg"
      ;;
    *)
      echo "install $_install_pkg failed. unsupported package manager: $_install_manager ($(uname -a))"
      if [ -f "/etc/os-release" ]; then cat /etc/os-release; fi
      return 1
  esac

  return $?
}
readonly _install_

# grep 是基础函数，必须要提前安装。安装尽可能不依赖任何其他函数
InstallGrep(){
  if ! command -v grep >/dev/null 2>&1; then
    _install_sudo=''
    if [ "$(id -u)" != '0' ] && command -v sudo >/dev/null 2>&1; then
      _install_sudo='sudo'
    fi
    _install_ grep "$_install_sudo"
  fi
}
export InstallGrep
readonly InstallGrep

IsLocaleChinese(){
  # Check ENV
  case ",${LANG:-},${LC_ALL:-}" in
    *,zh_Hans*|*,zh_CN*|*,zh_SG*|*,zh_MY*)
      return 0
      ;;
  esac

  InstallGrep
  # Check locale config
  if command -v locale >/dev/null 2>&1 && locale -a 2>/dev/null | grep -q -E '^zh_(Hans|CN|SG|MY)(\..*)?$'; then
    return 0
  fi

  for _islocalechiense_file in "/etc/default/locale" "/etc/locale.conf"; do
    if [ -f "$_islocalechiense_file" ] && grep -q -E "=.*zh_(Hans|CN|SG|MY)" "$_islocalechiense_file" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}
export IsLocaleChinese
readonly IsLocaleChinese

IsSupportChinese(){
  if IsLocaleChinese; then
    return 0
  fi
  _issupportchinese_nations='zh_CN zh_SG zh_MY'
  if [ -d '/usr/lib/locale' ]; then
    for _issupportchinese_nation in $_issupportchinese_nations; do
      for _issupportchinese_enc in 'UTF-8' 'utf8' 'UTF8'; do
        if [ -d "/usr/lib/locale/${_issupportchinese_nation}.${_issupportchinese_enc}" ]; then
          return 0
        fi
      done
      if [ -d "/usr/lib/locale/${_issupportchinese_nation}" ]; then
        return 0
      fi
    done
  fi
  if [ -d '/usr/share/i18n/locales' ]; then
    for _issupportchinese_nation in $_issupportchinese_nations; do
      if [ -f "/usr/share/i18n/locales/${_issupportchinese_nation}" ]; then
        return 0
      fi
    done
  fi

  if [ -f "/usr/share/i18n/SUPPORTED" ]; then
    InstallGrep
    if grep -q -E "^zh_(CN|SG|MY)(\..*)? UTF-8" "/usr/share/i18n/SUPPORTED" 2>/dev/null; then
      return 0
    fi
  fi

  return 1
}
export IsSupportChinese
readonly IsSupportChinese

# 只有系统是中文，才输出中文。
IsInChinese(){
  case "$IN_CHINESE" in
    -1) return 1 ;;
    'TRUE') return 0 ;;
    1)
      if IsSupportChinese; then
        export IN_CHINESE='TRUE'
        return 0
      fi
      ;;
  esac
  if IsLocaleChinese; then
    export IN_CHINESE='TRUE'
    return 0
  fi

  export IN_CHINESE=-1
  return 1
}
export IsInChinese
readonly IsInChinese

_isNumber_(){
  InstallGrep
  if ! printf '%s' "${1:-}" | grep '^[[:digit:]]*$' >/dev/null 2>&1; then
    return 1
  fi
}
readonly _isNumber_

PanicIfNotNumber(){
  Usage $# -ge 1 'PanicIfNotNumber <arg> [arg]...'
  for _panicifnotumber in "$@"; do
    if ! _isNumber_ "$_panicifnotumber"; then Panic "'$_panicifnotumber' is not a valid number"; fi
  done
}
export PanicIfNotNumber
readonly PanicIfNotNumber

PanicIfNotFile(){
  Usage $# -ge 1 'PanicIfNotFile <path> [path]...'
  for _panicifnotfile in "$@"; do
    if [ ! -f "$_panicifnotfile" ]; then Panic "not found file '$_panicifnotfile'"; fi
  done
}
export PanicIfNotFile
readonly PanicIfNotFile

PanicIfNotDir(){
  Usage $# -ge 1 'PanicIfNotDir <path> [path]...'
  for _panicifnotdir in "$@"; do
    if [ ! -d "$_panicifnotdir" ]; then Panic "not found directory '$_panicifnotdir'"; fi
  done
}
export PanicIfNotDir
readonly PanicIfNotDir

# Require: IsInChinese
PanicUsage() {
  if [ "$QUITE_LOGS" -eq 0 ]; then
    _panicusage_u='Usage: '
    if IsInChinese; then _panicusage_u='使用方法：'; fi
    if [ "$AA_LOG_NO_COLOR" != '1' ]; then
      printf "%s ${_RED_}%s%s${_NC_}\n" "$(Now)" "$_panicusage_u" "$1" >&2
    else
      printf "%s %s%s\n" "$(Now)" "$_panicusage_u" "$1" >&2
    fi
  fi
  exit 1
}
export PanicUsage
readonly PanicUsage

# Require: _is_number, PanicUsage
Usage(){
  _usage_tip=$(cat << EOF
Usage <arg_count:number> <min|flag:-ge/-gt/-eq/-lt/-le> <expected_count:number> <usage message>
Example:
  Usage $# 1 3 'Func <arg> [arg] [arg]'
  Usage $# -eq 2 'Func <arg1> <arg2>'
  Usage $# -ge 2 'Func <arg> <arg> [arg]...'
EOF
)
  if [ $# -lt 4 ]; then
    PanicUsage "$_usage_tip"
  fi
  _usage_n="$1"
  _usage_flag="$2"
  _usage_expected="$3"
  shift 3
  _usage_msg="$*"
  if ! _isNumber_ "$_usage_n" || ! _isNumber_ "$_usage_expected" ; then
    PanicUsage "$_usage_tip"
  fi

  # handle: Usage <count> <min> <max> <message>
  if _isNumber_ "$_usage_flag"; then
    if [ "$_usage_n" -ge "$_usage_flag" ] && [ "$_usage_n" -le "$_usage_expected" ]; then
      return 0
    fi
    PanicUsage "$_usage_msg"
  fi

  # handle: Usage <count> <flag:-eq/-ge/-gt> <expected> <message>
  case "$_usage_flag" in
    -eq)
      if  [ "$_usage_n" -eq "$_usage_expected" ]; then return 0; fi
      ;;
    -ge)
      if  [ "$_usage_n" -ge "$_usage_expected" ]; then return 0; fi
      ;;
    -gt)
      if  [ "$_usage_n" -gt "$_usage_expected" ]; then return 0; fi
      ;;
    -le)
      if  [ "$_usage_n" -le "$_usage_expected" ]; then return 0; fi
      ;;
    -lt)
      if  [ "$_usage_n" -lt "$_usage_expected" ]; then return 0; fi
      ;;
    *)
      PanicUsage "$_usage_tip"
      ;;
  esac

  PanicUsage "$_usage_msg"
}
export Usage
readonly Usage

# Require: IsInChinese
Dict(){
  Usage $# -eq 2 'Dict <english> <chinese>'
  if IsInChinese; then
    printf '%s' "$2"
    return
  fi
  printf '%s' "$1"
}
export Dict
readonly Dict

_nowUsage_(){
  cat <<-EOF
  Usage: Now [option]
  Options:
    -a abbreviated weekday name (e.g. Mon)
    -A weekday name (e.g. Monday)
    -f date (e.g. 20141010)
    -F date (e.g. 0000-00-00)
    -n datetime (e.g. 20141010_010101)
    -N datetime (e.g. 20141010010101)
    -s Unix Time  (e.g. 1000000000)
    -T time (e.g. 00:00:00)
    -Tz time with zone (e.g. 00:00:00+0800)
    -TZ time with zone name (e.g. 00:00:00 CST)
    -z datetime with zone (e.g. 0000-00-00 00:00:00+0800)
    -Z datetime with zone name (e.g. 0000-00-00 00:00:00 CST)
    -O|-iso8601|-rfc3339 (e.g. 0000-00-00T00:00:00+0800)
EOF
}
readonly _nowUsage_


Now(){
  Usage $# -le 1 "$(_nowUsage_)"

  if [ $# -eq 0 ]; then
    date +'%Y-%m-%d %H:%M:%S'
    return 0
  fi

  case "$1" in
    -a) date +'%a' ;;
    -A) date +'%A' ;;
    -f) date +'%Y%m%d' ;;
    -F) date +'%Y-%m-%d' ;;
    -n) date +'%Y%m%d_%H%M%S' ;;
    -N) date +'%Y%m%d%H%M%S' ;;
    -s) date +'%s' ;;
    -T) date +'%H:%M:%S' ;;
    -Tz) date +'%H:%M:%S%z' ;;
    -TZ) date +'%H:%M:%S %Z' ;;
    -z) date +'%Y-%m-%d %H:%M:%S%z' ;;
    -Z) date +'%Y-%m-%d %H:%M:%S %Z' ;;
    -O|-iso8601|-rfc3339) date +'%Y-%m-%dT%H:%M:%S%z' ;;
    *)  _nowUsage_ ;;
  esac
}
export Now
readonly Now

Today(){
  Now -F
}
export Today
readonly Today

PrintColor(){
  Usage $# -ge 2 'PrintColor <color> {message}'
  _printcolor=$1
  shift
  if [ "$AA_LOG_NO_COLOR" != '1' ]; then
    printf "${_printcolor}%s${_NC_}\n" "$*"
  else
    printf "%s\n" "$*"
  fi
}
export PrintColor
readonly PrintColor

Lowlight(){
  if [ "$AA_LOG_NO_COLOR" != '1' ]; then
    printf "${_GRAY_}%s${_NC_}\n" "$*"
  else
    printf "%s\n" "$*"
  fi
}
export Lowlight
readonly Lowlight

LowlightD(){
  Usage $# -eq 2 'LowlightD <english> <chinese>'
  Lowlight "$(Dict "$1" "$2")"
}
export LowlightD
readonly LowlightD

Highlight(){
  if [ "$AA_LOG_NO_COLOR" != '1' ]; then
    printf "${_LIGHT_MAGENTA_}%s${_NC_}\n" "$*"
  else
    printf "%s\n" "$*"
  fi
}
export Highlight
readonly Highlight

HighlightD(){
  Usage $# -eq 2 'HighlightD <english> <chinese>'
  Highlight "$(Dict "$1" "$2")"
}
export HighlightD
readonly HighlightD

Heading(){
  if [ "$QUITE_LOGS" -eq 0 ]; then
    if [ "$AA_LOG_NO_COLOR" != '1' ]; then
      printf "\n${_LIGHT_YELLOW_}%s${_NC_}\n" "$*"
    else
      printf "\n%s\n" "$*"
    fi
  fi
  _saveToLogFile "" "$@"
}
export Heading
readonly Heading

HeadingD(){
  Usage $# -eq 2 'HeadingD <english> <chinese>'
  Heading "$(Dict "$1" "$2")"
}
export HeadingD
readonly HeadingD

SetLibLogFile(){
  export LIB_LOG_FILE="$1"
}
export SetLibLogFile
readonly SetLibLogFile

UnsetLibLogFile(){
  export LIB_LOG_FILE=''
}
export UnsetLibLogFile
readonly UnsetLibLogFile


_saveToLogFile(){
  _saveToLogFileLevel=${1:+"$1 "}
  _savetologfile_msg="$2"
  _savetologfile=${3:-"$LIB_LOG_FILE"}
  if [ -z "$_savetologfile" ]; then
    return 0
  fi

  if [ ! -f "$_savetologfile" ]; then
    _savetologfile_dir=$(dirname "$_savetologfile")
    if [ ! -d "$_savetologfile_dir" ]; then
      mkdir -p "$_savetologfile_dir"
      chmod 777 "$_savetologfile_dir" || sudo chmod 777 "$_savetologfile_dir"
    fi

    _log_ "" "$_BLUE_" "creating lib log file: $_savetologfile"
    touch "$_savetologfile"
    chmod 777 "$_savetologfile" || sudo chmod 777 "$_savetologfile"
  fi
  printf '%s %s%s\n' "$(Now)" "$_saveToLogFileLevel" "$_savetologfile_msg" >> "$_savetologfile"
}
readonly _saveToLogFile

_log_() {
  Usage $# -ge 3 '_log_ <level tag> <color> {message}'
  _log_level=${1:+"$1 "}
  _log_color=$2
  shift 2
  _log_message="$*"

  if [ "$QUITE_LOGS" -eq 0 ]; then
    if [ "$AA_LOG_NO_COLOR" != '1' ]; then
      printf "%s ${_log_color}%s${_NC_}\n" "$(Now)" "${_log_level}${_log_message}"
    else
      printf "%s %s\n" "$(Now)" "${_log_level}${_log_message}"
    fi
  fi
}
# @warn 函数不能设置 readonly，可以重写 _log_(){} ，但是不能作为变量赋值了，如  _log_=100 就会报错
readonly _log_

Log() {
  _log_ "" "" "$*"
  _saveToLogFile "" "$@"
}
export Log
readonly Log

LogD(){
  Usage $# -eq 2 'LogD <english> <chinese>'
  Log "$(Dict "$1" "$2")"
}
export LogD
readonly LogD

Debug() {
  _log_ "[debug]" "$_CYAN_" "$*"
  _saveToLogFile "[debug]" "$@"
}
export Debug
readonly Debug

DebugD(){
  Usage $# -eq 2 'DebugD <english> <chinese>'
  Debug "$(Dict "$1" "$2")"
}
export DebugD
readonly DebugD

Info() {
  _log_ "[info]" "$_GREEN_" "$*"
  _saveToLogFile "[info]" "$@"
}
export Info
readonly Info

InfoD(){
  Usage $# -eq 2 'InfoD <english> <chinese>'
  Info "$(Dict "$1" "$2")"
}
export InfoD
readonly InfoD

Notice() {
  _log_ "[notice]" "$_MAGENTA_" "$*"
  _saveToLogFile "[notice]" "$@"
}
export Notice
readonly Notice

NoticeD(){
  Usage $# -eq 2 'NoticeD <english> <chinese>'
  Notice "$(Dict "$1" "$2")"
}
export NoticeD
readonly NoticeD

Warn() {
  _log_ "[warn]" "$_YELLOW_" "$*" >&2
  _saveToLogFile "[warn]" "$@"
}
export Warn
readonly Warn

WarnD(){
  Usage $# -eq 2 'Warn <english> <chinese>'
  Warn "$(Dict "$1" "$2")"
}
export WarnD
readonly WarnD

Error() {
  _log_ "[error]" "$_RED_" "$*" >&2
  _saveToLogFile "[error]" "$@"
}
export Error
readonly Error

ErrorD(){
  Usage $# -eq 2 'ErrorD <english> <chinese>'
  Error "$(Dict "$1" "$2")"
}
export ErrorD
readonly ErrorD

Panic() {
  Error "$@"
  exit 1
}
export Panic
readonly Panic

PanicD(){
  Usage $# -eq 2 'PanicD <english> <chinese>'
  Panic "$(Dict "$1" "$2")"
}
export PanicD
readonly PanicD

IsNumber(){
  Usage $# -eq 1 'if ! IsNumber <string>; then ... fi'
  _isNumber_ "$1"
}
export IsNumber
readonly IsNumber

Abs(){
  Usage $# -eq 1 'Abs <number>'
  printf '%s' "${1#-}"
}
export Abs
readonly Abs

Max(){
  Usage $# -eq 2 'Max <number> <number>'
  if [ "$1" -gt "$2" ]; then
    printf '%s' "$1"
    return 0
  fi
  printf '%s' "$2"
}
export Max
readonly Max

Min(){
  Usage $# -eq 2 'Min <number> <number>'
  if [ "$1" -lt "$2" ]; then
    printf '%s' "$1"
    return 0
  fi
  printf '%s' "$2"
}
export Min
readonly Min


# Check is LF or '\n'
IsLF() {
  Usage $# -eq 1 'IsLF <char>'
  if [ "$1" != "\n" ] && [ "$1" != "$LF" ]; then
    return 1
  fi
}
export IsLF
readonly IsLF

Confirm(){
  Usage $# -le 1 'if Confirm <message>; then ... fi'
  _confirm_msg="${1:-"$(Dict "Are you sure?" "确定？")"}"

  if [ "$AA_LOG_NO_COLOR" != '1' ]; then
    printf "${_RED_}%s ${_NC_}[y/N] \n" "$_confirm_msg"
  else
    printf "%s [y/N] \n" "$_confirm_msg"
  fi

  read -r _confirm_resp

  case "$_confirm_resp" in
    [yY] | [yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}
export Confirm
readonly Confirm

ConfirmD(){
  Usage $# -eq 2 'ConfirmD <english> <chinese>'
  Confirm "$(Dict "$1" "$2")"
}
export ConfirmD
readonly ConfirmD

# Check current user is root
# Example: if ! IAmRoot; then ...
IAmRoot() {
  # https://github.com/koalaman/shellcheck/wiki/SC2015
  if [ "$(id -u)" != '0' ]; then
    return 1
  fi
}
export IAmRoot
readonly IAmRoot

# 获取CPU类型：amd 或 arm 架构
CpuArch() {
  # debian/ubuntu
  if command -v dpkg >/dev/null 2>&1; then
    InstallGrep
    if dpkg --help 2>/dev/null | grep -q -- "--print-architecture"; then
      dpkg --print-architecture 2>/dev/null | sed 's/.*-//'
      return 0
    fi
  fi

  # alpine
  if command -v apk >/dev/null 2>&1; then
    _cpuarch=$(apk --print-arch 2>/dev/null)
    if [ -n "$_cpuarch" ]; then
      case "$_cpuarch" in
        x86_64) printf '%s' "amd64" ;;
        aarch64) printf '%s' "arm64" ;;
        armv7) printf '%s' "armhf" ;;
        *) printf '%s' "$_cpuarch" ;;
      esac
      return 0
    fi
  fi

  # centos/redhat
  if command -v rpm >/dev/null 2>&1; then
    _cpuarch=$(rpm --eval '%{_arch}' 2>/dev/null)
    if [ -n "$_cpuarch" ]; then
      case "$_cpuarch" in
        x86_64) printf '%s' "amd64" ;;
        aarch64) printf '%s' "arm64" ;;
        armv7l) printf '%s' "armhf" ;;
        *) printf '%s' "$_cpuarch" ;;
      esac
      return 0
    fi
  fi

  # fallback: use uname for other linux distributions
  case "$(uname -m)" in
    x86_64) printf '%s' "amd64" ;;
    aarch64 | arm64) printf '%s' "arm64" ;;
    armv7l) printf '%s' "armhf" ;;
    *) printf '%s' "$(uname -m)" ;;
  esac
}
export CpuArch
readonly CpuArch



Install(){
  Usage $# -ge 1 'Install <app> [app]...'

  _install_sudo=''
  if ! IAmRoot && command -v sudo >/dev/null 2>&1; then
    _install_sudo='sudo'
  fi

  for _install_pkg in "$@"; do
    if [ -n "$_install_pkg" ]; then
      if ! _install_ "$_install_pkg" "$_install_sudo"; then
        Error "install $_install_pkg failed"
        return 1
      fi
      Info "installed $_install_pkg"
    fi
  done
}
export Install
readonly Install

CleanPkgManager(){
  _cleanpkgmanager="$(DetectPkgManager)"

  if [ -z "$_cleanpkgmanager" ]; then
    return 0
  fi

  Info "clean package manager: $_cleanpkgmanager"
  _cleanpkgmanager_sudo=''
  if ! IAmRoot && command -v sudo >/dev/null 2>&1; then
    _cleanpkgmanager_sudo='sudo'
  fi

  case "$_cleanpkgmanager" in
    'apk')
      echo ">>> $_cleanpkgmanager_sudo apk cache clean"
      $_cleanpkgmanager_sudo apk cache clean
      ;;
    'apt-get'|'dnf'|'yum')
      echo ">>> $_cleanpkgmanager_sudo $_cleanpkgmanager clean all -q"
      # shellcheck disable=SC2086    # 不要加引号
      $_cleanpkgmanager_sudo $_cleanpkgmanager clean all -q
      ;;
    'microdnf')
      echo ">>> $_cleanpkgmanager_sudo $_cleanpkgmanager clean all"
      # shellcheck disable=SC2086    # 不要加引号
      $_cleanpkgmanager_sudo $_cleanpkgmanager clean all > /dev/null
      ;;
    'opkg')
      ;;
    'pacman')
      echo ">>> $_cleanpkgmanager_sudo pacman -Scc --noconfirm"
      $_cleanpkgmanager_sudo pacman -Scc --noconfirm
      ;;
    'zypper')
      echo ">>> $_cleanpkgmanager_sudo zypper --non-interactive clean"
      $_cleanpkgmanager_sudo zypper --non-interactive clean
      ;;
    *)
      ErrorD "clean package manager failed. unsupported package manager: $_cleanpkgmanager" "清理包管理失败。暂不支持包管理：$_cleanpkgmanager"
      echo "uname -a => ($(uname -a))"
      if [ -f "/etc/os-release" ]; then cat /etc/os-release; fi
  esac
}
export CleanPkgManager
readonly CleanPkgManager

_uninstall_(){
  Usage $# -eq 1 '_uninstall_ <app>'
  _uninstall_pkg="$1"

  _uninstall_sudo=''
  if ! IAmRoot && command -v sudo >/dev/null 2>&1; then
    _uninstall_sudo='sudo'
  fi

  _uninstall_manager="$(DetectPkgManager)"

  case "$_uninstall_manager" in
    'apk')
      echo ">>> $_uninstall_sudo apk del --no-cache --quiet $_uninstall_pkg"
      $_uninstall_sudo apk del --no-cache --quiet "$_uninstall_pkg"
      CleanPkgManager
      ;;
    'apt-get'|'dnf'|'yum')
      echo ">>> $_uninstall_sudo $_uninstall_manager remove -y -q $_uninstall_pkg"
      # shellcheck disable=SC2086    # 不要加引号
      $_uninstall_sudo $_uninstall_manager remove -y -q "$_uninstall_pkg"
      echo ">>> $_uninstall_sudo $_uninstall_manager autoremove -y -q"
      # shellcheck disable=SC2086    # 不要加引号
      $_uninstall_sudo $_uninstall_manager autoremove -y -q
      CleanPkgManager
      ;;
    'microdnf')
      echo ">>> $_uninstall_sudo $_uninstall_manager remove -y $_uninstall_pkg"
      # shellcheck disable=SC2086    # 不要加引号
      $_uninstall_sudo $_uninstall_manager remove -y "$_uninstall_pkg" > /dev/null
      echo ">>> $_uninstall_sudo $_uninstall_manager autoremove -y"
      # shellcheck disable=SC2086    # 不要加引号
      $_uninstall_sudo $_uninstall_manager autoremove -y > /dev/null
      CleanPkgManager
      ;;
    'opkg')
      echo ">>> $_uninstall_sudo opkg remove $_uninstall_pkg"
      $_uninstall_sudo opkg remove "$_uninstall_pkg"
      CleanPkgManager
      ;;
    'pacman')
      echo ">>> $_uninstall_sudo pacman -R --noconfirm --nosave $_uninstall_pkg"
      $_uninstall_sudo pacman -R --noconfirm --nosave "$_uninstall_pkg"
      CleanPkgManager
      ;;
    'zypper')
      echo ">>> $_uninstall_sudo zypper --non-interactive remove $_uninstall_pkg"
      $_uninstall_sudo zypper --non-interactive remove "$_uninstall_pkg"
      CleanPkgManager
      ;;
    *)
      ErrorD "uninstall $_uninstall_pkg failed. unsupported package manager: $_uninstall_manager" "卸载${_uninstall_pkg}失败，暂不支持包管理：$_uninstall_manager"
      echo "uname -a => ($(uname -a))"
      if [ -f "/etc/os-release" ]; then cat /etc/os-release; fi
  esac
}
readonly _uninstall_

Uninstall(){
  Usage $# -ge 1 'Uninstall <app> [app]...'
  _uninstall_result=0
  for _uninstall_pkg in "$@"; do
    if ! _uninstall_ "$_uninstall_pkg"; then
      _uninstall_result=1
    fi
  done
  return $_uninstall_result
}
export Uninstall
readonly Uninstall

IsAccessible(){
  Usage $# 1 3 'IsAccessible <url> [timeout=5] [install_net_tool=true|false]'
  _isaccessible_url="$1"
  _isaccessible_timeout="${2:-10}"
  _isaccessible_install="${3:-true}"

  _isaccessible_installed=0

  if ! StartWith "$_isaccessible_url" 'http://' 'https://'; then
    _isaccessible_url="https://$_isaccessible_url"
  fi

  if command -v curl >/dev/null 2>&1; then
    _isaccessible_installed=1
    if curl -s -f --connect-timeout "$_isaccessible_timeout" -o /dev/null "$_isaccessible_url" >/dev/null 2>&1; then
      return 0
    fi
  fi

  if command -v wget >/dev/null 2>&1; then
    _isaccessible_installed=1
    if wget --spider --timeout="$_isaccessible_timeout" "$_isaccessible_url" 2>/dev/null; then
      return 0
    fi
  fi

  # in case not install net tool
  if [ "$_isaccessible_installed" -eq 0 ] && [ "$_isaccessible_install" != 'false' ]; then
    if Install curl || Install wget ; then
      if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
        IsAccessible "$_isaccessible_url" "$_isaccessible_timeout" false
      fi
    fi
  fi

  return 1
}
export IsAccessible
readonly IsAccessible

IsWanAccessible(){
  Usage $# -le 1 'IsWanAccessible [-q:quiet]'
  _iswanaccessible_quiet="${1:-}"
  _iswanaccessible_urls='https://google.com https://github.com/aarioai https://hub.docker.com/_/alpine https://kubernetes.io'
  for _iswanaccessible_url in $_iswanaccessible_urls; do
    if ! IsAccessible "$_iswanaccessible_url"; then
      if [ "$_iswanaccessible_quiet" != '-q' ]; then
        WarnD "$_iswanaccessible_url is not accessible" "无法访问 $_iswanaccessible_url"
      fi
      return 1
    fi
  done
}
export IsWanAccessible
readonly IsWanAccessible

HttpCode(){
  Usage $# -ge 1 'HttpCode <url> [max_time=3]'
  _httpcode_url="$1"
  _httpcode_maxtime="${2:-3}"
  if command -v curl >/dev/null 2>&1; then
    curl --max-time "$_httpcode_maxtime" -s -w '%{http_code}\n' -o /dev/null "$_httpcode_url" || printf ''
    return
  fi

  # busybox 系统无curl，也不好安装。但是一般会有wget
  if command -v wget >/dev/null 2>&1; then
    wget --spider --timeout="$_httpcode_maxtime" --tries=1 -S "$_httpcode_url" 2>&1 | awk '/HTTP\// {print $2}' | tail -1 || printf ''
    return
  fi

  if Install curl || Install wget ; then
    if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
      HttpCode "$_httpcode_url" "$_httpcode_maxtime"
    fi
  fi

  PanicD "require install curl or wget" "需要安装 curl 或 wget"
}
export HttpCode
readonly HttpCode

HttpOK(){
  Usage $# -ge 1 'HttpOK <url> [max_time=3]'
  _httpok_code=$(HttpCode "$@")
  case $_httpok_code in
    2??|3??) return 0 ;;
  esac
  return 1
}
export HttpOK
readonly HttpOK

Download(){
  Usage $# 1 2 'Download <url> [output_name]'
  _download_url="$1"
  _download_rename="${2:-"$(basename "$_download_url")"}"

  # 移除查询参数，如 index?a=100&b=200
  _download_rename=$(echo "$_download_rename" | cut -d'?' -f1)

  # curl -f -L -o 的行为（-f 失败时返回非0退出码，-L 跟随重定向，-o 指定输出文件名）
  if command -v curl >/dev/null 2>&1; then
      curl -f -L -o "$_download_rename" "$_download_url"
      return $?
  fi

  # busybox 系统无curl，也不好安装。但是一般会有wget
  if command -v wget >/dev/null 2>&1; then
    wget --tries=1 -O "$_download_rename" "$_download_url"
    return $?
  fi

  if Install curl || Install wget || command -v wget >/dev/null 2>&1; then
    if command -v curl >/dev/null 2>&1; then
      _download_ "$_download_url"
      return $?
    fi
  fi

  Error "missing package curl or wget"
  return 1
}
export Download
readonly Download

Filename(){
  Usage $# 1 2 'Filename <path> [with_ext]'
  _filename=$(basename "$1")
  _filename_with_ext="${2:-}"
  if [ "$_filename_with_ext" = 'with_ext' ]; then
    printf '%s' "$_filename"
    return 0
  fi

  case "$_filename" in
  *.*)
    printf '%s' "${_filename%.*}"
    return 0
    ;;
  esac
  printf '%s' "$_filename"
}
export Filename
readonly Filename

Extname(){
  Usage $# 1 2 'Extname <path> [with_dot]'
  _extname_base=$(basename "$1")
  _extname_with_dot="${2:-}"

  _extname_dot=''
  if [ "$_extname_with_dot" = 'with_dot' ]; then
    _extname_dot='.'
  fi

  case "$_extname_base" in
  *.*)
    printf '%s%s' "$_extname_dot" "${_extname_base##*.}"
    return 0
    ;;
  esac
  printf ''
}
export ExtName
readonly ExtName


FindFileByExt(){
  Usage $# -ge 3 'FindFileByExt <dir> <filename> <ext> [ext]...'
  _findfilebyext_dir="$1"
  _findfilebyext_filename="$2"
  shift 2
  if [ ! -d "$_findfilebyext_dir" ]; then
    printf ''
    return 0
  fi
  for _findfilebyext_ext in "$@"; do
    # remove dot
    _findfilebyext_ext="${_findfilebyext_ext#.}"
    _findfilebyext_path="$_findfilebyext_dir/$_findfilebyext_filename.$_findfilebyext_ext"

    if [ -f "$_findfilebyext_path" ]; then
      printf '%s' "$_findfilebyext_path"
      return 0
    fi
  done
  printf ''
}
export FindFileByExt
readonly FindFileByExt

# 获取字符的ASCII码
EncodeASCII() {
  Usage $# -eq 1 'EncodeASCII <char>'
  printf '%d' "'$1"
}
export EncodeASCII
readonly EncodeASCII

# ASCII码转字符
DecodeASCII() {
  Usage $# -eq 1 'DecodeASCII <char>'
  printf '%b' "\0$(printf '%03o' "$1")"
}
export DecodeASCII
readonly DecodeASCII

# 将字符ASCII码加一个数，返回ASCII码对应的字符
AddASCII() {
  Usage $# 1 2 "AddASCII <char> [add=1]\n  AddASCII <char> 0 => DecodeASCII <char>"
  _addascii_n=$(EncodeASCII "$1")
  _addascii_add=1
  if [ $# -gt 1 ]; then
    _addascii_add=$2
  fi
  DecodeASCII $((_addascii_n + _addascii_add))
}
export AddASCII
readonly AddASCII

# Example:
#   LastN 2 - 'a-b-c-d-e'   ==> d-e
#   LastN 2 / 'a/b/c/d/e'   ==> d/e
LastN(){
  Usage $# -ge 3 'LastN <n:number> <separator> <string>'
  _lastn="$1"
  _lastn_sep="${2:-/}"
  shift 2
  _lastn_s="$*"

  PanicIfNotNumber "$_lastn"

  if [ -z "$_lastn_sep" ] || [ -z "$_lastn_s" ]; then
    printf '%s' "$_lastn_s"
    return
  fi

  _lastn_count=0
  _lastn_result=''
  while [ -n "$_lastn_s" ] && [ "$_lastn_count" -lt "$_lastn" ]; do
    _lastn_last="${_lastn_s##*"$_lastn_sep"}"
    if [ -n "$_lastn_last" ]; then
      if [ -z "$_lastn_result" ]; then
        _lastn_result="$_lastn_last"
      else
        _lastn_result="${_lastn_last}${_lastn_sep}${_lastn_result}"
      fi
      _lastn_count=$((_lastn_count + 1))
    fi
    if [ "$_lastn_s" = "${_lastn_s%/*}" ]; then break; fi
    _lastn_s="${_lastn_s%"${_lastn_sep}${_lastn_last}"}"
  done
  printf '%s' "$_lastn_result"
}

StartWith() {
  Usage $# -ge 2 'if ! StartWith <string> <sub_string> [sub_string...]; then ... fi'
  _startwith_s="$1"
  if [ -z "$_startwith_s" ]; then return 1; fi
  shift

  # | while IFS 通道不能向外面传参，而这种情形下，也不用考虑空格分割问题，可以直接使用 for in "$@"
  for _startwith_sub in "$@"; do
    if [ -n "$_startwith_sub" ]; then
      case "$_startwith_s" in
      "$_startwith_sub"*) return 0 ;;
      esac
    fi
  done
  return 1
}
export StartWith
readonly StartWith

EndWith() {
  Usage $# -ge 2 'if ! EndWith <string> <sub_string> [sub_string...]; then ... fi'
  _endwith_s="$1"
  if [ -z "$_endwith_s" ]; then return 1; fi
  shift

  # | while IFS 通道不能向外面传参，而这种情形下，也不用考虑空格分割问题，可以直接使用 for in "$@"
  for _endwith_sub in "$@"; do
    if [ -n "$_endwith_sub" ]; then
      case "$_endwith_s" in
      *"$_endwith_sub") return 0 ;;
      esac
    fi
  done
  return 1
}
export EndWith
readonly EndWith

StrRepeat() {
  Usage $# 1 2 'StrRepeat <length> [str=" "]'
  _strrepeat_n=$1
  _strrepeat_str=${2:-" "}
  _strrepeat_i=0
  while [ "$_strrepeat_n" -gt "$_strrepeat_i" ]; do
    printf '%s' "$_strrepeat_str"
    _strrepeat_i=$((_strrepeat_i + 1))
  done
}
export StrRepeat
readonly StrRepeat


StrPad(){
  Usage $# 2 4 'StrPad <string> <length> [padding=" "] [pad_left=0]'
  _strpad_s="$1"
  _strpad_n="$2"
  _strpad_padding="${3:-" "}"
  _strpad_left="${4:-0}"
  _strpad_sn=${#_strpad_s}
  _strpad_x=$(( _strpad_n - _strpad_sn ))
  _strpad_padding=''
  if [ "$_strpad_x" -gt 0 ]; then
    _strpad_padding="$(StrRepeat $_strpad_x "$_strpad_padding")"
  fi
  if [ "$_strpad_left" -eq 1 ]; then
    _strpad_s="${_strpad_padding}${_strpad_s}"
  else
    _strpad_s="${_strpad_s}${_strpad_padding}"
  fi
  printf '%s' "$_strpad_s"
}
export StrPad
readonly StrPad

StrPadLeft(){
  Usage $# 2 3 'StrPadLeft <string> <length> [padding=" "]'
  _strpadleft_s="$1"
  _strpadleft_n="$2"
  _strpadleft_padding="${3:-" "}"
  StrPad "$_strpadleft_s" "$_strpadleft_n" "$_strpadleft_padding" 1
}
export StrPadLeft
readonly StrPadLeft

# Convert all characters into a specific character
ToPlaceholder(){
  Usage $# -ge 1 'ToPlaceholder [char=" "] <string>'
  _toplaceholder_char=' '
  _toplaceholder_s="$1"
  if [ $# -gt 1 ] && [ "${#1}" -eq 1 ]; then
    _toplaceholder_char="$1"
    shift
    _toplaceholder_s="$*"
  fi
  _toplaceholder_s_len=${#_toplaceholder_s}
  StrRepeat "$_toplaceholder_s_len" "$_toplaceholder_char"
}
export ToPlaceholder
readonly ToPlaceholder

AlignKVPair(){
  Usage $# 4 5 'AlignKVPair <key> <align_length> <separator> <value> [pad_length=2]'
  _alignkvpair_key="$1"
  _alignkvpair_keyalign="$2"
  _alignkvpair_sep="$3"
  _alignkvpair_value="$4"
  _alignkvpair_valuepad="${5:-2}"
  StrPad "$_alignkvpair_key" "$_alignkvpair_keyalign"
  printf '%s' "$_alignkvpair_sep"
  if [ "$_alignkvpair_valuepad" -gt 0 ]; then StrRepeat "$_alignkvpair_valuepad" ' '; fi
  printf '%s' "$_alignkvpair_value"
}
export AlignKVPair
readonly AlignKVPair

# Get the 1st character
FirstChar() {
  Usage $# -eq 1 'FirstChar <string>'
  printf %.1s "$1"
}
export FirstChar
readonly FirstChar

# 从左边移除n个字符
# Required: StrRepeat
CutLeft() {
  Usage $# -ge 2 'CutLeft <length> {string}'
  _cutleft_n=$1
  shift
  # See: https://github.com/koalaman/shellcheck/wiki/SC2124
  _cutleft_s=$(printf '%s\n' "$@")
  _cutleft_is_first_line=1
  printf '%s\n' "$_cutleft_s" | while IFS= read -r _cutleft_line; do
    if [ "$_cutleft_n" -le 0 ]; then
      if [ "$_cutleft_is_first_line" -ne 1 ]; then printf '\n'; fi
      _cutleft_is_first_line=0
      if [ -n "$_cutleft_line" ]; then printf '%s' "$_cutleft_line"; fi
      continue
    fi
    _cutleft_n=$((_cutleft_n - ${#_cutleft_line}))
    if [ "$_cutleft_n" -eq 0 ]; then
      if [ "$_cutleft_is_first_line" -ne 1 ]; then printf '\n'; fi
      _cutleft_is_first_line=0
      continue
    fi
    if [ "$_cutleft_n" -eq 1 ]; then
      _cutleft_n=0
      continue
    fi
    if [ "$_cutleft_n" -gt 1 ]; then
      _cutleft_n=$((_cutleft_n - 1))
      continue
    fi

    # 刚好在该行内截取结束
    if [ "$_cutleft_is_first_line" -ne 1 ]; then printf '\n'; fi
    _cutleft_is_first_line=0

    _cutleft_cut_range=$(( ${#_cutleft_line} + _cutleft_n + 1 ))
    # cut -c 这种写法，遇到尾部空格，会被转为换行符LF，因此需要处理一下
    _cutleft_cut_end_blank=$(printf '%s' "$_cutleft_line" | cut -c "${_cutleft_cut_range}-")
    _cutleft_cut_end_len=${#_cutleft_cut_end_blank}
    # printf 把尾部换行符全部移除
    _cutleft_cut_end_blank=$(printf '%s' "$_cutleft_cut_end_blank")
    _cutleft_cut_end_len=$(( _cutleft_cut_end_len - ${#_cutleft_cut_end_blank} ))

    if [ -n "$_cutleft_cut_end_blank" ]; then printf '%s' "$_cutleft_cut_end_blank"; fi
    # 填充尾部空格
    if [ "$_cutleft_cut_end_len" -gt 0 ]; then StrRepeat "$_cutleft_cut_end_len"; fi

    _cutleft_n=0
  done
}
export CutLeft
readonly CutLeft

# Warn: $() 获取时，尾部的换行符一律会被截取掉
# Required: CutLeft
Substr() {
  Usage $# 2 3 'Substr <string> <start:number> [length]'
  _substr_s="$1"
  _substr_start=$2
  _substr_len=${#_substr_s}
  _substr_length=${3:-"$_substr_len"}
  if [ "$_substr_start" -lt 0 ]; then _substr_start=$((_substr_len + _substr_start)); fi
  if [ "$_substr_length" -le 0 ]; then Panic "Substr: invalid length"; fi
  if [ "$_substr_start" -gt 0 ]; then _substr_s=$(CutLeft "$_substr_start" "$_substr_s"); fi

  _substr_is_first_line=1
  _substr_value=$(printf '%s\n' "$_substr_s" | while IFS= read -r _substr_line; do
    # 第一行为空，表示上面截取掉导致第一个字符是换行符
    if [ -z "$_substr_line" ]; then _substr_is_first_line=0; fi

    _substr_length_temp="$_substr_length"
    _substr_length=$((_substr_length - ${#_substr_line}))

    if [ "$_substr_length" -gt 1 ]; then
      if [ "$_substr_is_first_line" -ne 1 ]; then printf '\n'; fi
      _substr_is_first_line=0
      if [ -n "$_substr_line" ]; then printf '%s' "$_substr_line"; fi
      _substr_length=$((_substr_length - 1))
      continue
    fi

    if [ "$_substr_length" -eq 1 ]; then
      if [ "$_substr_is_first_line" -ne 1 ]; then printf '\n'; fi
      _substr_is_first_line=0
      if [ -n "$_substr_line" ]; then printf '%s' "$_substr_line"; fi
      return 0
    fi
    if [ "$_substr_length" -eq 0 ]; then
      if [ "$_substr_is_first_line" -ne 1 ]; then printf '\n'; fi
      _substr_is_first_line=0
      if [ -n "$_substr_line" ]; then printf '%s' "$_substr_line"; fi
      return 0
    fi

    printf '%s' "$_substr_line" | cut -c "-${_substr_length_temp}"
    return 0
  done)

  # 必须要这个处理，因为上面多了换行符。通过 printf 移除尾部换行符
  printf '%s' "$_substr_value"
}
export Substr
readonly Substr

# POSIX 不支持 ${s::} 切片方法，所以这里重新写
# Example:
#   Substring "Aario" -1    => o
#   Substring "Aario" -2    => io
#   Substring "Aario" 1 -1  => ari
# Required: Substr
Substring() {
  Usage $# 2 3 'Substring <string> <start:number> [end]'
  _substring_s="$1"
  _substring_start=$2
  _substring_len=${#_substring_s}
  _substring_end=${3:-"$_substring_len"}
  if [ "$_substring_start" -lt 0 ]; then _substring_start=$((_substring_len + _substring_start)); fi
  if [ "$_substring_end" -le 0 ]; then _substring_end=$((_substring_len + _substring_end)); fi
  if [ "$_substring_end" -le "$_substring_start" ]; then Panic "Substring: end(${_substring_end}) must greater than start(${_substring_start})"; fi
  if [ "$_substring_end" -eq "$_substring_start" ]; then printf '%s' "$_substring_s"; fi
  Substr "$_substring_s" "$_substring_start" "$((_substring_end - _substring_start))"
}
export Substring
readonly Substring

# 把左侧所有匹配的字符，全部删除
# Required: Substr
TrimLeft() {
  Usage $# 1 2 'TrimLeft <string> [cut=" "]'
  _trimleft_s="$1"
  _trimleft_cut=${2:-' '}
  _trimleft_l=${#_trimleft_cut}
  while [ ${#_trimleft_s} -gt "$_trimleft_l" ]; do
    _trimleft_seg=$(Substr "$_trimleft_s" 0 "$_trimleft_l")
    if [ "$_trimleft_seg" != "$_trimleft_cut" ]; then
      printf '%s' "$_trimleft_s"
      return 0
    fi
    _trimleft_s=$(Substr "$_trimleft_s" "$_trimleft_l")
  done
  printf '%s' "$_trimleft_s"
}
export TrimLeft
readonly TrimLeft

# 把右侧所有匹配的字符，全部删除
# Required: Substr, Substring
TrimRight() {
  Usage $# 1 2 'TrimRight <string> [cut=" "]'
  _trimright_s="$1"
  _trimright_cut=${2:-' '}
  _trimright_l=${#_trimright_cut}
  while [ ${#_trimright_s} -gt "$_trimright_l" ]; do
    _trimright_seg=$(Substr "$_trimright_s" "-$_trimright_l")
    if [ "$_trimright_seg" != "$_trimright_cut" ]; then
      printf '%s' "$_trimright_s"
      return 0
    fi
    _trimright_s=$(Substring "$_trimright_s" 0 "-$_trimright_l")
  done
  printf '%s' "$_trimright_s"
}
export TrimRight
readonly TrimRight

# 把两侧所有匹配的字符，全部删除
# Required: TrimLeft, TrimRight
Trim() {
  Usage $# 1 2 'Trim <string> [cut=" "]'
  _trim_s="$1"
  _trim_cut=${2:-' '}
  _trim_s=$(TrimLeft "$_trim_s" "$_trim_cut")
  _trim_s=$(TrimRight "$_trim_s" "$_trim_cut")
  printf '%s' "$_trim_s"
}
export Trim
readonly Trim

# string IndexOf
# Required: Substr
IndexOf() {
  Usage $# -ge 2 'IndexOf <sub_string> {string}'
  _indexof_sub="$1"
  shift
  # See: https://github.com/koalaman/shellcheck/wiki/SC2124
  _indexof_s=$(printf '%s\n' "$@")
  _indexof_len=${#_indexof_s}
  _indexof_l=${#_indexof_sub}

  _indexof_index=0
  _indexof_result=$(printf '%s\n' "$_indexof_s" | while IFS= read -r _indexof_line; do
    _indexof_line_len=${#_indexof_line}
    # 对换行符，只能匹配单个换行符，不能跨行匹配
    if [ "$_indexof_sub" = "$LF" ] || [ "$_indexof_sub" = "\n" ]; then
      printf '%d' "$_indexof_line_len"
      return 0
    fi

    # 只在单行内匹配，不跨行匹配（即不能包括换行符）
    _indexof_i=0
    while [ "$_indexof_i" -lt "$_indexof_line_len" ]; do
      _indexof_next=$(Substr "$_indexof_line" "$_indexof_i" "$_indexof_l")
      if [ "$_indexof_next" = "$_indexof_sub" ]; then
        printf '%d' $((_indexof_index + _indexof_i))
        return 0
      fi
      _indexof_i=$((_indexof_i + 1))
    done
    _indexof_index=$((_indexof_index + _indexof_line_len + 1))
  done)

  if [ -z "$_indexof_result" ]; then _indexof_result=-1; fi
  printf '%d' "$_indexof_result"
}
export IndexOf
readonly IndexOf

StrIn() {
  Usage $# -ge 2 'if StrIn <sub_string> {string}; then ... fi'
  _strin_sub="$1"
  shift
  _strin_s="$*"
  if [ "${_strin_s#*"$_strin_sub"}" = "$_strin_s" ]; then
    return 1
  fi
}
export StrIn
readonly StrIn

SliceIn(){
  Usage $# -ge 1 'if SliceIn <sub_string> {string}; then ... fi'
  _slicein_sub="$1"
  shift
  _slicein_s="$*"
  # append and prepend spaces
  if ! StrIn " $_slicein_sub " " $_slicein_s "; then
    return 1
  fi
}
export SliceIn
readonly SliceIn

# Count matches. Not support LF 统计匹配次数。只能单独统计匹配单个换行符（会自动忽略尾部换行符），不能跨行匹配
# Required: Substr
CountMatches() {
  Usage $# -ge 1 'CountMatches <sub_string> {string}'
  _countmatches_sub="$1"
  shift
  # See: https://github.com/koalaman/shellcheck/wiki/SC2124
  _countmatches_s=$(printf '%s\n' "$@")
  _countmatches_sublen=${#_countmatches_sub}
  _countmatches_is_first_line=1
  _countmatches_counting=$(printf '%s\n' "$_countmatches_s" | while IFS= read -r _countmatches_line; do
    if IsLF "$_countmatches_sub"; then
      if [ "$_countmatches_is_first_line" -eq 1 ]; then
        _countmatches_is_first_line=0
      else
        printf '|'
      fi
      continue
    fi
    if [ -z "$_countmatches_line" ]; then
      continue
    fi
    _countmatches_i=0
    _countmatches_line_len=${#_countmatches_line}
    while [ $_countmatches_i -lt "$_countmatches_line_len" ]; do
      _countmatches_cutlen=$(Substr "$_countmatches_line" "$_countmatches_i" "$_countmatches_sublen")
      if [ "$_countmatches_cutlen" = "$_countmatches_sub" ]; then
        printf '|'
        _countmatches_i=$((_countmatches_i + _countmatches_sublen))
      else
        _countmatches_i=$((_countmatches_i + 1))
      fi
    done
  done)

  printf '%d' "${#_countmatches_counting}"
}
export CountMatches
readonly CountMatches

# Replace matched string
# Required: IndexOf, Substr, CutLeft, Replace
Replace() {
  Usage $# 3 4 'Replace <string> <old> <new> [n=1 replace once, otherwise replace all]'
  _replace_s=$1
  _replace_old=$2
  _replace_new="$3"
  _replace_all=1 #
  if [ $# -ge 4 ] && [ "$4" -eq 1 ]; then _replace_all=0; fi

  _replace_index=$(IndexOf "$_replace_old" "$_replace_s")

  if [ "$_replace_index" -lt 0 ]; then
    printf '%s' "$_replace_s"
    return 0
  fi

  if [ "$_replace_index" -gt 0 ]; then Substr "$_replace_s" 0 "${_replace_index}"; fi
  printf '%s' "$_replace_new"
  _replace_next=$((_replace_index + ${#_replace_old}))

  _replace_s=$(CutLeft "${_replace_next}" "$_replace_s")

  if [ "$_replace_all" -eq 0 ]; then
    printf '%s' "$_replace_s"
    return 0
  fi

  Replace "$_replace_s" "$_replace_old" "$_replace_new"
}
export Replace
readonly Replace


# 替换所有的换行符 LF 为两个字符 '\n'
# Warn: 传参会移除掉尾部换行符，但是不会移除开头的换行符
PackLF() {
  printf '%s' "$*" | {
    cat -u
    printf '\n'
  } | awk -v ORS= '{print sep $0; sep="\\n"}'
}
export PackLF
readonly PackLF

# 替换所有两个字符 \n 为一个换行符 LF
UnpackLF() {
  printf "${*}%s" ''
}
export UnpackLF
readonly UnpackLF

# Replace all \n
ReplaceLF(){
  Usage $# 1 2 'ReplaceLF <string> [to=" "]'
  _replacelf="$1"
  _replacelf_to="${2-" "}" # $2='' 不会匹配
  if [ "$_replacelf_to" = "/" ] || [ "$_replacelf_to" = "#" ] || [ "$_replacelf_to" = "\$" ]; then
    _replacelf_to="\\${_replacelf_to}"
  fi
  printf '%s' "$_replacelf" | sed ":a;N;\$!ba;s/\n/$_replacelf_to/g"
}
export ReplaceLF
readonly ReplaceLF

# Replace all LF and "\n" into spaces, trailing LFs will be ignored
ReplaceLFToSpace() {
  _replacelftospace_usage=$(cat << EOF
ReplaceLFToSpace <flag> {string}
  flag: 0  remove head spaces, and combine consecutive spaces into one
        1  keep all spaces
        2  remove head spaces only
        3  combine consecutive spaces into one only
EOF
)
  Usage $# -ge 1 "$_replacelftospace_usage"
  _replacelftospace_flag="$1"
  shift
  # See: https://github.com/koalaman/shellcheck/wiki/SC2124
  _replacelftospace_s=$(printf '%s\n' "$@")
  _replacelftospace_is_first_line=1
  printf '%s\n' "$_replacelftospace_s" | while IFS= read -r _replacelftospace_line; do
    if [ "$_replacelftospace_line" = "" ]; then
      case "$_replacelftospace_flag" in
      0) continue ;;
      1) ;;
      2) if [ "$_replacelftospace_is_first_line" -ne 0 ]; then continue; fi ;;
      3)
        if [ "$_replacelftospace_is_first_line" -eq 1 ]; then
          printf ' '
        else
          continue
        fi
        ;;
      *) Panic "invalid tag ${_replacelftospace_flag}" ;;
      esac
    fi

    if [ "$_replacelftospace_is_first_line" -eq 0 ]; then
      printf ' '
    else
      _replacelftospace_is_first_line=0
    fi

    printf '%s' "$_replacelftospace_line" | sed 's/\\n/ /g' # \n is not LF, it's `\` + `n`
  done
}
export ReplaceLFToSpace
readonly ReplaceLFToSpace

# Replace all spaces into LF, trailing LFs will be ignored
ReplaceSpaceToLF() {
  Usage $# -ge 1 'ReplaceSpaceToLF {string} | while IFS= read -r <line>; do ...; done'
  printf '%s\n' "$@" | tr ' ' '\n'
}
export ReplaceSpaceToLF
readonly ReplaceSpaceToLF

# 数组长度
# Required: ReplaceSpaceToLF
SliceLen() {
  Usage $# -ge 1 'SliceLen {string}'
  # See: https://github.com/koalaman/shellcheck/wiki/SC2124
  _slicelen_s=$(printf '%s\n' "$@")
  _slicelen_counting=$(printf '%s\n' "$_slicelen_s" | while IFS= read -r _slicelen_line; do
    if [ -z "$_slicelen_line" ]; then continue; fi
    ReplaceSpaceToLF "$_slicelen_line" | while IFS= read -r _slicelen_item; do
      if [ -z "$_slicelen_item" ]; then continue; fi
      printf '|'
    done
  done)
  #printf '%s' "$_slicelen_counting"
  printf '%d' "${#_slicelen_counting}"
}
export SliceLen
readonly SliceLen

# POSIX 不支持数组，所以这里写了个方法。
# Warn: 单个元素不能包含空格，否则会被分拆扩展为新数组
#   index 为负数，表示第index个（含）之后所有都合并
# Require: ReplaceSpaceToLF
Slice() {
  Usage $# -ge 2 'Slice <index:number> {slice}'
  _slice_index=$1
  shift
  _slice_i=0
  _slice_merge=0
  if [ "$_slice_index" -lt 0 ]; then
    _slice_merge=1
    _slice_index=$(( 0 - _slice_index ))
  fi

  ReplaceSpaceToLF "$@" | while IFS= read -r _slice_seg; do
    # 排除连续多个空格
    if [ -z "$_slice_seg" ]; then
      continue
    fi
    if [ "$_slice_i" -eq "$_slice_index" ]; then
      printf '%s' "$_slice_seg"
      if [ "$_slice_merge" -ne 1 ];then return 0; fi
    elif [ "$_slice_i" -gt "$_slice_index" ];then
      printf ' %s' "$_slice_seg"  # append a space
    fi
    _slice_i=$((_slice_i + 1)) # 内部可以使用一次外部传进来的值，并且通道内复用。但是不能再传出去了
  done
}
export Slice
readonly Slice

# Split string
# Required: Replace
Split() {
  Usage $# 1 3 "Split <strings> [delimiter=,] [merge=0 merge continuous delimiters]\n  Split <string> | while IFS= read -r xxx; do ... done"
  _split_s="$1"
  _split_delimiter=${2:-","}
  _split_merge=${3:-0}
  _split_dl=${#_split_delimiter}
  if [ -z "$_split_s" ]; then return 0; fi
  if [ "$_split_dl" -ne 1 ]; then Panic "Split: delimiter must be one byte, got: ${_split_delimiter}"; fi
  _split_prev_sep=0
  while [ "${#_split_s}" -gt 0 ]; do
    _split_s_first=$(FirstChar "$_split_s")
    _split_s=$(printf '%s' "$_split_s" | cut -c '2-')
    if [ "$_split_s_first" != "$_split_delimiter" ] && [ "$_split_s_first" != "$LF" ]; then
      printf '%s' "$_split_s_first"
      _split_prev_sep=0
      continue
    fi
    # merge continuous delimiters
    if [ "$_split_merge" -eq 1 ] && [ "$_split_prev_sep" -eq 1 ]; then
      continue
    fi
    _split_prev_sep=1
    printf '%s' "$LF"
  done
  Replace "$_split_s" "$_split_delimiter" "$LF" # 使用换行符，方便遍历
  printf '\n'  # 尾部增加一个换行符，方便 | while IFS ...
}
export Split
readonly Split

# Split array-like [a,b,c] or a,b,c
SplitArray() {
  Usage $# -ge 1 'SplitArray {string} | while IFS= read -r <item>; do ...; done'
  _parsearray_input="$*"
  if [ -z "$_parsearray_input" ]; then return 0; fi
  _parsearray_input=$(TrimLeft "$_parsearray_input" '[')
  _parsearray_input=$(TrimRight "$_parsearray_input" ']')
  Split "$_parsearray_input"
}
export SplitArray
readonly SplitArray

# Join array string into string
# Required: ReplaceSpaceToLF
Join() {
  Usage $# -ge 2 "Join <separators> {slice}\n  Join --- 'a b c' 'd'"
  _join_delimiter="$1"
  shift
  _join_first=1

  ReplaceSpaceToLF "$@" | while IFS= read -r _join_seg; do
    # 通道可以将外界值传进来，并且期间可以改变。但是传不出去。
    # 因此 first 修改之后，通道内可以重复使用，但是通道外值不会变
    if [ "$_join_first" -eq 1 ]; then
      _join_first=0
      printf '%s' "$_join_seg"
    else
      printf '%s' "${_join_delimiter}${_join_seg}"
    fi
  done
}
export Join
readonly Join

# Count words in a sentence that split with spaces
CountWords(){
  Usage $# -ge 1 'CountWords {string>'
  printf "%s" "$*" | awk '
  BEGIN { total = 0 }
  {
    for(i=1; i<=NF; i++) {
      if($i != "") total++
    }
  }
  END { print total }'
}
export CountWords
readonly CountWords

# Find the index of the word in a sentence
# Return: -1 not found
WordIndex(){
  Usage $# -ge 2 'WordIndex <word> {string}'
  _wordindex="$1"
  shift
  printf '%s' "$*" | awk -v target="$_wordindex" '{
    for(i=1; i<=NF; i++) {
      if($i == target) {
        print i-1
        exit
      }
    }
    print -1
  }'
}
export WordIndex
readonly WordIndex

WordIn(){
  Usage $# -ge 2 'WordIn <word> {string} => if ! WordIn <word> {string}; then ... fi'
  _wordin_index=$(WordIndex "$@")
  if [ "$_wordin_index" -lt 0 ]; then
    return 1
  fi
}

# Get the word in the nth position in a sentence
NthWord(){
  Usage $# -eq 2 'NthWord <n> {string}'
  _nthword="$1"
  shift
  printf '%s' "$*" | awk -v n="$_nthword" '{
    if(n >= 0 && n < NF) {
      print $(n+1)
    } else {
      print ""
    }
  }'
}
export NthWord
readonly NthWord

# Get nth to from end mth words
WordsBetween(){
  Usage $# -ge 3 'WordsBetween <nth> <end_nth> {sentence}'
  _wordsbetween_start="$1"
  _wordsbetween_from_end="$2"
  shift 2
  _wordsbetween_str="$*"

  # 处理空字符串
  if [ -z "$_wordsbetween_str" ]; then
    printf '%s' ''
    return 0
  fi

  # 保存原来的 IFS
  _wordsbetween_old_IFS="$IFS"

  # 设置 IFS 为空格进行分词
  IFS=' '

  # 将字符串拆分为位置参数
  # shellcheck disable=SC2086    # 不要加引号
  set -- $_wordsbetween_str
  _wordsbetween_total_words=$#

  # 恢复原来的 IFS
  IFS="$_wordsbetween_old_IFS"

  # 处理起始索引（从0开始）
  if [ "$_wordsbetween_start" -lt 0 ]; then
    _wordsbetween_start=$((_wordsbetween_total_words + _wordsbetween_start))
    if [ "$_wordsbetween_start" -lt 0 ]; then
      _wordsbetween_start=0
    fi
  fi

  # 计算实际结束位置（从0开始计数）
  # 倒数第m个单词的位置 = 总单词数 - m
  # 这样当 m=1 时，结束位置就是最后一个单词（总单词数-1）
  _wordsbetween_real_end=$((_wordsbetween_total_words - _wordsbetween_from_end))

  # 边界检查和处理结束位置
  if [ "$_wordsbetween_real_end" -lt 0 ]; then
    _wordsbetween_real_end=0
  fi
  if [ "$_wordsbetween_real_end" -ge "$_wordsbetween_total_words" ]; then
    _wordsbetween_real_end=$((_wordsbetween_total_words - 1))
  fi

  # 检查范围有效性
  if [ "$_wordsbetween_start" -ge "$_wordsbetween_total_words" ]; then
    return 1
  fi

  if [ "$_wordsbetween_real_end" -lt "$_wordsbetween_start" ]; then
    return 1
  fi

  # 计算需要输出的单词数量
  _wordsbetween_word_count=$((_wordsbetween_real_end - _wordsbetween_start + 1))

  # 检查单词数量是否有效
  if [ "$_wordsbetween_word_count" -le 0 ]; then
    return 1
  fi

  # 重新设置 IFS 进行分词
  IFS=' '
  # shellcheck disable=SC2086    # 不要加引号
  set -- $_wordsbetween_str

  # 移动到起始位置
  shift "$_wordsbetween_start"

  # 输出范围内的单词
  _wordsbetween_result=""
  _wordsbetween_current_count=0

  while [ "$_wordsbetween_current_count" -lt "$_wordsbetween_word_count" ] && [ $# -gt 0 ]; do
    if [ "$_wordsbetween_current_count" -eq 0 ]; then
      _wordsbetween_result="$1"
    else
      _wordsbetween_result="$_wordsbetween_result $1"
    fi
    shift
    _wordsbetween_current_count=$((_wordsbetween_current_count + 1))
  done

  # 输出结果，不追加换行符
  printf '%s' "$_wordsbetween_result"
}
export WordsBetween
readonly WordsBetween


# Get nth to mth words
# Require: WordsBetween
WordsRange(){
  Usage $# -ge 2 'WordsRange <start:number> <end:number> {words} => WordsRange 0 -1 "I Love You"'
  _wordsrange_start="$1"
  _wordsrange_end="$2"
  shift 2
  _wordsrange_str="$*"

  if [ -z "$_wordsrange_str" ]; then
    printf '%s' ''
    return 0
  fi

  if [ "$_wordsrange_end" -lt 0 ]; then
    _wordsrange_end="${_wordsrange_end#-}"
    WordsBetween "$_wordsrange_start" "$_wordsrange_end" "$_wordsrange_str"
    return 0
  fi

  # 将字符串拆分为单词数组
  IFS=' '
  # shellcheck disable=SC2086    # 不要加引号
  set -- $_wordsrange_str
  _wordsrange_total_words=$#

  # 处理起始索引
  if [ "$_wordsrange_start" -lt 0 ]; then
    _wordsrange_start=$((_wordsrange_total_words + _wordsrange_start))
    if [ "$_wordsrange_start" -lt 0 ]; then
      _wordsrange_start=0
    fi
  fi

  # 处理结束索引（不包括第m个）
  if [ "$_wordsrange_end" -lt 0 ]; then
    _wordsrange_end=$((_wordsrange_total_words + _wordsrange_end))
  fi

  # 边界检查
  if [ "$_wordsrange_start" -ge "$_wordsrange_total_words" ]; then
    printf '%s' ""
    return 1
  fi

  # 调整结束索引（确保在有效范围内）
  if [ "$_wordsrange_end" -le "$_wordsrange_start" ]; then
    printf '%s' ""
    return 1
  fi

  if [ "$_wordsrange_end" -gt "$_wordsrange_total_words" ]; then
    _wordsrange_end="$_wordsrange_total_words"
  fi

  # 计算需要输出的单词数量（不包括第m个）
  _wordsrange_word_count=$((_wordsrange_end - _wordsrange_start))

  # 移动到起始位置
  shift "$_wordsrange_start"

  # 输出范围内的单词
  _wordsrange_result=""
  _wordsrange_current_count=0

  while [ "$_wordsrange_current_count" -lt "$_wordsrange_word_count" ] && [ $# -gt 0 ]; do
    if [ -z "$_wordsrange_result" ]; then
      _wordsrange_result="$1"
    else
      _wordsrange_result="$_wordsrange_result $1"
    fi
    shift
    _wordsrange_current_count=$((_wordsrange_current_count + 1))
  done

  printf '%s' "$_wordsrange_result"
}
export WordsRange
readonly WordsRange

# Require: CountWords, WordIndex, NthWord
ProcessMatch(){
  Usage $# -ge 2 'ProcessMatch <flag> {process/pid sub match} => if ! ProcessMatch -x "mysql"; then ...; fi'

  _processmatch_flag="$1"
  shift
  _processmatch_command="$*"
  if ! command -v ps >/dev/null 2>&1; then
    Install procps
    return 0
  fi

  _processmatch_matched_n=''
  _processmatch_matched_n_pid=''
  _processmatch_matched_n_command=''
  _processmatch_matched_n_command_end=''
  # alpine 不支持 -o command（得用comm）且不支持 --no-headers
  # git-bash 里面 ps 不支持 -o -x
  # ps -f 是兼容性最大的
  _processmatch_matched=$(ps -f | while IFS= read -r _processmatch_ps; do
    if [ -z "$_processmatch_matched_n" ]; then
      _processmatch_matched_n="$(CountWords "$_processmatch_ps")"
      _processmatch_matched_n_pid="$(WordIndex 'PID' "$_processmatch_ps")"
      _processmatch_matched_n_command="$(WordIndex 'COMMAND' "$_processmatch_ps")"
      if [ -z "$_processmatch_matched_n_command" ] || [ "$_processmatch_matched_n_command" -lt 0 ]; then
        # alpine 可能会使用 CMD
        _processmatch_matched_n_command="$(WordIndex 'CMD' "$_processmatch_ps")"
      fi
      _processmatch_matched_n_command_end="$((_processmatch_matched_n - _processmatch_matched_n_command))"
      continue
    fi
    _processmatch_pid="$(NthWord "$_processmatch_matched_n_pid" "$_processmatch_ps")"
    if [ "$_processmatch_pid" = "$_processmatch_command" ]; then
      printf '%s' "$_processmatch_pid"
      break
    fi
    _processmatch_cmd="$(WordsBetween "$_processmatch_matched_n_command" "$_processmatch_matched_n_command_end" "$_processmatch_ps")"
    if StrIn "$_processmatch_command" "$_processmatch_cmd"; then
      printf '%s' "$_processmatch_cmd"
      break
    fi
  done)

  if [ -z "$_processmatch_matched" ]; then return 1; fi
}
export ProcessMatch
readonly ProcessMatch

# Matches the first process of current session user
# Require: ProcessMatch
MyProcessMatch(){
  Usage $# -ge 1 'MyProcessMatch {process/pid sub match} => if ! MyProcessMatch "mysql"; then ...; fi'
  ProcessMatch -x "$@"
}
export MyProcessMatch
readonly MyProcessMatch

# Matches the first process of all users
# Require: ProcessMatch
AllProcessMatch(){
  Usage $# -ge 1 'AllProcessMatch {process/pid sub match} => if ! AllProcessMatch "mysql"; then ...; fi'
  ProcessMatch -ax "$@"
}
export AllProcessMatch
readonly AllProcessMatch

# Require: ProcessMatch
AwaitProcessStartup(){
  Usage $# -ge 2 'AwaitProcessStartup <flag> {process/pid sub match}'
  if [ $# -le 2 ]; then return 0; fi
  _awaitprocessstart_maxtry=100
  _awaitprocessstart_i=0
  _awaitprocessstart_cmd="$*"
  while ! ProcessMatch "$@";do
    if [ "$_awaitprocessstart_i" -gt "$_awaitprocessstart_maxtry" ]; then Panic "no process: ps ${_awaitprocessstart_cmd}"; fi
    _awaitprocessstart_i=$(( _awaitprocessstart_i + 1 ))
    Debug "awaiting process startup: ps ${_awaitprocessstart_cmd}"
    sleep "$_awaitprocessstart_i"
  done
}
export AwaitProcessStartup
readonly AwaitProcessStartup

# Require: AwaitProcessStartup
AwaitMyProcessStartup(){
  Usage $# -ge 1 'AwaitMyProcessStartup {process/pid sub match}'
  AwaitProcessStartup 'x' "$@"
}
export AwaitMyProcessStartup
readonly AwaitMyProcessStartup

# Require: AwaitProcessStartup
AwaitAllProcessStartup(){
  Usage $# -ge 1 'AwaitAllProcessStartup {process/pid sub match}'
  AwaitProcessStartup 'ax' "$@"
}
export AwaitAllProcessStartup
readonly AwaitAllProcessStartup

SendCrossServiceSignal(){
  if [ -n "${AA_CROSS_SERVICE_SIGNAL:-}" ]; then printf '\nAA_CROSS_SERVICE_SIGNAL=%s\n' "$AA_CROSS_SERVICE_SIGNAL"; fi
}
export SendCrossServiceSignal
readonly SendCrossServiceSignal

# Require: AwaitMyProcessStartup, SendCrossServiceSignal
AwaitMyProcessCrossServiceSignal() {
  Usage $# -ge 1 'AwaitMyProcessCrossServiceSignal {process/pid sub match}'
  AwaitMyProcessStartup "$@"
  SendCrossServiceSignal
}
export AwaitMyProcessCrossServiceSignal
readonly AwaitMyProcessCrossServiceSignal

# Require: AwaitAllProcessStartup, SendCrossServiceSignal
AwaitCrossServiceSignal() {
  Usage $# -ge 1 'AwaitCrossServiceSignal {process/pid sub match}'
  AwaitAllProcessStartup "$@"
  SendCrossServiceSignal
}
export AwaitCrossServiceSignal
readonly AwaitCrossServiceSignal

# Export profile and save into profile
ExportProfile(){
  Usage $# 2 3 'ExportProfile <key> <value> [destine=/etc/profile]'
  _exportprofile_key="$1"
  _exportprofile_value="$2"
  _exportprofile_dst=${3:-"/etc/profile"}

  if [ -z "$_exportprofile_value" ]; then return 0; fi

  export "${_exportprofile_key}=${_exportprofile_value}"

  if [ -f "$_exportprofile_dst" ]; then
    _exportprofile_pattern="^\s*export\s+${_exportprofile_key}\s*=\s*=${_exportprofile_value}\s*$"
    InstallGrep
    if grep -E "$_exportprofile_pattern" "$_exportprofile_dst" >/dev/null 2>&1; then
      return 0
    fi
  else
    touch "$_exportprofile_dst"
  fi

  if [ ! -w "$_exportprofile_dst" ]; then
    Warn "export ${_exportprofile_key}=${_exportprofile_value} failed. ${_exportprofile_dst} is not writable"
    return 0
  fi
  sed -i "/^\s*export\s*${_exportprofile_key}\s*=.*/d" "$_exportprofile_dst" >/dev/null 2>&1
  printf "export %s=%s\n" "$_exportprofile_key" "$_exportprofile_value" >> "$_exportprofile_dst"
}
export ExportProfile
readonly ExportProfile

AbsDir() {
  # shellcheck disable=SC2016
  Usage $# -eq 1 'AbsDir <path> => bash: AbsDir "${BASH_SOURCE[0]}"; posix: AbsDir "$0"'
  _fulldir_file="${1:-.}"
  printf '%s' "$(cd "$(dirname "$_fulldir_file")" && pwd)"
}
export AbsDir
readonly AbsDir

ParentDir(){
  Usage $# 1 2 'ParentDir <path> [depth=1]'
  _parentdir_path="$1"
  _parentdir_depth="${2:-1}"
  if [ -f "$_parentdir_path" ]; then
    _parentdir_path="$(AbsDir "$_parentdir_path")"
  else
    _parentdir_path="$(cd "$_parentdir_path" && pwd)"
  fi
  while [ "$_parentdir_depth" -gt 0 ]; do
    _parentdir_path="${_parentdir_path}/.."
    _parentdir_depth=$((_parentdir_depth - 1))
  done
  printf '%s' "$(cd "$_parentdir_path" && pwd)"
}
export ParentDir
readonly ParentDir

# Require: FirstChar, AbsDir
AbsPath(){
  # shellcheck disable=SC2016
  Usage $# -le 1 'AbsPath [path=$0]'
  _fullpath_file=${1:-"$0"}
  if [ "$(FirstChar "$_fullpath_file")" = '/' ]; then
    printf '%s' "$_fullpath_file"
    return
  fi
  _fullpath_dir=$(AbsDir "$_fullpath_file")
  _fullpath_filename=$(basename "$_fullpath_file")
  printf '%s/%s' "$_fullpath_dir" "$_fullpath_filename"
}
export AbsPath
readonly AbsPath

ExistGroup(){
  Usage $# -eq 1 'ExistGroup <group>'
  _existgroup_g="$1"

  if [ -f "/etc/group" ]; then
    InstallGrep
    if ! grep -q "^${_existgroup_g}:" /etc/group; then
      return 1
    fi
    return
  fi

  if command -v getent >/dev/null 2>&1; then
    if ! getent group "$_existgroup_g" >/dev/null 2>&1; then
      return 1
    fi
    return
  fi
  Panic "missing command getent or file /etc/group"
}
export ExistGroup
readonly ExistGroup

ExistUser(){
  Usage $# -eq 1 'ExistUser <user>'
  _existuser_u="$1"
  if [ -f "/etc/passwd" ]; then
    InstallGrep
    if ! grep -q "^${_existuser_u}:" /etc/passwd; then
      return 1
    fi
    return
  fi

  if command -v getent >/dev/null 2>&1; then
    if ! getent passwd "$_existuser_u" >/dev/null 2>&1; then
      return 1
    fi
    return
  fi
  Panic "missing command getent or file /etc/passwd"
}
export ExistUser
readonly ExistUser

# Add a group if not exists
AddGroupNx(){
  _addgroupnx_usage="AddGroupNx [-r/--system] <group> [gid]"
  Usage $# 1 3 "$_addgroupnx_usage"
  _addgroupnx_r=''
  if [ "$1" = "-r" ] || [ "$1" = "--system" ] || [ "$1" = "-S" ]; then
    _addgroupnx_r="--system"
    shift
    Usage $# 1 2 "$_addgroupnx_usage"
  fi
  _addgroupnx_group="$1"
  _addgroupnx_gid="${2-}"

  # group exists
  if ExistGroup "$_addgroupnx_group"; then
    return
  fi

  if command -v addgroup >/dev/null 2>&1; then
    if [ -z "$_addgroupnx_gid" ]; then
      # @warn do not quote $_addgroupnx_r
      addgroup $_addgroupnx_r "$_addgroupnx_group"
    else
      # @warn do not quote $_addgroupnx_r
      addgroup $_addgroupnx_r --gid "$_addgroupnx_gid" "$_addgroupnx_group"
    fi
    return
  fi

  if [ -z "$_addgroupnx_gid" ]; then
    # @warn do not quote $_addgroupnx_r
    groupadd $_addgroupnx_r "$_addgroupnx_group"
  else
    # @warn do not quote $_addgroupnx_r
    groupadd $_addgroupnx_r --gid "$_addgroupnx_gid" "$_addgroupnx_group"
  fi
}
export addGroupx
readonly addGroupx

# add a non-login user if not exists
AddUserNx(){
  _addusernx_usage="AddUserNx [-r/--system] <user> [group=users|gid]"
  Usage $# 1 3 "$_addusernx_usage"
  _addusernx_r=''
  if [ "$1" = "-r" ] || [ "$1" = "--system" ]; then
    _addusernx_r="--system"
    shift
    Usage $# 1 2 "$_addusernx_usage"
  fi
  _addusernx_user="$1"
  _addusernx_group="${2-}"

  if ExistUser "$_addusernx_user"; then
    return
  fi

  # --gid
  if IsNumber "$_addusernx_group"; then
    if command -v adduser >/dev/null 2>&1; then
      if [ -n "$_addusernx_group" ];then
        # @warn do not quote $_addusernx_r
        adduser $_addusernx_r --disabled-password --disabled-login --no-create-home --shell /sbin/nologin --gid "$_addusernx_group" --gecos "$_addusernx_user" "$_addusernx_user"
      else
        # @warn do not quote $_addusernx_r
        adduser $_addusernx_r --disabled-password --disabled-login --no-create-home --shell /sbin/nologin --gecos "$_addusernx_user" "$_addusernx_user"
      fi
      return
    fi

    if [ -n "$_addusernx_group" ]; then
      # @warn do not quote $_addusernx_r
      useradd $_addusernx_r --shell /sbin/nologin --gid "$_addusernx_group" "$_addusernx_user"
    else
      # @warn do not quote $_addusernx_r
      useradd $_addusernx_r --shell /sbin/nologin  "$_addusernx_user"
    fi

    return
  fi

  # --group
  if [ -n "$_addusernx_group" ]; then
    # @warn do not quote $_addusernx_r
    AddGroupNx $_addusernx_r "$_addusernx_group"
  fi
  if command -v adduser >/dev/null 2>&1; then
    if [ -n "$_addusernx_group" ];then
      # @warn do not quote $_addusernx_r
      adduser $_addusernx_r --disabled-password --disabled-login --no-create-home --shell /sbin/nologin --ingroup "$_addusernx_group" --gecos "$_addusernx_user" "$_addusernx_user"
    else
      # @warn do not quote $_addusernx_r
      adduser $_addusernx_r --disabled-password --disabled-login --no-create-home --shell /sbin/nologin --gecos "$_addusernx_user" "$_addusernx_user"
    fi
    return
  fi

  if [ -n "$_addusernx_group" ]; then
    # @warn do not quote $_addusernx_r
    useradd $_addusernx_r --shell /sbin/nologin  -g "$_addusernx_group" "$_addusernx_user"
  else
    # @warn do not quote $_addusernx_r
    useradd $_addusernx_r --shell /sbin/nologin  "$_addusernx_user"
  fi
}
export AddUserNx
readonly AddUserNx

# Require: IAmRoot
MkdirP(){
  _mkdir="$1"
  if [ -d "$_mkdir" ]; then return 0; fi


  if mkdir -p "$_mkdir" 2>/dev/null; then
    return 0
  fi

  if IAmRoot || ! command -v sudo >/dev/null 2>&1; then
    return 1
  fi

  sudo mkdir -p "$_mkdir"
}
export MkdirP
readonly MkdirP


# 递归修改目录及子目录用户。
# Required: ReplaceSpaceToLF
ChownR() {
  Usage $# -ge 2 'ChownR <user> <dir> [dir...]'
  _chownr_user="$1"
  shift

  ReplaceSpaceToLF "$@" | while IFS= read -r _chownr_dir; do
    if [ -z "$_chownr_dir" ]; then continue; fi
    # 这样修改权限比 `chown -R` 性能更好
    if find "$_chownr_dir" \! -user "$_chownr_user" -exec chown "$_chownr_user" {} + >/dev/null 2>&1; then
      continue
    fi
    if chown -R "$_chownr_user" "$_chownr_dir" 2>/dev/null; then
      continue
    fi
    if IAmRoot || ! command -v sudo >/dev/null 2>&1; then
      Warn "failed to ChownR $_chownr_user $_chownr_dir"
      continue
    fi
    sudo chown -R "$_chownr_user" "$_chownr_dir"
  done
}
export ChownR
readonly ChownR

# 递归修改目录及子目录用户组。这样修改权限比 `chgrp -R` 性能更好
# Required: ReplaceSpaceToLF
ChgrpR() {
  Usage $# -ge 2 'ChgrpR <group> <dir> [dir...]'
  _chgrpr_group="$1"
  shift

  ReplaceSpaceToLF "$@" | while IFS= read -r _chgrpr_dir; do
    if [ -z "$_chgrpr_dir" ]; then continue; fi
    if find "$_chgrpr_dir" \! -group "$_chgrpr_group" -exec chgrp "$_chgrpr_group" {} + >/dev/null 2>&1; then
      continue
    fi
    if chgrp -R "$_chgrpr_group" "$_chgrpr_dir" 2>/dev/null; then
      continue
    fi
    if IAmRoot || ! command -v sudo >/dev/null 2>&1; then
      Warn "failed to ChgrpR $_chgrpr_group $_chgrpr_dir"
      continue
    fi
    sudo chgrp -R "$_chgrpr_group" "$_chgrpr_dir"
  done
}
export ChgrpR
readonly ChgrpR

# Require: ReplaceSpaceToLF, Mkdir
ChmodOrMkdir(){
  Usage $# -ge 2 'ChmodOrMkdir <mod> <dir> [dir]...'
  _chmodormkdir_mod="$1"
  shift
  ReplaceSpaceToLF "$@" | while IFS= read -r _chmodormkdir_dir; do
    if [ -z "$_chmodormkdir_dir" ]; then continue; fi
    if [ ! -d "$_chmodormkdir_dir" ]; then MkdirP "$_chmodormkdir_dir"; fi

    if chmod -R "$_chmodormkdir_mod" "$_chmodormkdir_dir" 2>/dev/null; then
      continue
    fi
    if IAmRoot || ! command -v sudo >/dev/null 2>&1; then
      Warn "failed to ChmodOrMkdir $_chmodormkdir_mod $_chmodormkdir_dir"
      continue
    fi
    sudo chmod -R "$_chmodormkdir_mod" "$_chmodormkdir_dir"
  done
}
export ChmodOrMkdir
readonly ChmodOrMkdir

# Change mode of files, create files if not exists
ChmodOrCreate(){
  Usage $# -ge 2 'ChmodOrCreate <mod> <file> [file]... => ChmodOrCreate a+rw file1 file 2; ChmodOrCreate 1777 file'
  _chmodorcreate_mod="$1"
  shift
  ReplaceSpaceToLF "$@" | while IFS= read -r _chmodorcreate_file; do
    if [ -z "$_chmodorcreate_file" ]; then continue; fi
    if [ ! -e "$_chmodorcreate_file" ]; then touch "$_chmodorcreate_file"; fi

    if chmod "$_chmodorcreate_mod" "$_chmodorcreate_file" 2>/dev/null; then
      continue
    fi
    if IAmRoot || ! command -v sudo >/dev/null 2>&1; then
      Warn "failed to ChmodOrCreate $_chmodorcreate_mod $_chmodorcreate_file"
      continue
    fi
    sudo chmod "$_chmodorcreate_mod" "$_chmodorcreate_file"
  done
}
export ChmodOrCreate
readonly ChmodOrCreate

# Create dirs with a certain owner
# Require: Split
ChownOrMkdir(){
  Usage $# -ge 2 'ChownOrMkdir <user|user:group> <dir> [dir...]'
  _chownormkdir_ug="$1"
  shift
  _chownormkdir_user="$_chownormkdir_ug"
  _chownormkdir_group=''
  case "$_chownormkdir_user" in
    *:*)
      _chownormkdir_group="${_chownormkdir_ug#*:}"
      _chownormkdir_user="${_chownormkdir_ug%:*}"
      ;;
  esac

  if [ -z "$_chownormkdir_user" ]; then PanicUsage 'ChownOrMkdir <user|user:group> <dir> [dir...]'; fi

  ReplaceSpaceToLF "$@" | while IFS= read -r _chownormkdir_dir; do
    if [ -z "$_chownormkdir_dir" ]; then continue; fi
    if [ ! -d "$_chownormkdir_dir" ]; then MkdirP "$_chownormkdir_dir"; fi
    if [ -n "$_chownormkdir_group" ]; then
      if chown -R "$_chownormkdir_user":"$_chownormkdir_group" "$_chownormkdir_dir" 2>/dev/null; then
        continue
      fi
      if IAmRoot || ! command -v sudo >/dev/null 2>&1; then
        Warn "failed to ChownOrMkdir $_chownormkdir_group $_chownormkdir_dir"
        continue
      fi
      sudo chown -R "$_chownormkdir_user":"$_chownormkdir_group" "$_chownormkdir_dir"
      continue
    fi

    ChownR "$_chownormkdir_user" "$_chownormkdir_dir"
  done
}
export ChownOrMkdir
readonly ChownOrMkdir

CleanOrMkdir(){
  Usage $# 1 2 'CleanOrMkdir <dir> [mod=0777]'
  _cleanormkdir="$1"
  _cleanormkdir_mod="${2:-0777}"
  if [ ! -d "$_cleanormkdir" ]; then
    ChmodOrMkdir "$_cleanormkdir_mod" "$_cleanormkdir"
    return 0
  fi
  # Check is already empty
  if [ -z "$(ls -A "$_cleanormkdir" 2>/dev/null)" ]; then
    return 0
  fi
  rm -rf "${_cleanormkdir:?}/"*
}
export CleanOrMkdir
readonly CleanOrMkdir

# Create a temporary directory if not exists or clear this directory
# Require: ChmodOrMkdir
ClearTMPDIR(){
  # shellcheck disable=SC2016
  Usage $# -le 1 'ClearTMPDIR [dir=$TMPDIR]'
  CleanOrMkdir "${1:-"$TMPDIR"}" 1777
}
export ClearTMPDIR
readonly ClearTMPDIR



CdOrPanic(){
  Usage $# -eq 1 'CdOrPanic <path>'
  if [ -z "$1" ] || [ "$1" = ' ' ] || [ "$1" = '*' ]; then
    Panic "illegal directory name: '$1'"
  fi
  PanicIfNotDir "$1"
  cd "$1" || Panic "failed to ${_NC_}cd $1"
}
export CdOrPanic
readonly CdOrPanic

# Require: ChmodOrMkdir, CdOrPanic
CdOrMkdir(){
  Usage $# 1 2 'CdOrMkdir <dir> [mod=0777]'
  _cdormkdir="$1"
  _cdormkdir_mod="${2:-0777}"
  if [ ! -d "$_cdormkdir" ]; then
    ChmodOrMkdir "$_cdormkdir_mod" "$_cdormkdir"
  fi
  CdOrPanic "$_cdormkdir"
}
export CdOrMkdir
readonly CdOrMkdir

CheckDirs(){
  Usage $# -ge 2 'CheckDirs <ignore_empty_dir 1|0> <dir>[<dir>...]'
  _checkdirs_ignore="$1"
  shift
  ReplaceSpaceToLF "$@"  | while IFS= read -r _checkdirs_dir; do
    if [ -z "$_checkdirs_dir" ]; then
      if [ "$_checkdirs_ignore" -eq 1 ]; then
        continue
      fi
      Panic "directory ${_checkdirs_dir} is not exists"
    fi
    CdOrPanic "$_checkdirs_dir"
  done
}
export CheckDirs
readonly CheckDirs

# Format ,a,b,c or [,a,,'b',  "c"] to ['a', 'b', 'c'] or other format
# It'll ignore empty value at head or at tail
FormatArrayString(){
  _formatarraystring_usage=$(cat << EOF
FormatArrayString <string> [quotation=\'] [ignore middle empty=0]
Example: FormatArrayString 'a,b,c' ''    ==>  [a, b, c]
         FormatArrayString 'a,b,c'      ==> ['a', 'b', 'c']
EOF
)
  Usage $# 1 3 "$_formatarraystring_usage"
  _formatarraystring_s="$(Trim "$1")"
  _formatarraystring_quotation="${2-"'"}"  # only if $2 not set, set to '.  $2='' will not match
  _formatarraystring_ignore_middle_empty="${3-}"
  if [ -z "$_formatarraystring_s" ] ||[ "$_formatarraystring_s" = '[]' ]; then
    printf '[]'
    return 0
  fi
  _formatarraystring_s=$(TrimLeft "$_formatarraystring_s" '[')
  _formatarraystring_s=$(TrimRight "$_formatarraystring_s" ']')
  printf '['
  _formatarraystring_item_start=0
  _formatarraystring_item_empty_n=0
  Split "$_formatarraystring_s"  | while IFS= read -r _formatarraystring_item; do
    _formatarraystring_item="$(Trim "$_formatarraystring_item")"
    if [ -z "$_formatarraystring_item" ]; then
      _formatarraystring_item_empty_n=$(( _formatarraystring_item_empty_n + 1 ))
      continue
    fi

    if [ "$_formatarraystring_item_start" -eq 1 ]; then
      if [ -z "$_formatarraystring_ignore_middle_empty" ] || [ "$_formatarraystring_ignore_middle_empty" = "0" ]; then
        while [ "$_formatarraystring_item_empty_n" -gt 0 ]; do
          _formatarraystring_item_empty_n=$(( _formatarraystring_item_empty_n - 1 ))
          printf ',%s%s' "$_formatarraystring_quotation" "$_formatarraystring_quotation"
        done
      fi
      printf ','
    else
      _formatarraystring_item_start=1
      _formatarraystring_item_empty_n=0
    fi
    printf "%s%s%s" "$_formatarraystring_quotation" "$_formatarraystring_item" "$_formatarraystring_quotation"
  done
  printf ']'
}
export FormatArrayString
readonly FormatArrayString


# Parse string like "[x,xx],[xx,x]" into array. Note: can not contains invalid spaces
# Required: StartWith, Substr, Substring
ParseArrays() {
  Usage $# -ge 1 'ParseArrays {string} | while IFS= read -r <item>; do ...; done'
  _parsearrargs_input="$*"

  # 不以 [ 开头，直接返回
  if ! StartWith "$_parsearrargs_input" '['; then
    printf '%s' "$_parsearrargs_input"
    return 0
  fi

  _parsearrargs_start=1
  _parsearrargs_char=''
  _parsearrargs_len=${#_parsearrargs_input}
  _parsearrargs_last=$((_parsearrargs_len - 1))
  _parsearrargs_next=''
  _parsearrargs_result=''

  _parsearrargs_i=1
  while [ $_parsearrargs_i -lt "$_parsearrargs_len" ]; do
    _parsearrargs_char=$(Substr "$_parsearrargs_input" "$_parsearrargs_i" 1)
    if [ "$_parsearrargs_start" -eq -1 ]; then
      if [ "$_parsearrargs_char" != "[" ]; then Panic "ParseArrays: invalid array argument: $_parsearrargs_input"; fi
      _parsearrargs_i=$((_parsearrargs_i + 1))
      _parsearrargs_start=$_parsearrargs_i
    elif [ "$_parsearrargs_char" = "]" ]; then
      _parsearrargs_next=$(Substr "$_parsearrargs_input" "$((_parsearrargs_i + 1))" 1)
      if [ "$_parsearrargs_next" = "," ]; then
        if [ -n "$_parsearrargs_result" ]; then _parsearrargs_result="$_parsearrargs_result${LF}"; fi
        _parsearrargs_result="${_parsearrargs_result}$(Substring "$_parsearrargs_input" "$_parsearrargs_start" "$_parsearrargs_i")"
        _parsearrargs_start=-1
        _parsearrargs_i=$((_parsearrargs_i + 1))
      elif [ $_parsearrargs_i -eq $_parsearrargs_last ]; then
        if [ -n "$_parsearrargs_result" ]; then _parsearrargs_result="$_parsearrargs_result${LF}"; fi
        _parsearrargs_result="${_parsearrargs_result}$(Substring "$_parsearrargs_input" "$_parsearrargs_start" "$_parsearrargs_i")"
      fi
    fi
    _parsearrargs_i=$((_parsearrargs_i + 1))
  done
  # append a LF for | while IFS= read -r <item>; do ...; done
  if [ -n "$_parsearrargs_result" ]; then printf '%s\n' "$_parsearrargs_result"; fi
}
export ParseArrays
readonly ParseArrays

# Parse `k v` or `k=v` configure value
ParseConfig() {
  Usage $# -eq 2 'ParseConfig <file> <key_name>'
  _parseconfig_file="$1"
  _parseconfig_key="$2"

  if [ ! -f "$_parseconfig_file" ]; then Panic "ParseConfig: config file not found: $_parseconfig_file"; fi
  if [ -z "$_parseconfig_key" ]; then Panic "ParseConfig: key parameter is required"; fi

  _value_=$(awk -v key="$_parseconfig_key" '
    $0 ~ "^[[:space:]]*" key "[[:space:]]*[= ]" {
      sub("^[[:space:]]*" key "[[:space:]]*=?[[:space:]]*", "")
      sub("[[:space:]]*$", "")
      print
      exit
    }
  ' "$_parseconfig_file")

  printf '%s' "${_value_:-}"
}
export ParseConfig
readonly ParseConfig

# Required: ParseConfig
SetConfig() {
  Usage $# -eq 2 'SetConfig <data> <config_file>'
  _setconfig_data="$1"
  _setconfig_file="$2"

  if [ -z "$_setconfig_data" ]; then Panic "SetConfig: config data cannot be empty"; fi
  if [ ! -f "$_setconfig_file" ]; then Panic "SetConfig: config file not found: $_setconfig_file"; fi

  _setconfig_key=''
  _setconfig_value=''

  # handle separator =
  case "$_setconfig_data" in
  *=*)
    _setconfig_key=${_setconfig_data%%=*}
    _setconfig_key=$(printf '%s' "$_setconfig_key" | sed 's/[[:space:]]*$//') # 去除尾部空格
    _setconfig_value=${_setconfig_data#*=}
    _setconfig_value=$(printf '%s' "$_setconfig_value" | sed 's/^[[:space:]]*//') # 去除首部空格
    ;;
  *)
    # handle separator space
    _setconfig_key=${_setconfig_data%% *}
    _setconfig_value=${_setconfig_data#* }
    [ "$_setconfig_key" = "$_setconfig_value" ] && _setconfig_value='' # 如果没有空格，_setconfig_value 应该为空
    ;;
  esac

  if [ -z "$_setconfig_key" ]; then Panic "SetConfig: invalid config format: $_setconfig_data"; fi
  if [ -n "$_setconfig_value" ]; then
    _setconfig_old=$(ParseConfig "$_setconfig_file" "$_setconfig_key")
    if [ -z "$_setconfig_old" ]; then
      # remove last spaces line
      sed '${/^$/d}' "$_setconfig_file"
      printf '\n%s\n' "$_setconfig_data" >> "$_setconfig_file"
    elif [ "$_setconfig_old" != "$_setconfig_value" ]; then
      sed -i.bak -E "s/^[[:space:]]*${_setconfig_key}[[:space:]]*=*[[:space:]]*.*$/${_setconfig_data}/" "$_setconfig_file"
      rm -f "${_setconfig_file}.bak"
    fi
  fi
}

# 整行匹配，并过滤掉重复的
# Require: StrIn
MatchedLines(){
  Usage $# 2 3 'MatchedLines <file> <pattern> [trim=1|0] | while IFS= read -r match; do ... done'
  _matchedlines_file="$1"
  _matchedlines_pattern="$2"
  _matchedlines_trim="${3:-1}"
  PanicIfNotFile "$_matchedlines_file"

  _matchedlines_matched=0
  _matchedlines_result="$TAB"
  InstallGrep
  grep "^[[:space:]]*${_matchedlines_pattern}.*[[:space:]]*$" "$_matchedlines_file" | while IFS= read -r _matchedlines_match; do
    if [ "$_matchedlines_trim" = '1' ]; then
      # trim left spaces
      _matchedlines_match="${_matchedlines_match#"${_matchedlines_match%%[![:space:]]*}"}"
      # trim right spaces
      _matchedlines_match="${_matchedlines_match%"${_matchedlines_match##*[![:space:]]}"}"
    fi

    if ! StrIn "${TAB}$_matchedlines_match${TAB}" "$_matchedlines_result"; then
      _matchedlines_result="${_matchedlines_result}$_matchedlines_match${TAB}"
      echo "$_matchedlines_match"
      # shellcheck disable=SC2030
      _matchedlines_matched=1
    fi
  done

  # shellcheck disable=SC2031
  # 增加一行，方便 while IFS= 处理
  if [ "$_matchedlines_matched" -eq 0 ]; then
    echo ''
  fi
}
export MatchedLines
readonly MatchedLines

# 替换 YAML 文件中配置标记
ReplaceYamlConfig(){
  Usage $# 3 4 'ReplaceYamlConfig <src:file> <dst> <tag> [replacement:file=<tag, trim @>]'
  _replaceyamlconfig_src="$1"
  _replaceyamlconfig_dst="$2"
  _replaceyamlconfig_tag="$3"
  _replaceyamlconfig_rep="${4:-"${_replaceyamlconfig_tag#@}"}"

  PanicIfNotFile "$_replaceyamlconfig_src" "$_replaceyamlconfig_rep"

  _replaceyamlconfig_temp=$(mktemp)
  trap 'rm -f "$_replaceyamlconfig_temp"' INT TERM EXIT # 临时文件，退出后自动删除

  #  || [ -n "$_replaceyamlconfig_line" ]  防止尾部不是以换行符结尾
  while IFS= read -r _replaceyamlconfig_line || [ -n "$_replaceyamlconfig_line" ]; do
    case "$_replaceyamlconfig_line" in
      *"$_replaceyamlconfig_tag"*)
        # 获取当前行的缩进部分
        _replaceyamlconfig_indent=$(echo "$_replaceyamlconfig_line" | sed "s#${_replaceyamlconfig_tag}.*##")

        # 读取替换文件内容并添加缩进
        while IFS= read -r _replaceyamlconfig_rep_line || [ -n "$_replaceyamlconfig_rep_line" ]; do
          echo "${_replaceyamlconfig_indent}${_replaceyamlconfig_rep_line}" >> "$_replaceyamlconfig_temp"
        done < "$_replaceyamlconfig_rep"
        ;;
      *)
        printf "%s\n" "$_replaceyamlconfig_line" >> "$_replaceyamlconfig_temp"
        ;;
    esac
  done < "$_replaceyamlconfig_src"

  rm -f "$_replaceyamlconfig_dst"
  cp "$_replaceyamlconfig_temp" "$_replaceyamlconfig_dst"
}
export ReplaceYamlConfig
readonly ReplaceYamlConfig

_generateRSAKey_() {
  _generatersakey_size="$1"
  _generatersakey_full="$2"
  _generatersakey_base="$3"
  _generatersakey_tmp="$4"

  # 如果目标文件已存在且有效，则跳过生成
  if [ -s "${_generatersakey_base}.priv.der" ] && [ -s "${_generatersakey_base}.pub.der.b64" ]; then
    return 0
  fi

  # 串联所有操作，任一步骤失败都会导致整体失败

  # 生成PKCS8私钥 ==> 可以删除
  openssl genrsa -out "${_generatersakey_tmp}.priv" "$_generatersakey_size" &&
  # 将私钥生成公钥
  openssl rsa -pubout -in "${_generatersakey_tmp}.priv" -out "${_generatersakey_tmp}.pub" &&

  # 还原回DER  --> 节省 airis config 空间占用，以及加解密效率
  openssl rsa -in "${_generatersakey_tmp}.priv" -outform DER -out "${_generatersakey_tmp}.priv.der" &&
  openssl rsa -pubout -in "${_generatersakey_tmp}.priv" -outform DER -out "${_generatersakey_tmp}.pub.der" &&

  # 将DER转回PEM
  # openssl rsa -inform DER -in "${_generatersakey_base}.der" -out "${_generatersakey_base}.pem"

  # 将 DER 格式转为 base64  --> 这里跟私钥
  # base64 更便于传递，而且这里去掉通用头，空间更小，且更不容易被前端反向工程识别到
  base64 -w 0 "${_generatersakey_tmp}.pub.der" >"${_generatersakey_tmp}.pub.der.b64" &&

  # 将 base64 编码的DER文件转换为 pem 文件
  # ./rsa_b2pem.sh public "${_generatersakey_base}.pub.der.base64" "${_generatersakey_base}.pub"

  # 私钥直接用二进制的，公钥需要开放出去，因此保留base64的
  mv "${_generatersakey_tmp}.priv.der" "${_generatersakey_base}.priv.der" &&
  mv "${_generatersakey_tmp}.pub.der.b64" "${_generatersakey_base}.pub.der.b64" || return 1

  if [ "$_generatersakey_full" = "full" ]; then
    mv "${_generatersakey_tmp}.priv" "${_generatersakey_base}.priv" &&
    mv "${_generatersakey_tmp}.pub" "${_generatersakey_base}.pub" &&
    mv "${_generatersakey_tmp}.pub.der" "${_generatersakey_base}.pub.der" || return 1
  fi

  return 0
}
readonly _generateRSAKey_

# 批量生成 RSA 密钥
# PKCS1(PEM格式）  -----BEGIN RSA PRIVATE KEY---
# PKCS8(PEM格式）默认使用  -----BEGIN PRIVATE KEY---
# DER 二进制格式，计算最原始状态。可以跟PEM格式互相转换，更节省空间和计算量
# openssl genrsa 生成的是 PKCS8 格式。如果想生成 PKCS1，加 -traditional
# Required: Split, ChownR
GenerateRSAKeys() {
  if ! Install openssl; then
    Panic "failed install openssl"
  fi
  Usage $# -eq 5 'GenerateRSAKeys <stream|full> <user|user:group> <dir> <prefix> <key_size[,key_size...]>'
  _generatersakeys_full="$1"
  _generatersakeys_owner="$2"
  _generatersakeys_dir="$3"
  _generatersakeys_prefix="$4"

  # 创建临时文件，当接收到信号后，自动删除
  _generatersakeys_tempdir=$(mktemp -d)
  trap 'rm -rf "$_generatersakeys_tempdir"' INT TERM EXIT

  mkdir -p "$_generatersakeys_dir"

  # ()& 并行操作
  Split "$5" | while IFS= read -r _generatersakeys_size; do
    _generatersakeys_base="${_generatersakeys_dir}/${_generatersakeys_prefix}${_generatersakeys_size}"
    _generatersakeys_tmp="${_generatersakeys_tempdir}/${_generatersakeys_prefix}${_generatersakeys_size}"
    if ! _generateRSAKey_ "$_generatersakeys_size" "$_generatersakeys_full" "$_generatersakeys_base" "$_generatersakeys_tmp"; then
      Panic "GenerateRSAKeys: failed to generate RSA keys for size ${_generatersakeys_size}"
    fi
    Info "generated rsa keys: ${_generatersakeys_base}"
  done

  ChownR "$_generatersakeys_owner" "$_generatersakeys_dir" || Panic "GenerateRSAKeys: failed to ChownR ${_generatersakeys_owner} ${_generatersakeys_dir}"
  find "$_generatersakeys_dir" -type f -name "*.priv.der" -exec chmod 600 {} + || Panic "GenerateRSAKeys: failed to chmod 600 ${_generatersakeys_dir}/*.priv.der"
  find "$_generatersakeys_dir" -type f -name "*.pub.der.b64" -exec chmod 644 {} + || Panic "GenerateRSAKeys: failed to chmod 644 ${_generatersakeys_dir}/*.pub.der.b64"
}
export GenerateRSAKeys
readonly GenerateRSAKeys