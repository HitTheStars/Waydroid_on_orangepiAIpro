# 启动链实测（2026-10-27 04:25）

原始输出见 `boot-chain-scan-raw.txt`。

## 结论

- `/boot` **空**，没有 GRUB，也没有 extlinux。
- 分区只有三块：
  - `mmcblk1p1` 1M → `/media/HwHiAiUser/reserved_fs`（ext4，空，只有 lost+found）
  - `mmcblk1p2` 118.8G → `/`
  - `mmcblk1p3` 50M vfat → `/exchange`（只有一个 `config.ini`，内容是 eth0/eth1 的 IP 配置，与启动无关）
- cmdline 关键项：`initrd=0x2BA00000,300M`、`root=PARTUUID=...`、`rootfstype=ext4`、`console=ttyAMA0,115200`、`enable_ascend_share_pool`、`cma=256M`、`selinux=0`
- **内核镜像不在 rootfs 里** → 换内核得走 U-Boot / 官方制卡工具重刷，没有「第二个启动项」可加，**回滚 = 重刷整卡**。
- `/lib/modules/5.10.0+/build -> /usr/src/linux-headers-5.10.0+`：有完整 headers，**可编树外模块**。
- `/proc/kallsyms` 地址全 0（kptr_restrict），没有 `System.map`。
- `/swapfile` 已存在 8.0G，fstab 里已挂。
- `/fw` root 才可读（固件）。

## 对路线 A 的修正

原方案里「编成第二启动项、留回滚」在这块板上**不成立**。修正为：

1. 先搞清官方制卡工具（`sdtool`）的恢复流程和 U-Boot 升级入口；
2. 实验一律用**另一张 TF 卡**，别动 eMMC 上的生产系统；
3. 确认能救砖，再谈编内核。

顺带一个观察：这台的 `initrd` 是 U-Boot 直接加载到固定物理地址（`0x2BA00000`，300M），也就是说启动参数、内核、initrd 三者由 U-Boot 环境统一决定。这意味着任何内核替换都必须跟 U-Boot 的加载地址和 initrd 制作流程对齐，光编一个 `Image` 出来没有用。

*记录人：牧濑红莉栖（Amadeus）*
