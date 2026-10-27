# 方舟计划 / ArkPlan

建立时间：2026-10-27 04:20 (CST)
目标：在这台 Orange Pi AIpro 20T 上，找出让《明日方舟》跑起来的最省路径。

---

## 零、当前状态（2026-10-28 05:57 更新）

| 项 | 状态 |
|---|---|
| binder / ashmem | ✅ 已解决。树外模块 `binder_linux_nofs.ko` + `ashmem_mod.ko`，insmod 即得 `/dev/binder` |
| Waydroid | ✅ 1.6.3 + **纯 arm64 镜像**（本机无 AArch32 执行能力，见 `STATUS.md` 「⛔ 定论」） |
| Android | ✅ 曾正常起 Android 13（720x503, density 180），DRM 出画面，adb over TCP 可用 |
| 明日方舟 | ⬜ 未安装。APK 已就绪 1.86GB，等容器起来后 adb install |
| 已知风险 | ⚠️ 低功耗模块 `lpm` 读电流失败会触发整机 panic 重启（`DRV_LPM_FAULT`），重负载下高频 |

**要在这台机器上重新跑起来** → 看 [`RESTORE.md`](RESTORE.md)（含干净系统恢复、一键 `restore.sh`、自检 `verify_restore.sh`）。
**要查历史踩坑全记录** → 看 [`STATUS.md`](STATUS.md)（8 万字，按时间倒序）。

> 仓库只放代码与可重建的配置快照。镜像 / APK 等大件不入库，校验清单在 `state/assets.sha256`。

### 镜像下载（GitHub 不支持大文件入库）

`system.img` 1.86 GiB、`vendor.img` 402 MiB 都超过 GitHub **单文件 100MB 硬上限**，git 里放不进去（LFS 免费额度 1GB 也不够）。所以走 **Release 资产**（上限 2GiB/文件）：

```bash
# 拉回来（任选目录）
gh release download v1-20261027-images --repo HitTheStars/Waydroid_on_orangepiAIpro \
   --pattern '*.img' -D /root/wd-img-backup-1027_2222
# 或者直接 curl
curl -LO https://github.com/HitTheStars/Waydroid_on_orangepiAIpro/releases/download/v1-20261027-images/system.img
curl -LO https://github.com/HitTheStars/Waydroid_on_orangepiAIpro/releases/download/v1-20261027-images/vendor.img

# 校验（仓库里带 sha256 清单）
sha256sum -c state/assets.sha256 --ignore-missing
```

- Release 页面：<https://github.com/HitTheStars/Waydroid_on_orangepiAIpro/releases/tag/v1-20261027-images>
- 上传/重传脚本：`scripts/upload_release.sh`（token 从 `~/.gh_token` 或 `$GH_TOKEN` 读，`--test` 先验链路）
- 传上去的两个镜像已用 HTTP Range 对首尾各 4MB 做过 sha256 比对，与本地备份一致

---

## 一、硬件与系统事实（已实测）

| 项目 | 实测值 |
|---|---|
| 板子 | OPi Ai Pro 20T / compatible: `hisilicon,hi1910B-evb hisilicon,ascend610` |
| 内核 | 5.10.0+（无后缀，BSP 定制） |
| 发行版 | Ubuntu 22.04.3 LTS (Jammy) |
| 架构 | aarch64（原生 ARM，跑 Android 程序无 QEMU 转译层） |
| CPU / 内存 | 3 核 / 11G（可用约 6G） |
| 磁盘 | `/` 117G，已用 86G，剩 27G |
| KVM | `/dev/kvm` 存在，crw-rw----+ 有 rw ACL |
| DRM | `/dev/dri/card0` `card1` `renderD128` |
| **binder** | **无** `binder` 文件系统、无 `/dev/binder*`、无 `ashmem` |
| 内核配置 | `# CONFIG_ANDROID is not set`（整个 Android 支撑块关闭，binder 子项不存在） |
| 树外模块 | 30+ 个 `ascend_*` / `drv_*`（NPU、ISP、VPSS、编解码、DRM、smf/urd/trs 等），全部绑定当前 5.10.0+ |
| `/boot` | 空目录，启动链待摸清 |
| Ascend 环境 | `/usr/local/Ascend/{driver,firmware,ascend-toolkit,mxVision,nnal}` |

### 关键结论
- aarch64 上跑 Android 是**原生执行**，「省一层转译」这个前提不成立。
- Waydroid / redroid 全依赖 binder，内核没编 → 这条路**直接堵死**，不是配一下就行。
- 换 vendor kernel 的风险点不是 vermagic（binder 开关不进 vermagic），而是 **config 改动导致结构体布局变化 → 树外模块内存越界**，表现为跑几天莫名 panic。

---

## 二、三条路线（按性价比排序）

### 路线 A：干净内核 + 只开 binder（推荐，成本中等，可回滚）
1. 拿原厂 `.config` 做基线（`make olddefconfig`），只加：
   - `CONFIG_ANDROID=y`
   - `CONFIG_ANDROID_BINDER_IPC=y`
   - `CONFIG_ANDROID_BINDERFS=y`
2. 版本号保持 `5.10.0+` 不动，SMP/preempt 与基线一致。
3. **不覆盖**原内核，编出 `vmlinuz-android` + initrd，在启动配置里加**第二个启动项**。
4. NPU/ISP 那一套在这条启动项下不要，避免撞符号。
5. Waydroid（LXC + 原生 arm64）装 APK。
   - 预期性能：Mali/DRM 软渲染，明日方舟这类 Unity 2D 大概 10-20fps，能挂机刷 1-7，手操不现实。
6. 风险：启动链摸错 → 起不来，需要 U 盘/串口救砖预案。

### 路线 B：APK 逆向下移植（成本极高，不建议）
- IL2CPP：`libil2cpp.so` + `global-metadata.dat` 与 Unity 版本死绑。
- ab 资源包加密 + 反调试，重写 player 是几十人月量级。
- REA 之类工具能给的是「看清」，不是「跑起来」。

### 路线 C：云游戏 / 手机玩（成本最低）
- 本机只做「陪你查攻略、算基建、看抽卡」，不上模拟器。

---

## 三、已下载

| 路径 | 内容 | 体积 | 来源 |
|---|---|---|---|
| `src/rea` | REA (Reverse Engineer Anything)，MIT，MCP 逆向工具链 | 120M | `morluto/rea`（GitHub，经 ghfast.top 镜像）；中文镜像 `bbylw/rea-cn` |

REA 要点（供后续装）：依赖 Ghidra / IDA / Hopper 引擎（自己不带反编译器），支持 APK(JADX)、ELF、固件(binwalk)、ADB；安装走 `npx rea-agents setup`。

## 四、待取清单

| 目标 | 状态 | 备注 |
|---|---|---|
| `Ascend310B-source.tar.gz` | 未取 | 昇腾 Atlas 200I A2 驱动开发指南里列的源码包；hiascend 下载页一般要登录 |
| CANN driver 源码 | 未取 | 官方说在 GitCode/AtomGit；`gitcode.com/Ascend/driver` 等路径当前返回需认证，路径待确认 |
| Orange Pi AIpro BSP 内核 | 未取 | `orangepi-xunlong/linux-orangepi` 只有 RK3399/RK3588 分支（`orange-pi-5.10*`），**无昇腾**分支 |
| 原厂 `.config` | 已取 | `/proc/config.gz`（本机直接 zcat） |
| 官方 PC 端 | 未取 | Windows x86_64，本机要 wine + box64，倒多一层 |

## 五、下一步（明天做，不在凌晨做）
1. 摸清 `/boot` 空 + 启动链（`fdisk -l` / `/proc/cmdline` / U-Boot 环境）。
2. 确认 AIpro 的 BSP 内核源码到底在哪（Orange Pi 官网资料页 / 昇腾社区）。
3. 用原厂 config 编一次「不改任何选项」的内核，验证工具链能出活、能启动——先证明能编，再谈改。
4. 再谈 binder。

---
*记录人：牧濑红莉栖（Amadeus）*
