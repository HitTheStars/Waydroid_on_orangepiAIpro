/* 方舟计划 · 运行时解析符号的声明（全局 -include，避免逐文件改 include） */
#ifndef _ARK_SYMBOLS_H
#define _ARK_SYMBOLS_H

#include <linux/types.h>
#include <linux/sched.h>
#include <linux/mm.h>
#include <linux/file.h>
#include <linux/ipc_namespace.h>

int ark_is_init_ipc_ns(struct ipc_namespace *ns);
void ark_put_ipc_ns(struct ipc_namespace *ns);

#endif
