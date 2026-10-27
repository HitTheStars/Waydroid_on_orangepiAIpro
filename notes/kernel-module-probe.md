# 外部内核模块加载探针（2026-10-27 04:35）

## 结论：通路完全打通

```
[结果] insmod OK / dmesg: "arkplan: hello.ko loaded, probe OK" / lsmod 列出 hello / rmmod OK
```

## 内核配置关键项
CONFIG_MODULE_SIG_FORMAT=y
CONFIG_MODULES=y
CONFIG_MODULE_UNLOAD=y
CONFIG_MODULE_FORCE_UNLOAD=y
CONFIG_MODULE_SIG=y
CONFIG_MODULE_SIG_SHA1=y
CONFIG_MODULE_SIG_HASH="sha1"
CONFIG_MODULE_SIG_KEY="certs/signing_key.pem"

## 环境
- kernel: 5.10.0+ / gcc: 11
- build dir: /lib/modules/5.10.0+/build -> /usr/src/linux-headers-5.10.0+
- modules_disabled=0

## 产物
- src/hello-mod/hello.c (.ko 149616 B)
- 编译: make -C $(build) M=$PWD modules  用时约 4 秒

## 意义
树外模块可以自由编译并加载 → binder 打成 .ko 的路线成立。
剩余障碍不是加载，而是 binder.c 依赖的未导出内核符号需要 shim。
