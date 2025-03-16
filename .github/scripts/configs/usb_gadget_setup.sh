#!/bin/sh

# 确保configfs已挂载
mount -t configfs none /sys/kernel/config 2>/dev/null

# 创建gadget
GADGET=/sys/kernel/config/usb_gadget/g1
if [ ! -d "$GADGET" ]; then
    mkdir $GADGET
fi
cd $GADGET

# USB 设备信息配置
echo 0x05c6 > idVendor
echo 0x9024 > idProduct

# 设备描述符字符串
mkdir -p strings/0x409
SERIAL_NUMBER=$(cat /proc/device-tree/serial-number 2>/dev/null || echo "msm8916")
MODEL=$(cat /proc/device-tree/model 2>/dev/null || echo "UFI")

echo $SERIAL_NUMBER > strings/0x409/serialnumber
echo "Qualcomm, Inc" > strings/0x409/manufacturer
echo $MODEL > strings/0x409/product

# 创建配置
mkdir -p configs/c.1
mkdir -p configs/c.1/strings/0x409
echo "ADB_RNDIS" > configs/c.1/strings/0x409/configuration
echo 500 > configs/c.1/MaxPower

# 创建RNDIS function
mkdir -p functions/rndis.0

# 固定rndis的MAC地址
if [ -f /etc/rndis_mac.conf ]; then
    MAC_ADDR_DEV=$(sed -n '1p' /etc/rndis_mac.conf)
    MAC_ADDR_HOST=$(sed -n '2p' /etc/rndis_mac.conf)
    if [ -z "$MAC_ADDR_DEV" ]; then
        MAC_ADDR_DEV=$(cat functions/rndis.0/dev_addr)
        echo $MAC_ADDR_DEV > /etc/rndis_mac.conf
    else
        echo $MAC_ADDR_DEV > functions/rndis.0/dev_addr
    fi
    if [ -z "$MAC_ADDR_HOST" ]; then
        MAC_ADDR_HOST=$(cat functions/rndis.0/host_addr)
        echo $MAC_ADDR_HOST >> /etc/rndis_mac.conf
    else
        echo $MAC_ADDR_HOST > functions/rndis.0/host_addr
    fi
else
    MAC_ADDR_DEV=$(cat functions/rndis.0/dev_addr)
    MAC_ADDR_HOST=$(cat functions/rndis.0/host_addr)
    echo $MAC_ADDR_DEV > /etc/rndis_mac.conf
    echo $MAC_ADDR_HOST >> /etc/rndis_mac.conf
fi

# 创建ADB function
mkdir -p functions/ffs.adb

# 链接functions到config
ln -s functions/rndis.0 configs/c.1/
ln -s functions/ffs.adb configs/c.1/

# 创建ADB所需目录
mkdir -p /dev/usb-ffs/adb
mount -t functionfs adb /dev/usb-ffs/adb