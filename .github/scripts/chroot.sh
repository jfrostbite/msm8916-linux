#!/bin/bash

LANG_TARGET=en_US.UTF-8
PASSWORD=adminsp970
NAME=sp970

rm /etc/resolv.conf
echo "nameserver 8.8.8.8" > /etc/resolv.conf

apt update
apt full-upgrade -y
apt install -y apt-transport-https ca-certificates
apt install -y initramfs-tools locales openssh-server systemd-timesyncd fake-hwclock zram-tools rmtfs qrtr-tools dnsmasq iptables nano network-manager
# apt install -y /tmp/openstick-utils.deb
apt install -y /tmp/linux-image*.deb

mkdir -p /lib/firmware/msm-firmware-loader
chmod +x /tmp/firmware/msm-firmware-loader.sh
chmod +x /tmp/firmware/mobian-usb-gadget
chmod +x /tmp/firmware/mobian-setup-usb-network
chmod +x /tmp/firmware/mobian-expandisk-startup.sh
chmod +x /tmp/firmware/mobian-startup.sh
chmod +x /tmp/firmware/gc
chmod +x /tmp/firmware/adbd
chmod +x /tmp/firmware/run-iptables
chmod +x /tmp/firmware/uim-slot-selection.sh
cp /tmp/firmware/msm-firmware-loader.sh /usr/sbin/
cp /tmp/firmware/mobian-usb-gadget /usr/sbin/
cp /tmp/firmware/mobian-setup-usb-network /usr/sbin/
cp /tmp/firmware/mobian-expandisk-startup.sh /usr/sbin/
cp /tmp/firmware/mobian-startup.sh /usr/sbin/
cp /tmp/firmware/gc /usr/bin/
cp /tmp/firmware/adbd /usr/bin/

cp /tmp/firmware/msm-firmware-loader.service /etc/systemd/system/
cp /tmp/firmware/mobian-usb-gadget.service /etc/systemd/system/
cp /tmp/firmware/mobian-setup-usb-network.service /etc/systemd/system/
cp /tmp/firmware/mobian-ssh-keygen.service /etc/systemd/system/
cp /tmp/firmware/mobian-expandisk-startup.service /etc/systemd/system/
cp /tmp/firmware/mobian-startup.service /etc/systemd/system/
cp /tmp/firmware/mobian-startup.timer /etc/systemd/system/
cp -r /tmp/firmware/qcom/ /lib/firmware/

if [ ! -e /etc/dnsmasq.d ]; then
    mkdir -p /etc/dnsmasq.d
fi
cp /tmp/firmware/dnsmasq.conf /etc/dnsmasq.d/
if [ ! -e /etc/network/if-up.d ]; then
    mkdir -p /etc/network/if-up.d
fi
cp /tmp/firmware/run-iptables /etc/network/if-up.d/
cp /tmp/firmware/firewall.conf /etc/firewall.conf


cp /tmp/firmware/uim-slot-selection.sh /usr/sbin/
cp /tmp/firmware/uim-slot-selection.service /etc/systemd/system/

sed -i -e "s/# $LANG_TARGET UTF-8/$LANG_TARGET UTF-8/" /etc/locale.gen
dpkg-reconfigure --frontend=noninteractive locales
update-locale LANG=$LANG_TARGET LC_ALL=$LANG_TARGET LANGUAGE=$LANG_TARGET

echo -e "$PASSWORD\n$PASSWORD" | passwd
echo $NAME > /etc/hostname

sed -i 's/^.\?PermitRootLogin.*$/PermitRootLogin yes/g' /etc/ssh/sshd_config
sed -i 's/^.\?ALGO=.*$/ALGO=zstd/g' /etc/default/zramswap
sed -i 's/^.\?PERCENT=.*$/PERCENT=150/g' /etc/default/zramswap

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
rm -rf /var/lib/apt/lists
rm -rf /etc/resolv.conf
apt clean all

sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf

systemctl enable msm-firmware-loader
systemctl enable uim-slot-selection
systemctl enable mobian-usb-gadget
systemctl enable mobian-setup-usb-network
systemctl enable mobian-ssh-keygen
systemctl enable mobian-expandisk-startup
systemctl enable mobian-startup.timer

update-alternatives --set iptables /usr/sbin/iptables-legacy
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
update-alternatives --set arptables /usr/sbin/arptables-legacy
update-alternatives --set ebtables /usr/sbin/ebtables-legacy

exit
