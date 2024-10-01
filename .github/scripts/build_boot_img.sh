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

sed -i -e "s/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/" /etc/locale.gen
dpkg-reconfigure --frontend=noninteractive locales
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LANGUAGE=en_US.UTF-8
echo -n >/etc/resolv.conf
echo -e "admin\nadmin" | passwd
echo sp970 > /etc/hostname
sed -i 's/^.\?PermitRootLogin.*$/PermitRootLogin yes/g' /etc/ssh/sshd_config

cat <<EOI > /etc/apt/sources.list
deb http://mirrors.huaweicloud.com/debian/ bookworm main contrib non-free non-free-firmware
# deb-src http://mirrors.huaweicloud.com/debian/ bookworm main contrib non-free non-free-firmware

deb http://mirrors.huaweicloud.com/debian/ bookworm-updates main contrib non-free non-free-firmware
# deb-src http://mirrors.huaweicloud.com/debian/ bookworm-updates main contrib non-free non-free-firmware

deb http://mirrors.huaweicloud.com/debian/ bookworm-backports main contrib non-free non-free-firmware
# deb-src http://mirrors.huaweicloud.com/debian/ bookworm-backports main contrib non-free non-free-firmware

deb https://mirrors.huaweicloud.com/debian-security bookworm-security main contrib non-free non-free-firmware
# deb-src https://mirrors.huaweicloud.com/debian-security bookworm-security main contrib non-free non-free-firmware
EOI

rm -rf /etc/ssh/ssh_host_* /var/lib/apt/lists
rm -rf /tmp/* /root/.bash_history > /dev/null 2>&1
apt clean

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
cp rootfs/etc/debian_version ./
echo "查看"
cat ./debian_version

cat Image.gz $DTB_FILE > kernel-dtb
mkbootimg \
    --base 0x80000000 \
    --kernel_offset 0x00008000 \
    --ramdisk_offset 0x01000000 \
    --tags_offset 0x00000100 \
    --pagesize 2048 \
    --second_offset 0x00f00000 \
    --ramdisk $RAMDISK_FILE \
    --cmdline "androidboot.hardware=qcom androidboot.oem.product=HL6180W earlycon root=PARTLABEL=rootfs console=ttyMSM0,115200 no_framebuffer=true rw"\
    --kernel kernel-dtb -o boot.img

mv boot*.img ../../artifacts/

dd if=/dev/zero of=debian-sp970.img bs=1M count=$(( $(du -ms rootfs | cut -f1) + 100 ))
mkfs.ext4 -L rootfs debian-sp970.img
mkdir build && mount debian-sp970.img build
rsync -aH rootfs/ build/
umount build
img2simg debian-sp970.img rootfs.img
rm -rf debian-sp970.img rootfs build > /dev/null 2>&1

mv rootfs.img ../../artifacts/
