#!/bin/bash -e
#
# Build an ImmortalWrt rootfs image for MSM8916 UFI devices, reusing the
# kernel / DTB / modules produced by this tree (build.yml). The boot image is
# NOT rebuilt here: build_boot_img.sh already produces a working boot.img whose
# cmdline mounts root=PARTLABEL=system and runs /sbin/init (procd on
# ImmortalWrt), so the same boot.img boots this rootfs.
#
# This mirrors alpine_rootfs.sh: same artifact inputs, same files/rootfs.bin
# and files/boot.bin sparse-image outputs, same ../../immortalwrt_version file.
#
# The rootfs is produced with the official ImmortalWrt ImageBuilder for the
# generic aarch64 target (armsr/armv8). ImageBuilder lets us bake in the
# packages we need (luci, wpad, usbutils, ...) and a FILES overlay (our UCI
# config + gadget/firmware helpers) fully offline. We then graft this tree's
# out-of-tree kernel modules onto the result, since ImageBuilder only knows
# ImmortalWrt's own kernel.
#
# NOTE: run on Linux x86_64 (CI runner / container / VM). ImageBuilder ships
#       x86_64 host binaries and does not run on macOS or arm64 hosts.

if [ -z "$1" ]; then
    echo "No device name provided. Using default: ufi"
    NAME="ufi"
else
    NAME="$1"
fi

# ImmortalWrt release. Defaults to 25.12.2 (latest stable with apk, matching
# the apk-based snapshot we tested). Set IMMORTALWRT_VERSION=snapshots to use
# the rolling snapshot instead.
IMMORTALWRT_VERSION="${IMMORTALWRT_VERSION:-25.12.2}"
if [ "$IMMORTALWRT_VERSION" = "snapshots" ]; then
    IMMORTALWRT_BASE="https://downloads.immortalwrt.org/snapshots/targets/armsr/armv8"
else
    IMMORTALWRT_BASE="https://downloads.immortalwrt.org/releases/${IMMORTALWRT_VERSION}/targets/armsr/armv8"
fi

# ImageBuilder profile for armsr/armv8 is the generic board.
PROFILE="${PROFILE:-generic}"

# Packages to preinstall. Keep this list USERSPACE-only: we boot our own
# out-of-tree kernel and graft our own /lib/modules below, so ImmortalWrt
# kmod-* packages (built against ImmortalWrt's kernel) do not match our kernel
# ABI and must not be installed. Networking modules (USB gadget, wifi, ...)
# come from our own kernel's modules.
#
# Defaults cover: web UI (luci), USB gadget userspace tools, wifi userspace
# stack (wpad + hostapd/wpa_supplicant), ext4 tooling, adb.
PACKAGES="${PACKAGES:-\
luci luci-ssl luci-theme-argon luci-app-openclash \
usbutils \
wpad-mesh-openssl hostapd-common iw wireless-regdb \
e2fsprogs resize2fs \
adb \
-dnsmasq dnsmasq-full \
}"

export TMPDIR=${TMPDIR=/var/tmp/immortalwrt-build}
mkdir -p "${TMPDIR}"
export CHROOT=${CHROOT=${TMPDIR}/rootfs}

ARTIFACTS=../../artifacts
IB_DIR="${TMPDIR}/imagebuilder"
FILES_OVERLAY="${TMPDIR}/files-overlay"

# ---------------------------------------------------------------------------
# Input validation (same contract as alpine_rootfs.sh)
# ---------------------------------------------------------------------------

if [ ! -f "${ARTIFACTS}/Image.gz" ]; then
    echo "Kernel Image.gz not found"
    exit 1
fi

if [ "$NAME" = "ufi" ]; then
    if [ -z "$(ls ${ARTIFACTS}/msm8916-ufi-*.dtb 2>/dev/null)" ]; then
        echo "DTB file not found"
        exit 1
    fi
else
    if [ ! -f "${ARTIFACTS}/msm8916-ufi-${NAME}.dtb" ]; then
        echo "DTB file not found"
        exit 1
    fi
fi

if [ -z "$(ls ${ARTIFACTS}/linux-image-*.deb 2>/dev/null)" ]; then
    echo "linux-image deb not found (needed for kernel modules)"
    exit 1
fi

# ---------------------------------------------------------------------------
# Download + unpack ImageBuilder
# ---------------------------------------------------------------------------

echo "Resolving ImageBuilder from ${IMMORTALWRT_BASE}"
# Release names include the version (immortalwrt-imagebuilder-25.12.2-armsr-armv8...),
# snapshot names do not, so match both forms.
IB_NAME=$(curl -fsSL "${IMMORTALWRT_BASE}/sha256sums" \
    | grep -oE 'immortalwrt-imagebuilder-[^ ]*armsr-armv8\.Linux-x86_64\.tar\.(zst|xz)' \
    | head -n1)
if [ -z "${IB_NAME}" ]; then
    echo "Could not find ImageBuilder in ${IMMORTALWRT_BASE}/sha256sums"
    exit 1
fi

echo "Downloading ${IMMORTALWRT_BASE}/${IB_NAME}"
curl -fL --retry 3 --connect-timeout 30 \
    -o "${TMPDIR}/${IB_NAME}" "${IMMORTALWRT_BASE}/${IB_NAME}"

rm -rf "${IB_DIR}"
mkdir -p "${IB_DIR}"
case "${IB_NAME}" in
    *.tar.zst) tar --use-compress-program=unzstd -xf "${TMPDIR}/${IB_NAME}" -C "${IB_DIR}" --strip-components=1 ;;
    *.tar.xz)  tar -xJf "${TMPDIR}/${IB_NAME}" -C "${IB_DIR}" --strip-components=1 ;;
    *) echo "Unknown ImageBuilder archive format: ${IB_NAME}"; exit 1 ;;
esac
rm -f "${TMPDIR}/${IB_NAME}"

# ---------------------------------------------------------------------------
# Build the FILES overlay baked into the rootfs by ImageBuilder
#
# Network (UCI): the device exposes a USB RNDIS gadget (usb0) to the host PC as
# LAN 192.168.100.1/24 with DHCP, and the uplink (WAN) is Wi-Fi (radio0 joins
# an upstream AP as a station). No cellular modem is configured. The Wi-Fi
# wireless config stays disabled until SSID/key are set.
# ---------------------------------------------------------------------------

rm -rf "${FILES_OVERLAY}"
mkdir -p "${FILES_OVERLAY}/etc/config"
cp configs/immortalwrt/network  "${FILES_OVERLAY}/etc/config/network"
cp configs/immortalwrt/dhcp     "${FILES_OVERLAY}/etc/config/dhcp"
cp configs/immortalwrt/firewall "${FILES_OVERLAY}/etc/config/firewall"
cp configs/immortalwrt/wireless "${FILES_OVERLAY}/etc/config/wireless"

# USB gadget helper scripts (reused from the Alpine config set)
mkdir -p "${FILES_OVERLAY}/usr/local/bin"
cp configs/usb_gadget_setup.sh "${FILES_OVERLAY}/usr/local/bin/"
chmod +x "${FILES_OVERLAY}/usr/local/bin/usb_gadget_setup.sh"
if [ -f configs/adbd ]; then
    cp configs/adbd "${FILES_OVERLAY}/usr/local/bin/"
    chmod +x "${FILES_OVERLAY}/usr/local/bin/adbd"
fi

# USB gadget brought up by a procd init script at boot. OpenWrt's hotplug.d
# does not dispatch 'udc' events, so we start the gadget explicitly from init
# (builds the gadget tree, starts adbd, binds the UDC) rather than via hotplug.
mkdir -p "${FILES_OVERLAY}/etc/init.d"
cp configs/immortalwrt/usb_gadget.init \
    "${FILES_OVERLAY}/etc/init.d/usb_gadget"
chmod +x "${FILES_OVERLAY}/etc/init.d/usb_gadget"

# enable the service at first boot
mkdir -p "${FILES_OVERLAY}/etc/uci-defaults"
cat > "${FILES_OVERLAY}/etc/uci-defaults/98-enable-usb-gadget" <<'EOF'
#!/bin/sh
/etc/init.d/usb_gadget enable
exit 0
EOF
chmod +x "${FILES_OVERLAY}/etc/uci-defaults/98-enable-usb-gadget"

# Qualcomm WCNSS (Wi-Fi) module stack. Alpine gets these loaded by udev
# (modalias autoload). ImmortalWrt has no udev, so this init script inserts
# the modules explicitly, in dependency order, by full path.
cp configs/immortalwrt/qcom_wifi.init "${FILES_OVERLAY}/etc/init.d/qcom_wifi"
chmod +x "${FILES_OVERLAY}/etc/init.d/qcom_wifi"

cat > "${FILES_OVERLAY}/etc/uci-defaults/97-enable-qcom-wifi" <<'EOF'
#!/bin/sh
/etc/init.d/qcom_wifi enable
exit 0
EOF
chmod +x "${FILES_OVERLAY}/etc/uci-defaults/97-enable-qcom-wifi"

# Wi-Fi / modem firmware: wcn36xx (and modem/venus) firmware is NOT shipped in
# the rootfs; it lives on the device's own flash partitions. Reuse the same
# msm-firmware-loader this tree uses for Alpine/Debian: it mounts apnhlos/
# modem/persist/bluetooth, symlinks the blobs (incl. WCNSS_qcom_wlan_nv.bin and
# wcnss.mbn) into /lib/firmware/msm-firmware-loader/target and points
# firmware_class at it. Run it from an OpenWrt preinit hook so the firmware
# path is ready before wcn36xx probes. Its BASEDIR must already exist (it is
# created below, after the rootfs is extracted).
mkdir -p "${FILES_OVERLAY}/usr/sbin"
cp firmware/msm-firmware-loader.sh \
    "${FILES_OVERLAY}/usr/sbin/msm-firmware-loader.sh"
chmod +x "${FILES_OVERLAY}/usr/sbin/msm-firmware-loader.sh"

mkdir -p "${FILES_OVERLAY}/lib/preinit"
cat > "${FILES_OVERLAY}/lib/preinit/81_load_msm_firmware" <<'EOF'
#!/bin/sh
# Load Qualcomm firmware blobs from the on-device flash partitions before the
# rest of preinit runs, so wcn36xx wifi / modem firmware is available early.
load_msm_firmware() {
	[ -x /usr/sbin/msm-firmware-loader.sh ] && /usr/sbin/msm-firmware-loader.sh
}
boot_hook_add preinit_main load_msm_firmware
EOF
chmod +x "${FILES_OVERLAY}/lib/preinit/81_load_msm_firmware"

# Serial console: pin a getty on ttyMSM0 (the boot cmdline console).
cat > "${FILES_OVERLAY}/etc/uci-defaults/99-ttymsm0-console" <<'EOF'
#!/bin/sh
grep -q 'ttyMSM0' /etc/inittab 2>/dev/null || \
    echo 'ttyMSM0::askfirst:/usr/libexec/login.sh' >> /etc/inittab
exit 0
EOF
chmod +x "${FILES_OVERLAY}/etc/uci-defaults/99-ttymsm0-console"

# Grow the ext4 rootfs to fill the whole 'system' partition on first boot,
# the same thing alpine-startup.sh does with resize2fs. Runs once (uci-defaults
# scripts are removed after they succeed). resize2fs comes from e2fsprogs.
cat > "${FILES_OVERLAY}/etc/uci-defaults/99-resize-rootfs" <<'EOF'
#!/bin/sh
# /dev/disk/by-partlabel does not exist without udev, so fall back to the
# device that is mounted on / (BusyBox has no findmnt).
dev=/dev/disk/by-partlabel/system
[ -e "$dev" ] || dev=$(awk '$2 == "/" { print $1; exit }' /proc/mounts)
if [ -z "$dev" ] || [ ! -e "$dev" ]; then
    logger -t resize-rootfs "root device not found, skipping resize"
    exit 0
fi
if resize2fs "$dev"; then
    logger -t resize-rootfs "resized $dev"
else
    logger -t resize-rootfs "resize2fs failed on $dev"
fi
exit 0
EOF
chmod +x "${FILES_OVERLAY}/etc/uci-defaults/99-resize-rootfs"

# No custom /etc/fstab: the rootfs is mounted by the boot cmdline
# (root=PARTLABEL=system). The image has no udev, so /dev/disk/by-partlabel
# does not exist and a 'boot' fstab entry would fail at startup.

# ---------------------------------------------------------------------------
# Run ImageBuilder to produce the rootfs tarball
# ---------------------------------------------------------------------------

echo ">> make image PROFILE=${PROFILE}"
make -C "${IB_DIR}" image \
    PROFILE="${PROFILE}" \
    PACKAGES="${PACKAGES}" \
    FILES="${FILES_OVERLAY}"

# Locate the produced rootfs tarball
ROOTFS_TGZ=$(find "${IB_DIR}/bin/targets" -name '*generic-rootfs.tar.gz' | head -n1)
if [ -z "${ROOTFS_TGZ}" ] || [ ! -f "${ROOTFS_TGZ}" ]; then
    echo "ImageBuilder did not produce a generic-rootfs.tar.gz"
    find "${IB_DIR}/bin/targets" -type f || true
    exit 1
fi
echo ">> rootfs tarball: ${ROOTFS_TGZ}"

rm -rf "${CHROOT}"
mkdir -p "${CHROOT}"
tar -xzf "${ROOTFS_TGZ}" -C "${CHROOT}"

# Record the ImmortalWrt version for the release step
if [ -f "${CHROOT}/etc/immortalwrt_release" ]; then
    . "${CHROOT}/etc/immortalwrt_release" 2>/dev/null || true
    echo "${DISTRIB_RELEASE:-${IMMORTALWRT_VERSION}}" > ../../immortalwrt_version
elif [ -f "${CHROOT}/etc/openwrt_release" ]; then
    . "${CHROOT}/etc/openwrt_release" 2>/dev/null || true
    echo "${DISTRIB_RELEASE:-${IMMORTALWRT_VERSION}}" > ../../immortalwrt_version
else
    echo "${IMMORTALWRT_VERSION}" > ../../immortalwrt_version
fi

# ---------------------------------------------------------------------------
# Graft this tree's kernel modules. ImageBuilder installed kmods for
# ImmortalWrt's own kernel; we boot our own Image.gz, so replace /lib/modules
# with the modules from our linux-image deb (same approach as alpine_rootfs.sh).
# ---------------------------------------------------------------------------

MODS_TMP=${TMPDIR}/debmods
rm -rf "${MODS_TMP}"
mkdir -p "${MODS_TMP}"
dpkg-deb -x ${ARTIFACTS}/linux-image-*.deb "${MODS_TMP}"
rm -rf "${CHROOT}/lib/modules"
mkdir -p "${CHROOT}/lib"
cp -a "${MODS_TMP}/lib/modules" "${CHROOT}/lib/"
[ -d "${MODS_TMP}/lib/firmware" ] && cp -a "${MODS_TMP}/lib/firmware" "${CHROOT}/lib/"
rm -rf "${MODS_TMP}"
depmod -b "${CHROOT}" "$(ls ${CHROOT}/lib/modules)"

# msm-firmware-loader mounts tmpfs on this directory; it must exist first.
mkdir -p "${CHROOT}/lib/firmware/msm-firmware-loader"

# ---------------------------------------------------------------------------
# extlinux + boot partition contents (same layout as alpine_rootfs.sh so the
# existing boot.img / lk2nd setup keeps working)
# ---------------------------------------------------------------------------

mkdir -p "${CHROOT}/boot/extlinux"
cp configs/extlinux.conf "${CHROOT}/boot/extlinux/"
if [ "$NAME" = "ufi" ]; then
    sed -i 's|{FDT}|fdtdir /dtbs|g' "${CHROOT}/boot/extlinux/extlinux.conf"
else
    sed -i 's|{FDT}|fdt /dtbs/qcom/msm8916-ufi-'"$NAME"'.dtb|g' \
        "${CHROOT}/boot/extlinux/extlinux.conf"
fi

mkdir -p "${CHROOT}/boot/dtbs/qcom"
cp ${ARTIFACTS}/msm8916-ufi-*.dtb "${CHROOT}/boot/dtbs/qcom/"
cp ${ARTIFACTS}/Image.gz "${CHROOT}/boot/vmlinuz"

# ---------------------------------------------------------------------------
# Package rootfs/boot into sparse Android images (identical to alpine script)
# ---------------------------------------------------------------------------

rm -f "${TMPDIR}/rootfs.img" "${TMPDIR}/boot.img"
mkdir -p files "${TMPDIR}/mnt"

# boot partition (ext2)
BOOT_SIZE=$(du -sb "${CHROOT}/boot" | cut -f1)
BOOT_SIZE=$((BOOT_SIZE + 1048576))
truncate -s "$BOOT_SIZE" "${TMPDIR}/boot.img"
mkfs.ext2 "${TMPDIR}/boot.img"
mount "${TMPDIR}/boot.img" "${TMPDIR}/mnt"
rsync -aH "${CHROOT}/boot/" "${TMPDIR}/mnt/"
umount "${TMPDIR}/mnt"

# root partition (ext4)
ROOTFS_SIZE=$(du -sb "${CHROOT}" | cut -f1)
ROOTFS_SIZE=$((ROOTFS_SIZE + 67108864))
truncate -s "$ROOTFS_SIZE" "${TMPDIR}/rootfs.img"
mkfs.ext4 "${TMPDIR}/rootfs.img"
mount "${TMPDIR}/rootfs.img" "${TMPDIR}/mnt"
rsync -aH --exclude=/boot/* --exclude=/proc/* --exclude=/sys/* --exclude=/dev/* \
    "${CHROOT}/" "${TMPDIR}/mnt/"
umount "${TMPDIR}/mnt"

img2simg "${TMPDIR}/rootfs.img" files/rootfs.bin
img2simg "${TMPDIR}/boot.img" files/boot.bin

echo "ImmortalWrt rootfs built: files/rootfs.bin files/boot.bin"
