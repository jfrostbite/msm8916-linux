#/bin/bash

DIST=bookworm
BOOT_URL="https://github.com/KyonLi/ufi003-kernel/releases/download/6.6.52-1/boot.img"
BOOT_NO_MODEM_URL="https://github.com/KyonLi/ufi003-kernel/releases/download/6.6.52-1/boot-no-modem.img"
BOOT_NO_MODEM_OC_URL="https://github.com/KyonLi/ufi003-kernel/releases/download/6.6.52-1/boot-no-modem-oc.img"
K_IMAGE_DEB_URL="https://github.com/KyonLi/ufi003-kernel/releases/download/6.6.52-1/linux-image-6.6.52-msm8916-gf7f8dd961c8e_6.6.52-gf7f8dd961c8e-1_arm64.deb"
K_DEV_URL="https://github.com/KyonLi/ufi003-kernel/releases/tag/6.6.52-1"
UUID=62ae670d-01b7-4c7d-8e72-60bcd00410b7

rm -rf ../kernel/* > /dev/null 2>&1
wget -P ../kernel "$BOOT_URL"
wget -P ../kernel "$BOOT_NO_MODEM_URL"
wget -P ../kernel "$BOOT_NO_MODEM_OC_URL"
wget -P ../kernel "$K_IMAGE_DEB_URL"

mkdir debian build
debootstrap --arch=arm64 --foreign $DIST debian https://deb.debian.org/debian/
LANG=C LANGUAGE=C LC_ALL=C chroot debian /debootstrap/debootstrap --second-stage
cp ../../artifacts/linux-*.deb chroot.sh debian/tmp/
mount --bind /proc debian/proc
mount --bind /dev debian/dev
mount --bind /dev/pts debian/dev/pts
mount --bind /sys debian/sys
LANG=C LANGUAGE=C LC_ALL=C chroot debian /tmp/chroot.sh
umount debian/proc
umount debian/dev/pts
umount debian/dev
umount debian/sys
cp debian/etc/debian_version ../../
mv debian/tmp/info.md ../../
echo >> ../../info.md
rm -rf debian/tmp/* debian/root/.bash_history > /dev/null 2>&1

dd if=/dev/zero of=debian-sp970.img bs=1M count=$(( $(du -ms debian | cut -f1) + 100 ))
mkfs.ext4 -L rootfs -U $UUID debian-sp970.img
mount debian-sp970.img build
rsync -aH debian/ build/
umount build
img2simg debian-sp970.img rootfs.img
rm -rf debian-sp970.img debian build > /dev/null 2>&1
mv rootfs.img ../../artifacts/