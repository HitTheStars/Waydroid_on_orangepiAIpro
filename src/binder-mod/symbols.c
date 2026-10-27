/* 方舟计划 · 未导出内核符号运行时解析层
 *
 * 背景：本机内核 5.10.0+ 未导出 kallsyms_lookup_name（5.7 起移出 EXPORT_SYMBOL），
 * 而 binder / binderfs 需要的这些符号同样未导出：
 *   can_nice / task_work_add / zap_page_range / __close_fd_get_file
 *   init_ipc_ns / put_ipc_ns   （binderfs 用）
 * 手法：用 kprobe 在 kallsyms_lookup_name 上下一个探针，从 kp.addr 直接读地址，
 *      再用它查这些符号，缓存成函数指针。惰性初始化，零侵入原 binder 代码。
 * KASLR 已开（CONFIG_RANDOMIZE_BASE=y），所以必须运行时解析，不能硬编码。
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/kprobes.h>
#include <linux/sched.h>
#include <linux/mm.h>
#include <linux/file.h>
#include <linux/task_work.h>
#include <linux/ipc_namespace.h>
#include <linux/errno.h>

typedef unsigned long (*ark_kln_t)(const char *name);

static ark_kln_t ark_kln;

static int (*p_can_nice)(const struct task_struct *p, const int nice);
static int (*p_task_work_add)(struct task_struct *task,
			      struct callback_head *work,
			      enum task_work_notify_mode notify);
static void (*p_zap_page_range)(struct vm_area_struct *vma,
				unsigned long address, unsigned long size);
static struct file *(*p_close_fd_get_file)(unsigned int fd);
static struct ipc_namespace *ark_init_ns;
static void (*p_put_ipc_ns)(struct ipc_namespace *ns);

static int ark_state;	/* 0=未初始化 1=成功 -1=失败 */

static int ark_ensure(void)
{
	struct kprobe kp = { .symbol_name = "kallsyms_lookup_name" };
	int ret;

	if (ark_state == 1)
		return 0;
	if (ark_state == -1)
		return -ENOENT;

	ret = register_kprobe(&kp);
	if (ret < 0) {
		pr_err("arkplan: register_kprobe(kallsyms_lookup_name) 失败: %d\n", ret);
		ark_state = -1;
		return ret;
	}
	ark_kln = (ark_kln_t)(void *)kp.addr;
	unregister_kprobe(&kp);

	if (!ark_kln) {
		pr_err("arkplan: kallsyms_lookup_name 地址为空\n");
		ark_state = -1;
		return -ENOENT;
	}

	p_can_nice = (void *)ark_kln("can_nice");
	p_task_work_add = (void *)ark_kln("task_work_add");
	p_zap_page_range = (void *)ark_kln("zap_page_range");
	p_close_fd_get_file = (void *)ark_kln("__close_fd_get_file");
	ark_init_ns = (void *)ark_kln("init_ipc_ns");
	p_put_ipc_ns = (void *)ark_kln("put_ipc_ns");

	pr_info("arkplan: kln=%px can_nice=%px twa=%px zap=%px cfd=%px init_ipc_ns=%px put_ipc_ns=%px\n",
		(void *)ark_kln, p_can_nice, p_task_work_add,
		p_zap_page_range, p_close_fd_get_file,
		(void *)ark_init_ns, p_put_ipc_ns);

	if (!p_can_nice || !p_task_work_add || !p_zap_page_range ||
	    !p_close_fd_get_file || !ark_init_ns) {
		pr_err("arkplan: 有符号没解析到\n");
		ark_state = -1;
		return -ENOENT;
	}

	ark_state = 1;
	return 0;
}

int ark_can_nice(const struct task_struct *p, const int nice)
{
	if (ark_ensure())
		return 0;
	return p_can_nice(p, nice);
}

int ark_task_work_add(struct task_struct *task, struct callback_head *work,
		      enum task_work_notify_mode notify)
{
	if (ark_ensure())
		return -ENOSYS;
	return p_task_work_add(task, work, notify);
}

void ark_zap_page_range(struct vm_area_struct *vma, unsigned long address,
			unsigned long size)
{
	if (ark_ensure())
		return;
	p_zap_page_range(vma, address, size);
}

struct file *ark_close_fd_get_file(unsigned int fd)
{
	if (ark_ensure())
		return NULL;
	return p_close_fd_get_file(fd);
}

/* binderfs：判断某个 ipc namespace 是不是初始 namespace（决定能否用保留设备号） */
int ark_is_init_ipc_ns(struct ipc_namespace *ns)
{
	if (ark_ensure())
		return 0;
	return ns == ark_init_ns;
}

/* binderfs：释放对 ipc namespace 的引用 */
void ark_put_ipc_ns(struct ipc_namespace *ns)
{
	if (ark_ensure())
		return;
	if (p_put_ipc_ns)
		p_put_ipc_ns(ns);
}

MODULE_LICENSE("GPL v2");
MODULE_DESCRIPTION("Android binder driver (out-of-tree build)");
