#!/bin/bash

# Skrypt automatycznie konfiguruje Proxmox VE do używania DHCP 
# Uniwersalny z wyborem interfejsu sieciowego

set -e

BACKUP="/etc/network/interfaces.bak.$(date +%Y%m%d%H%M%S)"
echo "[💾] Tworzenie backupu pliku interfaces: $BACKUP"
cp /etc/network/interfaces "$BACKUP"

echo "[INFO] 🔍 Szukanie fizycznych interfejsów sieciowych..."

# Pobieramy listę fizycznych interfejsów (pomijamy loopback i wirtualne)
mapfile -t ifaces < <(ip -o link show | awk -F': ' '{print $2}' | grep -vE 'lo|vmbr|veth|tap|br-|docker|bond|fwbr')

if [ ${#ifaces[@]} -eq 0 ]; then
    echo "[❌ BŁĄD] Nie znaleziono fizycznych interfejsów sieciowych."
    echo "[🧯] Przywracanie backupu: $BACKUP"
    cp "$BACKUP" /etc/network/interfaces
    exit 0
fi

if [ ${#ifaces[@]} -eq 1 ]; then
    PHY_IFACE="${ifaces[0]}"
    echo "[✅] Znaleziono jeden interfejs: $PHY_IFACE"
else
    echo "[INFO] Znaleziono kilka interfejsów, wybierz jeden:"
    for i in "${!ifaces[@]}"; do
    iface="${ifaces[$i]}"
    status=$(cat /sys/class/net/"$iface"/operstate 2>/dev/null || echo "unknown")
    mac=$(cat /sys/class/net/"$iface"/address 2>/dev/null || echo "brak")
    ip=$(ip -4 -o addr show "$iface" | awk '{print $4}' | cut -d/ -f1 | head -n1)
    [ -z "$ip" ] && ip="brak"
    echo "$((i+1))) $iface — status: $status, MAC: $mac, IP: $ip"
done
    while true; do
        read -rp "Wpisz numer interfejsu i naciśnij Enter: " choice
        if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [ "$choice" -le "${#ifaces[@]}" ]; then
            PHY_IFACE="${ifaces[$((choice-1))]}"
            echo "[✅] Wybrano interfejs: $PHY_IFACE"
            break
        else
            echo "❌ Nieprawidłowy wybór, spróbuj ponownie."
        fi
    done
fi



echo "[🛠️] Tworzenie nowego pliku /etc/network/interfaces z DHCP na vmbr0..."

cat <<EOF > /etc/network/interfaces
auto lo
iface lo inet loopback

auto vmbr0
iface vmbr0 inet dhcp
    bridge_ports $PHY_IFACE
    bridge_stp off
    bridge_fd 0
EOF

echo "[♻️] Restartowanie interfejsu vmbr0..."
ifdown vmbr0 || true
ifup vmbr0

echo "[✅ GOTOWE] vmbr0 skonfigurowany z DHCP na interfejsie $PHY_IFACE"
echo "[🧯] W razie problemów przywróć backup:"
echo "    cp $BACKUP /etc/network/interfaces"
