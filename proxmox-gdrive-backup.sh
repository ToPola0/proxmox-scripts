#!/bin/bash
set -e

CONFIG_PATH="/root/.config/rclone/rclone.conf"
MOUNT_POINT="/mnt/gdrive"
STORAGE_NAME="gdrive-backup"
STORAGE_CFG="/etc/pve/storage.cfg"
SERVICE_FILE="/etc/systemd/system/gdrive-mount.service"
BACKUP_DIR="/root/gdrive_backup_$(date +%Y%m%d%H%M%S)"

function check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "[!] Uruchom skrypt jako root."
        exit 1
    fi
}

function install_rclone() {
    if ! command -v rclone &>/dev/null; then
        echo "[*] Instaluję rclone przez apt..."
        apt update && apt install -y rclone || INSTALL_FAIL=1
        if ! command -v rclone &>/dev/null; then
            echo "[!] Instalacja przez apt nie powiodła się. Próbuję pobrać binarkę rclone..."
            curl -Of https://downloads.rclone.org/rclone-current-linux-amd64.deb
            dpkg -i rclone-current-linux-amd64.deb || true
            rm -f rclone-current-linux-amd64.deb
        fi
        if ! command -v rclone &>/dev/null && [ -x /usr/bin/rclone ]; then
            ln -sf /usr/bin/rclone /usr/local/bin/rclone
        fi
        if ! command -v rclone &>/dev/null; then
            echo "[!] Instalacja rclone nie powiodła się lub rclone nie jest w PATH!"
            echo "[i] PATH: $PATH"
            echo "[i] Dostępne pliki rclone:"
            ls -l /usr/bin/rclone 2>/dev/null || echo "Brak /usr/bin/rclone"
            ls -l /usr/local/bin/rclone 2>/dev/null || echo "Brak /usr/local/bin/rclone"
            exit 2
        fi
        echo "[+] Zainstalowano rclone."
    else
        echo "[=] rclone już zainstalowany."
    fi
}

function backup_files() {
    echo "[*] Tworzę backup plików konfiguracyjnych w $BACKUP_DIR..."
    mkdir -p "$BACKUP_DIR"
    cp "$STORAGE_CFG" "$BACKUP_DIR/" 2>/dev/null || true
    [ -f "$SERVICE_FILE" ] && cp "$SERVICE_FILE" "$BACKUP_DIR/"
}

function restore_backup() {
    echo "[!] Wystąpił błąd. Przywracam pliki z backupu..."
    [ -f "$BACKUP_DIR/storage.cfg" ] && cp "$BACKUP_DIR/storage.cfg" "$STORAGE_CFG"
    [ -f "$BACKUP_DIR/gdrive-mount.service" ] && cp "$BACKUP_DIR/gdrive-mount.service" "$SERVICE_FILE"
    systemctl daemon-reexec
    echo "[+] Przywrócono oryginalne pliki."
}

function configure_gdrive() {
    install_rclone
    echo "=== Konfiguracja Google Drive ==="
    echo "Uruchomiona zostanie konfiguracja rclone. Wybierz kolejno:"
    echo "  n (nowy remote), nazwa: gdrive, typ: drive, domyślne opcje"
    echo "  Otwórz link w przeglądarce, zaloguj się, wklej kod do terminala"
    read -p "Naciśnij Enter, aby rozpocząć konfigurację..."

    set +e
    {
        echo "========== DEBUG INFO =========="
        echo "[DEBUG] whoami: $(whoami)"
        echo "[DEBUG] pwd: $(pwd)"
        echo "[DEBUG] PATH: $PATH"
        echo "[DEBUG] SHELL: $SHELL"
        echo "[DEBUG] HOME: $HOME"
        echo "[DEBUG] env:"
        env
        echo "[DEBUG] which rclone: $(which rclone 2>&1)"
        echo "[DEBUG] type rclone: $(type rclone 2>&1)"
        echo "[DEBUG] hash rclone:"
        hash rclone 2>&1
        echo "[DEBUG] ls -l /usr/bin/rclone:"
        ls -l /usr/bin/rclone 2>&1 || echo "Brak /usr/bin/rclone"
        echo "[DEBUG] ls -l /usr/local/bin/rclone:"
        ls -l /usr/local/bin/rclone 2>&1 || echo "Brak /usr/local/bin/rclone"
        echo "[DEBUG] dpkg -l | grep rclone:"
        dpkg -l | grep rclone || echo "rclone nie jest zainstalowany wg dpkg"
        echo "[DEBUG] apt-cache policy rclone:"
        apt-cache policy rclone
        echo "[DEBUG] uname -a:"
        uname -a
        echo "[DEBUG] ldd --version:"
        ldd --version
        echo "[DEBUG] file /usr/bin/rclone:"
        file /usr/bin/rclone 2>&1 || echo "Brak /usr/bin/rclone"
        echo "[DEBUG] file /usr/local/bin/rclone:"
        file /usr/local/bin/rclone 2>&1 || echo "Brak /usr/local/bin/rclone"
        echo "[DEBUG] cat /etc/os-release:"
        cat /etc/os-release 2>&1
        echo "[DEBUG] id:"
        id
        echo "[DEBUG] ls -ld / /usr /usr/bin /usr/local /usr/local/bin"
        ls -ld / /usr /usr/bin /usr/local /usr/local/bin
        echo "[DEBUG] mount:"
        mount
        echo "[DEBUG] df -h:"
        df -h
        echo "[DEBUG] ps aux | grep rclone:"
        ps aux | grep rclone
        echo "================================"
    } >&2

    if ! command -v rclone &>/dev/null; then
        echo "[!] rclone: command not found" >&2
        exit 127
    fi
    which rclone
    rclone version || echo "[DEBUG] rclone version nie działa" >&2
    rclone config || echo "[DEBUG] rclone config nie działa" >&2
    set -e
}

function mount_gdrive() {
    install_rclone
    echo "[*] Montuję Google Drive w $MOUNT_POINT..."
    mkdir -p "$MOUNT_POINT"
    fusermount -u "$MOUNT_POINT" 2>/dev/null || true
    rclone mount gdrive:/proxmox-backup "$MOUNT_POINT" --allow-other --daemon
    echo "[+] Zamontowano."
}

function create_service() {
    install_rclone
    echo "[*] Tworzę usługę systemd..."
    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Mount Google Drive via Rclone
After=network-online.target

[Service]
ExecStart=$(which rclone) mount gdrive:/proxmox-backup $MOUNT_POINT \\
  --allow-other \\
  --dir-cache-time 72h \\
  --poll-interval 15s \\
  --umask 002 \\
  --vfs-cache-mode full \\
  --vfs-cache-max-size 1G \\
  --vfs-cache-max-age 5m
ExecStop=/bin/fusermount -u $MOUNT_POINT
Restart=always
User=root

[Install]
WantedBy=default.target
EOF

    systemctl daemon-reexec
    systemctl enable --now gdrive-mount
    echo "[+] Usługa włączona."
}

function add_to_proxmox_cfg() {
    if grep -q "$STORAGE_NAME" "$STORAGE_CFG"; then
        echo "[=] Storage '$STORAGE_NAME' już istnieje."
    else
        echo "[*] Dodaję storage do Proxmoxa..."
        cat <<EOF >> "$STORAGE_CFG"

dir: $STORAGE_NAME
    path $MOUNT_POINT
    content backup
    maxfiles 3
    prune-backups yes
EOF
        echo "[+] Dodano storage '$STORAGE_NAME'."
    fi
}

function safe_run() {
    backup_files
    trap restore_backup ERR
    "$@"
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
        echo "4. Wyjdź"
        read -p "Wybierz opcję: " opt
        case $opt in
            0) configure_gdrive ;;
            1) safe_run mount_gdrive ;;
            2) safe_run create_service ;;
            3) safe_run add_to_proxmox_cfg ;;
            4) exit 0 ;;
            *) echo "Nieprawidłowa opcja" ; sleep 1 ;;
        esac
        read -p "Naciśnij Enter, aby kontynuować..."
    done
}

check_root
menu
