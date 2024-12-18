#!/bin/bash

# Constants
DOWNLOAD_SERVER="images.linuxcontainers.org"
DOWNLOAD_INDEX_PATH="/meta/1.0/index-system"
DOWNLOAD_DISTRO="debian;bookworm;arm64;default"
DIST=bookworm
DEVICE="mfx32"
VENDOR="xx"
DTB_FILE="msm8916-${VENDOR}-${DEVICE}.dtb"
CMDLINE="earlycon console=tty0 console=ttyMSM0,115200 root=PARTLABEL=system rw"

# 判断../../artifacts/是否存在，并且有linux-*.deb文件，如果不存在，那么从../../../中复制, 如果复制失败，那么退出
if [ ! -d "../../artifacts/" ] || [ ! -f "../../artifacts/linux-*.deb" ]; then
    echo "artifacts directory or linux-*.deb file not found, copying from ../../../artifacts/"
    mkdir -p ../../artifacts
    cp -r ../../../linux-image*.deb ../../artifacts/
    cp -r ../../../linux-headers*.deb ../../artifacts/
    if [ $? -ne 0 ]; then
        echo "Failed to copy linux-*.deb from ../../../artifacts/, exiting."
        exit 1
    fi
fi

# 1. Download and prepare rootfs
echo "Preparing rootfs..."
if [ ! -d "rootfs" ]; then
    rootfs_url="https://$DOWNLOAD_SERVER$(curl -m 10 -fsSL "https://$DOWNLOAD_SERVER$DOWNLOAD_INDEX_PATH" | grep "$DOWNLOAD_DISTRO" | cut -f 6 -d ';')rootfs.tar.xz"
    echo "Download rootfs from $rootfs_url"
    curl -L -o rootfs.tar.xz "$rootfs_url"
    mkdir rootfs && tar -xf rootfs.tar.xz -C rootfs && rm rootfs.tar.xz
else
    echo "rootfs directory already exists, skipping download."
fi

# 2. Build boot image
echo "Building boot image..."
# Setup chroot environment for boot image
cat <<EOF > rootfs/tmp/chroot.sh
#!/bin/bash

rm /etc/resolv.conf
echo "nameserver 8.8.8.8" > /etc/resolv.conf

apt update
apt install -y initramfs-tools
apt install -y /tmp/*.deb

exit
EOF

chmod 755 rootfs/tmp/chroot.sh
cp ../../artifacts/linux-*.deb rootfs/tmp/

# Mount and chroot
mount --bind /proc rootfs/proc
mount --bind /dev rootfs/dev
mount --bind /dev/pts rootfs/dev/pts
mount --bind /sys rootfs/sys
LANG=C LANGUAGE=C LC_ALL=C chroot rootfs /tmp/chroot.sh

# Unmount
umount rootfs/proc
umount rootfs/dev/pts
umount rootfs/dev
umount rootfs/sys

# Copy necessary files
cp rootfs/boot/vmlinuz* ./Image.gz
cp rootfs/boot/initrd.img* ./initrd.img
cp rootfs/usr/lib/linux-image*/qcom/$DTB_FILE ./

echo "DTB file: $DTB_FILE"
file $DTB_FILE

# Create boot image
cat Image.gz $DTB_FILE > kernel-dtb
mkbootimg \
    --base 0x80000000 \
    --kernel_offset 0x00008000 \
    --ramdisk_offset 0x01000000 \
    --tags_offset 0x00000100 \
    --pagesize 2048 \
    --second_offset 0x00f00000 \
    --ramdisk initrd.img \
    --cmdline "$CMDLINE" \
    --kernel kernel-dtb -o boot.img

mv boot.img ../../artifacts/

# 3. Build system rootfs
echo "Building system rootfs..."
# Copy necessary files
cp -r ../../artifacts/*.deb chroot.sh firmware/ rootfs/tmp/
chmod +x rootfs/tmp/chroot.sh

# Mount necessary directories
mount --bind /proc rootfs/proc
mount --bind /dev rootfs/dev
mount --bind /dev/pts rootfs/dev/pts
mount --bind /sys rootfs/sys

# Chroot and setup
LANG=C LANGUAGE=C LC_ALL=C chroot rootfs /tmp/chroot.sh

# Unmount
umount rootfs/proc
umount rootfs/dev/pts
umount rootfs/dev
umount rootfs/sys

# Save debian version
cp rootfs/etc/debian_version ../../

# Cleanup
rm -rf rootfs/tmp/* rootfs/root/.bash_history > /dev/null 2>&1

# Create and process rootfs image
dd if=/dev/zero of=debian-${DEVICE}.img bs=1M count=$(( $(du -ms rootfs | cut -f1) + 100 ))
mkfs.ext4 -L rootfs debian-${DEVICE}.img
mkdir -p build
mount debian-${DEVICE}.img build
rsync -aH rootfs/ build/
umount build
img2simg debian-${DEVICE}.img rootfs.img
rm -rf debian-${DEVICE}.img build Image.gz initrd.img kernel-dtb *.dtb > /dev/null 2>&1
# xz rootfs.img
mv rootfs.img ../../artifacts/

# Final cleanup
# rm -rf rootfs
