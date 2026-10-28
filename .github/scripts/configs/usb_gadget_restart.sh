#!/bin/sh

sleep 3

if [ -f "/sys/class/power_supply/pm8916-lbc-chgr/online" ]; then
    online_status=$(cat /sys/class/power_supply/pm8916-lbc-chgr/online)
    if [ "$online_status" -eq 1 ]; then
        /sbin/service usb_gadget restart
    fi
else
    # Device is directly powered by USB, not a battery-powered device
    /sbin/service usb_gadget restart
fi
