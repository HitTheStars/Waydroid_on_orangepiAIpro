/* 编译期符号改名表（用 gcc -include 强制预置）
 * 把 binder 源码里对未导出符号的调用，整体重定向到 symbols.c 的运行时解析版本。
 * 由于本文件在所有内核头文件之前展开，头文件里的同名 extern 声明会被一起改名，
 * 签名不变，因此不会破坏声明。
 */
#ifndef _ARK_SHIM_RENAME_H
#define _ARK_SHIM_RENAME_H

#define can_nice		ark_can_nice
#define task_work_add		ark_task_work_add
#define zap_page_range		ark_zap_page_range
#define __close_fd_get_file	ark_close_fd_get_file

#endif
