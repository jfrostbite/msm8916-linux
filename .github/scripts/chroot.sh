#!/bin/bash

LANG_TARGET=en_US.UTF-8
PASSWORD=admin
NAME=sp970
PARTUUID=a7ab80e8-e9d1-e8cd-f157-93f69b1d141e

cat <<EOF > /etc/fstab
PARTUUID=$PARTUUID / ext4 defaults,noatime,commit=600,errors=remount-ro 0 1
tmpfs /tmp tmpfs defaults,nosuid 0 0
EOF

rm /etc/resolv.conf
echo "nameserver 8.8.8.8" > /etc/resolv.conf

apt update
apt full-upgrade -y
apt install -y initramfs-tools locales network-manager openssh-server systemd-timesyncd fake-hwclock
apt install -y /tmp/*.deb
sed -i -e "s/# $LANG_TARGET UTF-8/$LANG_TARGET UTF-8/" /etc/locale.gen
dpkg-reconfigure --frontend=noninteractive locales
update-locale LANG=$LANG_TARGET LC_ALL=$LANG_TARGET LANGUAGE=$LANG_TARGET

echo -e "$PASSWORD\n$PASSWORD" | passwd
echo $NAME > /etc/hostname

sed -i 's/^.\?PermitRootLogin.*$/PermitRootLogin yes/g' /etc/ssh/sshd_config

cat <<EOF > /etc/apt/sources.list
deb http://mirrors.huaweicloud.com/debian/ bookworm main contrib non-free non-free-firmware
# deb-src http://mirrors.huaweicloud.com/debian/ bookworm main contrib non-free non-free-firmware
deb http://mirrors.huaweicloud.com/debian/ bookworm-updates main contrib non-free non-free-firmware
# deb-src http://mirrors.huaweicloud.com/debian/ bookworm-updates main contrib non-free non-free-firmware
deb http://mirrors.huaweicloud.com/debian/ bookworm-backports main contrib non-free non-free-firmware
# deb-src http://mirrors.huaweicloud.com/debian/ bookworm-backports main contrib non-free non-free-firmware
deb https://mirrors.huaweicloud.com/debian-security bookworm-security main contrib non-free non-free-firmware
# deb-src https://mirrors.huaweicloud.com/debian-security bookworm-security main contrib non-free non-free-firmware
EOF

vmlinuz_name=$(basename /boot/vmlinuz-*)
cat <<EOF > /tmp/info.md
- 内核版本: ${vmlinuz_name#*-}
- 默认用户名: root
- 默认密码: $PASSWORD
EOF
rm -rf /etc/ssh/ssh_host_* /var/lib/apt/lists
rm -rf /tmp/* /root/.bash_history > /dev/null 2>&1
apt clean
exit
