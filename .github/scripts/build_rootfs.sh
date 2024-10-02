#/bin/bash

DIST=bookworm

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
