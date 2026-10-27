#!/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

LXC="lxc-attach -P /var/lib/waydroid/lxc -n waydroid --"
sleep 8
echo "=== model ids after clean reboot ==="
$LXC /system/bin/sh -c "dumpsys activity top 2>/dev/null | grep -oE 'WorkspaceItemInfo\(id=[0-9]+' | sort -u | tr '\n' ' '"
echo
echo "=== load errors count ==="
$LXC /system/bin/sh -c "logcat -d 2>/dev/null | grep -cE 'Error loading shortcut'"
echo "=== db rows ==="
$LXC /system/bin/sh -c 'cp -a /data/data/com.android.launcher3/databases/launcher_4_by_5.db /data/local/tmp/after.db'
$LXC /system/bin/cat /data/local/tmp/after.db > /home/HwHiAiUser/data/workspaces/napcat_FriendMessage_1272063565/arkplan/launcher/dbnow/after_reboot.db
chmod 666 /home/HwHiAiUser/data/workspaces/napcat_FriendMessage_1272063565/arkplan/launcher/dbnow/after_reboot.db
$LXC /system/bin/screencap -p /data/local/tmp/ws_H.png
$LXC /system/bin/cat /data/local/tmp/ws_H.png > /home/HwHiAiUser/data/workspaces/napcat_FriendMessage_1272063565/arkplan/launcher/ws_after_reboot_20261028_030010.png
chmod 666 /home/HwHiAiUser/data/workspaces/napcat_FriendMessage_1272063565/arkplan/launcher/ws_after_reboot_20261028_030010.png
echo DONE
