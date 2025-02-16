#!/bin/sh

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hello from Alpine Linux!"

# set led trigger to none
echo "none" > /sys/class/leds/blue\:wan/trigger

# expand rootfs
resize2fs /dev/disk/by-partlabel/system

# enable ip forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# enable ipv6 forwarding
echo 1 > /proc/sys/net/ipv6/conf/all/forwarding

echo "System is ready!" 
