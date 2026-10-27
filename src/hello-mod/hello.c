// 方舟计划 · 最小内核模块加载探针
// 目的：验证这块板子的内核能否加载外部编译的 .ko（不改任何内核状态）
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>

#define TAG "arkplan: "

static int __init ark_probe_init(void)
{
	pr_info(TAG "hello.ko loaded, probe OK\n");
	return 0;
}

static void __exit ark_probe_exit(void)
{
	pr_info(TAG "hello.ko unloaded\n");
}

module_init(ark_probe_init);
module_exit(ark_probe_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Kurisu/Amadeus");
MODULE_DESCRIPTION("arkplan minimal out-of-tree module load probe");
