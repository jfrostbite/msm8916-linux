#!/bin/sh -e
if [ -z "$1" ]; then
    echo "No device name provided. Using default: ufi"
    NAME="ufi"
else
    NAME="$1"
fi
export TMPDIR=${TMPDIR=/var/tmp/alpine-build}
mkdir -p ${TMPDIR}
# log the mount options of the build dir; "nosuid" here breaks setuid files in apk
findmnt -T ${TMPDIR} -o TARGET,FSTYPE,OPTIONS || true
export CHROOT=${CHROOT=${TMPDIR}/rootfs}
export RELEASE=${RELEASE=latest-stable}
export PMOS_RELEASE=${PMOS_RELEASE=master}
export MIRROR=${MIRROR=http://mirrors.hust.edu.cn/alpine}
export PMOS_MIRROR=${PMOS_MIRROR=http://mirrors.aliyun.com/postmarketOS}

PASSWORD="admin$NAME"

if [ ! -f "../../artifacts/Image.gz" ]; then
    echo "Kernel Image.gz not found"
    exit 1
fi

if [ "$NAME" = "ufi" ]; then
    if [ -z "$(ls ../../artifacts/msm8916-ufi-*.dtb 2>/dev/null)" ]; then
        echo "DTB file not found"
        exit 1
    fi
else
    if [ ! -f "../../artifacts/msm8916-ufi-${NAME}.dtb" ]; then
        echo "DTB file not found"
        exit 1
    fi
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

# fetch apk.static from the Alpine CDN (gitlab.alpinelinux.org is unreachable from CI)
APK_REPO=http://dl-cdn.alpinelinux.org/alpine/latest-stable/main/$(uname -m)
curl -fL --retry 3 --connect-timeout 30 -o APKINDEX.tar.gz "${APK_REPO}/APKINDEX.tar.gz"
APK_TOOLS_VER=$(tar -xzOf APKINDEX.tar.gz APKINDEX | awk '/^P:apk-tools-static$/ {p=1; next} p && /^V:/ {sub(/^V:/, ""); print; exit}')
curl -fL --retry 3 --connect-timeout 30 -o apk-tools-static.apk "${APK_REPO}/apk-tools-static-${APK_TOOLS_VER}.apk"
tar -xzf apk-tools-static.apk sbin/apk.static
mv sbin/apk.static apk.static
rm -rf sbin apk-tools-static.apk APKINDEX.tar.gz
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

# install battery led control
cp configs/battery_led_control.sh ${CHROOT}/usr/local/bin/
chmod +x ${CHROOT}/usr/local/bin/battery_led_control.sh

# install usb_gadget_restart
cp configs/usb_gadget_restart.sh ${CHROOT}/usr/local/bin/
chmod +x ${CHROOT}/usr/local/bin/usb_gadget_restart.sh

# install apps
chroot ${CHROOT} ash -l -c "
set -e
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
    tzdata \
    wireless-regdb \
    zram-init \
    iw \
    shadow

if [ "$NAME" == "sp970" ]; then
    apk add --no-cache msm-modem-uim-selection || echo 'WARNING: msm-modem-uim-selection not installed'
fi
"

# setup alpine
chroot ${CHROOT} ash -l -c "
if [ "$NAME" != "ufi" ]; then
    echo ${NAME}:${PASSWORD}::::/home/${NAME}:/bin/ash | newusers
fi
echo root:${PASSWORD} | chpasswd
apk del shadow

cat > /root/login.sh << 'EOL'
#!/bin/sh
exec /bin/login -f root
EOL
chmod +x /root/login.sh

if [ "$NAME" != "ufi" ]; then
    setup-hostname ${NAME}
fi
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
rc-update add iptables boot
rc-update add mount-ro shutdown
rc-update add killprocs shutdown
rc-update add savecache shutdown
rc-update add dropbear default
rc-update add rmtfs default
rc-update add local default
rc-update add modemmanager default
rc-update add networkmanager default
rc-update add dnsmasq default
rc-update add zram-init default
rc-update add usb_gadget default
rc-update add fake-hwclock default
"

# add sudoers 
mkdir -p ${CHROOT}/etc/sudoers.d
if [ "$NAME" != "ufi" ]; then
    echo "${NAME} ALL=(ALL:ALL) ALL" > ${CHROOT}/etc/sudoers.d/${NAME}
fi

# add nftables rules
mkdir -p ${CHROOT}/etc/iptables
cp configs/ruleset.nft ${CHROOT}/etc/iptables/rules-save

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

# Add chronyd to default runlevel but delay its start
mkdir -p ${CHROOT}/etc/local.d
cat << EOF > ${CHROOT}/etc/local.d/chronyd-delay.start
#!/bin/sh
# Wait for network connectivity or 60 seconds, whichever comes first
timeout 60 sh -c 'until ping -c1 8.8.8.8 >/dev/null 2>&1; do sleep 1; done'
# Start chronyd
rc-service chronyd start
EOF
chmod +x ${CHROOT}/etc/local.d/chronyd-delay.start

# Add disablebt
cat << EOF > ${CHROOT}/etc/local.d/disablebt.start
#!/bin/sh
rfkill toggle bluetooth 
echo '1500' > /proc/sys/vm/dirty_writeback_centisecs
EOF
chmod +x ${CHROOT}/etc/local.d/disablebt.start

# enable autologin on console
sed -i '/^tty/ s/^/#/' ${CHROOT}/etc/inittab
echo 'ttyMSM0::respawn:/bin/busybox getty -L -n -l /root/login.sh ttyMSM0 115200' >> ${CHROOT}/etc/inittab

# setup zram
sed -i "s/num_devices=[0-9]*/num_devices=1/" ${CHROOT}/etc/conf.d/zram-init
# zram-init is the only zram manager: postmarketos-zram-swap needs /etc/deviceinfo,
# which this rootfs does not ship, and it would fight zram-init over zram0.
# zram-init's "need ... swap" pulls in that provider, so drop the requirement.
# postmarketos-base-openrc requires postmarketos-zram-openrc, so the package must stay.
# Remove the service from every runlevel and delete its init script instead.
chroot ${CHROOT} ash -l -c "rc-update del postmarketos-zram-swap 2>/dev/null; true"
rm -f ${CHROOT}/etc/init.d/postmarketos-zram-swap
sed -i 's/need localmount swap/need localmount/' ${CHROOT}/etc/init.d/zram-init

# setup NetworkManager
# log which conf file the networkmanager package actually shipped
chroot ${CHROOT} apk info -L networkmanager | grep -i 'conf' || true
mkdir -p ${CHROOT}/etc/NetworkManager/system-connections
mkdir -p ${CHROOT}/etc/NetworkManager
if [ ! -f ${CHROOT}/etc/NetworkManager/NetworkManager.conf ]; then
    printf '[main]\n' > ${CHROOT}/etc/NetworkManager/NetworkManager.conf
fi
cp configs/*.nmconnection ${CHROOT}/etc/NetworkManager/system-connections
chmod 0600 ${CHROOT}/etc/NetworkManager/system-connections/*
sed -i '/\[main\]/a dns=dnsmasq' ${CHROOT}/etc/NetworkManager/NetworkManager.conf

# setup dnsmasq
mkdir -p ${CHROOT}/etc/dnsmasq.d
cp configs/dnsmasq.conf ${CHROOT}/etc/dnsmasq.d/

# setup extlinux
mkdir -p ${CHROOT}/boot/extlinux
cp configs/extlinux.conf ${CHROOT}/boot/extlinux
if [ "$NAME" = "ufi" ]; then
    sed -i 's/{FDT}/fdtdir \/dtbs/g' ${CHROOT}/boot/extlinux/extlinux.conf
else
    sed -i 's/{FDT}/fdt \/dtbs\/qcom\/msm8916-ufi-'$NAME'.dtb/g' ${CHROOT}/boot/extlinux/extlinux.conf
fi

# copy custom dtb's
mkdir -p ${CHROOT}/boot/dtbs/qcom
cp ../../artifacts/msm8916-ufi-*.dtb ${CHROOT}/boot/dtbs/qcom

# copy kernel
cp ../../artifacts/Image.gz ${CHROOT}/boot/vmlinuz

# copy modules from the kernel package built in the build job
MODS_TMP=${TMPDIR}/debmods
rm -rf ${MODS_TMP}
mkdir -p ${MODS_TMP}
dpkg-deb -x ../../artifacts/linux-image-*.deb ${MODS_TMP}
cp -a ${MODS_TMP}/lib ${CHROOT}/
rm -rf ${MODS_TMP}
depmod -b ${CHROOT} $(ls ${CHROOT}/lib/modules)

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

# export the Alpine version for the release step (replaces debian_version)
cp ${CHROOT}/etc/alpine-release ../../alpine_version

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
rsync -aH --exclude=/boot/* --exclude=/proc/* --exclude=/sys/* --exclude=/dev/* ${CHROOT}/ ${TMPDIR}/mnt/
umount ${TMPDIR}/mnt

# create sparse android images 
img2simg ${TMPDIR}/rootfs.img files/rootfs.bin
img2simg ${TMPDIR}/boot.img files/boot.bin
