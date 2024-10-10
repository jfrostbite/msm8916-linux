#!/bin/bash

LANG_TARGET=en_US.UTF-8
PASSWORD=admin
NAME=sp970

rm /etc/resolv.conf
echo "nameserver 8.8.8.8" > /etc/resolv.conf

apt update
apt full-upgrade -y
apt install -y initramfs-tools locales network-manager openssh-server systemd-timesyncd fake-hwclock rmtfs qrtr-tools
apt install -y /tmp/openstick-utils.deb
apt install -y /tmp/linux-image*.deb

mkdir -p /lib/firmware/msm-firmware-loader
chmod +x /tmp/firmware/msm-firmware-loader.sh
chmod +x /tmp/firmware/uim-slot-selection.sh
cp /tmp/firmware/msm-firmware-loader.sh /usr/sbin/
cp /tmp/firmware/msm-firmware-loader.service /etc/systemd/system/
cp /tmp/firmware/uim-slot-selection.sh /usr/sbin/
cp /tmp/firmware/uim-slot-selection.service /etc/systemd/system/

sed -i -e "s/# $LANG_TARGET UTF-8/$LANG_TARGET UTF-8/" /etc/locale.gen
dpkg-reconfigure --frontend=noninteractive locales
update-locale LANG=$LANG_TARGET LC_ALL=$LANG_TARGET LANGUAGE=$LANG_TARGET

echo -e "$PASSWORD\n$PASSWORD" | passwd
echo $NAME > /etc/hostname

sed -i 's/^.\?PermitRootLogin.*$/PermitRootLogin yes/g' /etc/ssh/sshd_config

cat <<EOF > /etc/apt/sources.list
deb http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware
# deb-src http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware

deb http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware
# deb-src http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware

deb http://deb.debian.org/debian/ bookworm-backports main contrib non-free non-free-firmware
# deb-src http://deb.debian.org/debian/ bookworm-backports main contrib non-free non-free-firmware

deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
# deb-src http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF

rm -rf /etc/ssh/ssh_host_* /var/lib/apt/lists
rm -rf /tmp/* /root/.bash_history > /dev/null 2>&1
apt clean

systemctl enable msm-firmware-loader
systemctl enable uim-slot-selection

exit
