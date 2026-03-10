#!/bin/bash
# ============================================
#   OGH-UDP - UDP REQUEST MANAGER
#   Binary: udpServer (OGH)
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
BIN_URL="https://github.com/chanelog/Ogh/raw/main/udpServer"
BIN_PATH="/usr/local/bin/udpServer"
BIN_OLD_PATHS=("/usr/bin/udpServer" "/opt/udpServer" "/usr/local/bin/udp-server" "/usr/local/bin/udpserver")
SERVICE_NAME="ogh-udp"
CONFIG_DIR="/etc/ogh-udp"
USER_DB="$CONFIG_DIR/users.db"
LOG_FILE="/var/log/ogh-udp.log"

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
    # Kill old processes
    pkill -f "udpServer" 2>/dev/null
    pkill -f "udp-server" 2>/dev/null
    # Remove old service
    systemctl stop ogh-udp 2>/dev/null
    systemctl disable ogh-udp 2>/dev/null
    rm -f /etc/systemd/system/ogh-udp.service
    systemctl daemon-reload
    echo -e "${GREEN}[✓] Binary lama berhasil dihapus!${NC}"
}

install_binary() {
    echo -e "${CYAN}[*] Mengunduh binary udpServer (OGH)...${NC}"
    wget -q --show-progress -O "$BIN_PATH" "$BIN_URL"
    chmod +x "$BIN_PATH"
    echo -e "${GREEN}[✓] Binary berhasil diinstal: $BIN_PATH${NC}"
}

setup_config() {
    mkdir -p "$CONFIG_DIR"
    touch "$USER_DB"
    touch "$LOG_FILE"

    if [ ! -f "$CONFIG_DIR/ogh.conf" ]; then
        cat > "$CONFIG_DIR/ogh.conf" <<EOF
PORT=1-65535
UDP_PORT=7300
LOG_LEVEL=info
MAX_CONNECTIONS=500
TIMEOUT=60
EOF
    fi
}

create_service() {
    cat > /etc/systemd/system/$SERVICE_NAME.service <<EOF
[Unit]
Description=OGH UDP Request Service
After=network.target

[Service]
Type=simple
ExecStart=$BIN_PATH
Restart=always
RestartSec=3
User=root
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
    cat > /usr/local/bin/menu <<'MENUEOF'
#!/bin/bash
/usr/local/bin/ogh-udp-menu
MENUEOF
    chmod +x /usr/local/bin/menu
}

auto_install() {
    clear
    echo -e "${CYAN}"
    echo "  ╔═══════════════════════════════════════╗"
    echo "  ║        OGH-UDP AUTO INSTALLER         ║"
    echo "  ╚═══════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${YELLOW}[*] Memulai instalasi OGH-UDP...${NC}"
    sleep 1

    install_dependencies
    remove_old_binaries
    install_binary
    setup_config
    create_service
    install_menu_script
    create_menu_command

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   ✓ OGH-UDP BERHASIL DIINSTAL!          ║${NC}"
    echo -e "${GREEN}║   Ketik: menu  →  untuk membuka menu     ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
    echo ""
}

install_menu_script() {
    cp "$0" /usr/local/bin/ogh-udp-menu
    chmod +x /usr/local/bin/ogh-udp-menu
}

# ─────────────────────────────────────────
# UTILITY FUNCTIONS
# ─────────────────────────────────────────

get_ip() {
    curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}'
}

get_isp() {
    curl -s "https://ipinfo.io/org" 2>/dev/null || echo "Unknown ISP"
}

get_location() {
    curl -s "https://ipinfo.io/city" 2>/dev/null || echo "Unknown"
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

count_online() {
    ss -tunp 2>/dev/null | grep -c "udpServer" || echo "0"
}

# ─────────────────────────────────────────
# USER MANAGEMENT
# ─────────────────────────────────────────

add_user() {
    clear
    show_logo
    echo -e "${WHITE}TAMBAH AKUN UDP-OGH${NC}"
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

    # Check duplicate
    if grep -q "^$username:" "$USER_DB" 2>/dev/null; then
        echo -e "${RED}[✗] Username sudah ada!${NC}"
        sleep 2; return
    fi

    exp_date=$(date -d "+${days} days" +"%Y-%m-%d")
    uuid=$(uuidgen)
    echo "$username:$password:$exp_date:${maxlogin:-2}:$uuid" >> "$USER_DB"
    
    ip=$(get_ip)
    clear
    show_logo
    echo -e "${GREEN}✓ AKUN BERHASIL DIBUAT${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    echo ""
    echo -e "  Username   : ${WHITE}$username${NC}"
    echo -e "  Password   : ${WHITE}$password${NC}"
    echo -e "  Expired    : ${WHITE}$exp_date${NC}"
    echo -e "  Max Login  : ${WHITE}${maxlogin:-2}${NC}"
    echo -e "  IP Server  : ${WHITE}$ip${NC}"
    echo ""
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    read -p "  Tekan ENTER untuk kembali..."
}

delete_user() {
    clear
    show_logo
    echo -e "${WHITE}HAPUS AKUN UDP-OGH${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    echo ""
    list_users_simple
    echo ""
    read -p "  Username yang akan dihapus: " username

    if grep -q "^$username:" "$USER_DB" 2>/dev/null; then
        sed -i "/^$username:/d" "$USER_DB"
        echo -e "${GREEN}[✓] User $username berhasil dihapus!${NC}"
    else
        echo -e "${RED}[✗] User tidak ditemukan!${NC}"
    fi
    sleep 2
}

check_user() {
    clear
    show_logo
    echo -e "${WHITE}CEK AKUN UDP-OGH${NC}"
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

        echo ""
        echo -e "  Username   : ${WHITE}$username${NC}"
        echo -e "  Password   : ${WHITE}$pass${NC}"
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
    echo -e "${WHITE}DAFTAR AKUN UDP-OGH${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    echo ""
    echo -e "  ${CYAN}USERNAME          EXPIRED       STATUS${NC}"
    echo -e "  $(printf '─%.0s' {1..36})"
    
    today=$(date +"%Y-%m-%d")
    today_ts=$(date -d "$today" +%s)

    if [ ! -s "$USER_DB" ]; then
        echo -e "  ${YELLOW}Belum ada akun terdaftar${NC}"
    else
        while IFS=: read -r user pass exp max uuid; do
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
    while IFS=: read -r user pass exp max uuid; do
        echo -e "  - $user (exp: $exp)"
    done < "$USER_DB"
}

renew_user() {
    clear
    show_logo
    echo -e "${WHITE}PERPANJANG AKUN UDP-OGH${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    echo ""
    list_users_simple
    echo ""
    read -p "  Username: " username
    read -p "  Tambah hari: " days

    if grep -q "^$username:" "$USER_DB" 2>/dev/null; then
        old_exp=$(grep "^$username:" "$USER_DB" | cut -d: -f3)
        new_exp=$(date -d "$old_exp +${days} days" +"%Y-%m-%d" 2>/dev/null || date -d "+${days} days" +"%Y-%m-%d")
        sed -i "s/^$username:\([^:]*\):[^:]*:/`echo $username`:\1:$new_exp:/" "$USER_DB"
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

    while IFS=: read -r user pass exp max uuid; do
        exp_ts=$(date -d "$exp" +%s 2>/dev/null)
        sisa=$(( (exp_ts - today_ts) / 86400 ))
        if [ "$sisa" -lt 0 ]; then
            sed -i "/^$user:/d" "$USER_DB"
            echo -e "  ${GREEN}[✓] Dihapus: $user${NC}"
            ((count++))
        fi
    done < <(cat "$USER_DB" 2>/dev/null)

    echo ""
    echo -e "  Total dihapus: ${WHITE}$count akun${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    sleep 2
}

# ─────────────────────────────────────────
# SERVICE MANAGEMENT
# ─────────────────────────────────────────

service_menu() {
    clear
    show_logo
    echo -e "${WHITE}KELOLA SERVICE OGH-UDP${NC}"
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
    echo -e "${YELLOW}              UDP REQUEST MANAGER v1.0${NC}"
    echo -e "${BLUE}$(printf '═%.0s' {1..54})${NC}"
}

show_info() {
    local ip=$(get_ip)
    local uptime=$(get_uptime)
    local ram=$(get_ram)
    local disk=$(get_disk)
    local users=$(count_users)
    local status=$(service_status)

    echo -e "${WHITE}  SERVER INFORMATION${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..40})${NC}"
    echo -e "  IP Server  : ${WHITE}$ip${NC}"
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
    echo -e "  ${CYAN}[ SERVICE ]${NC}"
    echo -e "  ${WHITE}7${NC}  Kelola Service"
    echo -e "  ${WHITE}8${NC}  Restart Service"
    echo ""
    echo -e "  ${RED}[ SYSTEM ]${NC}"
    echo -e "  ${WHITE}9${NC}  Update Script"
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
            8) systemctl restart $SERVICE_NAME; echo -e "${GREEN}Service direstart!${NC}"; sleep 2 ;;
            9) bash <(curl -s "https://github.com/chanelog/Ogh/raw/main/udpServer") ;;
            0) echo -e "${YELLOW}Keluar...${NC}"; exit 0 ;;
            *) echo -e "${RED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

# ─────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Script harus dijalankan sebagai root!${NC}"
    exit 1
fi

# First run = install, else menu
if [ ! -f "$BIN_PATH" ] || [ "$1" = "install" ]; then
    auto_install
    main_menu
else
    main_menu
fi
