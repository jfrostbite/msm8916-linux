#!/bin/bash

DOWNLOAD_SERVER="images.linuxcontainers.org"
DOWNLOAD_INDEX_PATH="/meta/1.0/index-system"
DOWNLOAD_DISTRO="debian;bookworm;arm64;default"

DTB_FILE=msm8916-cj-sp970.dtb
RAMDISK_FILE=initrd.img

rootfs_url="https://$DOWNLOAD_SERVER$(curl -m 10 -fsSL "https://$DOWNLOAD_SERVER$DOWNLOAD_INDEX_PATH" | grep "$DOWNLOAD_DISTRO" | cut -f 6 -d ';')rootfs.tar.xz"
echo "Download rootfs from $rootfs_url"
curl -L -o rootfs.tar.xz "$rootfs_url"
mkdir rootfs && tar -xf rootfs.tar.xz -C rootfs && rm rootfs.tar.xz

cat <<EOF > rootfs/tmp/chroot.sh
#!/bin/bash

rm /etc/resolv.conf
echo "nameserver 8.8.8.8" > /etc/resolv.conf

apt update
apt install -y initramfs-tools locales network-manager openssh-server systemd-timesyncd fake-hwclock
apt install -y /tmp/*.deb

exit
EOF
chmod 755 rootfs/tmp/chroot.sh
cp ../../artifacts/linux-*.deb rootfs/tmp/
mount --bind /proc rootfs/proc
mount --bind /dev rootfs/dev
mount --bind /dev/pts rootfs/dev/pts
mount --bind /sys rootfs/sys
LANG=C LANGUAGE=C LC_ALL=C chroot rootfs /tmp/chroot.sh
umount rootfs/proc
umount rootfs/dev/pts
umount rootfs/dev
umount rootfs/sys
cp rootfs/boot/vmlinuz* ./Image.gz
cp rootfs/boot/initrd.img* ./initrd.img
cp rootfs/usr/lib/linux-image*/qcom/*sp970*.dtb ./

cat Image.gz $DTB_FILE > kernel-dtb
mkbootimg \
    --base 0x80000000 \
    --kernel_offset 0x00008000 \
    --ramdisk_offset 0x01000000 \
    --tags_offset 0x00000100 \
    --pagesize 2048 \
    --second_offset 0x00f00000 \
    --ramdisk $RAMDISK_FILE \
    --cmdline "earlycon root=PARTUUID=a7ab80e8-e9d1-e8cd-57f1-93f69b1d141e console=ttyMSM0,115200 no_framebuffer=true rw"\
    --kernel kernel-dtb -o boot.img

mv boot*.img ../../artifacts/
