#!/bin/bash
# ============================================
#   OGH-UDP - ZIV UDP MANAGER
#   Binary: udp-zivpn
#   Config: config.json
#   Telegram Bot Integration
# ============================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
PURPLE='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# Config
ZIV_BIN_URL="https://github.com/fauzanihanipah/ziv-udp/releases/download/udp-zivpn/udp-zivpn-linux-amd64"
ZIV_CONFIG_URL="https://raw.githubusercontent.com/fauzanihanipah/ziv-udp/main/config.json"
BIN_PATH="/usr/local/bin/udp-zivpn"
BIN_OLD_PATHS=("/usr/bin/udp-zivpn" "/opt/udp-zivpn" "/usr/local/bin/zivpn" "/usr/bin/zivpn")
SERVICE_NAME="ziv-udp"
CONFIG_DIR="/etc/ziv-udp"
CONFIG_FILE="$CONFIG_DIR/config.json"
USER_DB="$CONFIG_DIR/users.db"
LOG_FILE="/var/log/ziv-udp.log"

# ─────────────────────────────────────────
# INSTALL FUNCTIONS
# ─────────────────────────────────────────

install_dependencies() {
    apt-get update -qq
    apt-get install -y curl wget jq net-tools iptables uuid-runtime bc -qq
}

remove_old_binaries() {
    echo -e "${YELLOW}[*] Menghapus binary lama secara permanen...${NC}"
    for path in "${BIN_OLD_PATHS[@]}"; do
        if [ -f "$path" ]; then
            rm -f "$path"
            echo -e "${GREEN}[✓] Dihapus: $path${NC}"
        fi
    done
    pkill -f "udp-zivpn" 2>/dev/null
    pkill -f "zivpn" 2>/dev/null
    systemctl stop ziv-udp 2>/dev/null
    systemctl disable ziv-udp 2>/dev/null
    rm -f /etc/systemd/system/ziv-udp.service
    systemctl daemon-reload
    echo -e "${GREEN}[✓] Binary lama berhasil dihapus!${NC}"
}

install_binary() {
    echo -e "${CYAN}[*] Mengunduh binary udp-zivpn...${NC}"
    wget -q --show-progress -O "$BIN_PATH" "$ZIV_BIN_URL"
    chmod +x "$BIN_PATH"
    echo -e "${GREEN}[✓] Binary berhasil diinstal: $BIN_PATH${NC}"
}

download_config() {
    echo -e "${CYAN}[*] Mengunduh config.json...${NC}"
    mkdir -p "$CONFIG_DIR"
    wget -q -O "$CONFIG_FILE" "$ZIV_CONFIG_URL"

    # Fallback config jika gagal download
    if [ ! -s "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" <<'EOF'
{
  "listen": ":7300",
  "timeout": 60,
  "target": "127.0.0.1:22",
  "password": "",
  "obfs": "ogh-udp",
  "up_mbps": 100,
  "down_mbps": 100,
  "auth": {
    "mode": "passwords",
    "passwords": []
  },
  "masquerade": {
    "type": "proxy",
    "proxy": {
      "url": "https://news.ycombinator.com/",
      "rewriteHost": true
    }
  }
}
EOF
        echo -e "${YELLOW}[!] Config default digunakan${NC}"
    else
        echo -e "${GREEN}[✓] Config berhasil diunduh${NC}"
    fi
}

setup_dirs() {
    mkdir -p "$CONFIG_DIR"
    touch "$USER_DB"
    touch "$LOG_FILE"
}

create_service() {
    cat > /etc/systemd/system/$SERVICE_NAME.service <<EOF
[Unit]
Description=ZIV UDP Service (OGH-UDP)
After=network.target

[Service]
Type=simple
ExecStart=$BIN_PATH server --config $CONFIG_FILE
Restart=always
RestartSec=3
User=root
WorkingDirectory=$CONFIG_DIR
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    systemctl start $SERVICE_NAME
}

create_menu_command() {
    # Only create if not already pointing to ogh-udp-menu
    cat > /usr/local/bin/menu <<'MENUEOF'
#!/bin/bash
/usr/local/bin/ziv-udp-menu
MENUEOF
    chmod +x /usr/local/bin/menu
}

install_menu_script() {
    cp "$0" /usr/local/bin/ziv-udp-menu
    chmod +x /usr/local/bin/ziv-udp-menu
}

auto_install() {
    clear
    echo -e "${CYAN}"
    echo "  ╔═══════════════════════════════════════╗"
    echo "  ║     OGH-UDP ZIV AUTO INSTALLER        ║"
    echo "  ╚═══════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${YELLOW}[*] Memulai instalasi ZIV-UDP...${NC}"
    sleep 1

    install_dependencies
    remove_old_binaries
    install_binary
    setup_dirs
    download_config
    create_service
    install_menu_script
    create_menu_command

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   ✓ ZIV-UDP BERHASIL DIINSTAL!          ║${NC}"
    echo -e "${GREEN}║   Ketik: menu  →  untuk membuka menu     ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
    echo ""
}

# ─────────────────────────────────────────
# CONFIG MANAGEMENT
# ─────────────────────────────────────────

edit_config() {
    clear
    show_logo
    echo -e "${WHITE}KONFIGURASI ZIV-UDP${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    echo ""
    echo -e "  File Config: ${WHITE}$CONFIG_FILE${NC}"
    echo ""
    
    if command -v nano &>/dev/null; then
        nano "$CONFIG_FILE"
    else
        vi "$CONFIG_FILE"
    fi
    
    systemctl restart $SERVICE_NAME
    echo -e "${GREEN}[✓] Config disimpan dan service direstart!${NC}"
    sleep 2
}

show_config() {
    clear
    show_logo
    echo -e "${WHITE}ISI CONFIG.JSON${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    echo ""
    cat "$CONFIG_FILE" 2>/dev/null || echo -e "${RED}Config tidak ditemukan!${NC}"
    echo ""
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    read -p "  Tekan ENTER untuk kembali..."
}

set_port() {
    clear
    show_logo
    echo -e "${WHITE}SET PORT ZIV-UDP${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    echo ""
    read -p "  Port baru (contoh: 7300): " port
    
    if [ -n "$port" ] && [ "$port" -eq "$port" ] 2>/dev/null; then
        if command -v jq &>/dev/null; then
            jq --arg p ":$port" '.listen = $p' "$CONFIG_FILE" > /tmp/config_tmp.json
            mv /tmp/config_tmp.json "$CONFIG_FILE"
        else
            sed -i "s/\"listen\": \":[0-9]*/\"listen\": \":$port/" "$CONFIG_FILE"
        fi
        systemctl restart $SERVICE_NAME
        echo -e "${GREEN}[✓] Port diubah ke $port dan service direstart!${NC}"
    else
        echo -e "${RED}[✗] Port tidak valid!${NC}"
    fi
    sleep 2
}

# ─────────────────────────────────────────
# USER MANAGEMENT (Update config.json)
# ─────────────────────────────────────────

get_config_passwords() {
    jq -r '.auth.passwords[]?' "$CONFIG_FILE" 2>/dev/null
}

add_user_to_config() {
    local password="$1"
    if command -v jq &>/dev/null; then
        jq --arg pwd "$password" '.auth.passwords += [$pwd]' "$CONFIG_FILE" > /tmp/cfg_tmp.json
        mv /tmp/cfg_tmp.json "$CONFIG_FILE"
    fi
}

remove_user_from_config() {
    local password="$1"
    if command -v jq &>/dev/null; then
        jq --arg pwd "$password" '.auth.passwords -= [$pwd]' "$CONFIG_FILE" > /tmp/cfg_tmp.json
        mv /tmp/cfg_tmp.json "$CONFIG_FILE"
    fi
}

add_user() {
    clear
    show_logo
    echo -e "${WHITE}TAMBAH AKUN ZIV-UDP${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    echo ""
    read -p "  Username   : " username
    read -p "  Password   : " password
    read -p "  Masa Aktif (hari): " days
    read -p "  Max Login  : " maxlogin

    if [ -z "$username" ] || [ -z "$password" ] || [ -z "$days" ]; then
        echo -e "${RED}[✗] Semua field harus diisi!${NC}"
        sleep 2; return
    fi

    if grep -q "^$username:" "$USER_DB" 2>/dev/null; then
        echo -e "${RED}[✗] Username sudah ada!${NC}"
        sleep 2; return
    fi

    exp_date=$(date -d "+${days} days" +"%Y-%m-%d")
    echo "$username:$password:$exp_date:${maxlogin:-2}" >> "$USER_DB"
    
    # Tambah ke config.json
    add_user_to_config "$password"
    systemctl restart $SERVICE_NAME

    ip=$(get_ip)
    port=$(jq -r '.listen' "$CONFIG_FILE" 2>/dev/null | tr -d ':' || echo "7300")

    clear
    show_logo
    echo -e "${GREEN}✓ AKUN ZIV-UDP BERHASIL DIBUAT${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    echo ""
    echo -e "  Username   : ${WHITE}$username${NC}"
    echo -e "  Password   : ${WHITE}$password${NC}"
    echo -e "  Expired    : ${WHITE}$exp_date${NC}"
    echo -e "  Max Login  : ${WHITE}${maxlogin:-2}${NC}"
    echo -e "  IP Server  : ${WHITE}$ip${NC}"
    echo -e "  Port       : ${WHITE}$port${NC}"
    echo -e "  Protocol   : ${WHITE}UDP/ZIV${NC}"
    echo ""
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    read -p "  Tekan ENTER untuk kembali..."
}

delete_user() {
    clear
    show_logo
    echo -e "${WHITE}HAPUS AKUN ZIV-UDP${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    echo ""
    list_users_simple
    echo ""
    read -p "  Username yang akan dihapus: " username

    if grep -q "^$username:" "$USER_DB" 2>/dev/null; then
        pass=$(grep "^$username:" "$USER_DB" | cut -d: -f2)
        sed -i "/^$username:/d" "$USER_DB"
        remove_user_from_config "$pass"
        systemctl restart $SERVICE_NAME
        echo -e "${GREEN}[✓] User $username berhasil dihapus!${NC}"
    else
        echo -e "${RED}[✗] User tidak ditemukan!${NC}"
    fi
    sleep 2
}

check_user() {
    clear
    show_logo
    echo -e "${WHITE}CEK AKUN ZIV-UDP${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    echo ""
    read -p "  Username: " username

    if grep -q "^$username:" "$USER_DB" 2>/dev/null; then
        line=$(grep "^$username:" "$USER_DB")
        pass=$(echo $line | cut -d: -f2)
        exp=$(echo $line | cut -d: -f3)
        max=$(echo $line | cut -d: -f4)
        
        today=$(date +"%Y-%m-%d")
        exp_ts=$(date -d "$exp" +%s 2>/dev/null)
        today_ts=$(date -d "$today" +%s)
        sisa=$(( (exp_ts - today_ts) / 86400 ))

        ip=$(get_ip)
        port=$(jq -r '.listen' "$CONFIG_FILE" 2>/dev/null | tr -d ':' || echo "7300")

        echo ""
        echo -e "  Username   : ${WHITE}$username${NC}"
        echo -e "  Password   : ${WHITE}$pass${NC}"
        echo -e "  IP Server  : ${WHITE}$ip${NC}"
        echo -e "  Port       : ${WHITE}$port${NC}"
        echo -e "  Expired    : ${WHITE}$exp${NC}"
        echo -e "  Sisa Hari  : ${WHITE}$sisa hari${NC}"
        echo -e "  Max Login  : ${WHITE}$max${NC}"
        
        if [ "$sisa" -lt 0 ]; then
            echo -e "  Status     : ${RED}EXPIRED${NC}"
        else
            echo -e "  Status     : ${GREEN}AKTIF${NC}"
        fi
    else
        echo -e "${RED}[✗] User tidak ditemukan!${NC}"
    fi
    echo ""
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    read -p "  Tekan ENTER untuk kembali..."
}

list_users() {
    clear
    show_logo
    echo -e "${WHITE}DAFTAR AKUN ZIV-UDP${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    echo ""
    echo -e "  ${CYAN}USERNAME          EXPIRED       STATUS${NC}"
    echo -e "  $(printf '─%.0s' {1..36})"
    
    today=$(date +"%Y-%m-%d")
    today_ts=$(date -d "$today" +%s)

    if [ ! -s "$USER_DB" ]; then
        echo -e "  ${YELLOW}Belum ada akun terdaftar${NC}"
    else
        while IFS=: read -r user pass exp max; do
            exp_ts=$(date -d "$exp" +%s 2>/dev/null)
            sisa=$(( (exp_ts - today_ts) / 86400 ))
            if [ "$sisa" -lt 0 ]; then
                status="${RED}EXPIRED${NC}"
            else
                status="${GREEN}AKTIF${NC}"
            fi
            printf "  %-16s %-12s %b\n" "$user" "$exp" "$status"
        done < "$USER_DB"
    fi
    echo ""
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    read -p "  Tekan ENTER untuk kembali..."
}

list_users_simple() {
    if [ ! -s "$USER_DB" ]; then
        echo -e "  ${YELLOW}Belum ada akun${NC}"
        return
    fi
    while IFS=: read -r user pass exp max; do
        echo -e "  - $user (exp: $exp)"
    done < "$USER_DB"
}

renew_user() {
    clear
    show_logo
    echo -e "${WHITE}PERPANJANG AKUN ZIV-UDP${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    echo ""
    list_users_simple
    echo ""
    read -p "  Username: " username
    read -p "  Tambah hari: " days

    if grep -q "^$username:" "$USER_DB" 2>/dev/null; then
        old_exp=$(grep "^$username:" "$USER_DB" | cut -d: -f3)
        today=$(date +"%Y-%m-%d")
        today_ts=$(date -d "$today" +%s)
        exp_ts=$(date -d "$old_exp" +%s 2>/dev/null)
        sisa=$(( (exp_ts - today_ts) / 86400 ))
        
        if [ "$sisa" -lt 0 ]; then
            new_exp=$(date -d "+${days} days" +"%Y-%m-%d")
        else
            new_exp=$(date -d "$old_exp +${days} days" +"%Y-%m-%d")
        fi
        
        sed -i "s/^$username:\([^:]*\):[^:]*:\([^:]*\)/$username:\1:$new_exp:\2/" "$USER_DB"
        echo -e "${GREEN}[✓] Akun $username diperpanjang sampai $new_exp${NC}"
    else
        echo -e "${RED}[✗] User tidak ditemukan!${NC}"
    fi
    sleep 2
}

delete_expired() {
    clear
    show_logo
    echo -e "${WHITE}HAPUS AKUN EXPIRED${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    echo ""
    today=$(date +"%Y-%m-%d")
    today_ts=$(date -d "$today" +%s)
    count=0

    while IFS=: read -r user pass exp max; do
        exp_ts=$(date -d "$exp" +%s 2>/dev/null)
        sisa=$(( (exp_ts - today_ts) / 86400 ))
        if [ "$sisa" -lt 0 ]; then
            sed -i "/^$user:/d" "$USER_DB"
            remove_user_from_config "$pass"
            echo -e "  ${GREEN}[✓] Dihapus: $user${NC}"
            ((count++))
        fi
    done < <(cat "$USER_DB" 2>/dev/null)

    [ "$count" -gt 0 ] && systemctl restart $SERVICE_NAME

    echo ""
    echo -e "  Total dihapus: ${WHITE}$count akun${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    sleep 2
}

# ─────────────────────────────────────────
# UTILITY
# ─────────────────────────────────────────

get_ip() {
    curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}'
}

service_status() {
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "${GREEN}● RUNNING${NC}"
    else
        echo -e "${RED}● STOPPED${NC}"
    fi
}

get_uptime() {
    uptime -p 2>/dev/null || uptime
}

get_ram() {
    free -h | awk '/^Mem:/ {print $3"/"$2}'
}

get_disk() {
    df -h / | awk 'NR==2 {print $3"/"$2}'
}

count_users() {
    [ -f "$USER_DB" ] && wc -l < "$USER_DB" || echo "0"
}

service_menu() {
    clear
    show_logo
    echo -e "${WHITE}KELOLA SERVICE ZIV-UDP${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    echo ""
    echo -e "  Status   : $(service_status)"
    echo ""
    echo -e "  ${WHITE}1${NC} Start Service"
    echo -e "  ${WHITE}2${NC} Stop Service"
    echo -e "  ${WHITE}3${NC} Restart Service"
    echo -e "  ${WHITE}4${NC} Lihat Log"
    echo -e "  ${WHITE}0${NC} Kembali"
    echo ""
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    read -p "  Pilihan: " opt
    case $opt in
        1) systemctl start $SERVICE_NAME && echo -e "${GREEN}Service dijalankan!${NC}" ;;
        2) systemctl stop $SERVICE_NAME && echo -e "${YELLOW}Service dihentikan!${NC}" ;;
        3) systemctl restart $SERVICE_NAME && echo -e "${GREEN}Service direstart!${NC}" ;;
        4) tail -50 "$LOG_FILE"; read -p "Enter..." ;;
        0) return ;;
    esac
    sleep 2
}

# ─────────────────────────────────────────
# DISPLAY
# ─────────────────────────────────────────

show_logo() {
    echo -e "${CYAN}"
    echo "   ██████╗  ██████╗ ██╗  ██╗    ██╗   ██╗██████╗ ██████╗ "
    echo "  ██╔═══██╗██╔════╝ ██║  ██║    ██║   ██║██╔══██╗██╔══██╗"
    echo "  ██║   ██║██║  ███╗███████║    ██║   ██║██║  ██║██████╔╝"
    echo "  ██║   ██║██║   ██║██╔══██║    ██║   ██║██║  ██║██╔═══╝ "
    echo "  ╚██████╔╝╚██████╔╝██║  ██║    ╚██████╔╝██████╔╝██║     "
    echo "   ╚═════╝  ╚═════╝ ╚═╝  ╚═╝     ╚═════╝ ╚═════╝ ╚═╝     "
    echo -e "${NC}"
    echo -e "${PURPLE}              ZIV-UDP MANAGER v1.0${NC}"
    echo -e "${BLUE}$(printf '═%.0s' {1..54})${NC}"
}

show_info() {
    local ip=$(get_ip)
    local port=$(jq -r '.listen' "$CONFIG_FILE" 2>/dev/null | tr -d ':' || echo "7300")
    local uptime=$(get_uptime)
    local ram=$(get_ram)
    local disk=$(get_disk)
    local users=$(count_users)
    local status=$(service_status)

    echo -e "${WHITE}  SERVER INFORMATION${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    echo -e "  IP Server  : ${WHITE}$ip${NC}"
    echo -e "  Port ZIV   : ${WHITE}$port${NC}"
    echo -e "  Uptime     : ${WHITE}$uptime${NC}"
    echo -e "  RAM        : ${WHITE}$ram${NC}"
    echo -e "  Disk       : ${WHITE}$disk${NC}"
    echo -e "  Total Akun : ${WHITE}$users${NC}"
    echo -e "  Service    : $status"
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
}

show_main_menu() {
    echo ""
    echo -e "${WHITE}  MENU UTAMA${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    echo ""
    echo -e "  ${GREEN}[ MANAJEMEN AKUN ]${NC}"
    echo -e "  ${WHITE}1${NC}  Tambah Akun"
    echo -e "  ${WHITE}2${NC}  Hapus Akun"
    echo -e "  ${WHITE}3${NC}  Cek Akun"
    echo -e "  ${WHITE}4${NC}  Daftar Akun"
    echo -e "  ${WHITE}5${NC}  Perpanjang Akun"
    echo -e "  ${WHITE}6${NC}  Hapus Akun Expired"
    echo ""
    echo -e "  ${CYAN}[ SERVICE & CONFIG ]${NC}"
    echo -e "  ${WHITE}7${NC}  Kelola Service"
    echo -e "  ${WHITE}8${NC}  Edit Config"
    echo -e "  ${WHITE}9${NC}  Lihat Config"
    echo -e "  ${WHITE}10${NC} Set Port"
    echo ""
    echo -e "  ${RED}[ SYSTEM ]${NC}"
    echo -e "  ${WHITE}0${NC}  Keluar"
    echo ""
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
}

main_menu() {
    while true; do
        clear
        show_logo
        show_info
        show_main_menu
        read -p "  Pilihan: " opt
        case $opt in
            1) add_user ;;
            2) delete_user ;;
            3) check_user ;;
            4) list_users ;;
            5) renew_user ;;
            6) delete_expired ;;
            7) service_menu ;;
            8) edit_config ;;
            9) show_config ;;
            10) set_port ;;
            0) echo -e "${YELLOW}Keluar...${NC}"; exit 0 ;;
            *) echo -e "${RED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

# ─────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Script harus dijalankan sebagai root!${NC}"
    exit 1
fi

if [ ! -f "$BIN_PATH" ] || [ "$1" = "install" ]; then
    auto_install
    main_menu
else
    main_menu
fi
