#!/bin/sh
set -eu

# https://github.com/aarioai/opt
if [ -x "../lib/aa-posix-lib.sh" ]; then . ../lib/aa-posix-lib.sh; else . /opt/aa/lib/aa-posix-lib.sh; fi

config="./aa-posix-lib-test.conf"
if [ ! -f "$config" ]; then config="/opt/aa/tests/aa-posix-lib-test.conf"; fi

lib="../lib/aa-posix-lib.sh"
if [ ! -f "$lib" ]; then lib="/opt/aa/lib/aa-posix-lib.sh"; fi

export IN_CHINESE=1
HERE="$(AbsDir "$0")"
readonly HERE
dictTesting="$(Dict "testing" "测试")"
readonly dictTesting

Lowlight "${dictTesting} <${lib}>  <${config}>"

testing(){
  if [ "$QUITE_LOGS" -eq 0 ]; then printf "${_LIGHT_CYAN_}>> ${dictTesting} %s${_NC_}\n" "$*"; fi
  _saveToLogFile "" "$@"
}

init(){
  # mktemp 依赖 $TMPDIR 文件夹
  if [ ! -d "$TMPDIR" ]; then
    mkdir -p "$TMPDIR"
    chmod -R 1777 "$TMPDIR"
  fi
}


fail() {
  printf "${_LIGHT_RED_}[error] %s\n  want: (%s)    len:%d\n  got: (%s)    len:%d${_NC_}\n" "$1" "$2" "${#2}" "$3" "${#3}"
  exit 1
}

assert(){
  name="$1"
  want="$2"
  got="$3"
  if [ "$got" != "$want" ]; then
    fail "$name" "$want" "$got"
  fi
}

testLog() {
  temp=$(mktemp -d)
  trap 'rm -rf "$temp"' EXIT # 临时文件，退出后自动删除
  tmp="${temp}/lib-test.log"
  SetLibLogFile "$tmp"
  Log "testing log"

  if [ ! -s "$tmp" ]; then
    printf '%s\n' "save log to file failed, not found $tmp"
    exit 1
  fi
  UnsetLibLogFile
}

testAbs(){
  testing 'Abs'
  assert 'Abs' 0 "$(Abs 0)"
  assert 'Abs' 1 "$(Abs 1)"
  assert 'Abs' 1 "$(Abs -1)"
}

testMin(){
  testing 'Min'
  assert 'Min' 9 "$(Min 9 9)"
  assert 'Min' 0 "$(Min 0 2)"
  assert 'Min' -1 "$(Min -1 1)"
  assert 'Min' -5 "$(Min 1 -5)"
  assert 'Min' -8 "$(Min -3 -8)"
}

testMax(){
  testing 'Max'
  assert 'Max' 9 "$(Max 9 9)"
  assert 'Max' 2 "$(Max 0 2)"
  assert 'Max' 1 "$(Max -1 1)"
  assert 'Max' 1 "$(Max 1 -5)"
  assert 'Max' -3 "$(Max -3 -8)"
}

testIsLF() {
  testing 'IsLF'
  if ! IsLF '\n'; then fail 'IsLF \n' 'true' 'false'; fi
  if ! IsLF "$LF"; then fail "IsLF $LF" 'true' 'false'; fi
  if IsLF '\r\n'; then fail "IsLF \r\n" 'false' 'true'; fi
}

testCrossServiceSignal() {
  return 0
}

testIAmRoot() {
  testing 'IAmRoot'
  is_root=0
  got=0
  [ "$(id -u)" = '0' ] && is_root=1
  if IAmRoot; then
    got=1
  fi
  assert 'IAmRoot' "$is_root" "$got"
}

testCpuArchitecture() {
  testing 'CpuArch'
  arc=$(CpuArch)
  if [ "$arc" != "amd64" ] && [ "$arc" != "arm64" ]; then fail 'CpuArch' 'amd64|arm64' "$arc"; fi

}

testChwonR() {
  return 0
}

testChgrpR() {
  return 0
}

testIncrVersion(){
  testing "IncrVersion"
  prev=''
  want=''
  #assert "IncrVersion $prev" "$want" "$(IncrVersion "$prev")"

  prev='0.0.1'
  want='0.0.2'
  assert "IncrVersion $prev" "$want" "$(IncrVersion "$prev")"

  prev='1.2.99'
  want='1.3.0'
  assert "IncrVersion $prev" "$want" "$(IncrVersion "$prev")"

  prev='v1.99.99'
  want='v2.0.0'
  assert "IncrVersion $prev" "$want" "$(IncrVersion "$prev")"

  prev='v1.2.1'
  want='v1.2.3'
  assert "IncrVersion $prev 99 2" "$want" "$(IncrVersion "$prev" 99 2)"

  prev='1.2.1'
  want='1.2.5'
  assert "IncrVersion $prev 99 4" "$want" "$(IncrVersion "$prev" 99 4)"

  prev='1.0.9'
  want='1.1.0'
  assert "IncrVersion $prev 9" "$want" "$(IncrVersion "$prev" 9)"

  prev='1.0.99.98'
  want='1.1.0.0'
  assert "IncrVersion $prev 99 2" "$want" "$(IncrVersion "$prev" 99 2)"
}

testASCII() {
  testing 'EncodeASCII/DecodeASCII/AddASCII'
  char='X'
  want=88
  got=$(EncodeASCII "$char")
  assert 'EncodeASCII' "$want" "$got"

  got=$(DecodeASCII "$want")
  want=$char
  assert 'DecodeASCII' "$want" "$got"

  want='Z'
  got=$(AddASCII "$char" 2)
  assert 'AddASCII' "$want" "$got"

  char=8
  want=56
  got=$(EncodeASCII "$char")
  assert 'EncodeASCII' "$want" "$got"

  want='9'
  got=$(AddASCII "$char")
  assert 'AddASCII' "$want" "$got"
}


testSplit() {
  testing 'Split'
  # 测试单个字符
  s="a"
  want='a'
  got=$(Split "$s")
  assert 'Split' "$want" "$got"

  # 测试逗号隔开
  s="a,b,c,d"
  want=$(printf "%s\n%s\n%s\n%s" a b c d)
  got=$(Split "$s")
  assert 'Split' "$want" "$got"

  # 测试空格隔开
  s="a, b, c,d"
  want=$(printf "%s\n%s\n%s" a, b, c,d)
  got=$(Split "$s" ' ')
  assert 'Split' "$want" "$got"

  # 测试遍历
  s="a,b,c,d"
  want='a'
  Split "$s" | while IFS= read -r c; do
    if [ "$c" != "$want" ]; then fail 'Split' "$want" "$c"; fi
    want=$(AddASCII "$want")
  done
}

testStrRepeat() {
  testing 'StrRepeat'
  str='A'
  want='AAAAA'
  got=$(StrRepeat 5 "$str")
  assert 'StrRepeat' "$want" "$got"

  want='   '
  got=$(StrRepeat 3)
  assert 'StrRepeat' "$want" "$got"
}

testStrpad() {
  testing 'StrPad'
  str='A'
  want='A    '
  got=$(StrPad "$str" ${#want})
  assert 'StrPad' "$want" "$got"
}
testStrpadLeft() {
  testing 'StrPadLeft'
  str='A'
  want='    A'
  got=$(StrPadLeft "$str" ${#want})
  assert 'StrPad' "$want" "$got"
}
testAlignKVPair(){
  testing 'AlignKVPair'
  want='name    =  Aario'
  got=$(AlignKVPair 'name' 8 '=' 'Aario' 2)
  assert 'AlignKVPair' "$want" "$got"
}

testStrFirst() {
  testing 'FirstChar'
  s="Aario"
  want="A"
  got=$(FirstChar "$s")
  assert 'FirstChar' "$want" "$got"
}
testCutLeft() {
  testing 'CutLeft'
  s="Aario ${LF}TE${LF}ST"
  want="ario ${LF}TE${LF}ST"
  got=$(CutLeft 1 "$s")
  assert 'CutLeft' "$want" "$got"

  want="rio ${LF}TE${LF}ST"
  got=$(CutLeft 2 "$s")
  assert 'CutLeft' "$want" "$got"
}
testSubstr() {
  testing 'Substr'
  s="000,111,222,333"
  want='000'
  got=$(Substr "$s" 0 3)
  assert 'Substr' "$want" "$got"

  # 测试换行符
  s="ABC${LF}DEF"
  # $() 获取时，尾部的换行符一律会被截取掉
  want=''
  got=$(Substr "$s" 3 1)
  assert 'Substr' "$want" "$got"

  s="0123456789"
  want="456"
  got=$(Substr "$s" 4 3)
  assert 'Substr' "$want" "$got"

  # 测试length为空
  want="789"
  got=$(Substr "$s" 7)
  assert 'Substr' "$want" "$got"

  # 测试负数+省略length
  want="789"
  got=$(Substr "$s" -3)
  assert 'Substr' "$want" "$got"

}

testSubstring() {
  testing 'Substring'
  s="0123456789"
  want="456"
  got=$(Substring "$s" 4 7)
  assert 'Substring' "$want" "$got"

  # 测试负数
  want="12345678"
  got=$(Substring "$s" 1 -1)
  assert 'Substring' "$want" "$got"

  # 测试双负数
  want="78"
  got=$(Substring "$s" -3 -1)
  assert 'Substring' "$want" "$got"

  # 测试双负数
  want="789"
  got=$(Substring "$s" -3)
  assert 'Substring' "$want" "$got"
}

testLastN(){
  testing 'LastN'
  want='d/e'
  got=$(LastN 2 '/' 'a/b/c/d/e')
  assert 'LastN' "$want" "$got"

  want='c/d/e'
  got=$(LastN 3 '/' 'a/b/c/d/e/')
  assert 'LastN' "$want" "$got"

  want='gz'
  got=$(LastN 1 '.' 'c.tar.gz')
  assert 'LastN' "$want" "$got"
}

testStartWith() {
  testing 'StartWith'
  s="Aario's Work"
  if ! StartWith "$s" "Aario"; then fail 'StartWith' true false; fi
  if StartWith "$s" "aario"; then fail 'StartWith' false true; fi
}

testEndWith() {
  testing 'EndWith'
  s="Aario's Work"
  if ! EndWith "$s" "Work"; then fail 'EndWith' true false; fi
  if EndWith "$s" "work"; then fail 'EndWith' false true; fi
}

testTrimLeft() {
  testing 'TrimLeft'
  s="   Aario "
  want="Aario "
  got=$(TrimLeft "$s")
  assert 'TrimLeft' "$want" "$got"

  s="---Aario ---"
  want="Aario ---"
  got=$(TrimLeft "$s" -)
  assert 'TrimLeft' "$want" "$got"

  # 测试多字符cut
  s="ababaBabab Aario"
  want="aBabab Aario"
  got=$(TrimLeft "$s" ab)
  assert 'TrimLeft' "$want" "$got"
}

testTrimRight() {
  testing 'TrimRight'
  s="   Aario "
  want="   Aario"
  got=$(TrimRight "$s")
  assert 'TrimRight' "$want" "$got"

  s="---Aario ---"
  want="---Aario "
  got=$(TrimRight "$s" -)
  assert 'TrimRight' "$want" "$got"

  # 测试多字符cut
  s="ababaBabab Aario Aababab"
  want="ababaBabab Aario A"
  got=$(TrimRight "$s" ab)
  assert 'TrimRight' "$want" "$got"
}

testTrim() {
  testing 'Trim'
  s='[[,,a,b,c,,d,,]'
  want=',,a,b,c,,d,,]'
  got=$(TrimLeft "$s" '[')
  assert 'Trim:TrimLeft' "$want" "$got"

  want=',,a,b,c,,d,,'
  got=$(TrimRight "$got" ']')
  assert 'Trim:TrimRight' "$want" "$got"

  s="   Aario "
  want="Aario"
  got=$(Trim "$s")
  assert 'Trim' "$want" "$got"

  s="---Aario ---"
  want="Aario "
  got=$(Trim "$s" -)
  assert 'Trim' "$want" "$got"

  # 测试多字符cut
  s="ababaBabab Aario Aababab"
  want="aBabab Aario A"
  got=$(Trim "$s" ab)
  assert 'Trim' "$want" "$got"
}

testIndexOf() {
  testing 'IndexOf'
  s="0123456789"
  want=5
  got=$(IndexOf "$want" "$s")
  assert 'IndexOf' "$want" "$got"

  # 测试单个换行符
  s="Hello${LF}Aario${LF} Hello"
  sub="$LF"
  want=5
  got=$(IndexOf "$sub" "$s")
  assert 'IndexOf' "$want" "$got"

}

testStrIn() {
  testing 'StrIn'
  s="Aario"
  sub="ri"
  if ! StrIn "$sub" "$s"; then fail "StrIn" true false; fi

  # 测试换行符
  s="Hello${LF}Aario"
  sub="$LF"
  if ! StrIn "$sub" "$s"; then fail "StrIn" true false; fi
}
testSliceIn(){
  testing 'SliceIn'
  sub="Aario"
  if SliceIn "$sub" "HAario" "Aarios" "aario"; then fail "SliceIn" false true; fi

  if ! SliceIn "$sub" "HAario" "Aario" "aario"; then fail "SliceIn" false true; fi
}

testPackLF() {
  testing 'PackLF'
  s=$(printf '\n\n%s\n\n%s\n\n\n' A B)
  want='\n\nA\n\nB'
  got=$(PackLF "$s")
  assert 'PackLF' "$want" "$got"
  # \n 是2个字符
  if [ "${#got}" -ne 10 ]; then fail 'PackLF' "len 10" "len ${#got}"; fi

  got=$(UnpackLF "$want")
  if [ "${#got}" -ne 6 ]; then fail 'UnpackLF' "len 6" "len ${#got}"; fi
}

testReplace() {
  testing 'Replace'
  s="AA,BB,CC,DD"
  want="AA${LF}BB${LF}CC${LF}DD"
  got=$(Replace "$s" ',' "$LF")
  assert 'Replace' "$want" "$got"

  # 测试换行符
  s=$(printf '%s' "a${LF}b${LF}c")
  want=$(printf "%s\n%s" "a,b" "c")
  got=$(Replace "$s" "$LF" ',' 1)
  assert 'Replace' "$want" "$got"

  # 测试常规
  s="0000123456"
  want="000123456"
  got=$(Replace "$s" '0' '' 1)
  assert 'Replace' "$want" "$got"

  # 测试全部替换
  want="123456"
  got=$(Replace "$s" '0' '')
  assert 'Replace' "$want" "$got"

  # 测试替换一次多字符
  s="abcabcabc123456"
  want="abcabc123456"
  got=$(Replace "$s" 'abc' '' 1)
  assert 'Replace' "$want" "$got"

  # 测试替换全部多字符
  s="abcabcabc123456"
  want="123456"
  got=$(Replace "$s" 'abc' '')
  assert 'Replace' "$want" "$got"

  # 测试替换为其他字符
  s="abcabcabc123456"
  want="ABCABCABC123456"
  got=$(Replace "$s" 'abc' 'ABC')
  assert 'Replace' "$want" "$got"

}

testReplaceLF() {
  testing 'ReplaceLF'
  s=$(printf '%s\n%s\n' "ABC" "DEF")
  want="ABCDEF"
  got=$(ReplaceLF "$s" '')
  assert "ReplaceLF $s" "$want" "$got"

  want="ABC DEF"
  got=$(ReplaceLF "$s")
  assert "ReplaceLF $s" "$want" "$got"

  # 测试正则边界符号
  want="ABC#DEF"
  got=$(ReplaceLF "$s" '#')
  assert "ReplaceLF $s" "$want" "$got"

  want="ABC\$DEF"
  got=$(ReplaceLF "$s" '$')
  assert "ReplaceLF $s" "$want" "$got"
}

testReplaceLFToSpace() {
  testing 'ReplaceLFToSpace'
  # 测试单字符
  s="${LF}"
  want=""
  got=$(ReplaceLFToSpace 0 "$s")
  assert 'ReplaceLFToSpace 0' "$want" "$got"

  # 测试单字符
  s="A"
  want="A"
  got=$(ReplaceLFToSpace 0 "$s")
  assert 'ReplaceLFToSpace 0' "$want" "$got"

  # tag=0 移除连续空格和首尾空格
  s="${LF}${LF}A${LF}B${LF}${LF}C${LF}D${LF}"
  want="A B C D"
  got=$(ReplaceLFToSpace 0 "$s")
  assert 'ReplaceLFToSpace 0' "$want" "$got"

  # tag=1 保留所有空格（除尾部）
  want="  A B  C D"
  got=$(ReplaceLFToSpace 1 "$s")
  assert 'ReplaceLFToSpace 1' "$want" "$got"

  # tag=2 仅移除首尾空格
  want="A B  C D"
  got=$(ReplaceLFToSpace 2 "$s")
  assert 'ReplaceLFToSpace 2' "$want" "$got"

  # tag=3 合并连续空格，并移除尾部空格
  want="  A B C D"
  got=$(ReplaceLFToSpace 3 "$s")
  assert 'ReplaceLFToSpace 3' "$want" "$got"
}
testReplaceSpaceToLF() {
  testing 'ReplaceSpaceToLF'
  # 测试单字符
  s="  "
  want="" # 尾部空格会被自动忽略
  got=$(ReplaceSpaceToLF "$s")
  assert 'ReplaceSpaceToLF' "$want" "$got"

  # 测试单字符
  s="A"
  want="A"
  got=$(ReplaceSpaceToLF "$s")
  assert 'ReplaceSpaceToLF' "$want" "$got"

  s="  A B  C D "
  want="${LF}${LF}A${LF}B${LF}${LF}C${LF}D" # 尾部空格会被自动忽略
  got=$(ReplaceSpaceToLF "$s")
  assert 'ReplaceSpaceToLF' "$want" "$got"
}
testSlicelen() {
  testing 'SliceLen'
  # 测试单个数组
  want='Aario'
  Split "$want" | while IFS= read -r got;do
    assert 'Slice | while IFS= read -r' "$want" "$got"
  done

  arr=$(Split "A,B,C,D,E,F,G")
  want=7
  got=$(SliceLen "$arr")
  assert 'SliceLen' "$want" "$got"

  # 测试多空格分割情况
  arr="   1 2 3 4   5   6"
  want=6
  got=$(SliceLen "$arr")
  assert 'SliceLen' "$want" "$got"
}

testSlice() {
  testing 'Split'
  arr=$(Split "Aario:administrator|management" ':')
  want="Aario"
  got=$(Slice 0 "$arr")
  assert 'Slice' "$want" "$got"
  want="administrator|management"
  got=$(Slice 1 "$arr")
  assert 'Slice' "$want" "$got"

  arr=$(Split "A,B,C,D,E,F,G")
  want="D"
  got=$(Slice 3 "$arr")
  assert 'Slice' "$want" "$got"

  # 测试多空格分割情况
  arr="   0 1 2 3 4   5   6"
  want="4"
  got=$(Slice 4 "$arr")
  assert 'Slice' "$want" "$got"
}

testCountMatches() {
  testing 'CountMatches'
  # 测试单换行符
  # \n 不是换行符
  s="${LF}${LF}1${LF}23456${LF}66${LF}6777${LF}88899${LF}96${LF}66643\n2423"
  want="8"
  got=$(CountMatches "${LF}" "$s")
  assert 'CountMatches' "$want" "$got"

  # 测试单换行符
  s="12345666${LF}67778889996666"
  want="3"
  got=$(CountMatches '66' "$s")
  assert 'CountMatches' "$want" "$got"

  # 测试多字符
  s="1234566667778889996666"
  want="4"
  got=$(CountMatches '66' "$s")
  assert 'CountMatches' "$want" "$got"

  # 测试单字符
  s="12345666777888999"
  want="3"
  got=$(CountMatches '6' "$s")
  assert 'CountMatches' "$want" "$got"
}

testJoin() {
  testing 'Join'
  s="a b c"
  want="a,b,c"
  got=$(Join , "$s")
  assert 'Join' "$want" "$got"

  s="a${LF}b${LF}${LF}c    d"
  want="a,b,,c,,,,d"
  got=$(Join , "$s")
  assert 'Join' "$want" "$got"
}

testIsAccessible(){
  testing 'IsAccessible'
  urls='https://codeup.aliyun.com https://luexu.com'
  for url in $urls; do
    if ! IsAccessible "$url"; then WarnD "$url is not accessible" "无法访问 $url"; fi
  done

  if ! IsWanAccessible; then
    echo 'GFW warning!'
  fi
}

testHttpCode(){
  testing 'HttpCode'
  url='https://codeup.aliyun.com'
  code="$(HttpCode "$url")"
  if [ "$code" != '302' ]; then WarnD "$url http code is $code, want 302" "$url 状态码是$code，预期是 302"; fi

  url='https://www.baidu.com'
  code="$(HttpCode "$url")"
  if [ "$code" != '200' ]; then WarnD "$url http code is $code, want 200" "$url 状态码是$code，预期是 200"; fi
}

testHttpOK(){
  testing 'HttpOK'
  urls='https://codeup.aliyun.com https://www.baidu.com https://luexu.com'
  for url in $urls; do
    if ! HttpOK "$url"; then WarnD "$url status code is not in 200-399" "$url 状态码不在200-399"; fi
  done
}

testDownload(){
  testing 'Download'
  url='https://www.baidu.com'
  filename='baidu.index'
  temp=$(mktemp -d)
  trap 'rm -rf "$temp"' EXIT # 临时文件，退出后自动删除
  cd "$temp"
  if ! Download "$url" "$filename"; then
    WarnD "Download $url failed" "Download $url 失败"
    return
  fi
  if [ ! -f "$filename" ]; then
        WarnD "rename downloaded $url to $filename failed" "重命名下载 $url 为 $filename 失败"
  fi
}

testAbsDir() {
  testing 'AbsDir'
  want=${PWD:-"$(pwd)"}
  if [ -n "$want" ]; then
    got=$(AbsDir ".")
    assert 'AbsDir' "$want" "$got"
  fi

  want=$(AbsDir "./")
  temp=$(mktemp -d)
  trap 'rm -rf "$temp"' EXIT # 临时文件，退出后自动删除
  cd "$temp"
  cd "$want" || fail 'AbsDir' "$want" ""
}

testParentDir() {
  testing 'ParentDir'
  temp=$(mktemp -d)
  trap 'rm -rf "$temp"' EXIT # 临时文件，退出后自动删除
  dir="$temp/a/b/c/d/e/f/g"
  file="${dir}/test.txt"
  mkdir -p "$dir"
  echo "$dir" > "$file"

  got="$(ParentDir "$dir")"
  want="$temp/a/b/c/d/e/f"
  assert "ParentDir $dir" "$want" "$got"

  got="$(ParentDir "$dir" 2)"
  want="$temp/a/b/c/d/e"
  assert "ParentDir $dir 2" "$want" "$got"

  got="$(ParentDir "$dir" 4)"
  want="$temp/a/b/c"
  assert "ParentDir $dir 4" "$want" "$got"

  got="$(ParentDir "$file" 4)"
  want="$temp/a/b/c"
  assert "ParentDir $file 4" "$want" "$got"

  got="$(ParentDir "$file")"
  want="$temp/a/b/c/d/e/f"
  assert "ParentDir $file" "$want" "$got"
}

testAbsPath() {
  testing 'AbsPath'
  cur=${PWD:-"$(pwd)"}

  temp=$(mktemp -d)
  trap 'rm -rf "$temp"' EXIT # 临时文件，退出后自动删除
  cd "$temp"
  echo "A" > "a.txt"
  dir="${temp}/test/hello"
  mkdir -p "${dir}"
  cd "$dir"
  echo "B" > "b.txt"

  want="${dir}/b.txt"
  got=$(AbsPath "./b.txt")
  assert 'AbsPath' "$want" "$got"

  want="${temp}/a.txt"
  got=$(AbsPath "../../a.txt")
  assert 'AbsPath' "$want" "$got"

  cd "$cur"
}
testFilename(){
  testing 'Filename'
  path='/opt/aa/hello.sh'
  want='hello'
  got="$(Filename "$path")"
  assert 'Filename' "$want" "$got"

  want='hello.sh'
  got="$(Filename "$path" with_ext)"
  assert 'Filename' "$want" "$got"
}
testExtname(){
  testing 'Extname'
  path='/opt/aa/hello.sh'
  want='sh'
  got="$(Extname "$path")"
  assert 'Extname' "$want" "$got"

  want='.sh'
  got="$(Extname "$path" with_dot)"
  assert 'Extname' "$want" "$got"
}
testFindFileByExt(){
  testing 'FindFileByExt'
  want="$HERE/aa-posix-lib-test.conf"
  got=$(FindFileByExt "$HERE" "$(Filename "$0")" conf sh)
  assert 'FindFileByExt' "$want" "$got"

  got=$(FindFileByExt "$HERE" NOT_EXISTS_FILE conf sh)
  if [ -n "$got" ]; then
    fail 'FindFileByExt NOT_EXISTS_FILE' 'error' 'ok'
  fi
}

testCountWords(){
  testing 'CountWords'
  got=$(CountWords "   I Love\n  You ")
  assert 'CountWords' 3 "$got"
}

testWordIndex(){
  testing 'WordIndex'
  got=$(WordIndex 'Love' '   I Love  You ')
  assert 'WordIndex' 1 "$got"
}

testWordIn(){
  testing 'WordIn'
  if ! WordIn 'Love' '   I Love  You '; then
    fail 'WordIn Love' true false
  fi

  if WordIn 'love' '   I Love  You '; then
    fail 'WordIn love' false true
  fi

  if WordIn 'Lo' '   I Love  You '; then
    fail 'WordIn Lo' false true
  fi

  if WordIn '' '   I Love  You '; then
    fail 'WordIn ' false true
  fi

  if ! WordIn '-help' '-h -help --help'; then
    fail 'WordIn -help' true false
  fi
}

testNthWord(){
  testing 'NthWord'
  got=$(NthWord 1 '   I Love  You ')
  assert 'NthWord' 'Love' "$got"

  got=$(NthWord 0 'Not at all!')
  assert 'NthWord' 'Not' "$got"
}

testWordsBetween(){
  testing 'WordsBetween'
  sentence=' aaa bbbb ccc dddd eeeee ffff  gggg hhhh'
  want='aaa bbbb ccc dddd eeeee ffff gggg hhhh'
  got="$(WordsBetween 0 1 "$sentence")"
  assert 'WordsBetween' "$want" "$got"

  want='bbbb ccc dddd eeeee ffff'
  got=$(WordsBetween 1 3 "$sentence")
  assert 'WordsBetween' "$want" "$got"
}

testWordsRange(){
  testing 'WordsRange'
  sentence=' aaa bbbb ccc dddd eeeee ffff  gggg hhhh'
  got="$(WordsRange 0 1 "$sentence")"
  assert 'WordsRange' 'aaa' "$got"

  want='aaa bbbb'
  got=$(WordsRange 0 2 "$sentence")
  assert 'WordsRange' "$want" "$got"

  want='aaa bbbb ccc dddd eeeee ffff gggg hhhh'
  got=$(WordsRange 0 -1 "$want")
  assert 'WordsRange' "$want" "$got"

  want='bbbb ccc dddd eeeee ffff gggg'
  got=$(WordsRange 1 -2 "$sentence")
  assert 'WordsRange' "$want" "$got"
}

testProcessMatch(){
  testing 'MyProcessMatch'
  script="$0"
  if ! MyProcessMatch "$script";then
    ps -f
    fail "MyProcessMatch $script" 'true' 'false'
  fi

  commandNotExists="commandNotExists"
  if MyProcessMatch "$commandNotExists";then
    ps -f
    fail "MyProcessMatch $commandNotExists" 'false' 'true'
  fi
}

_testFormatArrayString(){
  # 测试双引号
  s="$1"
  want='["a","b","c","d","","10","32"]'
  got=$(FormatArrayString "$s" '"')
  assert 'FormatArrayString' "$want" "$got"

  # 测试单引号
  want="['a','b','c','d','','10','32']"
  got=$(FormatArrayString "$s")
  assert 'FormatArrayString' "$want" "$got"

  # 测试无引号
  want='[a,b,c,d,,10,32]'
  got=$(FormatArrayString "$s" '')
  assert 'FormatArrayString' "$want" "$got"

  # 测试忽略中间空值
  want='[a,b,c,d,10,32]'
  got=$(FormatArrayString "$s" '' 1)
  assert 'FormatArrayString' "$want" "$got"
}
testFormatArrayString(){
  testing 'FormatArrayString'
  _testFormatArrayString ',,a,b,c,d,,10,32,,'
  _testFormatArrayString '[,a,b,c,d,,10,32,,]'
}

testParseArrays() {
  testing 'ParseArrays'
  s='[a,b,c,d],[1,2,3]'
  want="a,b,c,d${LF}1,2,3"
  got=$(ParseArrays "$s")
  assert 'ParseArrays' "$want" "$got"

  s='[abc_32342o,gf34^0ff*o0_xw3Ms,/,.*,.*,.*]'
  want='abc_32342o,gf34^0ff*o0_xw3Ms,/,.*,.*,.*'
  got=$(ParseArrays "$s")
  assert 'ParseArrays' "$want" "$got"
  ParseArrays "$s" | while IFS= read -r got; do
    assert 'ParseArrays | while IFS= read -r' "$want" "$got"
  done
}
testParseConfig() {
  testing 'ParseConfig'
  want="/var/run/mysqld/mysqld.pid"
  got=$(ParseConfig "$config" "pid-file")
  assert 'ParseConfig' "$want" "$got"

  want="1.0.0"
  got=$(ParseConfig "$config" "redis_version")
  assert 'ParseConfig' "$want" "$got"
}
testSetConfig() {
  testing 'SetConfig'
  want="$(date)"
  SetConfig "test-datetime=${want}" "$config"
  got=$(ParseConfig "$config" "test-datetime")
  assert 'SetConfig' "$want" "$got"
}
testGenerateRSAKeys() {
  testing 'GenerateRSAKeys'
  if ! command -v openssl >/dev/null 2>&1; then
    Warn "GenerateRSAKeys: need install openssl"
    return 0
  fi
  # 测试stream模式
  prefix=$(Now -N)
  temp=$(mktemp -d)
  trap 'rm -rf "$temp"' EXIT # 临时文件，退出后自动删除
  GenerateRSAKeys 'stream' "$(whoami)" "$temp" "A$prefix-" 512
  f="${temp}/A${prefix}"
  if [ ! -s "${f}-512.priv.der" ] || [ ! -s "${f}-512.pub.der.b64" ]; then
    printf '%s\n' "GenerateRSAKeys stream failed"
    exit
  fi

  if [ -f "${f}-512.priv" ] || [ -f "${f}-512.pub" ]; then
    printf '%s\n' "GenerateRSAKeys stream failed, found .priv/.pub"
    exit
  fi

  # 测试full模式
  prefix=$(Now -N)
  temp=$(mktemp -d)
  trap 'rm -rf "$temp"' EXIT # 临时文件，退出后自动删除
  GenerateRSAKeys 'full' "$(whoami)" "$temp" "B$prefix-" 512
  f="${temp}/B${prefix}"
  if [ ! -s "${f}-512.priv.der" ] || [ ! -s "${f}-512.pub.der.b64" ]; then
    printf '%s\n' "GenerateRSAKeys full failed"
    exit
  fi

  if [ ! -s "${f}-512.priv" ] || [ ! -s "${f}-512.pub" ]; then
    printf '%s\n' "GenerateRSAKeys full failed, not found .priv/.pub"
    exit
  fi
}



main() {
  if [ $# -ne 1 ]; then
    HighlightD "Testing a single function, you can use: $0 [func_name]" "测试单个函数，可以使用：$0 [函数名]"
  fi


  # 测试单个函数
  if [ $# -eq 1 ]; then
    func="$1"
    case "$func" in
      test*) "$func"; return $? ;;
      *) "test$func"; return $? ;;
    esac
  fi

  testLog
  testAbs
  testMin
  testMax
  testIsLF
  testCrossServiceSignal
  testIAmRoot
  testCpuArchitecture

  testIncrVersion
  testASCII

  testChwonR
  testChgrpR
  testStrRepeat
  testStrpad
  testStrpadLeft
  testAlignKVPair
  testStrFirst
  testCutLeft
  testSubstr
  testSubstring
  testStartWith
  testEndWith

  testTrimLeft
  testTrimRight
  testTrim

  testIndexOf
  testStrIn
  testSliceIn
  testPackLF
  testReplace
  testReplaceLF
  testReplaceLFToSpace
  testReplaceSpaceToLF
  testSlice

  testCountMatches
  testSlicelen
  testJoin
  testSplit

  testIsAccessible
  testHttpCode
  testHttpOK

  testAbsDir
  testParentDir
  testAbsPath
  testFilename
  testExtname
  testFindFileByExt
  testCountWords
  testWordIndex
  testWordIn
  testNthWord
  testWordsBetween
  testWordsRange
  testProcessMatch
  testFormatArrayString
  testParseArrays
  testParseConfig
  testSetConfig
  testGenerateRSAKeys



  Info "Test Success"
}
main "$@"