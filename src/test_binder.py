import os, fcntl, struct, sys

BINDER_VERSION = 0xC0046209  # _IOWR('b', 9, struct binder_version{int protocol_version})

def test(path):
    out = []
    try:
        fd = os.open(path, os.O_RDWR)
        out.append('open OK')
    except Exception as e:
        print(f'{path}: OPEN FAILED {type(e).__name__}: {e}')
        return
    try:
        buf = struct.pack('i', 0)
        res = fcntl.ioctl(fd, BINDER_VERSION, buf)
        out.append(f'protocol_version={struct.unpack("i", res)[0]}')
    except Exception as e:
        out.append(f'VERSION ioctl FAILED {type(e).__name__}: {e}')
    os.close(fd)
    print(f'{path}: ' + '  '.join(out))

for p in ('/dev/binderfs/binder', '/dev/binderfs/hwbinder', '/dev/binderfs/vndbinder', '/dev/binder'):
    test(p)
