#!/bin/bash

echo "🔍 Szukanie aktywnego interfejsu sieciowego..."
INTERFACE=$(ip -o -4 route show to default | awk '{print $5}')

if [ -z "$INTERFACE" ]; then
    echo "❌ Nie znaleziono interfejsu sieciowego z bramą domyślną."
    exit 1
fi

echo "✅ Wykryto interfejs: $INTERFACE"

BACKUP_FILE="/etc/network/interfaces.bak.$(date +%Y%m%d%H%M%S)"
echo "🛡️ Tworzenie kopii zapasowej: $BACKUP_FILE"
cp /etc/network/interfaces "$BACKUP_FILE"

echo "📝 Modyfikowanie pliku /etc/network/interfaces..."

cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto $INTERFACE
iface $INTERFACE inet dhcp
EOF

echo "✅ Zapisano nową konfigurację sieci (DHCP)"

read -p "🔁 Zrestartować system teraz? (t/n): " confirm
if [[ "$confirm" == "t" ]]; then
    echo "♻️ Restartowanie systemu..."
    reboot
else
    echo "ℹ️ Zmiany zostaną zastosowane po restarcie lub ręcznym restarcie interfejsu."
    echo "Możesz też użyć: ifdown $INTERFACE && ifup $INTERFACE"
fi
