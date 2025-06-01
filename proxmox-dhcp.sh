#!/bin/bash

# Skrypt automatycznie konfiguruje Proxmox VE do używania DHCP na vmbr0
# Wersja uniwersalna – bez ręcznych zmian

set -e

echo "[INFO] 🔍 Szukanie fizycznego interfejsu sieciowego..."

# Ignorujemy interfejsy wirtualne i wewnętrzne
PHY_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -vE 'lo|vmbr|veth|tap|br-|docker' | head -n1)

if [[ -z "$PHY_IFACE" ]]; then
    echo "[❌ BŁĄD] Nie znaleziono fizycznego interfejsu sieciowego."
    exit 1
fi

echo "[✅] Wykryto interfejs: $PHY_IFACE"

# Backup pliku
BACKUP="/etc/network/interfaces.bak.$(date +%Y%m%d%H%M%S)"
echo "[💾] Tworzenie backupu: $BACKUP"
cp /etc/network/interfaces "$BACKUP"

# Nowa konfiguracja interfaces
echo "[🛠️] Tworzenie nowego pliku /etc/network/interfaces..."

cat <<EOF > /etc/network/interfaces
auto lo
iface lo inet loopback

auto vmbr0
iface vmbr0 inet dhcp
    bridge_ports $PHY_IFACE
    bridge_stp off
    bridge_fd 0
EOF

# Restart sieci
echo "[♻️] Restartowanie sieci..."
ifdown vmbr0 || true
ifup vmbr0

echo "[✅ GOTOWE] vmbr0 skonfigurowany z DHCP na interfejsie $PHY_IFACE"
echo "[🧯] W razie problemów przywróć backup: cp $BACKUP /etc/network/interfaces"
