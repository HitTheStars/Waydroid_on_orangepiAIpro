/* ashmem 侧 shim 头：全局 -include 注入 */
#ifndef _ASHMEM_SHIM_H
#define _ASHMEM_SHIM_H

#include <linux/mm.h>

int ark_shmem_zero_setup(struct vm_area_struct *vma);

/* shmem_zero_setup 在内核里未 EXPORT，运行时解析后转发 */
#define shmem_zero_setup ark_shmem_zero_setup

#endif
