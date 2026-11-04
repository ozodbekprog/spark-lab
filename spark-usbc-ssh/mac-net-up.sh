#!/usr/bin/env bash
# Mac'da ishga tushiriladi: en3/en4 (USB-C NCM) ga statik IP beradi.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    exec sudo bash "$0" "$@"
fi

SERVICES="$(networksetup -listallnetworkservices 2>/dev/null || true)"

set_ip() {
    local dev="$1" ip="$2"
    if printf '%s\n' "$SERVICES" | grep -qx "Ethernet Adapter ($dev)"; then
        networksetup -setmanual "Ethernet Adapter ($dev)" "$ip" 255.255.255.0
        echo "$dev -> $ip (networksetup)"
    elif ifconfig "$dev" >/dev/null 2>&1; then
        ifconfig "$dev" "$ip" netmask 255.255.255.0 up
        echo "$dev -> $ip (ifconfig)"
    else
        echo "$dev topilmadi — USB-C kabelni tekshiring"
        return 1
    fi
}

set_ip en3 10.55.0.1 || true
set_ip en4 10.56.0.1 || true

echo
ifconfig en3 2>/dev/null | grep -E 'flags|inet |status|media' || true
ifconfig en4 2>/dev/null | grep -E 'flags|inet |status|media' || true

echo
echo "Tekshirish: ping -c 2 10.55.0.2 ; ping -c 2 10.56.0.2"
echo "SSH: ssh tony@10.55.0.2"
