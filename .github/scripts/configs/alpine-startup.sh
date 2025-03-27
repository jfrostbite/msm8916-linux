#!/bin/sh

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hello from Alpine Linux!"

# set led trigger to none
echo "none" > /sys/class/leds/blue\:wan/trigger

# set hostname, hostname from /proc/device-tree/compatible
USER_NAME=$(awk -F',' 'NR==1 {print $2}' /proc/device-tree/compatible)
USER_PASSWD="admin${USER_NAME}"
setup-hostname ${USER_NAME}
setup-user -u ${USER_NAME}
echo "${USER_NAME}:${USER_PASSWD}" | chpasswd

# expand rootfs
resize2fs /dev/disk/by-partlabel/system

echo "System is ready!" 
