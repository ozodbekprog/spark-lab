#!/usr/bin/env bash
# Spark'da ishga tushiriladi:
#   sudo bash install-on-spark.sh [/tmp/ncm/cdc_ncm.ko]
#
# Tuzatilgan versiya. Asl /tmp/ncm/install_driver.sh dagi
#   grep -qE '^05ACp1905' ...
# tekshiruvi hech qachon mos kelmaydi, chunki modinfo aliasi
# "usb:v05ACp1905d..." ko'rinishida boshlanadi.
set -uo pipefail

KO="${1:-/tmp/ncm/cdc_ncm.ko}"

if [ "$(id -u)" -ne 0 ]; then
    exec sudo bash "$0" "$@"
fi

K="$(uname -r)"
say() { printf '\n== %s\n' "$*"; }
die() { printf '\n!! %s\n' "$*" >&2; exit 1; }

say "Kernel: $K"
[ -f "$KO" ] || die "modul topilmadi: $KO"

say "Modul ma'lumoti"
VERMAGIC="$(modinfo -F vermagic "$KO" 2>/dev/null | awk '{print $1}')"
echo "vermagic: ${VERMAGIC:-?}"
[ "$VERMAGIC" = "$K" ] || die "vermagic mos emas (kerak: $K). Modulni qayta quring."

if modinfo -F alias "$KO" | grep -qi 'v05ACp1905'; then
    echo "05ac:1905 aliaslari:"
    modinfo -F alias "$KO" | grep -i 'v05ACp1905'
else
    die "modulda 05ac:1905 aliasi yo'q — patch qo'llanmagan"
fi

say "Modulni o'rnatish (persistent)"
install -D -m 0644 "$KO" "/lib/modules/$K/updates/cdc_ncm.ko"
depmod -a "$K"
echo "O'rnatildi: /lib/modules/$K/updates/cdc_ncm.ko"

say "USB3 LPM quirk (05ac:1905)"
echo '05ac:1905:k' > /sys/module/usbcore/parameters/quirks 2>/dev/null || true
cat /sys/module/usbcore/parameters/quirks 2>/dev/null || true
printf 'w /sys/module/usbcore/parameters/quirks - - - - 05ac:1905:k\n' \
    > /etc/tmpfiles.d/usbcore-quirk.conf

say "Eski modulni yuklashdan chiqarish"
modprobe -r cdc_mbim 2>/dev/null || true
if lsmod | awk '{print $1}' | grep -qx cdc_ncm; then
    if ! modprobe -r cdc_ncm; then
        echo
        echo "cdc_ncm hozir band — uni xavfsiz chiqarib bo'lmadi."
        echo "Modul o'rnatildi; qayta yuklashda avtomatik yangilanadi."
        echo "Davom etish uchun: sudo reboot"
        exit 2
    fi
fi

say "Yangi modulni yuklash"
modprobe cdc_ncm || die "modprobe cdc_ncm xato"
echo "Yuklandi."

say "SSH ruxsati"
ufw allow OpenSSH 2>/dev/null || true
systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null || true

say "USB qayta skanerlash"
udevadm trigger --action=add --subsystem-match=usb 2>/dev/null || true
sleep 1
lsusb -d 05ac:1905 2>/dev/null || true
ip -br link | grep -E '^enx' || echo "enx hali yo'q"

cat <<EOF

== Endi USB-C kabelni uzib, qayta ulang
Mac tomoni qayta enum bo'ladi. So'ng Spark'da:

   ip -br link | grep enx
   lsusb -t
   dmesg | tail -20

Agar enx chiqsa, IP berish:

   sudo bash $(dirname "$0")/net-up.sh

Mac'da:

   bash ~/Documents/spark-usbc-ssh/mac-net-up.sh
   ssh tony@10.55.0.2

== Qaytarish
   sudo rm /lib/modules/$K/updates/cdc_ncm.ko
   sudo depmod -a && sudo reboot
EOF
