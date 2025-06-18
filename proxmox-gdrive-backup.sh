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

echo "=== Testowanie katalogu montowania ==="
# Jeśli katalog nie istnieje, utwórz go
if [ ! -d /mnt/gdrive ]; then
    mkdir -p /mnt/gdrive
fi

echo "=== Testowe montowanie Google Drive ==="
# Sprawdź, czy /mnt/gdrive jest już zamontowany przez FUSE/rclone (i czy jest aktywna sesja rclone/fuse)
if mountpoint -q /mnt/gdrive || grep -q '/mnt/gdrive' /proc/mounts || lsof +D /mnt/gdrive | grep -q rclone; then
    echo "Katalog /mnt/gdrive jest już zamontowany lub używany. Pomijam testowe montowanie."
    # Odmontuj jeśli jest zamontowany (opcjonalnie, wymuszenie czystości przed systemd)
    fusermount -uz /mnt/gdrive 2>/dev/null || true
else
    rclone mount gdrive:proxmox-backup /mnt/gdrive --daemon --allow-other
    sleep 5
    echo "Zawartość /mnt/gdrive:"
    ls /mnt/gdrive || { echo "Błąd: nie udało się uzyskać dostępu do /mnt/gdrive."; exit 1; }
    # Odmontuj po teście
    fusermount -uz /mnt/gdrive
fi

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
STORAGE_NAME="gdrive-backup"
STORAGE_PATH="/mnt/gdrive"
NODE_NAME=$(hostname)
STORAGE_CFG="/etc/pve/storage.cfg"

# Backup
if [ -f "$STORAGE_CFG" ]; then
    cp "$STORAGE_CFG" "$STORAGE_CFG.backup_$(date +%F_%T)"
fi

# Usuń stary wpis jeśli istnieje (żeby nie dublować)
sed -i "/^dir: $STORAGE_NAME/,/^\S/ d" "$STORAGE_CFG"

# Dodaj poprawny wpis
cat <<EOF >> "$STORAGE_CFG"

dir: $STORAGE_NAME
    path $STORAGE_PATH
    content backup
    maxfiles 3
    nodes $NODE_NAME
    enable 1
EOF

echo "Storage '$STORAGE_NAME' został dodany z pełną konfiguracją."

echo "=== Ustawienia FUSE ==="
# Odkomentuj user_allow_other w /etc/fuse.conf
if grep -q "^#user_allow_other" /etc/fuse.conf; then
    sed -i 's/^#\(user_allow_other\)/\1/' /etc/fuse.conf
fi

echo "Instalacja zakończona. Usługa gdrive-mount została uruchomiona i zamontowała Google Drive w /mnt/gdrive."
