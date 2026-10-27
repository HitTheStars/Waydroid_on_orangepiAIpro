import subprocess, os, time

BASE = "/home/HwHiAiUser/data/workspaces/napcat_FriendMessage_1272063565/arkplan/launcher"
LXC = "lxc-attach -P /var/lib/waydroid/lxc -n waydroid --"


def asroot(script, timeout=300, keep=True):
    """Run a shell script as root via the wdroot.service oneshot unit."""
    path = f"{BASE}/wd_task.sh"
    with open(path, "w") as f:
        f.write("#!/bin/sh\nPATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n")
        f.write(script + "\n")
    out_path = f"{BASE}/wd_out.txt"
    if os.path.exists(out_path):
        os.remove(out_path)
    r = subprocess.run("sudo -n /usr/bin/systemctl start wdroot.service",
                       capture_output=True, text=True, shell=True, timeout=timeout)
    out = open(out_path).read() if os.path.exists(out_path) else "(no output file)"
    if not keep:
        os.remove(path)
    return r.returncode, out, r.stderr


def sh(cmd, timeout=120):
    """Run a plain (non-root) host shell command, return (rc, out)."""
    r = subprocess.run(cmd, capture_output=True, text=True, shell=True, timeout=timeout)
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def act(cmd, timeout=120):
    """Run one command inside the container as root."""
    return asroot(f'{LXC} /system/bin/sh -c {sq(cmd)}', timeout=timeout)


def sq(s):
    return "'" + s.replace("'", "'\\''") + "'"
