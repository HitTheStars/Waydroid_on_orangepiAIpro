# RESTORE.md — 从干净系统镜像重建到 2026-10-28 05:20 的状态

> 结论先说：**git 仓库本身不够**。仓库能重建"改了什么、为什么改、怎么改"，
> 但重建需要 **4 个必须从仓库外带走的二进制资产**（2.3G 镜像 + 1.86G APK，见 §1）。
> 补齐后：`sudo bash arkplan/restore.sh` 一条命令即可回到当前状态（脚本已随仓库提交）。

---

## 1. 必须事先从这台机器拷走的资产（不在 git 里，重装即丢）

| 资产 | 当前路径 | 大小 | 校验 |
|---|---|---|---|
| 安卓 system 镜像 | `/root/wd-img-backup-1027_2222/system.img` | 1.9G | md5 `410bb605bc27b0a0610b924555bfba08` |
| 安卓 vendor 镜像 | `/root/wd-img-backup-1027_2222/vendor.img` | 403M | md5 `4ba49f5ea81523ec9db9d9ef6fa3df32` |
| 明日方舟官服 APK | `/home/HwHiAiUser/data/arkplan/apk/arknights-hg-2781.apk` | 1,861,585,573 B | ZIP 中央目录 3852 条目 |
| NDK（仅在需要重编 .ko 时） | `downloads/android-ndk-r26d-linux.zip` | ~660M | URL 已记录：`https://dl.google.com/android/repository/android-ndk-r26d-linux.zip` |

⚠️ 三个真实缺口：
1. **镜像的原始下载 URL 没有记录**。只能靠 md5 反查，或者直接用现成文件。→ 行动：把两个 img 复制到 PC / 移动硬盘。
2. **APK 的下载来源没有记录**（只有文件名里的 `hg-2781`）。→ 同上，或重下时记下渠道链接。
3. `/root/` 属主是 root、在系统盘上，"备份目录"这个名字有误导性——它其实是**正在被软链使用的镜像本体**，不是副本。整个目录只有一份。

拷贝示例（在 PC 上执行）：
```bash
scp -r HwHiAiUser@<板子IP>:/root/wd-img-backup-1027_2222 ~/arkplan-images/   # 需 sudo 权限读取
scp HwHiAiUser@<板子IP>:/home/HwHiAiUser/data/arkplan/apk/arknights-hg-2781.apk ~/arkplan-images/
```

---

## 2. 环境基线（干净镜像要满足）

- 内核 **5.10.0+ aarch64**，`CONFIG_MODULE_SIG=y` 但**未** `FORCE` → 未签名模块可加载
- `waydroid 1.6.3`、`lxc 1:5.0.0~git2209`（Ubuntu 源）
- 宿主 ufw **启用** 且 `DEFAULT_FORWARD_POLICY="DROP"` → 必须跑 `net/fix_host_net.sh`
- 同型号板子（Mali GPU、无 NPU 依赖本方案）

---

## 3. 一条命令恢复

```bash
cp -r ~/arkplan-images/wd-img-backup-1027_2222 /root/       # 放回镜像
sudo bash arkplan/restore.sh                               # 7 步，最后自动调 up.sh
```

`restore.sh` 干的事（对应提交内容）：

| 步 | 动作 | 数据来源 |
|---|---|---|
| 0 | 校验 `uname -r == 5.10.0+`，不符就停并指出重编路径 | 现场 |
| 2 | 建 `/var/lib/waydroid/images/{system,vendor}.img` 软链 | `$IMG_SRC` |
| 3 | 恢复 `waydroid.cfg`（`arch=arm64_only`、`binder_protocol=aidl3`、`mount_overlays=True`） | `state/etc/waydroid.cfg` |
| 4 | 回放安卓 system 内的真实改动：`libart.so`×2（UFFD 修复）、`vold.rc` | `state/overlay_rw_system/` |
| 5 | 替换被改过的 `waydroid-net.sh`（md5 `1a522e26…`，出网靠它） | `state/etc/waydroid-net.sh.modified` |
| 6 | 装 `wdroot2.service`（oneshot → `launcher/wd_task2.sh`） | `state/etc/wdroot2.service` |
| 7 | 调 `up.sh`：insmod 三模块 → ufw+ip_forward → renderD128/keystore 权限 → 等 adbd(≈44s) → 等 `sys.boot_completed=1` | `up.sh` + `net/fix_host_net.sh` |

`state/` 目录里除上表外还有：`images-provenance.txt`（镜像尺寸+md5）、`ufw-rules.txt`（10 条规则快照，脚本会自动重建其中 5 条）、`waydroid_base.prop`、`userdata-inventory.txt`（空的 `rootfs/data`，说明安卓从未启动到能写用户数据）。

---

## 4. adb（这块本来是"没写进仓库"的重点，现已明确）

- 安卓侧：`persist.adb.tcp.port=5555` **已持久化**，adbd 开机自监听，`/data/misc/adb/adb_keys` 持久 → 授权不重弹
- 宿主侧：`/home/HwHiAiUser/.android/adbkey`（1704B）是**这台机器专属**，干净系统会重新生成；重新生成后第一次连会弹授权，`up.sh` 会兜底写 `adb_keys`
- 连接目标：`adb -s 192.168.240.112:5555`（`up.sh` 里定义的 `ADB_TARGET`）
- 兜底：`up.sh` 在 unauthorized / 连不上时会 `setprop` 重开 adbd，不会误判成"炸了"
- 说明：`waydroid.cfg` 里 `auto_adb = False`（我们不用 waydroid 自带 adb 桥，改走 TCP）

---

## 5. 内核模块（binder / ashmem）

仓库里是**编好的 .ko**（vermagic `5.10.0+ SMP mod_unload aarch64`），同固件直接 `insmod`：

```
src/binder-nofs2/binder_linux_nofs.ko   # 当前主用（up.sh 首选）
src/binder-mod/binder_linux.ko
src/ashmem-mod/ashmem_mod.ko
src/hello/*/hello.ko                     # 只做加载验证用
```

若固件内核版本变了 → 必须重编，三个坑的解法在 `STATUS.md`：
1. `security_binder_*` 本地空实现
2. `kallsyms_lookup_name` 未导出 → kprobe 抓地址反查（5.7+ 起不导出）
3. 两个 `debug_mask` 重名 → 改名

---

## 6. 已知无法从仓库恢复的部分（诚实清单）

| 项 | 状态 |
|---|---|
| 明日方舟**游戏本体** | 未安装（APK 下好了但从未装上，`rootfs/data` 空），恢复后需重装+登录 |
| 安卓内已产生的用户数据 | 无（容器从未启动到写 data），所以这块**没损失** |
| sudo 密码 | 不入库，问 owner |
| adb 私钥 | 重新生成，影响仅"重弹一次授权" |
| 镜像/APK 下载 URL | 未记录，只能靠 md5 反查或用现成文件 |

---

## 7. 恢复后的验证（逐条可执行，全绿才算回到现状）

```bash
uname -r                                                       # 5.10.0+
lsmod | grep -E "binder|ashmem"                                # 三模块在
ls /dev/binder*                                                # binder binderfs hwbinder vndbinder
waydroid status                                                # Session: RUNNING
adb devices                                                    # 192.168.240.112:5555  device
adb -s 192.168.240.112:5555 shell getprop sys.boot_completed    # 1
adb -s 192.168.240.112:5555 shell ping -c2 8.8.8.8              # 出网正常
```

---

## 8. 关于稳定性（和恢复无关，但别忘）

内核层 LPM 读电流失败导致的整机 panic 仍在：2026-10-27 05:09 与 2026-10-28 04:17 两次，
`reboot_reason=OS_PANIC`、`from_module: [lpm]`、6 分钟内 `DRV_LPM_FAULT` 报 51 次。
恢复出来的系统**照样会崩**——这是板子电源/低功耗层的固件问题，不是我们重建出来的。
