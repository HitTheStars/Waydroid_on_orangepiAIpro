/*
 * binder_fda_trigger.c — 真正踩 binder_transaction_buffer_release 的 FDA 分支
 *
 * 经过核实: binder.c:2399 的 binder_deferred_fd_close() 只出现在
 * BINDER_TYPE_FDA (fd array) 分支, 且该分支无 is_failure 条件判断。
 * BINDER_TYPE_FD 分支是空实现, 发它等于没测。
 *
 * 观测手法: binder_deferred_fd_close() 内部是
 *     __close_fd_get_file(fd, &twcb->file)   // 从 current->files 摘 fd
 * 它关的是"调用者进程"的 fd 号。而 release 发生在接收方执行 BC_FREE_BUFFER
 * 的上下文, 所以让 server 自己占住 fd 5, 事务里填 handle=5,
 * free 之后 server 的 fd 5 若变成 EBADF, 就是该函数确实执行的铁证。
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <linux/android/binder.h>

#define MAP_SIZE  (1024 * 1024)
#define FD_COUNT  1
#define VICTIM_FD 5

static void die(const char *m)
{
	fprintf(stderr, "FATAL %s: %s\n", m, strerror(errno));
	exit(1);
}

static int binder_open(void)
{
	int fd = open("/dev/binder", O_RDWR | O_CLOEXEC);
	if (fd < 0)
		die("open /dev/binder");

	int32_t v = 0;
	if (ioctl(fd, BINDER_VERSION, &v) < 0)
		die("BINDER_VERSION");
	fprintf(stderr, "[%d] proto=%d binderfd=%d\n", getpid(), v, fd);

	if (mmap(NULL, MAP_SIZE, PROT_READ, MAP_PRIVATE | MAP_NORESERVE,
		 fd, 0) == MAP_FAILED)
		die("mmap");
	return fd;
}

/* ---------------- server ---------------- */
static void server_loop(int fd)
{
	uint32_t enter = BC_ENTER_LOOPER;
	struct binder_write_read w;

	memset(&w, 0, sizeof(w));
	w.write_size = sizeof(enter);
	w.write_buffer = (binder_uintptr_t)&enter;
	if (ioctl(fd, BINDER_WRITE_READ, &w) < 0)
		die("BC_ENTER_LOOPER");
	fprintf(stderr, "[server] BC_ENTER_LOOPER ok\n");

	for (;;) {
		char rbuf[8192];
		struct binder_write_read bwr;

		memset(&bwr, 0, sizeof(bwr));
		bwr.read_size = sizeof(rbuf);
		bwr.read_buffer = (binder_uintptr_t)rbuf;

		if (ioctl(fd, BINDER_WRITE_READ, &bwr) < 0)
			die("server read");

		char *p = rbuf;
		char *end = rbuf + bwr.read_consumed;

		while (p + 4 <= end) {
			uint32_t cmd = *(uint32_t *)p;
			p += 4;

			if (cmd == BR_NOOP || cmd == BR_TRANSACTION_COMPLETE)
				continue;

			if (cmd == BR_TRANSACTION) {
				struct binder_transaction_data *tr = (void *)p;
				p += sizeof(*tr);

				fprintf(stderr,
					"[server] BR_TRANSACTION data_size=%llu offsets_size=%llu\n",
					(unsigned long long)tr->data_size,
					(unsigned long long)tr->offsets_size);

				/*
				 * 从 buffer 里把 FDA 的真实 fd 挖出来:
				 * binder_translate_fd_array() 已经在接收方 proc 里
				 * fd_install() 过, buffer 里存的是接收方的 fd 号。
				 */
				unsigned char *data =
					(void *)(uintptr_t)tr->data.ptr.buffer;
				binder_size_t *offs =
					(void *)(uintptr_t)tr->data.ptr.offsets;
				size_t nobj = tr->offsets_size / sizeof(binder_size_t);
				int target_fd = -1;

				for (size_t i = 0; i < nobj; i++) {
					struct binder_object_header *h =
						(void *)(data + offs[i]);

					if (h->type != BINDER_TYPE_FDA)
						continue;

					struct binder_fd_array_object *fa =
						(void *)h;
					struct binder_buffer_object *pb =
						(void *)(data + offs[fa->parent]);
					size_t foff = (size_t)(pb->buffer -
						(binder_uintptr_t)(uintptr_t)data) +
						fa->parent_offset;
					int *arr = (int *)(data + foff);

					target_fd = arr[0];
					fprintf(stderr,
						"[server] FDA num_fds=%llu -> 本进程 fd = %d\n",
						(unsigned long long)fa->num_fds,
						target_fd);
				}

				if (target_fd < 0) {
					fprintf(stderr, "[server] 没找到 FDA\n");
					return;
				}

				int before = fcntl(target_fd, F_GETFD);
				fprintf(stderr, "[server] FREE 前 fd %d: %s\n",
					target_fd, before < 0 ? "已失效" : "有效");

				struct {
					uint32_t cmd;
					binder_uintptr_t ptr;
				} __attribute__((packed)) fb;

				fb.cmd = BC_FREE_BUFFER;
				fb.ptr = tr->data.ptr.buffer;

				struct binder_write_read fw;
				memset(&fw, 0, sizeof(fw));
				fw.write_size = sizeof(fb);
				fw.write_buffer = (binder_uintptr_t)&fb;
				if (ioctl(fd, BINDER_WRITE_READ, &fw) < 0)
					die("BC_FREE_BUFFER");
				fprintf(stderr, "[server] BC_FREE_BUFFER 已发\n");

				usleep(100 * 1000);

				int after = fcntl(target_fd, F_GETFD);
				if (after < 0 && errno == EBADF)
					fprintf(stderr,
						"[server] ★★★ fd %d -> EBADF: binder_deferred_fd_close() 确认执行 ★★★\n",
						target_fd);
				else
					fprintf(stderr,
						"[server] fd %d 仍然有效(%d), 没关掉\n",
						target_fd, after);
				return;
			}

			if (cmd == BR_SPAWN_LOOPER || cmd == BR_FAILED_REPLY ||
			    cmd == BR_DEAD_REPLY) {
				fprintf(stderr, "[server] cmd %#x\n", cmd);
				continue;
			}
			if (cmd == BR_DEAD_BINDER ||
			    cmd == BR_CLEAR_DEATH_NOTIFICATION_DONE) {
				p += 8;
				continue;
			}
			fprintf(stderr, "[server] unexpected %#x\n", cmd);
		}
	}
}

/* ---------------- client: 发 BINDER_TYPE_FDA 事务 ---------------- */
static int client_send(int victim_fd)
{
	int fd = binder_open();

	if (fcntl(victim_fd, F_GETFD) < 0) {
		fprintf(stderr, "[client] 继承的 fd %d 不可用: %s\n",
			victim_fd, strerror(errno));
		return 1;
	}
	fprintf(stderr, "[client] 使用 fd %d 构造 fd 数组\n", victim_fd);

	unsigned char buf[1024];
	memset(buf, 0, sizeof(buf));

	/*
	 * last_fixup_obj_off 用 0 当哨兵 (binder_validate_fixup 首行
	 * `if (!last_obj_offset) return false;`), 所以 PTR 对象不能落在
	 * offset 0, 前面留 8 字节填充避开。
	 */
	size_t off_pbo = 8;
	size_t off_fda = off_pbo + sizeof(struct binder_buffer_object);
	size_t off_arr = (off_fda + sizeof(struct binder_fd_array_object) + 7) & ~7UL;

	struct binder_buffer_object *pbo = (void *)(buf + off_pbo);
	struct binder_fd_array_object *fda = (void *)(buf + off_fda);
	int *arr = (int *)(buf + off_arr);

	arr[0] = victim_fd;

	pbo->hdr.type = BINDER_TYPE_PTR;
	pbo->buffer = (binder_uintptr_t)(uintptr_t)arr;
	pbo->length = FD_COUNT * sizeof(int);
	pbo->flags = 0;
	pbo->parent = 0;
	pbo->parent_offset = 0;

	fda->hdr.type = BINDER_TYPE_FDA;
	fda->num_fds = FD_COUNT;
	/*
	 * 注意: parent 是 offsets[] 的**索引**, 不是字节偏移。
	 * offsets[0] 指向 PTR, 所以这里是 0。
	 */
	fda->parent = 0;
	fda->parent_offset = 0;

	fprintf(stderr,
		"[client] 布局: pbo@%zu(%zuB) fda@%zu(%zuB) arr@%zu\n",
		off_pbo, sizeof(*pbo), off_fda, sizeof(*fda), off_arr);

	binder_size_t offsets[2];
	offsets[0] = off_pbo;
	offsets[1] = off_fda;

	struct binder_transaction_data tr;
	memset(&tr, 0, sizeof(tr));
	tr.target.handle = 0;
	tr.code = 2;
	tr.data_size = off_arr + FD_COUNT * sizeof(int);
	tr.data.ptr.buffer = (binder_uintptr_t)(uintptr_t)buf;
	tr.offsets_size = sizeof(offsets);
	tr.data.ptr.offsets = (binder_uintptr_t)(uintptr_t)offsets;

	/*
	 * 关键: BC_TRANSACTION 走 binder_transaction(..., 0), extra_buffers_size
	 * 写死为 0, 所以带 BINDER_TYPE_PTR 的事务必然报 "too large buffer"。
	 * 必须用 BC_TRANSACTION_SG 显式给 buffers_size。
	 */
	struct {
		uint32_t cmd;
		struct binder_transaction_data_sg tr;
	} __attribute__((packed)) bc;

	bc.cmd = BC_TRANSACTION_SG;
	memcpy(&bc.tr.transaction_data, &tr, sizeof(tr));
	bc.tr.buffers_size = (FD_COUNT * sizeof(int) + 7) & ~7UL;

	struct binder_write_read bwr;
	memset(&bwr, 0, sizeof(bwr));
	bwr.write_size = sizeof(bc);
	bwr.write_buffer = (binder_uintptr_t)&bc;
	bwr.read_size = 0;
	bwr.read_buffer = 0;

	if (ioctl(fd, BINDER_WRITE_READ, &bwr) < 0)
		die("client write");

	fprintf(stderr, "[client] 已发送 FDA 事务, consumed=%llu\n",
		(unsigned long long)bwr.write_consumed);
	usleep(3000 * 1000);
	return 0;
}

int main(void)
{
	int fd = binder_open();			/* fd 3 */

	int d4 = open("/dev/null", O_RDONLY);	/* fd 4 */
	int d5 = open("/etc/group", O_RDONLY);	/* fd 5 */
	fprintf(stderr, "[server] 占位: d4=%d d5=%d (期望 4,5)\n", d4, d5);
	if (d5 != VICTIM_FD)
		fprintf(stderr, "[server] 警告: 5 号槽位不对, 观测可能失效\n");

	struct flat_binder_object fbo;
	memset(&fbo, 0, sizeof(fbo));
	fbo.hdr.type = BINDER_TYPE_BINDER;
	fbo.flags = FLAT_BINDER_FLAG_ACCEPTS_FDS;

	if (ioctl(fd, BINDER_SET_CONTEXT_MGR_EXT, &fbo) < 0) {
		fprintf(stderr, "[server] EXT 失败(%s), 退回普通\n", strerror(errno));
		if (ioctl(fd, BINDER_SET_CONTEXT_MGR, 0) < 0)
			die("SET_CONTEXT_MGR");
	} else {
		fprintf(stderr, "[server] context manager, accept_fds=1\n");
	}

	pid_t pid = fork();
	if (pid < 0)
		die("fork");

	if (pid == 0) {
		usleep(300 * 1000);
		_exit(client_send(VICTIM_FD));
	}

	server_loop(fd);
	waitpid(pid, NULL, 0);

	fprintf(stderr, "=== 走完, 未崩溃 ===\n");
	return 0;
}
