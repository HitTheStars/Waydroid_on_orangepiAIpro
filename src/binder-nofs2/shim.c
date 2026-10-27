/* 方舟计划 binder 模块本地 shim
 * 内核 CONFIG_SECURITY=y 但 security_binder_* 未 EXPORT_SYMBOL，
 * 且本机 cmdline 带 selinux=0、未启用任何 LSM 的 binder hook，
 * 这里给本地实现（全部返回 0 = 放行），与内核内实现语义等价。
 */
#include <linux/kernel.h>
#include <linux/sched.h>
#include <linux/fs.h>

int security_binder_set_context_mgr(struct task_struct *mgr) { return 0; }
int security_binder_transaction(struct task_struct *from, struct task_struct *to) { return 0; }
int security_binder_transfer_binder(struct task_struct *from, struct task_struct *to) { return 0; }
int security_binder_transfer_file(struct task_struct *from, struct task_struct *to, struct file *file) { return 0; }
