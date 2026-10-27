# 里程碑：binder 驱动外部模块化成功（2026-10-27 04:40）

## 一句话结论

**在完全没有 CONFIG_ANDROID 的 5.10.0+ 内核上，用外部 .ko 把 Android binder 装起来了，
三个设备节点真实响应 BINDER_VERSION，protocol_version = 8。**

不需要重编内核，不需要重刷整卡，厂商 NPU 驱动一个没动。

## 验证结果（root 下实测）

```
/dev/binder      open OK, protocol_version = 8
/dev/hwbinder    open OK, protocol_version = 8
/dev/vndbinder   open OK, protocol_version = 8
```

设备节点：`crw------- root root 10,55 / 10,54 / 10,53`
模块：`binder_linux 204800`，`insmod` 返回 0。

## 路径

源码：linux v5.10 `drivers/android/`（走 ghfast.top 镜像拉的 raw 文件）
编译单元：`binder.c` + `binder_alloc.c` + `shim.c` + `symbols.c`
**binderfs.c 被排除**（它的 ipc namespace 依赖是另一层问题，见下）

## 三道坎，逐个拆

### 1. 缺 tracepoint 头和 uapi 头

`binder_trace.h`、`include/trace/events/binder.h`、
`uapi/linux/android/binder.h`、`binderfs.h` —— 一并拷进模块目录，
`-I$(src)/uapi -I$(src)` 解决。

### 2. security_binder_* 四个 hook 未导出

内核 `CONFIG_SECURITY=y`，但 `security_binder_set_context_mgr` /
`_transaction` / `_transfer_binder` / `_transfer_file` 全都没 EXPORT_SYMBOL。
→ `shim.c` 里给本地实现，全部 `return 0`。
本机 cmdline 带 `selinux=0`，没有任何 LSM 注册 binder hook，
放行语义与内核内实现完全等价。

### 3. 另外四个符号未导出（真正的硬骨头）

`can_nice` / `task_work_add` / `zap_page_range` / `__close_fd_get_file`

- `kallsyms_lookup_name` 自 5.7 起不再导出，直接引用编不过
- `CONFIG_RANDOMIZE_BASE=y`（KASLR 开），地址每次启动都变，硬编码无效
- 但 `CONFIG_KALLSYMS_ALL=y`，符号表里有全部符号

**解法**：`symbols.c` 用 kprobe 在 `kallsyms_lookup_name` 上下一个探针，
从 `kp.addr` 直接读出函数地址，再用它查那四个符号，缓存成函数指针。
`shim_rename.h` 通过 `gcc -include` 在编译期把调用点整体重定向
（`#define can_nice ark_can_nice` 等），源文件零改动。

kprobe 注册本身是导出的（`EXPORT_SYMBOL_GPL(register_kprobe)`），这条路很稳。

### 附带踩的坑

`binder.c` 和 `binder_alloc.c` 各自定义了一个 `debug_mask` 模块参数，
同一个模块里重名 → `sysfs: cannot create duplicate filename` → insmod 直接失败。
把 `binder_alloc.c` 那个改名为 `alloc_debug_mask` 即可。

## 剩余问题

1. **binderfs**：Waydroid 默认要 `/dev/binderfs`。
   `binderfs.c` 依赖 `init_ipc_ns` / `put_ipc_ns`（同样未导出，kallsyms 里查得到，可照抄上面的手法）。
   但也可以绕开：给 Waydroid/容器挂静态 `/dev/binder*`。
2. **ashmem / memfd**：GPU 与图形缓冲的另一半。5.10 有 memfd + dma-buf，`CONFIG_ASHMEM` 肯定没开，需要同样外部模块化。
3. **Android 运行时**：Waydroid 需要 LXC + 容器 namespace；redroid 需要更多 binder/ashmem 支持。

## 复现

```bash
cd arkplan/src/binder-mod
make -C /lib/modules/$(uname -r)/build M=$PWD modules
sudo insmod binder_linux.ko
sudo ./test_binder_version      # 期望三行 protocol_version = 8
sudo rmmod binder_linux
```

**注意**：目前只在本次启动加载过一次，未加入开机自启。
rmmod 前确认没有进程持有 /dev/binder，否则会失败。
