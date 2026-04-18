#!/bin/bash
set -euo pipefail

# https://github.com/aarioai/opt
if [ -x "./aa/lib/aa-posix-lib.sh" ]; then . ./aa/lib/aa-posix-lib.sh; else . /opt/aa/lib/aa-posix-lib.sh; fi

HERE="$(AbsDir "${BASH_SOURCE[0]}")"
readonly HERE


 # 生成 aa-posix-lib.sh hash 值
generateAaPosixLibHash(){
    local dir="${HERE}/aa/lib"
    local old
    old="$(find "$dir" -maxdepth 1 -name "md5-*" -type f -printf "%f\n" | head -1)"
    # 删除之前的md5文件
    find "$dir" -maxdepth 1 -name "md5-*" -type f -delete
    local hash
    hash=$(md5sum "${dir}/aa-posix-lib.sh" | awk '{print $1}')
    local new="md5-${hash}"
    touch "${dir}/$new"
    if [ "$old" != "$new" ]; then
        Info "aa-posix-lib.sh changed from ${old} => ${hash}"
    fi
}

main(){
  Usage $# -le 1 './gitpush.sh [comment]'
  local comment="${1:-"no comment"}"

  generateAaPosixLibHash

  # 将 CRLF 转为 LF
  git config core.autocrlf false
  git add -A .
  git commit -m "$comment"
  git push origin main
}

main "$@"