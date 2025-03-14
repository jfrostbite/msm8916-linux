#!/bin/sh -e
if [ -z "$1" ]; then
  echo "Usage: $0 <device>"
  exit 1
fi
export TMPDIR=${TMPDIR=/root/tmp}
export CHROOT=${CHROOT=${TMPDIR}/rootfs}
export RELEASE=${RELEASE=latest-stable}
export PMOS_RELEASE=${PMOS_RELEASE=master}
export MIRROR=${MIRROR=http://dl-cdn.alpinelinux.org/alpine}
export PMOS_MIRROR=${PMOS_MIRROR=http://mirror.postmarketos.org/postmarketos}

NAME="$1"
PASSWORD="admin$NAME"

if [ ! -f "../../arch/arm64/boot/Image.gz" ]; then
    echo "Kernel Image.gz not found"
    exit 1
fi

if [ ! -f "../../arch/arm64/boot/dts/qcom/msm8916-ufi-${NAME}.dtb" ]; then
    echo "DTB file not found"
    exit 1
fi

rm -rf ${CHROOT}

mkdir -p ${CHROOT}/etc/apk
cat << EOF >  ${CHROOT}/etc/apk/repositories
${MIRROR}/${RELEASE}/main
${MIRROR}/${RELEASE}/community
${PMOS_MIRROR}/${PMOS_RELEASE}
EOF

cp /etc/resolv.conf ${CHROOT}/etc/

# mkdir -p ${CHROOT}/usr/bin
# cp $(which qemu-aarch64-static) ${CHROOT}/usr/bin

curl -L -o apk.static https://gitlab.alpinelinux.org/api/v4/projects/5/packages/generic/v2.14.6/x86_64/apk.static
chmod a+x apk.static

./apk.static -X http://dl-cdn.alpinelinux.org/alpine/latest-stable/main/ -p ${CHROOT} --initdb -U --arch aarch64 --allow-untrusted add alpine-base
rm apk.static

# install startup script
mkdir -p ${CHROOT}/usr/local/bin
cp configs/alpine-startup.sh ${CHROOT}/usr/local/bin/
chmod +x ${CHROOT}/usr/local/bin/alpine-startup.sh

# install service
cp configs/alpine-startup ${CHROOT}/etc/init.d/alpine-startup
chmod +x ${CHROOT}/etc/init.d/alpine-startup

# install fake-hwclock
cp configs/fake-hwclock ${CHROOT}/usr/local/bin/
chmod +x ${CHROOT}/usr/local/bin/fake-hwclock

# install service
cp configs/fakehwclock ${CHROOT}/etc/init.d/fake-hwclock
chmod +x ${CHROOT}/etc/init.d/fake-hwclock

# copy adbd
cp configs/adbd ${CHROOT}/usr/local/bin/
chmod +x ${CHROOT}/usr/local/bin/adbd

# copy usb_gadget_setup.sh
cp configs/usb_gadget_setup.sh ${CHROOT}/usr/local/bin/
chmod +x ${CHROOT}/usr/local/bin/usb_gadget_setup.sh

# install service
cp configs/usb_gadget ${CHROOT}/etc/init.d/usb_gadget
chmod +x ${CHROOT}/etc/init.d/usb_gadget

# install apps
chroot ${CHROOT} ash -l -c "
apk add --no-cache --allow-untrusted postmarketos-keys
apk add --no-cache \
    bridge-utils \
    chrony \
    dropbear \
    eudev \
    iptables \
    modemmanager \
    msm-firmware-loader \
    networkmanager-cli \
    networkmanager-dnsmasq \
    networkmanager-tui \
    networkmanager-wifi \
    networkmanager-wwan \
    openrc \
    rmtfs \
    sudo \
    udev-init-scripts \
    udev-init-scripts-openrc \
    wireguard-tools \
    wireguard-tools-wg-quick \
    wpa_supplicant \
    e2fsprogs-extra \
    openssh-sftp-server \
    zram-init \
    shadow

if [ "$NAME" == "sp970" ]; then
    apk add --no-cache msm-modem-uim-selection
fi
"

# setup alpine
chroot ${CHROOT} ash -l -c "
echo ${NAME}:${PASSWORD}::::/home/${NAME}:/bin/ash | newusers
echo root:${PASSWORD} | chpasswd
apk del shadow

cat > /root/login.sh << 'EOL'
#!/bin/sh
exec /bin/login -f root
EOL
chmod +x /root/login.sh

setup-hostname ${NAME}
setup-timezone -z Asia/Shanghai

rc-update add alpine-startup default
rc-update add devfs sysinit
rc-update add dmesg sysinit
rc-update add udev sysinit
rc-update add udev-trigger sysinit
rc-update add udev-settle sysinit
rc-update add udev-postmount default
rc-update add hwclock boot
rc-update add modules boot
rc-update add sysctl boot
rc-update add hostname boot
rc-update add bootmisc boot
rc-update add mount-ro shutdown
rc-update add killprocs shutdown
rc-update add savecache shutdown
rc-update add dropbear default
rc-update add rmtfs default
rc-update add chronyd default
rc-update add modemmanager default
rc-update add networkmanager default
rc-update add dnsmasq default
rc-update add zram-init default
rc-update add usb_gadget default
rc-update add fake-hwclock default
"

# add sudoers 
mkdir -p ${CHROOT}/etc/sudoers.d
echo "${NAME} ALL=(ALL:ALL) ALL" > ${CHROOT}/etc/sudoers.d/${NAME}

# add udev rules
cat << EOF > ${CHROOT}/etc/udev/rules.d/10-udc.rules
ACTION=="add", SUBSYSTEM=="udc", RUN+="/sbin/modprobe libcomposite", RUN+="/usr/local/bin/usb_gadget_setup.sh"
EOF

cat << EOF > ${CHROOT}/etc/udev/rules.d/99-nm-usb0.rules
SUBSYSTEM=="net", ACTION=="add|change|move", ENV{DEVTYPE}=="gadget", ENV{NM_UNMANAGED}="0"
EOF

# add ip forwarding
cat << EOF > ${CHROOT}/etc/sysctl.d/local.conf
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF

# enable autologin on console
sed -i '/^tty/ s/^/#/' ${CHROOT}/etc/inittab
echo 'ttyMSM0::respawn:/bin/busybox getty -L -n -l /root/login.sh ttyMSM0 115200' >> ${CHROOT}/etc/inittab

# setup zram
sed -i "s/num_devices=[0-9]*/num_devices=1/" ${CHROOT}/etc/conf.d/zram-init

# setup hostname
sed -i "/localhost/ s/$/ ${NAME}/" ${CHROOT}/etc/hosts

# setup NetworkManager
cp configs/*.nmconnection ${CHROOT}/etc/NetworkManager/system-connections
chmod 0600 ${CHROOT}/etc/NetworkManager/system-connections/*
sed -i '/\[main\]/a dns=dnsmasq' ${CHROOT}/etc/NetworkManager/NetworkManager.conf

# setup dnsmasq
mkdir -p ${CHROOT}/etc/dnsmasq.d
cp configs/dnsmasq.conf ${CHROOT}/etc/dnsmasq.d/

# setup extlinux
mkdir -p ${CHROOT}/boot/extlinux
cp configs/extlinux.conf ${CHROOT}/boot/extlinux
sed -i 's/DEVICE/'$NAME'/g' ${CHROOT}/boot/extlinux/extlinux.conf

# copy custom dtb's
mkdir -p ${CHROOT}/boot/dtbs/qcom
cp ../../arch/arm64/boot/dts/qcom/msm8916-ufi-*.dtb ${CHROOT}/boot/dtbs/qcom

# copy kernel
cp ../../arch/arm64/boot/Image.gz ${CHROOT}/boot/vmlinuz

# copy modules
make -C ../../ ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules_install INSTALL_MOD_PATH=${CHROOT}

# update fstab
echo "/dev/disk/by-partlabel/boot\t/boot\text2\tdefaults\t0 2" > ${CHROOT}/etc/fstab

# backup rootfs
# tar cpzf alpine_rootfs.tgz \
#     --exclude="root/*" \
#     --exclude="usr/bin/qemu-aarch64-static" \
#     -C rootfs .

#package rootfs
rm -f ${TMPDIR}/rootfs.img ${TMPDIR}/boot.img
mkdir -p files ${TMPDIR}/mnt

# create boot
BOOT_SIZE=$(du -sb ${CHROOT}/boot | cut -f1)
BOOT_SIZE=$((BOOT_SIZE + 1048576))
truncate -s $BOOT_SIZE ${TMPDIR}/boot.img
mkfs.ext2 ${TMPDIR}/boot.img
mount ${TMPDIR}/boot.img ${TMPDIR}/mnt
rsync -aH ${CHROOT}/boot/ ${TMPDIR}/mnt/
umount ${TMPDIR}/mnt

# create root img
ROOTFS_SIZE=$(du -sb ${CHROOT} | cut -f1)
ROOTFS_SIZE=$((ROOTFS_SIZE + 67108864))
truncate -s $ROOTFS_SIZE ${TMPDIR}/rootfs.img
mkfs.ext4 ${TMPDIR}/rootfs.img
mount ${TMPDIR}/rootfs.img ${TMPDIR}/mnt
rsync -aH --exclude={"/boot/*","/proc/*","/sys/*","/dev/*"} ${CHROOT}/ ${TMPDIR}/mnt/
umount ${TMPDIR}/mnt

# create sparse android images 
img2simg ${TMPDIR}/rootfs.img files/rootfs.bin
img2simg ${TMPDIR}/boot.img files/boot.bin
