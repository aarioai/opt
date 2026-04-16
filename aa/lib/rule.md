# Shell 脚本规范

## 变量双引号问题

* 仅对明确是单个变量的，加双引号。其他情况不要加，可以将IDE该检测功能关闭。
  * 很多程序，如 redis-server 参数就不能带双引号，否则会无法启动

```shell

noNeedEmptyString(){
  echo $#
}

a=1
b=''
c=2
noNeedEmptyString "$a" "$b" "$c"    # Bad!
noNeedEmptyString $a $b $c          #  Good!



needEmptyString(){
  echo "$1"
  echo "$2"
  echo "$3"
}
needEmptyString "$a" "$b" "$c"    # Good!
needEmptyString $a $b $c          # Bad!


```