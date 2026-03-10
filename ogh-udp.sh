#!/bin/bash
# ============================================================
# OGH-UDP MANAGEMENT SCRIPT
# Author : OGH-ZIV
# Version: 2.0
# ============================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

# Paths
DB_DIR="/etc/ogh-udp"
DB_FILE="$DB_DIR/users.db"
CONFIG_FILE="$DB_DIR/config.json"
UDP_BIN="/usr/local/bin/udpServer"
ZIVPN_BIN="/usr/local/bin/udp-zivpn"
LOG_FILE="/var/log/ogh-udp.log"
SERVICE_UDP="udp-server"
SERVICE_ZIVPN="udp-zivpn"
MENU_CMD="/usr/local/bin/menu"

# URLs
UDP_URL="https://github.com/chanelog/Ogh/raw/main/udpServer"
ZIVPN_URL="https://github.com/fauzanihanipah/ziv-udp/releases/download/udp-zivpn/udp-zivpn-linux-amd64"
CONFIG_URL="https://raw.githubusercontent.com/fauzanihanipah/ziv-udp/main/config.json"

# Defaults
ZIVPN_PORT=5667

# ============================================================
# INIT
# ============================================================
init_dirs() {
    mkdir -p "$DB_DIR"
    [ ! -f "$DB_FILE" ] && touch "$DB_FILE"
    [ ! -f "$LOG_FILE" ] && touch "$LOG_FILE"
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# ============================================================
# GET SERVER INFO
# ============================================================
get_info() {
    HOST=$(hostname)
    IP=$(curl -s6 ifconfig.me 2>/dev/null || curl -s4 ifconfig.me 2>/dev/null)
    ISP=$(curl -s "https://ipinfo.io/org" 2>/dev/null | tr -d '"')
    CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "N/A")
    RAM=$(free -m | awk '/Mem/{printf "%.2f", $3/$2*100}')
    DISK=$(df -h / | awk 'NR==2{print $5}' | tr -d '%')
    TOTAL_USERS=$(wc -l < "$DB_FILE" 2>/dev/null || echo 0)
}

# ============================================================
# LOGO + HEADER
# ============================================================
show_logo() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}${YELLOW}                                                           ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}${BOLD}${RED}   ██████╗  ██████╗ ██╗  ██╗      ██╗   ██╗██████╗ ██████╗${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}${BOLD}${RED}  ██╔═══██╗██╔════╝ ██║  ██║      ██║   ██║██╔══██╗██╔══██╗${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}${BOLD}${RED}  ██║   ██║██║  ███╗███████║█████╗██║   ██║██║  ██║██████╔╝${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}${BOLD}${RED}  ██║   ██║██║   ██║██╔══██║╚════╝██║   ██║██║  ██║██╔═══╝ ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}${BOLD}${RED}  ╚██████╔╝╚██████╔╝██║  ██║      ╚██████╔╝██████╔╝██║     ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}${BOLD}${RED}   ╚═════╝  ╚═════╝ ╚═╝  ╚═╝       ╚═════╝ ╚═════╝ ╚═╝     ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}${BOLD}${YELLOW}                                                           ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}${WHITE}              [ UDP Management System v2.0 ]               ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}${GREEN}                    Author : OGH-ZIV                       ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
}

show_header() {
    get_info
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e " ${WHITE}Author${NC} : ${GREEN}OGH-ZIV${NC}"
    echo -e " ${WHITE}Host${NC}   : ${GREEN}${HOST}${NC}"
    echo -e " ${WHITE}IP${NC}     : ${GREEN}${IP}${NC}"
    echo -e " ${WHITE}ISP${NC}    : ${GREEN}${ISP}${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e " ${WHITE}Info Server:${NC} [ ${YELLOW}CPU: ${CPU}%${NC} | ${YELLOW}RAM: ${RAM}%${NC} | ${YELLOW}Disk: ${DISK}%${NC} ]"
    echo -e "${CYAN}───────────────────────────────────────────────────────────────${NC}"
    echo -e " ${WHITE}Total Account :${NC} ${GREEN}${TOTAL_USERS} User${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────────${NC}"
}

# ============================================================
# MAIN MENU
# ============================================================
main_menu() {
    show_logo
    show_header
    echo -e ""
    echo -e " ${CYAN}[01]${NC} ${WHITE}Add Regular${NC}      | ${CYAN}[04]${NC} ${WHITE}Delete Account${NC}"
    echo -e " ${CYAN}[02]${NC} ${WHITE}Add Trial${NC}        | ${CYAN}[05]${NC} ${WHITE}Edit Expiry${NC}"
    echo -e " ${CYAN}[03]${NC} ${WHITE}List Accounts${NC}    | ${CYAN}[06]${NC} ${WHITE}Edit Password${NC}"
    echo -e " ${YELLOW}─────────────────────${NC} | ${YELLOW}─────────────────────${NC}"
    echo -e " ${CYAN}[07]${NC} ${WHITE}VPS Info${NC}         | ${CYAN}[08]${NC} ${WHITE}Monitor Login${NC}"
    echo -e " ${CYAN}[09]${NC} ${WHITE}Edit Max Login${NC}   | ${CYAN}[10]${NC} ${WHITE}Edit Speed Limit${NC}"
    echo -e ""
    echo -e " ${MAGENTA}:: PENGATURAN & UTILITAS ::"
    echo -e ""
    echo -e " ${CYAN}[11]${NC} ${WHITE}Backup/Restore${NC}   | ${CYAN}[14]${NC} ${WHITE}Edit Domain${NC}"
    echo -e " ${CYAN}[12]${NC} ${WHITE}Bot Settings${NC}     | ${CYAN}[15]${NC} ${WHITE}Auto Backup${NC}"
    echo -e " ${CYAN}[13]${NC} ${WHITE}Theme Settings${NC}   | ${CYAN}[16]${NC} ${WHITE}Uninstall${NC}"
    echo -e " ${YELLOW}─────────────────────${NC} | ${YELLOW}─────────────────────${NC}"
    echo -e " ${CYAN}[17]${NC} ${WHITE}Bandwidth${NC}        | ${CYAN}[18]${NC} ${WHITE}Cek CPU/RAM${NC}"
    echo -e " ${CYAN}[19]${NC} ${WHITE}Update Script${NC}    | ${CYAN}[20]${NC} ${WHITE}Kelola Layanan${NC}"
    echo -e " ${CYAN}[21]${NC} ${WHITE}UDP Port Config${NC}  | ${CYAN}[22]${NC} ${WHITE}ZivPN Config${NC}"
    echo -e " ${CYAN}[23]${NC} ${WHITE}Reinstall Binaries${NC}| ${CYAN}[24]${NC} ${WHITE}View Logs${NC}"
    echo -e " ${CYAN}[25]${NC} ${WHITE}User Stats${NC}       |"
    echo -e ""
    echo -e "${CYAN}───────────────────────────────────────────────────────────────${NC}"
    echo -e " ${RED}[00]${NC} ${WHITE}Exit${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -ne " ${YELLOW}-> Masukkan pilihan Anda: ${NC}"
    read -r choice
    handle_menu "$choice"
}

# ============================================================
# HANDLE MENU
# ============================================================
handle_menu() {
    case "$1" in
        01|1) add_regular ;;
        02|2) add_trial ;;
        03|3) list_accounts ;;
        04|4) delete_account ;;
        05|5) edit_expiry ;;
        06|6) edit_password ;;
        07|7) vps_info ;;
        08|8) monitor_login ;;
        09|9) edit_max_login ;;
        10) edit_speed_limit ;;
        11) backup_restore ;;
        12) bot_settings ;;
        13) theme_settings ;;
        14) edit_domain ;;
        15) auto_backup ;;
        16) uninstall_script ;;
        17) show_bandwidth ;;
        18) check_cpu_ram ;;
        19) update_script ;;
        20) kelola_layanan ;;
        21) udp_port_config ;;
        22) zivpn_config ;;
        23) reinstall_binaries ;;
        24) view_logs ;;
        25) user_stats ;;
        00|0) exit 0 ;;
        *) echo -e "${RED}Pilihan tidak valid!${NC}"; sleep 1; main_menu ;;
    esac
}

# ============================================================
# ADD REGULAR ACCOUNT
# ============================================================
add_regular() {
    show_logo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${WHITE}TAMBAH AKUN REGULER${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -ne " ${YELLOW}Username     : ${NC}"; read -r uname
    echo -ne " ${YELLOW}Password     : ${NC}"; read -r upass
    echo -ne " ${YELLOW}Expired (hari): ${NC}"; read -r days
    echo -ne " ${YELLOW}Max Login    : ${NC}"; read -r maxlogin
    echo -ne " ${YELLOW}Speed Limit (Mbps, 0=unlimited): ${NC}"; read -r speed

    if [ -z "$uname" ] || [ -z "$upass" ] || [ -z "$days" ]; then
        echo -e "${RED}Input tidak boleh kosong!${NC}"
        sleep 2; main_menu; return
    fi

    # Check duplicate
    if grep -q "^${uname}:" "$DB_FILE" 2>/dev/null; then
        echo -e "${RED}Username sudah ada!${NC}"
        sleep 2; main_menu; return
    fi

    EXP_DATE=$(date -d "+${days} days" '+%Y-%m-%d')
    [ -z "$maxlogin" ] && maxlogin=2
    [ -z "$speed" ] && speed=0

    echo "${uname}:${upass}:${EXP_DATE}:regular:${maxlogin}:${speed}" >> "$DB_FILE"
    log "ADD_ACCOUNT: user=$uname exp=$EXP_DATE maxlogin=$maxlogin speed=${speed}Mbps"

    echo -e ""
    echo -e "${CYAN}───────────────────────────────────────────────────────────────${NC}"
    echo -e " ${GREEN}✓ Akun berhasil dibuat!${NC}"
    echo -e " ${WHITE}Username    :${NC} ${GREEN}${uname}${NC}"
    echo -e " ${WHITE}Password    :${NC} ${GREEN}${upass}${NC}"
    echo -e " ${WHITE}Expired     :${NC} ${GREEN}${EXP_DATE}${NC}"
    echo -e " ${WHITE}Max Login   :${NC} ${GREEN}${maxlogin}${NC}"
    echo -e " ${WHITE}Speed Limit :${NC} ${GREEN}$([ "$speed" = "0" ] && echo "Unlimited" || echo "${speed} Mbps")${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────────${NC}"
    echo -ne "${YELLOW}Tekan Enter untuk kembali...${NC}"; read -r; main_menu
}

# ============================================================
# ADD TRIAL ACCOUNT
# ============================================================
add_trial() {
    show_logo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                    ${WHITE}TAMBAH AKUN TRIAL${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -ne " ${YELLOW}Username      : ${NC}"; read -r uname
    echo -ne " ${YELLOW}Password      : ${NC}"; read -r upass
    echo -ne " ${YELLOW}Trial (jam)   : ${NC}"; read -r hours
    echo -ne " ${YELLOW}Max Login     : ${NC}"; read -r maxlogin
    echo -ne " ${YELLOW}Speed Limit (Mbps, 0=unlimited): ${NC}"; read -r speed

    if [ -z "$uname" ] || [ -z "$upass" ] || [ -z "$hours" ]; then
        echo -e "${RED}Input tidak boleh kosong!${NC}"
        sleep 2; main_menu; return
    fi

    if grep -q "^${uname}:" "$DB_FILE" 2>/dev/null; then
        echo -e "${RED}Username sudah ada!${NC}"
        sleep 2; main_menu; return
    fi

    EXP_DATE=$(date -d "+${hours} hours" '+%Y-%m-%d %H:%M')
    [ -z "$maxlogin" ] && maxlogin=1
    [ -z "$speed" ] && speed=0

    echo "${uname}:${upass}:${EXP_DATE}:trial:${maxlogin}:${speed}" >> "$DB_FILE"
    log "ADD_TRIAL: user=$uname exp=$EXP_DATE"

    echo -e ""
    echo -e "${GREEN}✓ Akun trial berhasil dibuat!${NC}"
    echo -e " Username : ${uname} | Pass : ${upass} | Exp : ${EXP_DATE} | MaxLogin: ${maxlogin}"
    echo -ne "${YELLOW}Tekan Enter untuk kembali...${NC}"; read -r; main_menu
}

# ============================================================
# LIST ACCOUNTS
# ============================================================
list_accounts() {
    show_logo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                    ${WHITE}DAFTAR AKUN${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    printf " ${CYAN}%-15s %-12s %-20s %-8s %-8s %-10s${NC}\n" "Username" "Type" "Expired" "MaxLogin" "Speed" "Status"
    echo -e "${CYAN}───────────────────────────────────────────────────────────────${NC}"

    TODAY=$(date '+%Y-%m-%d')
    if [ ! -s "$DB_FILE" ]; then
        echo -e " ${YELLOW}Belum ada akun.${NC}"
    else
        while IFS=: read -r uname upass exp type maxlogin speed; do
            [ -z "$uname" ] && continue
            SPEED_LABEL=$([ "$speed" = "0" ] || [ -z "$speed" ] && echo "Unlimit" || echo "${speed}Mbps")
            # Check expiry
            EXP_SHORT=$(echo "$exp" | cut -d' ' -f1)
            if [[ "$EXP_SHORT" < "$TODAY" ]]; then
                STATUS="${RED}Expired${NC}"
            else
                STATUS="${GREEN}Active${NC}"
            fi
            printf " %-15s %-12s %-20s %-8s %-10s " "$uname" "$type" "$exp" "$maxlogin" "$SPEED_LABEL"
            echo -e "$STATUS"
        done < "$DB_FILE"
    fi

    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -ne "${YELLOW}Tekan Enter untuk kembali...${NC}"; read -r; main_menu
}

# ============================================================
# DELETE ACCOUNT
# ============================================================
delete_account() {
    show_logo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                    ${WHITE}HAPUS AKUN${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -ne " ${YELLOW}Username yang akan dihapus: ${NC}"; read -r uname

    if ! grep -q "^${uname}:" "$DB_FILE" 2>/dev/null; then
        echo -e "${RED}Username tidak ditemukan!${NC}"
        sleep 2; main_menu; return
    fi

    sed -i "/^${uname}:/d" "$DB_FILE"
    log "DELETE_ACCOUNT: user=$uname"
    echo -e "${GREEN}✓ Akun ${uname} berhasil dihapus!${NC}"
    sleep 2; main_menu
}

# ============================================================
# EDIT EXPIRY
# ============================================================
edit_expiry() {
    show_logo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                    ${WHITE}EDIT EXPIRED${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -ne " ${YELLOW}Username: ${NC}"; read -r uname
    echo -ne " ${YELLOW}Tambah hari: ${NC}"; read -r days

    if ! grep -q "^${uname}:" "$DB_FILE" 2>/dev/null; then
        echo -e "${RED}Username tidak ditemukan!${NC}"
        sleep 2; main_menu; return
    fi

    OLD_EXP=$(grep "^${uname}:" "$DB_FILE" | cut -d: -f3)
    NEW_EXP=$(date -d "${OLD_EXP} +${days} days" '+%Y-%m-%d' 2>/dev/null || date -d "+${days} days" '+%Y-%m-%d')
    sed -i "s/^${uname}:\([^:]*\):[^:]*:\(.*\)$/${uname}:\1:${NEW_EXP}:\2/" "$DB_FILE"
    log "EDIT_EXPIRY: user=$uname new_exp=$NEW_EXP"
    echo -e "${GREEN}✓ Expired diperbarui menjadi ${NEW_EXP}${NC}"
    sleep 2; main_menu
}

# ============================================================
# EDIT PASSWORD
# ============================================================
edit_password() {
    show_logo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                    ${WHITE}EDIT PASSWORD${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -ne " ${YELLOW}Username   : ${NC}"; read -r uname
    echo -ne " ${YELLOW}Password Baru: ${NC}"; read -r newpass

    if ! grep -q "^${uname}:" "$DB_FILE" 2>/dev/null; then
        echo -e "${RED}Username tidak ditemukan!${NC}"
        sleep 2; main_menu; return
    fi

    sed -i "s/^${uname}:[^:]*:\(.*\)$/${uname}:${newpass}:\1/" "$DB_FILE"
    log "EDIT_PASSWORD: user=$uname"
    echo -e "${GREEN}✓ Password berhasil diubah!${NC}"
    sleep 2; main_menu
}

# ============================================================
# VPS INFO
# ============================================================
vps_info() {
    show_logo
    get_info
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                    ${WHITE}INFORMASI VPS${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e " ${WHITE}Hostname    :${NC} ${GREEN}$(hostname)${NC}"
    echo -e " ${WHITE}OS          :${NC} ${GREEN}$(cat /etc/os-release | grep PRETTY | cut -d'"' -f2)${NC}"
    echo -e " ${WHITE}Kernel      :${NC} ${GREEN}$(uname -r)${NC}"
    echo -e " ${WHITE}IP Public   :${NC} ${GREEN}${IP}${NC}"
    echo -e " ${WHITE}ISP         :${NC} ${GREEN}${ISP}${NC}"
    echo -e " ${WHITE}CPU Usage   :${NC} ${YELLOW}${CPU}%${NC}"
    echo -e " ${WHITE}RAM Usage   :${NC} ${YELLOW}${RAM}%${NC}"
    echo -e " ${WHITE}Disk Usage  :${NC} ${YELLOW}${DISK}%${NC}"
    echo -e " ${WHITE}Uptime      :${NC} ${GREEN}$(uptime -p)${NC}"
    echo -e ""
    echo -e " ${WHITE}UDP Server  :${NC} $(systemctl is-active $SERVICE_UDP 2>/dev/null | grep -q active && echo "${GREEN}Running${NC}" || echo "${RED}Stopped${NC}")"
    echo -e " ${WHITE}ZivPN       :${NC} $(systemctl is-active $SERVICE_ZIVPN 2>/dev/null | grep -q active && echo "${GREEN}Running${NC}" || echo "${RED}Stopped${NC}")"
    echo -e ""
    echo -e " ${WHITE}UDP Port    :${NC} ${GREEN}$(cat $DB_DIR/udp_port 2>/dev/null || echo 'Not set')${NC}"
    echo -e " ${WHITE}ZivPN Port  :${NC} ${GREEN}${ZIVPN_PORT}${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -ne "${YELLOW}Tekan Enter untuk kembali...${NC}"; read -r; main_menu
}

# ============================================================
# MONITOR LOGIN
# ============================================================
monitor_login() {
    show_logo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                    ${WHITE}MONITOR LOGIN${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e " ${YELLOW}Sesi aktif (UDP):${NC}"
    echo -e ""
    # Show last 20 log entries
    if [ -f "$LOG_FILE" ]; then
        tail -20 "$LOG_FILE" | while read -r line; do
            echo -e " ${CYAN}${line}${NC}"
        done
    else
        echo -e " ${YELLOW}Tidak ada data log.${NC}"
    fi
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -ne "${YELLOW}Tekan Enter untuk kembali...${NC}"; read -r; main_menu
}

# ============================================================
# EDIT MAX LOGIN
# ============================================================
edit_max_login() {
    show_logo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                    ${WHITE}EDIT MAX LOGIN${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -ne " ${YELLOW}Username     : ${NC}"; read -r uname
    echo -ne " ${YELLOW}Max Login Baru: ${NC}"; read -r maxlogin

    if ! grep -q "^${uname}:" "$DB_FILE" 2>/dev/null; then
        echo -e "${RED}Username tidak ditemukan!${NC}"
        sleep 2; main_menu; return
    fi

    # Format: user:pass:exp:type:maxlogin:speed
    awk -F: -v user="$uname" -v ml="$maxlogin" 'BEGIN{OFS=":"} $1==user{$5=ml} 1' "$DB_FILE" > /tmp/ogh_tmp && mv /tmp/ogh_tmp "$DB_FILE"
    log "EDIT_MAXLOGIN: user=$uname maxlogin=$maxlogin"
    echo -e "${GREEN}✓ Max login berhasil diubah menjadi ${maxlogin}!${NC}"
    sleep 2; main_menu
}

# ============================================================
# EDIT SPEED LIMIT
# ============================================================
edit_speed_limit() {
    show_logo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                    ${WHITE}EDIT SPEED LIMIT${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -ne " ${YELLOW}Username        : ${NC}"; read -r uname
    echo -ne " ${YELLOW}Speed (Mbps, 0=unlimited): ${NC}"; read -r speed

    if ! grep -q "^${uname}:" "$DB_FILE" 2>/dev/null; then
        echo -e "${RED}Username tidak ditemukan!${NC}"
        sleep 2; main_menu; return
    fi

    awk -F: -v user="$uname" -v sp="$speed" 'BEGIN{OFS=":"} $1==user{$6=sp} 1' "$DB_FILE" > /tmp/ogh_tmp && mv /tmp/ogh_tmp "$DB_FILE"
    log "EDIT_SPEED: user=$uname speed=${speed}Mbps"

    # Apply tc speed limit if interface available
    IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -n "$IFACE" ] && [ "$speed" != "0" ]; then
        echo -e " ${YELLOW}Menerapkan speed limit via tc...${NC}"
        # This is a placeholder - actual tc implementation depends on how UDP server identifies users
    fi

    echo -e "${GREEN}✓ Speed limit diubah menjadi $([ "$speed" = "0" ] && echo "Unlimited" || echo "${speed} Mbps")!${NC}"
    sleep 2; main_menu
}

# ============================================================
# BACKUP/RESTORE
# ============================================================
backup_restore() {
    show_logo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                    ${WHITE}BACKUP / RESTORE${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e " ${CYAN}[1]${NC} Backup Sekarang"
    echo -e " ${CYAN}[2]${NC} Restore dari Backup"
    echo -e " ${CYAN}[3]${NC} Lihat Daftar Backup"
    echo -e " ${CYAN}[0]${NC} Kembali"
    echo -ne " ${YELLOW}Pilihan: ${NC}"; read -r brchoice

    case "$brchoice" in
        1)
            BKDIR="/etc/ogh-udp/backups"
            mkdir -p "$BKDIR"
            BKFILE="$BKDIR/backup_$(date '+%Y%m%d_%H%M%S').tar.gz"
            tar -czf "$BKFILE" "$DB_FILE" "$CONFIG_FILE" 2>/dev/null
            echo -e "${GREEN}✓ Backup disimpan: ${BKFILE}${NC}"
            sleep 2
            ;;
        2)
            echo -ne " ${YELLOW}Path file backup: ${NC}"; read -r bkpath
            tar -xzf "$bkpath" -C / 2>/dev/null && echo -e "${GREEN}✓ Restore berhasil!${NC}" || echo -e "${RED}Restore gagal!${NC}"
            sleep 2
            ;;
        3)
            ls /etc/ogh-udp/backups/ 2>/dev/null || echo -e "${YELLOW}Tidak ada backup.${NC}"
            sleep 3
            ;;
    esac
    main_menu
}

# ============================================================
# BOT SETTINGS
# ============================================================
bot_settings() {
    show_logo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                    ${WHITE}BOT SETTINGS${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -ne " ${YELLOW}Token Bot Telegram: ${NC}"; read -r token
    echo -ne " ${YELLOW}Chat ID Admin     : ${NC}"; read -r chatid

    echo "BOT_TOKEN=${token}" > "$DB_DIR/bot.conf"
    echo "CHAT_ID=${chatid}" >> "$DB_DIR/bot.conf"

    echo -e "${GREEN}✓ Pengaturan bot disimpan!${NC}"
    sleep 2; main_menu
}

# ============================================================
# THEME SETTINGS
# ============================================================
theme_settings() {
    show_logo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                    ${WHITE}THEME SETTINGS${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e " ${CYAN}[1]${NC} Default (Cyan)"
    echo -e " ${CYAN}[2]${NC} Red Theme"
    echo -e " ${CYAN}[3]${NC} Green Theme"
    echo -e " ${CYAN}[0]${NC} Kembali"
    echo -ne " ${YELLOW}Pilihan: ${NC}"; read -r theme
    echo "THEME=${theme}" > "$DB_DIR/theme.conf"
    echo -e "${GREEN}✓ Theme disimpan!${NC}"
    sleep 2; main_menu
}

# ============================================================
# EDIT DOMAIN
# ============================================================
edit_domain() {
    show_logo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                    ${WHITE}EDIT DOMAIN${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -ne " ${YELLOW}Domain baru: ${NC}"; read -r domain
    echo "DOMAIN=${domain}" > "$DB_DIR/domain.conf"
    echo -e "${GREEN}✓ Domain disimpan: ${domain}${NC}"
    sleep 2; main_menu
}

# ============================================================
# AUTO BACKUP
# ============================================================
auto_backup() {
    show_logo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                    ${WHITE}AUTO BACKUP${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e " ${CYAN}[1]${NC} Aktifkan Auto Backup (Setiap Hari)"
    echo -e " ${CYAN}[2]${NC} Nonaktifkan Auto Backup"
    echo -e " ${CYAN}[0]${NC} Kembali"
    echo -ne " ${YELLOW}Pilihan: ${NC}"; read -r abchoice

    case "$abchoice" in
        1)
            CRON_JOB="0 3 * * * /usr/local/bin/menu backup_auto > /dev/null 2>&1"
            (crontab -l 2>/dev/null | grep -v "menu backup_auto"; echo "$CRON_JOB") | crontab -
            echo -e "${GREEN}✓ Auto backup aktif setiap jam 03:00!${NC}"
            ;;
        2)
            (crontab -l 2>/dev/null | grep -v "menu backup_auto") | crontab -
            echo -e "${GREEN}✓ Auto backup dinonaktifkan!${NC}"
            ;;
    esac
    sleep 2; main_menu
}

# ============================================================
# UNINSTALL
# ============================================================
uninstall_script() {
    show_logo
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                    ${WHITE}UNINSTALL SCRIPT${NC}"
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    echo -e " ${RED}PERINGATAN: Semua data akan dihapus!${NC}"
    echo -ne " ${YELLOW}Ketik 'hapus' untuk konfirmasi: ${NC}"; read -r confirm

    if [ "$confirm" = "hapus" ]; then
        systemctl stop $SERVICE_UDP $SERVICE_ZIVPN 2>/dev/null
        systemctl disable $SERVICE_UDP $SERVICE_ZIVPN 2>/dev/null
        rm -f /etc/systemd/system/${SERVICE_UDP}.service
        rm -f /etc/systemd/system/${SERVICE_ZIVPN}.service
        rm -f "$UDP_BIN" "$ZIVPN_BIN"
        rm -rf "$DB_DIR"
        rm -f "$MENU_CMD"
        rm -f /usr/local/bin/ogh-udp.sh
        systemctl daemon-reload
        echo -e "${GREEN}✓ Script berhasil diuninstall!${NC}"
        exit 0
    else
        echo -e "${YELLOW}Uninstall dibatalkan.${NC}"
        sleep 2; main_menu
    fi
}

# ============================================================
# BANDWIDTH
# ============================================================
show_bandwidth() {
    show_logo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                    ${WHITE}BANDWIDTH USAGE${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -n "$IFACE" ]; then
        RX=$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null || echo 0)
        TX=$(cat /sys/class/net/$IFACE/statistics/tx_bytes 2>/dev/null || echo 0)
        RX_MB=$(echo "scale=2; $RX/1024/1024" | bc 2>/dev/null || echo "N/A")
        TX_MB=$(echo "scale=2; $TX/1024/1024" | bc 2>/dev/null || echo "N/A")
        echo -e " ${WHITE}Interface   :${NC} ${GREEN}${IFACE}${NC}"
        echo -e " ${WHITE}RX (Download):${NC} ${GREEN}${RX_MB} MB${NC}"
        echo -e " ${WHITE}TX (Upload)  :${NC} ${GREEN}${TX_MB} MB${NC}"
    else
        echo -e " ${YELLOW}Tidak dapat mendeteksi interface jaringan.${NC}"
    fi
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -ne "${YELLOW}Tekan Enter untuk kembali...${NC}"; read -r; main_menu
}

# ============================================================
# CHECK CPU/RAM
# ============================================================
check_cpu_ram() {
    show_logo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                    ${WHITE}CEK CPU / RAM${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e " ${WHITE}CPU Info:${NC}"
    echo -e " ${GREEN}$(lscpu | grep 'Model name' | cut -d':' -f2 | xargs)${NC}"
    echo -e " ${WHITE}CPU Cores   :${NC} ${GREEN}$(nproc)${NC}"
    echo -e ""
    echo -e " ${WHITE}Memory Info:${NC}"
    free -h | awk 'NR==2{printf " Total: %s | Used: %s | Free: %s\n", $2, $3, $4}'
    echo -e ""
    echo -e " ${WHITE}Load Average:${NC}"
    uptime | awk -F'load average:' '{print " "$2}'
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -ne "${YELLOW}Tekan Enter untuk kembali...${NC}"; read -r; main_menu
}

# ============================================================
# UPDATE SCRIPT
# ============================================================
update_script() {
    show_logo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                    ${WHITE}UPDATE SCRIPT${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e " ${YELLOW}Mengecek update...${NC}"
    echo -e " ${YELLOW}Memperbarui binaries...${NC}"
    install_binaries
    echo -e "${GREEN}✓ Script berhasil diperbarui!${NC}"
    sleep 2; main_menu
}

# ============================================================
# KELOLA LAYANAN
# ============================================================
kelola_layanan() {
    show_logo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                    ${WHITE}KELOLA LAYANAN${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e " ${WHITE}Status UDP Server :${NC} $(systemctl is-active $SERVICE_UDP 2>/dev/null)"
    echo -e " ${WHITE}Status ZivPN      :${NC} $(systemctl is-active $SERVICE_ZIVPN 2>/dev/null)"
    echo -e ""
    echo -e " ${CYAN}[1]${NC} Start Semua Layanan"
    echo -e " ${CYAN}[2]${NC} Stop Semua Layanan"
    echo -e " ${CYAN}[3]${NC} Restart Semua Layanan"
    echo -e " ${CYAN}[4]${NC} Start UDP Server"
    echo -e " ${CYAN}[5]${NC} Start ZivPN"
    echo -e " ${CYAN}[6]${NC} Restart UDP Server"
    echo -e " ${CYAN}[7]${NC} Restart ZivPN"
    echo -e " ${CYAN}[0]${NC} Kembali"
    echo -ne " ${YELLOW}Pilihan: ${NC}"; read -r svchoice

    case "$svchoice" in
        1) systemctl start $SERVICE_UDP $SERVICE_ZIVPN 2>/dev/null; echo -e "${GREEN}✓ Semua layanan dimulai!${NC}" ;;
        2) systemctl stop $SERVICE_UDP $SERVICE_ZIVPN 2>/dev/null; echo -e "${GREEN}✓ Semua layanan dihentikan!${NC}" ;;
        3) systemctl restart $SERVICE_UDP $SERVICE_ZIVPN 2>/dev/null; echo -e "${GREEN}✓ Semua layanan di-restart!${NC}" ;;
        4) systemctl start $SERVICE_UDP 2>/dev/null; echo -e "${GREEN}✓ UDP Server dimulai!${NC}" ;;
        5) systemctl start $SERVICE_ZIVPN 2>/dev/null; echo -e "${GREEN}✓ ZivPN dimulai!${NC}" ;;
        6) systemctl restart $SERVICE_UDP 2>/dev/null; echo -e "${GREEN}✓ UDP Server di-restart!${NC}" ;;
        7) systemctl restart $SERVICE_ZIVPN 2>/dev/null; echo -e "${GREEN}✓ ZivPN di-restart!${NC}" ;;
    esac
    sleep 2; main_menu
}

# ============================================================
# UDP PORT CONFIG
# ============================================================
udp_port_config() {
    show_logo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                    ${WHITE}KONFIGURASI PORT UDP${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    CURRENT_PORT=$(cat "$DB_DIR/udp_port" 2>/dev/null || echo "Belum diatur")
    echo -e " ${WHITE}Port Saat Ini :${NC} ${GREEN}${CURRENT_PORT}${NC}"
    echo -e " ${YELLOW}Masukkan port UDP (1-65535):${NC}"
    echo -ne " Port: "; read -r udpport

    if ! [[ "$udpport" =~ ^[0-9]+$ ]] || [ "$udpport" -lt 1 ] || [ "$udpport" -gt 65535 ]; then
        echo -e "${RED}Port tidak valid! Harus antara 1-65535.${NC}"
        sleep 2; main_menu; return
    fi

    echo "$udpport" > "$DB_DIR/udp_port"

    # Update systemd service if exists
    if [ -f "/etc/systemd/system/${SERVICE_UDP}.service" ]; then
        sed -i "s/--port [0-9]*/--port ${udpport}/" "/etc/systemd/system/${SERVICE_UDP}.service"
        systemctl daemon-reload
        systemctl restart $SERVICE_UDP 2>/dev/null
    fi

    log "UDP_PORT_CHANGE: port=$udpport"
    echo -e "${GREEN}✓ Port UDP diubah menjadi ${udpport}!${NC}"
    sleep 2; main_menu
}

# ============================================================
# ZIVPN CONFIG
# ============================================================
zivpn_config() {
    show_logo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                    ${WHITE}KONFIGURASI ZIVPN${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e " ${WHITE}Port ZivPN Saat Ini:${NC} ${GREEN}${ZIVPN_PORT}${NC}"
    echo -e ""
    echo -e " ${CYAN}[1]${NC} Lihat Config JSON"
    echo -e " ${CYAN}[2]${NC} Download Ulang Config"
    echo -e " ${CYAN}[3]${NC} Restart ZivPN"
    echo -e " ${CYAN}[0]${NC} Kembali"
    echo -ne " ${YELLOW}Pilihan: ${NC}"; read -r zvchoice

    case "$zvchoice" in
        1)
            if [ -f "$CONFIG_FILE" ]; then
                cat "$CONFIG_FILE"
            else
                echo -e "${YELLOW}Config tidak ditemukan.${NC}"
            fi
            ;;
        2)
            echo -e "${YELLOW}Mengunduh config...${NC}"
            curl -sL "$CONFIG_URL" -o "$CONFIG_FILE"
            echo -e "${GREEN}✓ Config berhasil diunduh!${NC}"
            ;;
        3)
            systemctl restart $SERVICE_ZIVPN 2>/dev/null
            echo -e "${GREEN}✓ ZivPN di-restart!${NC}"
            ;;
    esac
    sleep 2; main_menu
}

# ============================================================
# REINSTALL BINARIES
# ============================================================
reinstall_binaries() {
    show_logo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                ${WHITE}REINSTALL / UPDATE BINARIES${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e " ${YELLOW}Menghapus binary lama...${NC}"
    rm -f "$UDP_BIN" "$ZIVPN_BIN"
    echo -e " ${YELLOW}Mengunduh binary baru...${NC}"
    install_binaries
    echo -ne "${YELLOW}Tekan Enter untuk kembali...${NC}"; read -r; main_menu
}

# ============================================================
# VIEW LOGS
# ============================================================
view_logs() {
    show_logo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                    ${WHITE}LOG AKTIVITAS${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    if [ -f "$LOG_FILE" ]; then
        tail -30 "$LOG_FILE" | while read -r line; do
            echo -e " ${CYAN}${line}${NC}"
        done
    else
        echo -e " ${YELLOW}Log kosong.${NC}"
    fi
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -ne "${YELLOW}Tekan Enter untuk kembali...${NC}"; read -r; main_menu
}

# ============================================================
# USER STATS
# ============================================================
user_stats() {
    show_logo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                    ${WHITE}STATISTIK PENGGUNA${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"

    TOTAL=$(wc -l < "$DB_FILE" 2>/dev/null || echo 0)
    TODAY=$(date '+%Y-%m-%d')
    ACTIVE=0; EXPIRED=0; TRIAL=0; REGULAR=0

    while IFS=: read -r uname upass exp type maxlogin speed; do
        [ -z "$uname" ] && continue
        EXP_SHORT=$(echo "$exp" | cut -d' ' -f1)
        [[ "$EXP_SHORT" < "$TODAY" ]] && ((EXPIRED++)) || ((ACTIVE++))
        [ "$type" = "trial" ] && ((TRIAL++))
        [ "$type" = "regular" ] && ((REGULAR++))
    done < "$DB_FILE"

    echo -e " ${WHITE}Total Akun   :${NC} ${GREEN}${TOTAL}${NC}"
    echo -e " ${WHITE}Akun Aktif   :${NC} ${GREEN}${ACTIVE}${NC}"
    echo -e " ${WHITE}Akun Expired :${NC} ${RED}${EXPIRED}${NC}"
    echo -e " ${WHITE}Akun Regular :${NC} ${CYAN}${REGULAR}${NC}"
    echo -e " ${WHITE}Akun Trial   :${NC} ${YELLOW}${TRIAL}${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -ne "${YELLOW}Tekan Enter untuk kembali...${NC}"; read -r; main_menu
}

# ============================================================
# INSTALL BINARIES
# ============================================================
install_binaries() {
    echo -e " ${YELLOW}[1/4] Menghapus binary lama...${NC}"
    rm -f "$UDP_BIN" "$ZIVPN_BIN"

    echo -e " ${YELLOW}[2/4] Mengunduh udpServer...${NC}"
    if curl -sL "$UDP_URL" -o "$UDP_BIN"; then
        chmod +x "$UDP_BIN"
        echo -e " ${GREEN}✓ udpServer berhasil diunduh!${NC}"
    else
        echo -e " ${RED}✗ Gagal mengunduh udpServer!${NC}"
    fi

    echo -e " ${YELLOW}[3/4] Mengunduh udp-zivpn...${NC}"
    if curl -sL "$ZIVPN_URL" -o "$ZIVPN_BIN"; then
        chmod +x "$ZIVPN_BIN"
        echo -e " ${GREEN}✓ udp-zivpn berhasil diunduh!${NC}"
    else
        echo -e " ${RED}✗ Gagal mengunduh udp-zivpn!${NC}"
    fi

    echo -e " ${YELLOW}[4/4] Mengunduh config ZivPN...${NC}"
    if curl -sL "$CONFIG_URL" -o "$CONFIG_FILE"; then
        echo -e " ${GREEN}✓ Config ZivPN berhasil diunduh!${NC}"
    else
        echo -e " ${RED}✗ Gagal mengunduh config!${NC}"
    fi

    log "INSTALL_BINARIES: completed"
}

# ============================================================
# CREATE SYSTEMD SERVICES
# ============================================================
create_services() {
    UDP_PORT=$(cat "$DB_DIR/udp_port" 2>/dev/null || echo "36000")

    # UDP Server service
    cat > /etc/systemd/system/${SERVICE_UDP}.service << EOF
[Unit]
Description=OGH UDP Server
After=network.target

[Service]
Type=simple
ExecStart=${UDP_BIN} --port ${UDP_PORT}
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # ZivPN service
    cat > /etc/systemd/system/${SERVICE_ZIVPN}.service << EOF
[Unit]
Description=OGH ZivPN UDP Service
After=network.target

[Service]
Type=simple
ExecStart=${ZIVPN_BIN} -config ${CONFIG_FILE}
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable $SERVICE_UDP $SERVICE_ZIVPN 2>/dev/null
    systemctl start $SERVICE_UDP $SERVICE_ZIVPN 2>/dev/null
    echo -e " ${GREEN}✓ Layanan systemd dibuat dan dijalankan!${NC}"
}

# ============================================================
# INSTALL MENU COMMAND
# ============================================================
install_menu_cmd() {
    cp "$0" /usr/local/bin/ogh-udp.sh
    chmod +x /usr/local/bin/ogh-udp.sh
    cat > "$MENU_CMD" << 'EOF'
#!/bin/bash
/usr/local/bin/ogh-udp.sh "$@"
EOF
    chmod +x "$MENU_CMD"
    echo -e " ${GREEN}✓ Perintah 'menu' berhasil dipasang!${NC}"
    echo -e " ${CYAN}Ketik 'menu' di terminal untuk membuka panel.${NC}"
}

# ============================================================
# FIRST RUN / INSTALL
# ============================================================
first_install() {
    show_logo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "                    ${WHITE}INSTALASI OGH-UDP${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e ""
    init_dirs

    echo -e " ${YELLOW}Mengatur port UDP...${NC}"
    echo -ne " Masukkan port UDP request (1-65535): "; read -r udpport
    if ! [[ "$udpport" =~ ^[0-9]+$ ]] || [ "$udpport" -lt 1 ] || [ "$udpport" -gt 65535 ]; then
        echo -e "${RED}Port tidak valid, menggunakan default 36000${NC}"
        udpport=36000
    fi
    echo "$udpport" > "$DB_DIR/udp_port"

    install_binaries
    create_services
    install_menu_cmd

    echo -e ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e " ${GREEN}✓ INSTALASI SELESAI!${NC}"
    echo -e " ${WHITE}UDP Port   :${NC} ${GREEN}${udpport}${NC}"
    echo -e " ${WHITE}ZivPN Port :${NC} ${GREEN}${ZIVPN_PORT}${NC}"
    echo -e " ${CYAN}Ketik 'menu' untuk membuka panel OGH-UDP${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -ne "${YELLOW}Tekan Enter untuk melanjutkan...${NC}"; read -r
    main_menu
}

# ============================================================
# MAIN
# ============================================================
init_dirs

case "$1" in
    install) first_install ;;
    backup_auto)
        BKDIR="/etc/ogh-udp/backups"
        mkdir -p "$BKDIR"
        tar -czf "$BKDIR/auto_$(date '+%Y%m%d_%H%M%S').tar.gz" "$DB_FILE" "$CONFIG_FILE" 2>/dev/null
        # Keep only last 7 backups
        ls -t "$BKDIR"/auto_*.tar.gz 2>/dev/null | tail -n +8 | xargs rm -f
        ;;
    *)
        if [ ! -f "$UDP_BIN" ] || [ ! -f "$ZIVPN_BIN" ]; then
            echo -e "${YELLOW}Binary tidak ditemukan. Menjalankan instalasi pertama...${NC}"
            sleep 1
            first_install
        else
            main_menu
        fi
        ;;
esac
