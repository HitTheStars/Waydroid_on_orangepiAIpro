# 方舟计划 · 崩溃排查方案

生成时间：2026-10-27 05:42

## 一、取证结论：现场已全部丢失

| 证据源 | 状态 | 原因 |
|---|---|---|
| `/sys/fs/pstore/` | 空目录 | 内核有 pstore 模块，但设备树没有 ramoops 保留内存节点 |
| journald | 最后写入 04:17:02 | 时间从 2023 跳到 2026，journald 遇时间倒退后停止写入 |
| kern.log | 最早 05:01:58 | 04:17 之前的被轮转清掉；05:02-05:09 期间 rsyslog 卡死，整段空白 |
| `log_redirect=0x1fc000@0x22741000` | 读到了 | 但内容是 U-Boot 的 pinmux/pcie 探测日志，**不是内核 kmsg** |
| `dump_data_addr=0x20A0000000` | 未读 | 该地址在 130GB 偏移，远超 DDR，不是有效 dump 区 |

已确认的事实（来自 cmdline + bbox）：

```
reboot_reason=OS_PANIC
[bbox] device-0 reboot reason [OS_PANIC][0x24]
```

→ 上次复位是**内核软件 panic**，不是掉电、不是看门狗、不是硬件故障。

**但 oops 栈本身没有了。** 继续猜就是编。

## 二、时间线（从日志残片重建）

```
04:17:02  journald 最后一次写入，之后日志系统死亡
04:1x-05:01  系统在跑，但零日志（这段干了什么无从查证）
05:01:58  内核重新启动（说明 05:00 前后有一次 panic）
05:02:01  rsyslog 记录到 [13.8s]，随后 7 分钟完全空白
05:08:30  mmap+裸读测试（脚本里 m[0] 必然 SIGBUS，被外层 exit 0 掩盖）
05:08:40  test_binder.py 返回 -7 (SIGBUS)
05:09:08  rm /dev/binder + ln -s + insmod ashmem_mod.ko
05:09:24  restore_runtime.sh（0 字节空文件）
05:09:xx  整机复位（OS_PANIC）
05:10:xx  重启，日志恢复正常（3093 行）
```

关键异常：**05:02 到 05:09 这 7 分钟，内核一条 printk 都没落盘**。
系统还能执行命令，但日志管道已经死了 —— 这本身说明内核在那段时间已经处于不健康状态。

## 三、下次的布网方案（按代价排序）

### 级别 1：软件布网（今晚就能配，零硬件）
```bash
# 1. oops 立即 panic，不让它半死不活拖 7 分钟
sysctl -w kernel.panic_on_oops=1
sysctl -w kernel.panic=10          # panic 后 10 秒自动重启

# 2. rsyslog 同步落盘，保证 oops 那几行不丢在缓冲区
#    /etc/rsyslog.conf 加:  $ActionFileEnableSync on
systemctl restart rsyslog

# 3. 修 journald 时间跳变问题
systemctl restart systemd-journald
# 若仍不写入：mv /var/log/journal /var/log/journal.bak && mkdir /var/log/journal

# 4. 提高 printk 控制台级别，确保 oops 一定输出
sysctl -w kernel.printk="8 4 1 7"
```

### 级别 2：netconsole（需要另一台机器收）
```bash
# 本机（把 192.168.x.y / MAC 换成对端）
modprobe netconsole netconsole=6666@10.250.192.128/wlan0,6666@192.168.x.y/aa:bb:cc:dd:ee:ff
# 对端：nc -u -l 6666
```
崩溃瞬间的完整栈会 UDP 发出去，是**唯一能在 panic 当场抓到全栈且不改内核的手段**。

### 级别 3：串口（需要 USB-TTL 线）
cmdline 里已有 `console=ttyAMA0,115200`，接上 ttyAMA0 就能看到全部输出。
这是最硬的方案，panic 全程可见。

## 四、加载纪律（不管有没有布网，都必须遵守）

1. **一次只加载一个模块**，binder 和 ashmem 分开验证
2. 每步前打点：`echo "ARKSTEP-x" > /dev/kmsg; logger -t arkstep "STEP x"; sync`
3. 崩了之后重启，`journalctl -k | grep ARKSTEP | tail -1` 就知道死在哪一步
4. 见 `load_step.sh`
