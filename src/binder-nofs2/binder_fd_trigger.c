/*
 * binder_fd_trigger.c — 逼 binder 走 binder_deferred_fd_close()
 *
 * 路径: BC_TRANSACTION(带 BINDER_TYPE_FD) -> 成功送达 -> 接收方 BC_FREE_BUFFER
 *       -> binder_free_buf -> binder_transaction_buffer_release
 *       -> case BINDER_TYPE_FD -> binder_deferred_fd_close()
 *
 * 这条路径就是 2026-10-27 17:41 那次 Oops 的现场。
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

#define MAP_SIZE (1024 * 1024)

static void die(const char *msg)
{
	fprintf(stderr, "FATAL: %s: %s\n", msg, strerror(errno));
	exit(1);
}

static int binder_open(void)
{
	int fd = open("/dev/binder", O_RDWR | O_CLOEXEC);
	if (fd < 0)
		die("open /dev/binder");

	int32_t ver = 0;
	if (ioctl(fd, BINDER_VERSION, &ver) < 0)
		die("BINDER_VERSION");
	fprintf(stderr, "[%d] binder protocol_version = %d\n", getpid(), ver);

	if (mmap(NULL, MAP_SIZE, PROT_READ, MAP_PRIVATE | MAP_NORESERVE,
		 fd, 0) == MAP_FAILED)
		die("mmap binder");
	return fd;
}

/* ---------- 接收方: 拿到事务后立刻 BC_FREE_BUFFER ---------- */
static void server_loop(int fd)
{
	/* 关键: 不声明自己是 looper, 内核不会把这个线程派去处理 proc->todo,
	 * pending transaction 会一直躺着, binder_wait_for_work 永远不醒 */
	{
		uint32_t enter = BC_ENTER_LOOPER;
		struct binder_write_read w;

		memset(&w, 0, sizeof(w));
		w.write_size = sizeof(enter);
		w.write_buffer = (binder_uintptr_t)&enter;
		if (ioctl(fd, BINDER_WRITE_READ, &w) < 0)
			die("BC_ENTER_LOOPER");
		fprintf(stderr, "[server] BC_ENTER_LOOPER 已发送\n");
	}

	for (;;) {
		char rbuf[8192];
		struct binder_write_read bwr;

		memset(&bwr, 0, sizeof(bwr));
		bwr.read_size = sizeof(rbuf);
		bwr.read_buffer = (binder_uintptr_t)rbuf;

		if (ioctl(fd, BINDER_WRITE_READ, &bwr) < 0)
			die("server BINDER_WRITE_READ");

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

				struct {
					uint32_t cmd;
					binder_uintptr_t ptr;
				} __attribute__((packed)) fb;

				fb.cmd = BC_FREE_BUFFER;
				fb.ptr = tr->data.ptr.buffer;

				struct binder_write_read w;
				memset(&w, 0, sizeof(w));
				w.write_size = sizeof(fb);
				w.write_buffer = (binder_uintptr_t)&fb;

				if (ioctl(fd, BINDER_WRITE_READ, &w) < 0)
					die("BC_FREE_BUFFER");
				fprintf(stderr, "[server] BC_FREE_BUFFER sent -> 应触发 deferred fd close\n");
				return;
			}

			if (cmd == BR_SPAWN_LOOPER ||
			    cmd == BR_FAILED_REPLY || cmd == BR_DEAD_REPLY) {
				fprintf(stderr, "[server] cmd %#x\n", cmd);
				continue;
			}

			if (cmd == BR_DEAD_BINDER ||
			    cmd == BR_CLEAR_DEATH_NOTIFICATION_DONE) {
				p += 8;
				continue;
			}

			fprintf(stderr, "[server] unexpected cmd %#x\n", cmd);
		}
	}
}

/* ---------- 发送方: 发一个带 fd 的事务给 handle 0 ---------- */
static int client_send(void)
{
	int fd = binder_open();
	int payload = open("/etc/hostname", O_RDONLY);
	if (payload < 0)
		die("open payload file");
	fprintf(stderr, "[client] payload fd = %d\n", payload);

	struct flat_binder_object obj;
	memset(&obj, 0, sizeof(obj));
	obj.hdr.type = BINDER_TYPE_FD;
	obj.flags = FLAT_BINDER_FLAG_ACCEPTS_FDS;
	obj.handle = payload;
	obj.cookie = 0;

	binder_size_t offsets[1];
	offsets[0] = 0;

	struct binder_transaction_data tr;
	memset(&tr, 0, sizeof(tr));
	tr.target.handle = 0;
	tr.code = 1;
	tr.flags = 0;
	tr.data_size = sizeof(obj);
	tr.data.ptr.buffer = (binder_uintptr_t)&obj;
	tr.offsets_size = sizeof(offsets);
	tr.data.ptr.offsets = (binder_uintptr_t)offsets;

	struct {
		uint32_t cmd;
		struct binder_transaction_data tr;
	} __attribute__((packed)) bc;

	bc.cmd = BC_TRANSACTION;
	memcpy(&bc.tr, &tr, sizeof(tr));

	char rbuf[8192];
	struct binder_write_read bwr;
	memset(&bwr, 0, sizeof(bwr));
	bwr.write_size = sizeof(bc);
	bwr.write_buffer = (binder_uintptr_t)&bc;
	bwr.read_size = 0;
	bwr.read_buffer = 0;

	if (ioctl(fd, BINDER_WRITE_READ, &bwr) < 0)
		die("client BINDER_WRITE_READ");

	fprintf(stderr, "[client] 已发送, write_consumed=%llu (不进读循环, 避免死等)\n",
		(unsigned long long)bwr.write_consumed);
	usleep(3000 * 1000);
	fprintf(stderr, "[client] done\n");
	return 0;
}

int main(void)
{
	int fd = binder_open();

	struct flat_binder_object fbo;
	memset(&fbo, 0, sizeof(fbo));
	fbo.hdr.type = BINDER_TYPE_BINDER;
	fbo.flags = FLAT_BINDER_FLAG_ACCEPTS_FDS;
	fbo.binder = 0;
	fbo.cookie = 0;

	if (ioctl(fd, BINDER_SET_CONTEXT_MGR_EXT, &fbo) < 0) {
		fprintf(stderr, "[server] SET_CONTEXT_MGR_EXT 失败(%s), 退回普通模式\n",
			strerror(errno));
		if (ioctl(fd, BINDER_SET_CONTEXT_MGR, 0) < 0)
			die("BINDER_SET_CONTEXT_MGR");
	} else {
		fprintf(stderr, "[server] 已成为 context manager, accept_fds=1\n");
	}

	pid_t pid = fork();
	if (pid < 0)
		die("fork");

	if (pid == 0) {
		usleep(200 * 1000);
		_exit(client_send());
	}

	server_loop(fd);
	waitpid(pid, NULL, 0);

	fprintf(stderr, "=== 如果没崩, 说明修复生效 ===\n");
	return 0;
}
