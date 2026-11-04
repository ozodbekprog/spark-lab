#!/usr/bin/env bash
# Spark'da ishga tushiriladi: enx interfeyslariga IP beradi.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "sudo bilan ishga tushiring: sudo bash $0"; exit 1; }

mapfile -t IFACES < <(for i in /sys/class/net/enx*; do [ -e "$i" ] && basename "$i"; done)

if [ "${#IFACES[@]}" -eq 0 ]; then
    echo "enx interfeys topilmadi. Avval build-and-load.sh va kabelni qayta ulash."
    ip -br link
    exit 1
fi

echo "Topildi: ${IFACES[*]}"

n=0
for ifc in "${IFACES[@]}"; do
    subnet=$((55 + n))
    if command -v nmcli >/dev/null 2>&1; then
        nmcli device set "$ifc" managed no 2>/dev/null || true
    fi
    ip link set "$ifc" up
    ip addr replace "10.${subnet}.0.2/24" dev "$ifc"
    echo "$ifc -> 10.${subnet}.0.2/24  (carrier: $(cat "/sys/class/net/$ifc/carrier" 2>/dev/null || echo '?'))"
    n=$((n + 1))
done

ip -br addr show | grep -E 'enx|10\.5'

echo
echo "Mac tomonida: en3 -> 10.55.0.1, en4 -> 10.56.0.1"
echo "Tekshirish: ping -c 2 10.55.0.1 ; ping -c 2 10.56.0.1"
