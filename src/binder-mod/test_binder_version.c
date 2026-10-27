/* 方舟计划 · binder 设备可用性验证
 * 直接用 ioctl BINDER_VERSION 走真正的 binder 协议栈，
 * 能拿到协议版本号就说明 /dev/binder 是真驱动，不是空节点。
 */
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <sys/ioctl.h>

struct binder_version {
	int protocol_version;
};

#define BINDER_VERSION _IOWR('b', 9, struct binder_version)

int main(void)
{
	const char *devs[] = { "/dev/binder", "/dev/hwbinder", "/dev/vndbinder" };
	int i;

	for (i = 0; i < 3; i++) {
		struct binder_version ver = { -1 };
		int fd = open(devs[i], O_RDWR | O_CLOEXEC);

		if (fd < 0) {
			printf("%-16s open 失败: %s\n", devs[i], strerror(errno));
			continue;
		}
		if (ioctl(fd, BINDER_VERSION, &ver) < 0) {
			printf("%-16s open OK, ioctl 失败: %s\n", devs[i], strerror(errno));
			close(fd);
			continue;
		}
		printf("%-16s open OK, protocol_version = %d\n", devs[i], ver.protocol_version);
		close(fd);
	}
	return 0;
}
