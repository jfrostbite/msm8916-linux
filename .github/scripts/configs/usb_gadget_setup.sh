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
echo "msm8916" > strings/0x409/serialnumber
echo "Qualcomm, Inc" > strings/0x409/manufacturer
echo "MSM8916" > strings/0x409/product

# 创建配置
mkdir -p configs/c.1
mkdir -p configs/c.1/strings/0x409
echo "ADB_RNDIS" > configs/c.1/strings/0x409/configuration
echo 500 > configs/c.1/MaxPower

# 创建RNDIS function
mkdir -p functions/rndis.0

# 创建ADB function
mkdir -p functions/ffs.adb

# 链接functions到config
ln -s functions/rndis.0 configs/c.1/
ln -s functions/ffs.adb configs/c.1/

# 创建ADB所需目录
mkdir -p /dev/usb-ffs/adb
mount -t functionfs adb /dev/usb-ffs/adb