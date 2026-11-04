#!/usr/bin/env bash
# Spark (DGX OS, kernel 7.0.0-1019-nvidia) uchun cdc_ncm 05ac:1905 patch.
# Bu skript SPARK'DA, sudo bilan ishga tushiriladi.
set -euo pipefail

KVER="$(uname -r)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="/tmp/spark-cdc-ncm-build"
SRC="$WORK/cdc_ncm.c"

say() { printf '\n== %s\n' "$*"; }
die() { printf '\n!! %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "sudo bilan ishga tushiring: sudo bash $0"

say "Kernel: $KVER"

if command -v mokutil >/dev/null 2>&1; then
    say "Secure Boot holati"
    mokutil --sb-state || true
fi

say "Kernel headers tekshiruvi"
if [ ! -d "/lib/modules/$KVER/build" ]; then
    echo "Headers yo'q — o'rnatilmoqda..."
    apt-get update
    apt-get install -y "linux-headers-$KVER" || die "linux-headers-$KVER topilmadi"
fi
[ -f "/lib/modules/$KVER/build/Makefile" ] || die "Kernel build katalogi to'liq emas"

say "cdc_ncm modul sifatida bormi?"
if ! MODPATH="$(modinfo -n cdc_ncm 2>/dev/null)"; then
    grep -E '^CONFIG_USB_NET_CDC_NCM' "/boot/config-$KVER" 2>/dev/null || true
    die "cdc_ncm modul sifatida topilmadi (kernel ichida =y bo'lishi mumkin). Bu usul ishlamaydi."
fi
echo "Stock modul: $MODPATH"

say "Manba tayyorlash"
rm -rf "$WORK"
mkdir -p "$WORK"
if [ -f "$HERE/cdc_ncm-v7.0.c" ]; then
    cp "$HERE/cdc_ncm-v7.0.c" "$SRC"
else
    echo "cdc_ncm-v7.0.c topilmadi — kernel.org dan yuklanmoqda..."
    curl -fsSL --max-time 60 \
        "https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/drivers/net/usb/cdc_ncm.c?h=v7.0" \
        -o "$SRC"
fi
grep -q 'apple_private_interface_info' "$SRC" || die "manbada apple_private_interface_info yo'q"

say "05ac:1905 patch qo'llash"
python3 - "$SRC" <<'PY'
import sys

path = sys.argv[1]
src = open(path).read()
if "0x05ac, 0x1905" in src:
    print("allaqachon patch qilingan")
    sys.exit(0)

anchor = "\t/* Ericsson MBM devices like F5521gw */"
block = (
    "\t/* Mac (Apple Silicon, USB-C direct networking) */\n"
    "\t{ USB_DEVICE_INTERFACE_NUMBER(0x05ac, 0x1905, 0),\n"
    "\t\t.driver_info = (unsigned long)&apple_private_interface_info,\n"
    "\t},\n"
    "\t{ USB_DEVICE_INTERFACE_NUMBER(0x05ac, 0x1905, 2),\n"
    "\t\t.driver_info = (unsigned long)&apple_private_interface_info,\n"
    "\t},\n\n"
)
if anchor not in src:
    sys.exit("anchor topilmadi — cdc_ncm.c kutilgan shaklda emas")
open(path, "w").write(src.replace(anchor, block + anchor, 1))
print("patch qo'llandi (2 ta interface: 0 va 2)")
PY

cat > "$WORK/Makefile" <<'EOF'
obj-m := cdc_ncm.o
EOF

say "Modul qurilmoqda"
make -C "/lib/modules/$KVER/build" M="$WORK" modules
[ -f "$WORK/cdc_ncm.ko" ] || die "cdc_ncm.ko qurilmadi"

say "Tayyor modulni tekshirish"
modinfo "$WORK/cdc_ncm.ko" | grep -E '^(filename|version|vermagic|depends|name):' || true

say "Stock modulni yuklashdan chiqarish"
modprobe -r cdc_mbim 2>/dev/null || true
if ! modprobe -r cdc_ncm 2>/dev/null; then
    echo "Ogohlantirish: cdc_ncm hozir ishlatilmoqda, majburan yuklaymiz."
fi

say "Yangi modulni yuklash"
insmod "$WORK/cdc_ncm.ko"

say "USB3 LPM quirk (05ac:1905)"
echo '05ac:1905:k' > /sys/module/usbcore/parameters/quirks
cat /sys/module/usbcore/parameters/quirks

say "USB qayta skanerlash"
udevadm trigger --action=add --subsystem-match=usb 2>/dev/null || true
sleep 2

say "Holat"
ip -br link | grep -E 'enx|usb' || echo "enx interfeys hali yo'q"
dmesg | tail -20

cat <<EOF

== Keyingi qadamlar
1. USB-C kabelni Spark'dan uzib, qayta ulang (Mac tomoni ham qayta enum bo'lsin).
2. Spark'da:  ip -br link
3. enx... chiqsa:  sudo bash $HERE/net-up.sh
4. Mac'da:  bash mac-net-up.sh   (fayl Mac'dagi shu papkada)
5. Mac'da:  ssh tony@10.55.0.2

== Qaytarish
   sudo modprobe -r cdc_ncm && sudo modprobe cdc_ncm
   (yoki oddiygina reboot — stock modul qaytadi)

== Doimiy qilish (ixtiyoriy, xavfli)
   sudo cp $WORK/cdc_ncm.ko /lib/modules/$KVER/updates/cdc_ncm.ko
   sudo depmod -a
   # quirk uchun: /etc/tmpfiles.d/usbcore-quirk.conf
   # w /sys/module/usbcore/parameters/quirks - - - - 05ac:1905:k
EOF
