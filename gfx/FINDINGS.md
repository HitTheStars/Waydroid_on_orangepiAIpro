#!/bin/bash
# 图形层修复的完整过程与证据记录（2026-10-28）
# 本文件是 STATUS.md「图形层修复」一节引用的原始证据片段

================================================================
A. 修复前的误判 / 真根因
================================================================
原始崩溃栈（gbm_mesa_bo_import+320, x0=x1=0）确实是 NULL 解引用，但**不是**
libgbm_mesa_wrapper.so 版本不匹配。反汇编 /vendor/lib64/libminigbm_gralloc_gbm_mesa.so
0x12298 处：

  #00 gbm_mesa_bo_import+320:  f940039b  ldr x27, [x28]     ; x28 = NULL
  上一层 0x1227c:  ldr x0, [x19]        ; x0 = bo->drv
  0x12288:         bl  helper(0x11d80)  ; 拿 "gbm device cache" 条目，出参 [sp,#16]
  0x1228c:         ldr x28, [sp, #16]   ; == 0  ← helper 没填出参

helper 内部走 gbm_mesa_internals.cpp 的 DRM node 查找，失败时直接返回、不填出参，
上层对 ops 表取 [x28] 就踩 0。所以 x0/x1 全 0 是"设备拿不到"的**后果**，不是符号问题。

关键 log（容器内 logcat，main buffer，容器时区 GMT）：
  10-27 17:58:19.997 14118 14301 I [minigbm:gbm_mesa_internals.cpp(214)]: Using device /dev/dri/renderD128 as requested by gralloc.gbm.device
  10-27 17:58:19.997 14118 14301 E [minigbm:gbm_mesa_internals.cpp(183)]: Unable to open /dev/dri/renderD128 with error Permission denied
  10-27 17:58:19.997 14118 14301 E [minigbm:gbm_mesa_internals.cpp(228)]: Unable to find or open DRM node
  10-27 17:58:20.150 14118 14301 F DEBUG   :       #00 pc 0000000000012298  /vendor/lib64/libminigbm_gralloc_gbm_mesa.so (gbm_mesa_bo_import(bo*, drv_import_fd_data*)+320)
  10-27 17:58:34.158 14906 14944 W EGL-MAIN: failed to open /dev/dri/renderD128: Permission denied
  10-27 17:58:34.158 14906 14944 W EGL-MAIN: droid_open_device() Failed to open DRM device /dev/dri/renderD128

对照：容器内同进程族（surfaceflinger，pid 83）能正常 "Allocated: 720x503"，
因为它在容器启动早期就拿到了 fd；而 bootanimation / systemui / app 进程每次都重新 open。

================================================================
B. /dev/dri 权限现场
================================================================
宿主机:  crw-rw---- 1 root render 226,128   (MODE 0660, gid 109)
容器内:  crw-rw---- 1 0    109    226,128   ← gid 109 在 Android 侧不存在
         crw-rw-rw- 1 0    1003   226,0     card0/card1 正常（1003 = graphics）
Android 侧 ueventd.rc 明明写的是 `/dev/dri/* 0666 root graphics`，但节点是 bind mount，
宿主 udev 在容器启动过程中把 0660 又盖回来了（含 uaccess ACL，故带 "+"）。
Waydroid 自己 do_start() 里 set_permissions(args) 默认 mode=777 也会被这次覆盖顶掉，
所以只能从宿主机 udev 规则钉死。

================================================================
C. 修完权限后暴露的第二个卡点（abilist / 32 位）
================================================================
  FATAL EXCEPTION IN SYSTEM PROCESS: android.display
  java.lang.RuntimeException: Failed to inform zygote of boot_completed
    at android.os.ZygoteProcess.bootCompleted(ZygoteProcess.java:914)
  Caused by: android.os.ZygoteStartFailedEx: Error connecting to zygote
    at ...attemptConnectionToSecondaryZygote(...)
  Caused by: java.io.IOException: No such file or directory   ← /dev/socket/zygote_secondary 不存在
  → 连带 com.android.systemui: DeadSystemException，system_server 循环重启

原因：/vendor/odm/etc/build.prop（odm 分区优先级最高）写着
  ro.odm.product.cpu.abilist=arm64-v8a,armeabi-v7a,armeabi
虽然 ro.vendor.* / ro.system.* 都是 64 位-only，init 用 odm 的值派生出
  ro.product.cpu.abilist=arm64-v8a,armeabi-v7a,armeabi
于是 AMS 认为还要一个 32 位 zygote，而 /system/bin 下根本没有 32 位 zygote 二进制。
→ overlay 覆盖 odm build.prop 成 64 位-only。

================================================================
D. 修完 abilist 后暴露的第三个卡点（keystore2 数据库属主）
================================================================
  E AndroidRuntime: *** FATAL EXCEPTION IN SYSTEM PROCESS: LockSettingsService
  E AndroidRuntime: java.lang.AssertionError: 4
      at android.security.KeyStore.state(KeyStore.java:67)
      at com.android.server.locksettings.LockSettingsService.ensureProfileKeystoreUnlocked(...)
  keystore2 tombstone:
      Abort message: 'Failed to open database.: Failed to attach database persistent.
      0: unable to open database: file:/data/misc/keystore/persistent.sqlite
      1: Error code 14: Unable to open the database file'
  现场：/data/misc/keystore/persistent.sqlite 属主是 system:system(1000)，而 keystore2 跑 1017
  （宿主机侧看到的是 HwHiAiUser 1000 —— 之前有人用宿主机身份动过这个文件）
  → chown 1017:1017 之后 keystore2 不再重启，LockSettingsService 不再抛异常。

================================================================
E. 最终验证（2026-10-28 02:13，干净重启后，未手工 chmod）
================================================================
（见 evidence_20261028_boot2.txt 全文）
  sys.boot_completed = 1
  ro.hardware.gralloc = minigbm_gbm_mesa / ro.hardware.egl = mesa / ro.hardware.vulkan = panfrost
  ro.product.cpu.abilist = arm64-v8a, abilist32 = (空)
  init.svc.bootanim = stopped, surfaceflinger = running, zygote = running
  logcat -b crash: gbm_mesa_bo_import = 0, FATAL EXCEPTION = 0
  ELFCLASS32 processes = 0
  截图 shot_20261028_0209.png：桌面 + 状态栏 + 导航栏 + QS 面板，panfrost 真在渲染
