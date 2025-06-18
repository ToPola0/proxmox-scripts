#!/bin/bash
set -euo pipefail

# Sprawdź, czy uruchomiono jako root
if [ "$(id -u)" -ne 0 ]; then
    echo "Błąd: skrypt musi być uruchomiony jako root." >&2
    exit 1
fi

echo "=== Instalacja rclone ==="
# Instalacja rclone z repozytorium lub oficjalnego skryptu
if ! command -v rclone >/dev/null 2>&1; then
    apt-get update -qq
    if ! apt-get install -y rclone; then
        echo "Instalacja z repozytorium nie powiodła się. Pobieram oficjalny skrypt instalacyjny rclone..."
        curl -s https://rclone.org/install.sh | bash
    fi
fi

echo "=== Konfiguracja rclone ==="
echo "Uruchom kreator rclone config i skonfiguruj Google Drive (podaj nazwę remote, np. 'gdrive')."
rclone config

echo "=== Tworzenie punktu montowania ==="
mkdir -p /mnt/gdrive

echo "=== Testowe montowanie Google Drive ==="
# Montuj na chwilę i sprawdź
rclone mount gdrive:proxmox-backup /mnt/gdrive --daemon --allow-other
sleep 5
echo "Zawartość /mnt/gdrive:"
ls /mnt/gdrive || { echo "Błąd: nie udało się uzyskać dostępu do /mnt/gdrive."; exit 1; }
# Odmontuj po teście
fusermount -uz /mnt/gdrive

echo "=== Konfiguracja systemd ==="
# Plik usługi systemd
cat <<EOF > /etc/systemd/system/gdrive-mount.service
[Unit]
Description=Mount Google Drive at /mnt/gdrive
Wants=network-online.target
After=network-online.target

[Service]
Type=notify
User=root
Environment=RCLONE_CONFIG=/root/.config/rclone/rclone.conf
ExecStart=/usr/bin/rclone mount gdrive:proxmox-backup /mnt/gdrive \\
    --allow-other \\
    --dir-cache-time 12h \\
    --vfs-cache-mode minimal \\
    --vfs-cache-max-size 100M
ExecStop=/bin/fusermount -uz /mnt/gdrive
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Włącz i uruchom usługę
systemctl daemon-reload
systemctl enable gdrive-mount.service
systemctl start gdrive-mount.service

echo "=== Konfiguracja Proxmox storage ==="
# Backup pliku storage.cfg
if [ -f /etc/pve/storage.cfg ]; then
    cp /etc/pve/storage.cfg "/etc/pve/storage.cfg.backup_$(date +%F_%T)"
fi
# Dodaj wpis, jeśli nie istnieje
if ! grep -q "^dir: gdrive-backup" /etc/pve/storage.cfg; then
    cat <<EOC >> /etc/pve/storage.cfg
dir: gdrive-backup
    path /mnt/gdrive
    content backup
EOC
fi

# Dodanie storage do Proxmoxa (wersja z parametrami: maxfiles, nodes, enable)
STORAGE_NAME="gdrive"
STORAGE_PATH="/mnt/gdrive"
NODE_NAME=$(hostname)
STORAGE_CFG="/etc/pve/storage.cfg"

# Sprawdź, czy storage już istnieje (nowy format)
if grep -Eq "^\s*dir\s+$STORAGE_NAME" "$STORAGE_CFG"; then
    echo "Storage '$STORAGE_NAME' już istnieje w $STORAGE_CFG."
else
    echo "Dodaję storage '$STORAGE_NAME' do $STORAGE_CFG..."

    cat <<EOF >> "$STORAGE_CFG"

dir $STORAGE_NAME
    path $STORAGE_PATH
    content backup
    maxfiles 3
    nodes $NODE_NAME
    enable 1
EOF

    echo "Storage '$STORAGE_NAME' został dodany."
fi

echo "=== Ustawienia FUSE ==="
# Odkomentuj user_allow_other w /etc/fuse.conf
if grep -q "^#user_allow_other" /etc/fuse.conf; then
    sed -i 's/^#\(user_allow_other\)/\1/' /etc/fuse.conf
fi

echo "Instalacja zakończona. Usługa gdrive-mount została uruchomiona i zamontowała Google Drive w /mnt/gdrive."
