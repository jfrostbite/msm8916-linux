#!/bin/sh

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hello from Alpine Linux!"

# set led trigger to none
echo "none" > /sys/class/leds/blue\:wan/trigger

# expand rootfs
resize2fs /dev/disk/by-partlabel/system

echo "System is ready!" 
