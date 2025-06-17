\#!/bin/bash
set -e

CONFIG\_PATH="/root/.config/rclone/rclone.conf"
MOUNT\_POINT="/mnt/gdrive"
STORAGE\_NAME="gdrive-backup"
STORAGE\_CFG="/etc/pve/storage.cfg"
SERVICE\_FILE="/etc/systemd/system/gdrive-mount.service"
BACKUP\_DIR="/root/gdrive\_backup\_\$(date +%Y%m%d%H%M%S)"

function check\_root() {
if \[ "\$EUID" -ne 0 ]; then
echo "\[!] Uruchom skrypt jako root."
exit 1
fi
}

function install\_rclone() {
if ! command -v rclone &>/dev/null; then
echo "\[\*] Instaluję rclone..."
apt update && apt install -y rclone
echo "\[+] Zainstalowano rclone."
else
echo "\[=] rclone już zainstalowany."
fi
}

function backup\_files() {
echo "\[\*] Tworzę backup plików konfiguracyjnych w \$BACKUP\_DIR..."
mkdir -p "\$BACKUP\_DIR"
cp "\$STORAGE\_CFG" "\$BACKUP\_DIR/" 2>/dev/null || true
\[ -f "\$SERVICE\_FILE" ] && cp "\$SERVICE\_FILE" "\$BACKUP\_DIR/"
}

function restore\_backup() {
echo "\[!] Wystąpił błąd. Przywracam pliki z backupu..."
\[ -f "\$BACKUP\_DIR/storage.cfg" ] && cp "\$BACKUP\_DIR/storage.cfg" "\$STORAGE\_CFG"
\[ -f "\$BACKUP\_DIR/gdrive-mount.service" ] && cp "\$BACKUP\_DIR/gdrive-mount.service" "\$SERVICE\_FILE"
systemctl daemon-reexec
echo "\[+] Przywrócono oryginalne pliki."
}

function configure\_gdrive() {
echo "=== Konfiguracja Google Drive ==="
echo "Uruchomiona zostanie konfiguracja rclone. Wybierz kolejno:"
echo "  n (nowy remote), nazwa: gdrive, typ: drive, domyślne opcje"
echo "  Otwórz link w przeglądarce, zaloguj się, wklej kod do terminala"
read -p "Naciśnij Enter, aby rozpocząć konfigurację..."
rclone config
}

function mount\_gdrive() {
echo "\[\*] Montuję Google Drive w \$MOUNT\_POINT..."
mkdir -p "\$MOUNT\_POINT"
fusermount -u "\$MOUNT\_POINT" 2>/dev/null || true
rclone mount gdrive:/proxmox-backup "\$MOUNT\_POINT" --allow-other --daemon
echo "\[+] Zamontowano."
}

function create\_service() {
echo "\[\*] Tworzę usługę systemd..."
cat <<EOF > "\$SERVICE\_FILE"
\[Unit]
Description=Mount Google Drive via Rclone
After=network-online.target

\[Service]
ExecStart=/usr/bin/rclone mount gdrive:/proxmox-backup \$MOUNT\_POINT \\
\--allow-other \\
\--dir-cache-time 72h \\
\--poll-interval 15s \\
\--umask 002 \\
\--vfs-cache-mode full \\
\--vfs-cache-max-size 1G \\
\--vfs-cache-max-age 5m
ExecStop=/bin/fusermount -u \$MOUNT\_POINT
Restart=always
User=root

\[Install]
WantedBy=default.target
EOF

```
systemctl daemon-reexec
systemctl enable --now gdrive-mount
echo "[+] Usługa włączona."
```

}

function add\_to\_proxmox\_cfg() {
if grep -q "\$STORAGE\_NAME" "\$STORAGE\_CFG"; then
echo "\[=] Storage '\$STORAGE\_NAME' już istnieje."
else
echo "\[\*] Dodaję storage do Proxmoxa..."
echo "\ndir: \$STORAGE\_NAME
path \$MOUNT\_POINT
content backup
maxfiles 3
prune-backups yes" >> "\$STORAGE\_CFG"
echo "\[+] Dodano storage '\$STORAGE\_NAME'."
fi
}

function uninstall\_all() {
echo "\[!] Odinstalowuję konfigurację GDrive..."
systemctl stop gdrive-mount 2>/dev/null || true
systemctl disable gdrive-mount 2>/dev/null || true
rm -f "\$SERVICE\_FILE"
sed -i "/^dir: \$STORAGE\_NAME/,/^\$/d" "\$STORAGE\_CFG"
fusermount -u "\$MOUNT\_POINT" 2>/dev/null || true
umount "\$MOUNT\_POINT" 2>/dev/null || true
rm -rf "\$MOUNT\_POINT"
echo "\[+] Usunięto usługę, storage i montowanie."
}

function safe\_run() {
backup\_files
trap restore\_backup ERR
"\$@"
trap - ERR
}

function menu() {
while true; do
clear
echo "=== Instalator Google Drive dla Proxmoxa ==="
echo "0. Skonfiguruj Google Drive (rclone config)"
echo "1. Montuj GDrive"
echo "2. Utwórz usługę systemd (automatyczny montaż)"
echo "3. Dodaj storage do Proxmoxa"
echo "4. Odinstaluj wszystko"
echo "5. Wyjdź"
read -p "Wybierz opcję: " opt
case \$opt in
0\) configure\_gdrive ;;
1\) safe\_run mount\_gdrive ;;
2\) safe\_run create\_service ;;
3\) safe\_run add\_to\_proxmox\_cfg ;;
4\) safe\_run uninstall\_all ;;
5\) exit 0 ;;
\*) echo "Nieprawidłowa opcja" ; sleep 1 ;;
esac
read -p "Naciśnij Enter, aby kontynuować..."
done
}

check\_root
install\_rclone
menu
