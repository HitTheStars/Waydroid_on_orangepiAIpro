/* ashmem 侧未导出符号垫片
 * shmem_zero_setup 在 mm/shmem.c 里没有 EXPORT_SYMBOL，树外模块拿不到。
 * 手法同 binder 侧：kprobe 抓 kallsyms_lookup_name 得地址，转发调用。
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/kprobes.h>
#include <linux/mm.h>

#undef shmem_zero_setup

typedef unsigned long (*ark_kln_t)(const char *name);

static int (*p_shmem_zero_setup)(struct vm_area_struct *vma);
static int ark_state;	/* 0=未初始化 1=成功 -1=失败 */

static int ark_ensure(void)
{
	struct kprobe kp = { .symbol_name = "kallsyms_lookup_name" };
	ark_kln_t kln;
	int ret;

	if (ark_state == 1)
		return 0;
	if (ark_state == -1)
		return -ENOENT;

	ret = register_kprobe(&kp);
	if (ret < 0) {
		pr_err("arkplan/ashmem: register_kprobe 失败 %d\n", ret);
		ark_state = -1;
		return ret;
	}
	kln = (ark_kln_t)(void *)kp.addr;
	unregister_kprobe(&kp);

	if (!kln) {
		ark_state = -1;
		return -ENOENT;
	}

	p_shmem_zero_setup = (void *)kln("shmem_zero_setup");
	pr_info("arkplan/ashmem: shmem_zero_setup=%px\n", p_shmem_zero_setup);

	if (!p_shmem_zero_setup) {
		ark_state = -1;
		return -ENOENT;
	}

	ark_state = 1;
	return 0;
}

int ark_shmem_zero_setup(struct vm_area_struct *vma)
{
	if (ark_ensure())
		return -ENOSYS;
	return p_shmem_zero_setup(vma);
}

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("arkplan ashmem shim (out-of-tree)");
