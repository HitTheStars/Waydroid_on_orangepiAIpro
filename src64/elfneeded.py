#!/usr/bin/env python3
"""Minimal ELF64 DT_NEEDED resolver for the waydroid rootfs (no elfutils needed)."""
import os
import struct
import sys

ROOT = "/var/lib/waydroid/rootfs"
SEARCH_DIRS = [
    "vendor/lib64/hw",
    "vendor/lib64/soundfx",
    "vendor/lib64/egl",
    "vendor/lib64",
    "system/lib64/hw",
    "system/lib64",
    "system/lib64/vndk-sp-33",
    "system/apex/com.android.runtime/lib64",
    "system/apex/com.android.runtime/lib64/bionic",
]


def needed(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"\x7fELF" or data[4] != 2:
        raise ValueError("not ELF64: %s" % path)
    e_phoff, = struct.unpack_from("<Q", data, 0x20)
    e_phentsize, e_phnum = struct.unpack_from("<HH", data, 0x36)
    phdrs = []
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align = struct.unpack_from(
            "<IIQQQQQQ", data, off)
        phdrs.append((p_type, p_offset, p_vaddr, p_filesz))

    def v2o(addr):
        for p_type, p_offset, p_vaddr, p_filesz in phdrs:
            if p_type == 1 and p_vaddr <= addr < p_vaddr + p_filesz:
                return p_offset + (addr - p_vaddr)
        return None

    dyn = next((p for p in phdrs if p[0] == 2), None)
    if dyn is None:
        return []
    _, d_off, _, d_sz = dyn
    strtab = None
    ents = []
    for i in range(d_sz // 16):
        tag, val = struct.unpack_from("<qQ", data, d_off + i * 16)
        if tag == 0:
            break
        if tag == 5:
            strtab = val
        elif tag == 1:
            ents.append(val)
    ob = v2o(strtab)
    out = []
    for e in ents:
        end = data.index(b"\0", ob + e)
        out.append(data[ob + e:end].decode())
    return out


def resolve(lib, extra_dirs=()):
    dirs = list(extra_dirs) + [os.path.join(ROOT, d) for d in SEARCH_DIRS]
    for d in dirs:
        p = os.path.join(d, lib)
        if os.path.exists(p):
            return p
    return None


def walk(path, depth=0, seen=None, missing=None):
    seen = seen if seen is not None else set()
    missing = missing if missing is not None else []
    if path in seen:
        return seen, missing
    seen.add(path)
    try:
        ns = needed(path)
    except Exception as e:
        missing.append((path, "PARSE:%s" % e))
        return seen, missing
    for n in ns:
        if n.startswith("ld-android") or n in ("libc.so", "libm.so", "libdl.so"):
            continue
        p = resolve(n)
        if p is None:
            missing.append((path, n))
        else:
            walk(p, depth + 1, seen, missing)
    return seen, missing


if __name__ == "__main__":
    seen, missing = walk(sys.argv[1])
    print("resolved %d libs" % len(seen))
    if missing:
        print("MISSING %d:" % len(missing))
        for a, b in missing:
            print("  %s -> %s" % (a.replace(ROOT, ""), b.replace(ROOT, "")))
    else:
        print("all NEEDED resolved")
