# Linux /opt 脚本集

直接将本目录下其他子目录复制进Linux 系统 /opt 目录下（如果不存在，则创建即可）。

然后将对应 /opt/xx/bin 导入PATH变量

如全部添加
```shell
echo 'export PATH=/opt/aa/bin:/opt/k8s/bin:/opt/postgres/bin:$PATH' >> /etc/profile
source /etc/profile
```

如只添加 /opt/aa/bin
```shell
echo 'export PATH=/opt/aa/bin:$PATH' >> /etc/profile
source /etc/profile
```