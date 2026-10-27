#!/bin/bash
# 根因修复：容器内 /dev/dri/renderD128 是 bind mount，组为宿主机 render(109) 且 0660，
# Android 进程（bootanimation / systemui / untrusted_app）不在 gid 109 → open() EACCES
# → gbm_mesa gbm_create_device 失败 → gbm_mesa_bo_import 里 ops 为 NULL → SIGSEGV。
# 宿主机侧把节点放开（bind mount 共享 inode，容器内立即可见），无需重启容器。
set -e
chmod 666 /dev/dri/renderD128
ls -ln /dev/dri/renderD128
