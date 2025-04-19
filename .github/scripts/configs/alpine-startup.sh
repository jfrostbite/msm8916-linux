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

# check usb gadget
echo 'ACTION=="unbind", SUBSYSTEM=="gadget", ENV{USEC_INITIALIZED}=="*", RUN+="/usr/local/bin/usb_gadget_restart.sh"' > /etc/udev/rules.d/99-usb-gadget.rules

# Check if this Linux system has a battery
if [ -d "/sys/class/power_supply/pm8916-bms-vm" ] || [ -d "/sys/class/power_supply/pm8916-lbc-chgr" ]; then
    echo 'ACTION=="change", SUBSYSTEM=="extcon", KERNEL=="extcon2", ENV{STATE}=="USB=1", RUN+="/sbin/service usb_gadget restart"' >> /etc/udev/rules.d/99-usb-gadget.rules
    echo 'ACTION=="change", SUBSYSTEM=="extcon", KERNEL=="extcon2", ENV{STATE}=="USB=0", RUN+="/sbin/service usb_gadget stop"' >> /etc/udev/rules.d/99-usb-gadget.rules
    echo 'SUBSYSTEM=="power_supply", ACTION=="change", RUN+="/usr/local/bin/battery_led_control.sh"' > /etc/udev/rules.d/99-battery.rules  
    /bin/udevadm control --reload-rules
    /bin/udevadm trigger 
fi

# improve power
iw dev wlan0 set power_save on
rfkill block bluetooth
rfkill block wifi

# expand rootfs
resize2fs /dev/disk/by-partlabel/system

echo "System is ready!" 
