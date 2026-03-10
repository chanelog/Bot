#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║          OGH-UDP ALL-IN-ONE MANAGER v3.0                    ║
# ║  OGH UDP  : github.com/chanelog/Ogh/raw/main/udpServer      ║
# ║  ZivPN UDP: github.com/fauzanihanipah/ziv-udp               ║
# ╚══════════════════════════════════════════════════════════════╝

# ─── COLORS ────────────────────────────────────────────────────
R='\033[0;31m'  ; G='\033[0;32m'  ; Y='\033[1;33m'
C='\033[0;36m'  ; M='\033[0;35m'  ; W='\033[1;37m'
B='\033[0;34m'  ; BOLD='\033[1m'  ; NC='\033[0m'
DIM='\033[2m'

# ─── PATHS ─────────────────────────────────────────────────────
OGH_BIN="/usr/local/bin/udpServer"
OGH_BIN_URL="https://github.com/chanelog/Ogh/raw/main/udpServer"
OGH_SVC="ogh-udp"
OGH_SVC_FILE="/etc/systemd/system/ogh-udp.service"
OGH_DIR="/etc/ogh-udp"
OGH_DB="$OGH_DIR/users.db"
OGH_PORT_FILE="$OGH_DIR/port.conf"
OGH_LOG="/var/log/ogh-udp.log"
OGH_QUOTA_DIR="$OGH_DIR/quota"
OGH_SESSION_DIR="$OGH_DIR/sessions"
OGH_DEFAULT_PORT=7300

ZIV_BIN="/usr/local/bin/udp-zivpn"
ZIV_BIN_URL="https://github.com/fauzanihanipah/ziv-udp/releases/download/udp-zivpn/udp-zivpn-linux-amd64"
ZIV_CFG_URL="https://raw.githubusercontent.com/fauzanihanipah/ziv-udp/main/config.json"
ZIV_SVC="zivpn-udp"
ZIV_SVC_FILE="/etc/systemd/system/zivpn-udp.service"
ZIV_DIR="/etc/zivpn-udp"
ZIV_CFG="$ZIV_DIR/config.json"
ZIV_DB="$ZIV_DIR/users.db"
ZIV_LOG="/var/log/zivpn-udp.log"
ZIV_QUOTA_DIR="$ZIV_DIR/quota"
ZIV_SESSION_DIR="$ZIV_DIR/sessions"

VERSION="3.0"

# ══════════════════════════════════════════════════════════════
#  UTILITY
# ══════════════════════════════════════════════════════════════
line()  { echo -e "${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
sline() { echo -e "  ${W}───────────────────────────────────────────────────────${NC}"; }
title() { line; echo -e "${BOLD}  $1${NC}"; line; }
ok()    { echo -e "${G}  [✓] $1${NC}"; }
err()   { echo -e "${R}  [✗] $1${NC}"; }
warn()  { echo -e "${Y}  [!] $1${NC}"; }
info()  { echo -e "${C}  [*] $1${NC}"; }

get_ip()     { curl -s --max-time 5 ifconfig.me 2>/dev/null || wget -qO- --timeout=5 ifconfig.me 2>/dev/null || echo "N/A"; }
get_isp()    { curl -s --max-time 5 "https://ipinfo.io/org" 2>/dev/null | cut -d' ' -f2- || echo "N/A"; }
get_uptime() { uptime -p 2>/dev/null | sed 's/up //' || echo "N/A"; }
get_ram()    { free -m | awk '/Mem:/{printf "%dMB / %dMB (%.0f%%)",$3,$2,$3/$2*100}'; }
get_disk()   { df -h / | awk 'NR==2{printf "%s / %s (%s)",$3,$2,$5}'; }
get_cpu()    { top -bn1 | grep "Cpu(s)" | awk '{printf "%.1f%%",$2+$4}' 2>/dev/null || echo "N/A"; }
get_load()   { uptime | awk -F'load average:' '{print $2}' | xargs; }
get_os()     { grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 || uname -s; }
get_kernel() { uname -r; }
get_date()   { date "+%A, %d %B %Y  %H:%M:%S"; }

ogh_port()   { [ -f "$OGH_PORT_FILE" ] && cat "$OGH_PORT_FILE" || echo $OGH_DEFAULT_PORT; }
ziv_port()   { [ -f "$ZIV_CFG" ] && grep '"listen"' "$ZIV_CFG" | grep -oE ':[0-9]+' | head -1 | tr -d ':' || echo "7200"; }

ogh_running() { systemctl is-active --quiet $OGH_SVC 2>/dev/null; }
ziv_running() { systemctl is-active --quiet $ZIV_SVC 2>/dev/null; }
ogh_stlabel() { ogh_running && echo -e "${G}● RUNNING${NC}" || echo -e "${R}● STOPPED${NC}"; }
ziv_stlabel() { ziv_running && echo -e "${G}● RUNNING${NC}" || echo -e "${R}● STOPPED${NC}"; }

count_db()    { [ -f "$1" ] && grep -c '.' "$1" 2>/dev/null || echo 0; }

bytes_human() {
    local B=${1:-0}
    if   [ "$B" -ge 1073741824 ]; then printf "%.2f GB" "$(echo "scale=2;$B/1073741824" | bc 2>/dev/null || echo 0)"
    elif [ "$B" -ge 1048576    ]; then printf "%.2f MB" "$(echo "scale=2;$B/1048576" | bc 2>/dev/null || echo 0)"
    elif [ "$B" -ge 1024       ]; then printf "%.2f KB" "$(echo "scale=2;$B/1024" | bc 2>/dev/null || echo 0)"
    else printf "%d B" "$B"; fi
}

human_bytes() {
    local V="$1"
    local NUM="${V//[^0-9.]/}"
    local UNIT; UNIT=$(echo "${V//[0-9. ]/}" | tr '[:lower:]' '[:upper:]')
    case "$UNIT" in
        GB|G) echo $(echo "${NUM:-0} * 1073741824" | bc | cut -d. -f1) ;;
        MB|M) echo $(echo "${NUM:-0} * 1048576"    | bc | cut -d. -f1) ;;
        KB|K) echo $(echo "${NUM:-0} * 1024"       | bc | cut -d. -f1) ;;
        *)    echo "${NUM:-0}" ;;
    esac
}

quota_file()   { echo "$1/$2.quota"; }
session_file() { echo "$1/$2.sess"; }

get_used()     { local F; F=$(quota_file "$1" "$2"); [ -f "$F" ] && cat "$F" || echo 0; }
get_sessions() { local F; F=$(session_file "$1" "$2"); [ -f "$F" ] && cat "$F" || echo 0; }

reset_sessions() {
    echo 0 > "$(session_file "$1" "$2")"
}

reset_quota_usage() {
    local QDIR="$1" USER="$2" DB="$3"
    echo 0 > "$(quota_file "$QDIR" "$USER")"
    sed -i "s/^${USER}|\([^|]*\)|\([^|]*\)|\([^|]*\)|\([^|]*\)|\([^|]*\)|\([^|]*\)|/${USER}|\1|\2|\3|\4|\5|0|/" "$DB" 2>/dev/null
    ok "Quota usage '$USER' direset."
}

# ══════════════════════════════════════════════════════════════
#  AUTO INSTALL
# ══════════════════════════════════════════════════════════════
_dl() {
    local URL="$1" DEST="$2"
    if command -v wget &>/dev/null; then
        wget -q --show-progress -O "$DEST" "$URL" 2>&1
    elif command -v curl &>/dev/null; then
        curl -L --progress-bar -o "$DEST" "$URL"
    else
        err "wget/curl tidak ditemukan!"; exit 1
    fi
}

auto_install() {
    clear
    echo -e "${C}"
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║    OGH-UDP ALL-IN-ONE  —  Inisialisasi v${VERSION}       ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # OGH-UDP
    if [ -f "$OGH_BIN" ]; then
        warn "Binary OGH-UDP lama ditemukan → hapus permanen..."
        systemctl stop $OGH_SVC 2>/dev/null
        systemctl disable $OGH_SVC 2>/dev/null
        rm -f "$OGH_BIN"
        ok "Binary lama OGH-UDP dihapus."
    fi
    mkdir -p "$OGH_DIR" "$OGH_QUOTA_DIR" "$OGH_SESSION_DIR"
    info "Mengunduh OGH-UDP binary..."
    _dl "$OGH_BIN_URL" "$OGH_BIN"
    if [ -f "$OGH_BIN" ] && [ -s "$OGH_BIN" ]; then
        chmod +x "$OGH_BIN"; ok "OGH-UDP binary siap."
    else
        err "Gagal unduh OGH-UDP binary!"
    fi

    # ZivPN
    if [ -f "$ZIV_BIN" ]; then
        warn "Binary ZivPN lama ditemukan → hapus permanen..."
        systemctl stop $ZIV_SVC 2>/dev/null
        systemctl disable $ZIV_SVC 2>/dev/null
        rm -f "$ZIV_BIN"
        ok "Binary lama ZivPN dihapus."
    fi
    mkdir -p "$ZIV_DIR" "$ZIV_QUOTA_DIR" "$ZIV_SESSION_DIR"
    info "Mengunduh ZivPN-UDP binary..."
    _dl "$ZIV_BIN_URL" "$ZIV_BIN"
    if [ -f "$ZIV_BIN" ] && [ -s "$ZIV_BIN" ]; then
        chmod +x "$ZIV_BIN"; ok "ZivPN-UDP binary siap."
    else
        err "Gagal unduh ZivPN-UDP binary!"
    fi

    # ZivPN config
    if [ ! -f "$ZIV_CFG" ]; then
        info "Mengunduh config.json ZivPN..."
        _dl "$ZIV_CFG_URL" "$ZIV_CFG"
        if [ ! -f "$ZIV_CFG" ] || [ ! -s "$ZIV_CFG" ]; then
            warn "Membuat config.json default..."
            cat > "$ZIV_CFG" <<'JSON'
{
  "listen": ":7200",
  "remote": "127.0.0.1:443",
  "key": "ogh-udp-zivpn",
  "obfs": "salamander",
  "auth": {
    "type": "password",
    "password": "zivpn2024"
  },
  "bandwidth": {
    "up": "100 mbps",
    "down": "100 mbps"
  },
  "masquerade": {
    "type": "proxy",
    "proxy": {
      "url": "https://news.ycombinator.com/",
      "rewriteHost": true
    }
  }
}
JSON
        fi
        ok "config.json ZivPN siap."
    fi

    [ ! -f "$OGH_DB" ] && touch "$OGH_DB"
    [ ! -f "$ZIV_DB" ] && touch "$ZIV_DB"
    touch "$OGH_LOG" "$ZIV_LOG"

    # Alias menu
    SELF="$(realpath "$0")"
    cp "$SELF" /usr/local/bin/ogh-manager 2>/dev/null
    chmod +x /usr/local/bin/ogh-manager 2>/dev/null
    ln -sf /usr/local/bin/ogh-manager /usr/local/bin/menu 2>/dev/null
    grep -q "alias menu=" ~/.bashrc 2>/dev/null || echo "alias menu='bash /usr/local/bin/ogh-manager'" >> ~/.bashrc

    command -v bc &>/dev/null || apt-get install -y bc &>/dev/null || yum install -y bc &>/dev/null

    ok "Inisialisasi selesai!"
    sleep 1
}

# ══════════════════════════════════════════════════════════════
#  HEADER
# ══════════════════════════════════════════════════════════════
show_header() {
    clear
    local IP ISP OS UPTIME RAM DISK CPU LOAD DT
    IP=$(get_ip); ISP=$(get_isp); OS=$(get_os)
    UPTIME=$(get_uptime); RAM=$(get_ram); DISK=$(get_disk)
    CPU=$(get_cpu); LOAD=$(get_load); DT=$(get_date)

    echo -e "${C}${BOLD}"
    echo "   ██████╗  ██████╗ ██╗  ██╗    ██╗   ██╗██████╗ ██████╗ "
    echo "  ██╔═══██╗██╔════╝ ██║  ██║    ██║   ██║██╔══██╗██╔══██╗"
    echo "  ██║   ██║██║  ███╗███████║    ██║   ██║██║  ██║██████╔╝"
    echo "  ██║   ██║██║   ██║██╔══██║    ██║   ██║██║  ██║██╔═══╝ "
    echo "  ╚██████╔╝╚██████╔╝██║  ██║    ╚██████╔╝██████╔╝██║     "
    echo "   ╚═════╝  ╚═════╝ ╚═╝  ╚═╝     ╚═════╝ ╚═════╝ ╚═╝     "
    echo -e "${NC}"
    echo -e "  ${Y}${BOLD}▓▓▓  OGH-UDP ALL-IN-ONE MANAGER v${VERSION}  ▓▓▓${NC}"
    echo -e "  ${DIM}$DT${NC}"

    line
    echo -e "${BOLD}  📡  INFO VPS${NC}"
    line
    echo -e "  ${C}IP Public  :${NC} ${W}$IP${NC}        ${C}ISP     :${NC} $ISP"
    echo -e "  ${C}OS         :${NC} $OS        ${C}Kernel  :${NC} $(get_kernel)"
    echo -e "  ${C}Uptime     :${NC} $UPTIME     ${C}Load    :${NC} $LOAD"
    echo -e "  ${C}CPU        :${NC} $CPU        ${C}RAM     :${NC} $RAM"
    echo -e "  ${C}Disk       :${NC} $DISK"
    sline
    echo -e "  ${C}OGH-UDP  ${NC} Port:${W}$(ogh_port)${NC}  Status:$(ogh_stlabel)  Akun:${W}$(count_db "$OGH_DB")${NC}"
    echo -e "  ${C}ZivPN-UDP${NC} Port:${W}$(ziv_port)${NC}  Status:$(ziv_stlabel)  Akun:${W}$(count_db "$ZIV_DB")${NC}"

    line
    echo -e "${BOLD}  🗂   MENU UTAMA${NC}"
    line

    echo -e "  ${M}${BOLD}◆ OGH-UDP — Manajemen Akun${NC}"
    sline
    echo -e "  ${G}[1]${NC}  Buat Akun              ${G}[2]${NC}  Hapus Akun"
    echo -e "  ${G}[3]${NC}  List Akun              ${G}[4]${NC}  Cek Detail Akun"
    echo -e "  ${G}[5]${NC}  Perpanjang Akun        ${G}[6]${NC}  Kunci / Buka Akun"
    echo -e "  ${G}[7]${NC}  Set MaxLogin           ${G}[8]${NC}  Set Kuota Data"
    echo -e "  ${G}[9]${NC}  Reset Kuota Usage      ${G}[10]${NC} Reset Session Login"
    echo -e "  ${G}[11]${NC} Hapus Akun Expired     ${G}[12]${NC} Hapus Semua Akun"
    echo ""
    echo -e "  ${M}${BOLD}◆ OGH-UDP — Service${NC}"
    sline
    echo -e "  ${Y}[13]${NC} Start    ${Y}[14]${NC} Stop    ${Y}[15]${NC} Restart    ${Y}[16]${NC} Status"
    echo -e "  ${C}[17]${NC} Ganti Port             ${C}[18]${NC} Lihat Log"
    echo ""
    echo -e "  ${M}${BOLD}◆ ZivPN-UDP — Manajemen Akun${NC}"
    sline
    echo -e "  ${G}[21]${NC} Buat Akun              ${G}[22]${NC} Hapus Akun"
    echo -e "  ${G}[23]${NC} List Akun              ${G}[24]${NC} Cek Detail Akun"
    echo -e "  ${G}[25]${NC} Perpanjang Akun        ${G}[26]${NC} Kunci / Buka Akun"
    echo -e "  ${G}[27]${NC} Set MaxLogin           ${G}[28]${NC} Set Kuota Data"
    echo -e "  ${G}[29]${NC} Reset Kuota Usage      ${G}[30]${NC} Reset Session Login"
    echo -e "  ${G}[31]${NC} Hapus Akun Expired     ${G}[32]${NC} Hapus Semua Akun"
    echo ""
    echo -e "  ${M}${BOLD}◆ ZivPN-UDP — Service & Config${NC}"
    sline
    echo -e "  ${Y}[33]${NC} Start    ${Y}[34]${NC} Stop    ${Y}[35]${NC} Restart    ${Y}[36]${NC} Status"
    echo -e "  ${C}[37]${NC} Ganti Port             ${C}[38]${NC} Lihat Log"
    echo -e "  ${C}[39]${NC} Lihat config.json      ${C}[40]${NC} Edit config.json"
    echo -e "  ${C}[41]${NC} Reset config.json      ${C}[42]${NC} Ganti Password"
    echo -e "  ${C}[43]${NC} Ganti Bandwidth"
    echo ""
    echo -e "  ${M}${BOLD}◆ Monitoring & Tools${NC}"
    sline
    echo -e "  ${B}[51]${NC} Monitor Live OGH       ${B}[52]${NC} Monitor Live ZivPN"
    echo -e "  ${B}[53]${NC} Statistik Akun OGH     ${B}[54]${NC} Statistik Akun ZivPN"
    echo -e "  ${B}[55]${NC} Cek Akun Mau Expired   ${B}[56]${NC} Backup Database"
    echo -e "  ${B}[57]${NC} Restore Database       ${B}[58]${NC} Export Akun ke TXT"
    echo ""
    echo -e "  ${M}${BOLD}◆ System${NC}"
    sline
    echo -e "  ${C}[61]${NC} Update Semua Binary    ${C}[62]${NC} Update OGH Binary"
    echo -e "  ${C}[63]${NC} Update ZivPN Binary    ${C}[64]${NC} Cek Versi Binary"
    echo -e "  ${C}[65]${NC} Start Semua Service    ${C}[66]${NC} Stop Semua Service"
    echo -e "  ${C}[67]${NC} Restart Semua Service  ${C}[68]${NC} Info Sistem Lengkap"

    line
    echo -e "  ${R}[0]${NC}   Keluar"
    line
    echo -e "  Ketik ${BOLD}menu${NC} kapan saja untuk kembali ke tampilan ini"
    line
}

# ══════════════════════════════════════════════════════════════
#  SERVICE MANAGEMENT
# ══════════════════════════════════════════════════════════════
_ogh_svc_setup() {
    cat > "$OGH_SVC_FILE" <<EOF
[Unit]
Description=OGH UDP Server
After=network.target
[Service]
Type=simple
ExecStart=$OGH_BIN -port $(ogh_port)
Restart=always
RestartSec=3
StandardOutput=append:$OGH_LOG
StandardError=append:$OGH_LOG
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable $OGH_SVC &>/dev/null
}

_ziv_svc_setup() {
    cat > "$ZIV_SVC_FILE" <<EOF
[Unit]
Description=OGH ZivPN UDP Server
After=network.target
[Service]
Type=simple
WorkingDirectory=$ZIV_DIR
ExecStart=$ZIV_BIN -c $ZIV_CFG
Restart=always
RestartSec=3
StandardOutput=append:$ZIV_LOG
StandardError=append:$ZIV_LOG
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable $ZIV_SVC &>/dev/null
}

ogh_start()   { _ogh_svc_setup; systemctl start $OGH_SVC; sleep 1
                ogh_running && ok "OGH-UDP berjalan di port $(ogh_port)" || err "Gagal start. Cek log [18]"; }
ogh_stop()    { systemctl stop $OGH_SVC; warn "OGH-UDP dihentikan."; }
ogh_restart() { _ogh_svc_setup; systemctl restart $OGH_SVC; sleep 1
                ogh_running && ok "OGH-UDP direstart." || err "Gagal restart."; }
ogh_status()  { systemctl status $OGH_SVC --no-pager; }

ziv_start()   { _ziv_svc_setup; systemctl start $ZIV_SVC; sleep 1
                ziv_running && ok "ZivPN berjalan di port $(ziv_port)" || err "Gagal start. Cek log [38]"; }
ziv_stop()    { systemctl stop $ZIV_SVC; warn "ZivPN dihentikan."; }
ziv_restart() { _ziv_svc_setup; systemctl restart $ZIV_SVC; sleep 1
                ziv_running && ok "ZivPN direstart." || err "Gagal restart."; }
ziv_status()  { systemctl status $ZIV_SVC --no-pager; }

start_all()   { ogh_start; ziv_start; }
stop_all()    { ogh_stop; ziv_stop; }
restart_all() { ogh_restart; ziv_restart; }

# ══════════════════════════════════════════════════════════════
#  USER MANAGEMENT
#  DB Format: user|pass|expired|created|maxlogin|quota_bytes|used_bytes|status
# ══════════════════════════════════════════════════════════════

_create_user() {
    local DB="$1" LABEL="$2" PORT_FN="$3" QDIR="$4" SDIR="$5"
    local PORT IP; PORT=$($PORT_FN); IP=$(get_ip)
    title "BUAT AKUN $LABEL"
    read -p "  Username        : " U
    [ -z "$U" ] && err "Username kosong." && return
    grep -q "^$U|" "$DB" 2>/dev/null && err "Username '$U' sudah ada." && return
    [[ "$U" =~ [^a-zA-Z0-9_] ]] && err "Username hanya boleh huruf, angka, underscore." && return
    read -s -p "  Password        : " P; echo
    [ -z "$P" ] && err "Password kosong." && return
    read -p "  Expired (hari)  [30]: " D; D=${D:-30}
    read -p "  Max Login       [0=unlimited]: " ML; ML=${ML:-0}
    read -p "  Kuota Data      [cth: 10GB, 500MB, 0=unlimited]: " QT
    local QB=0; [ -n "$QT" ] && QB=$(human_bytes "$QT"); [ -z "$QB" ] && QB=0
    local EXP; EXP=$(date -d "+${D} days" +%Y-%m-%d 2>/dev/null || date -v+${D}d +%Y-%m-%d)
    local NOW; NOW=$(date +%Y-%m-%d)
    echo "$U|$P|$EXP|$NOW|$ML|$QB|0|active" >> "$DB"
    echo 0 > "$(quota_file "$QDIR" "$U")"
    echo 0 > "$(session_file "$SDIR" "$U")"
    local QT_L; [ "$QB" = "0" ] && QT_L="Unlimited" || QT_L=$(bytes_human "$QB")
    local ML_L; [ "$ML" = "0" ] && ML_L="Unlimited" || ML_L="$ML device"
    line
    ok "Akun berhasil dibuat!"
    line
    echo -e "  ${C}Username    :${NC} $U"
    echo -e "  ${C}Password    :${NC} $P"
    echo -e "  ${C}Host        :${NC} $IP"
    echo -e "  ${C}Port        :${NC} $PORT"
    echo -e "  ${C}Expired     :${NC} $EXP  (+$D hari)"
    echo -e "  ${C}Max Login   :${NC} $ML_L"
    echo -e "  ${C}Kuota Data  :${NC} $QT_L"
    line
}

_delete_user() {
    local DB="$1" LABEL="$2" QDIR="$3" SDIR="$4"
    title "HAPUS AKUN $LABEL"
    _list_users_inline "$DB" "$QDIR" "$SDIR"
    read -p "  Username yang dihapus: " U
    [ -z "$U" ] && err "Username kosong." && return
    if grep -q "^$U|" "$DB" 2>/dev/null; then
        sed -i "/^$U|/d" "$DB"
        rm -f "$(quota_file "$QDIR" "$U")" "$(session_file "$SDIR" "$U")"
        ok "Akun '$U' dihapus."
    else
        err "Akun '$U' tidak ditemukan."
    fi
}

_list_users_inline() {
    local DB="$1" QDIR="$2" SDIR="$3"
    [ ! -s "$DB" ] && warn "Belum ada akun." && return
    echo ""
    printf "  ${C}%-3s %-15s %-11s %-8s %-10s %-12s %-10s %s${NC}\n" \
        "No" "Username" "Expired" "MaxLogin" "Sesi" "Kuota" "Terpakai" "Status"
    sline
    local N=1 TODAY; TODAY=$(date +%Y-%m-%d)
    while IFS='|' read -r U P EXP CR ML QB USED ST; do
        local EXP_C QB_H ML_L USED_H SESS ST_C
        [[ "$EXP" < "$TODAY" ]] && EXP_C="${R}$EXP${NC}" || EXP_C="${G}$EXP${NC}"
        [ "$QB" = "0" ] && QB_H="Unlimited" || QB_H=$(bytes_human "$QB")
        [ "$ML" = "0" ] && ML_L="Unlim" || ML_L="$ML"
        USED_H=$(bytes_human "$(get_used "$QDIR" "$U")")
        SESS=$(get_sessions "$SDIR" "$U")
        [ "$ST" = "locked" ] && ST_C="${R}LOCKED${NC}" || ST_C="${G}AKTIF${NC}"
        printf "  %-3s %-15s " "$N" "$U"
        echo -ne "$EXP_C  "
        printf "%-8s %-10s %-12s %-10s " "$ML_L" "${SESS}/${ML_L}" "$QB_H" "$USED_H"
        echo -e "$ST_C"
        ((N++))
    done < "$DB"
    echo ""
}

_list_users() {
    local DB="$1" LABEL="$2" QDIR="$3" SDIR="$4"
    title "LIST AKUN $LABEL"
    _list_users_inline "$DB" "$QDIR" "$SDIR"
    line
    echo -e "  Total: ${W}$(count_db "$DB")${NC} akun"
}

_check_user() {
    local DB="$1" LABEL="$2" PORT_FN="$3" QDIR="$4" SDIR="$5"
    local PORT IP; PORT=$($PORT_FN); IP=$(get_ip)
    title "CEK DETAIL AKUN $LABEL"
    read -p "  Username: " U
    local LINE; LINE=$(grep "^$U|" "$DB" 2>/dev/null | head -1)
    [ -z "$LINE" ] && err "Akun '$U' tidak ditemukan." && return
    IFS='|' read -r USER PASS EXP CR ML QB USED ST <<< "$LINE"
    local TODAY; TODAY=$(date +%Y-%m-%d)
    local SISA_L
    if [[ "$EXP" < "$TODAY" ]]; then
        SISA_L="${R}EXPIRED${NC}"
    else
        local SISA_D=$(( ($(date -d "$EXP" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$EXP" +%s) - $(date +%s)) / 86400 ))
        SISA_L="${G}${SISA_D} hari lagi${NC}"
    fi
    local QB_H ML_L USED_H SESS USED_B QUOTA_PCT
    [ "$QB" = "0" ] && QB_H="Unlimited" || QB_H=$(bytes_human "$QB")
    [ "$ML" = "0" ] && ML_L="Unlimited" || ML_L="$ML device"
    USED_B=$(get_used "$QDIR" "$USER")
    USED_H=$(bytes_human "$USED_B")
    SESS=$(get_sessions "$SDIR" "$USER")
    if [ "$QB" != "0" ] && [ "$QB" -gt 0 ] && command -v bc &>/dev/null; then
        QUOTA_PCT=$(echo "scale=1; $USED_B * 100 / $QB" | bc)%
    else
        QUOTA_PCT="N/A"
    fi
    local SESS_L; [ "$ML" = "0" ] && SESS_L="$SESS / Unlimited" || SESS_L="$SESS / $ML"
    line
    echo -e "  ${C}Username    :${NC} $USER"
    echo -e "  ${C}Password    :${NC} $PASS"
    echo -e "  ${C}Host        :${NC} $IP"
    echo -e "  ${C}Port        :${NC} $PORT"
    echo -e "  ${C}Dibuat      :${NC} $CR"
    echo -e "  ${C}Expired     :${NC} $EXP  ($SISA_L)"
    echo -e "  ${C}Status      :${NC} $ST"
    sline
    echo -e "  ${C}Max Login   :${NC} $ML_L"
    echo -e "  ${C}Sesi Aktif  :${NC} $SESS_L"
    sline
    echo -e "  ${C}Kuota Total :${NC} $QB_H"
    echo -e "  ${C}Terpakai    :${NC} $USED_H  ($QUOTA_PCT)"
    line
}

_renew_user() {
    local DB="$1" LABEL="$2" QDIR="$3" SDIR="$4"
    title "PERPANJANG AKUN $LABEL"
    _list_users_inline "$DB" "$QDIR" "$SDIR"
    read -p "  Username: " U
    local LINE; LINE=$(grep "^$U|" "$DB" 2>/dev/null | head -1)
    [ -z "$LINE" ] && err "Akun '$U' tidak ditemukan." && return
    IFS='|' read -r USR P EXP CR ML QB USED ST <<< "$LINE"
    echo -e "  Expired saat ini: ${Y}$EXP${NC}"
    read -p "  Tambah berapa hari: " D
    [[ ! "$D" =~ ^[0-9]+$ ]] && err "Nilai tidak valid." && return
    local TODAY; TODAY=$(date +%Y-%m-%d)
    local BASE; [[ "$EXP" > "$TODAY" ]] && BASE="$EXP" || BASE="$TODAY"
    local NEW_EXP; NEW_EXP=$(date -d "$BASE +${D} days" +%Y-%m-%d 2>/dev/null)
    sed -i "s/^${USR}|${P}|${EXP}|/${USR}|${P}|${NEW_EXP}|/" "$DB"
    ok "Akun '$USR' diperpanjang hingga $NEW_EXP (+$D hari)."
}

_toggle_lock() {
    local DB="$1" LABEL="$2"
    title "KUNCI / BUKA AKUN $LABEL"
    read -p "  Username: " U
    local LINE; LINE=$(grep "^$U|" "$DB" 2>/dev/null | head -1)
    [ -z "$LINE" ] && err "Akun '$U' tidak ditemukan." && return
    local CUR_ST; CUR_ST=$(echo "$LINE" | awk -F'|' '{print $8}')
    if [ "$CUR_ST" = "locked" ]; then
        sed -i "s/^${U}|\(.*\)|locked/${U}|\1|active/" "$DB"
        ok "Akun '$U' dibuka (active)."
    else
        sed -i "s/^${U}|\(.*\)|active/${U}|\1|locked/" "$DB"
        warn "Akun '$U' dikunci (locked)."
    fi
}

_set_maxlogin() {
    local DB="$1" LABEL="$2"
    title "SET MAXLOGIN $LABEL"
    read -p "  Username: " U
    local LINE; LINE=$(grep "^$U|" "$DB" 2>/dev/null | head -1)
    [ -z "$LINE" ] && err "Akun '$U' tidak ditemukan." && return
    IFS='|' read -r USR P EXP CR ML QB USED ST <<< "$LINE"
    echo -e "  MaxLogin saat ini: ${Y}${ML} (0=unlimited)${NC}"
    read -p "  MaxLogin baru [0=unlimited]: " NML
    [[ ! "$NML" =~ ^[0-9]+$ ]] && err "Nilai tidak valid." && return
    sed -i "s/^${USR}|${P}|${EXP}|${CR}|${ML}|/${USR}|${P}|${EXP}|${CR}|${NML}|/" "$DB"
    [ "$NML" = "0" ] && ok "MaxLogin '$USR' = Unlimited." || ok "MaxLogin '$USR' = $NML device."
}

_set_quota() {
    local DB="$1" LABEL="$2" QDIR="$3"
    title "SET KUOTA DATA $LABEL"
    read -p "  Username: " U
    local LINE; LINE=$(grep "^$U|" "$DB" 2>/dev/null | head -1)
    [ -z "$LINE" ] && err "Akun '$U' tidak ditemukan." && return
    IFS='|' read -r USR P EXP CR ML QB USED ST <<< "$LINE"
    local QB_H; [ "$QB" = "0" ] && QB_H="Unlimited" || QB_H=$(bytes_human "$QB")
    echo -e "  Kuota saat ini: ${Y}$QB_H${NC}"
    read -p "  Kuota baru [cth: 10GB, 500MB, 0=unlimited]: " NQ
    local NQB=0; [ -n "$NQ" ] && NQB=$(human_bytes "$NQ"); [ -z "$NQB" ] && NQB=0
    sed -i "s/^${USR}|${P}|${EXP}|${CR}|${ML}|${QB}|/${USR}|${P}|${EXP}|${CR}|${ML}|${NQB}|/" "$DB"
    [ "$NQB" = "0" ] && ok "Kuota '$USR' = Unlimited." || ok "Kuota '$USR' = $(bytes_human "$NQB")."
}

_reset_quota() {
    local DB="$1" LABEL="$2" QDIR="$3"
    title "RESET KUOTA USAGE $LABEL"
    read -p "  Username (atau 'all' untuk semua): " U
    if [ "$U" = "all" ]; then
        while IFS='|' read -r USR _; do reset_quota_usage "$QDIR" "$USR" "$DB"; done < "$DB" 2>/dev/null
        ok "Semua kuota usage direset."
    else
        grep -q "^$U|" "$DB" 2>/dev/null || { err "Akun tidak ditemukan."; return; }
        reset_quota_usage "$QDIR" "$U" "$DB"
    fi
}

_reset_session() {
    local DB="$1" LABEL="$2" SDIR="$3"
    title "RESET SESSION $LABEL"
    read -p "  Username (atau 'all' untuk semua): " U
    if [ "$U" = "all" ]; then
        while IFS='|' read -r USR _; do reset_sessions "$SDIR" "$USR"; done < "$DB" 2>/dev/null
        ok "Semua session direset."
    else
        grep -q "^$U|" "$DB" 2>/dev/null || { err "Akun tidak ditemukan."; return; }
        reset_sessions "$SDIR" "$U"; ok "Session '$U' direset."
    fi
}

_delete_expired() {
    local DB="$1" LABEL="$2" QDIR="$3" SDIR="$4"
    local TODAY; TODAY=$(date +%Y-%m-%d)
    local COUNT=0 TMPF; TMPF=$(mktemp)
    while IFS='|' read -r U P EXP REST; do
        if [[ "$EXP" < "$TODAY" ]]; then
            rm -f "$(quota_file "$QDIR" "$U")" "$(session_file "$SDIR" "$U")"
            ((COUNT++))
        else
            echo "$U|$P|$EXP|$REST" >> "$TMPF"
        fi
    done < "$DB" 2>/dev/null
    mv "$TMPF" "$DB"
    ok "$COUNT akun expired $LABEL dihapus."
}

_delete_all_users() {
    local DB="$1" LABEL="$2" QDIR="$3" SDIR="$4"
    warn "Hapus SEMUA akun $LABEL? (yes/no)"
    read -p "  Konfirmasi: " C
    if [ "$C" = "yes" ]; then
        > "$DB"
        rm -f "$QDIR/"*.quota "$SDIR/"*.sess 2>/dev/null
        ok "Semua akun $LABEL dihapus."
    else
        warn "Dibatalkan."
    fi
}

# ══════════════════════════════════════════════════════════════
#  PORT & CONFIG
# ══════════════════════════════════════════════════════════════
ogh_change_port() {
    title "GANTI PORT OGH-UDP"
    echo -e "  Port saat ini: ${Y}$(ogh_port)${NC}"
    read -p "  Port baru: " NP
    [[ ! "$NP" =~ ^[0-9]+$ ]] || [ "$NP" -lt 1 ] || [ "$NP" -gt 65535 ] && err "Port tidak valid." && return
    echo "$NP" > "$OGH_PORT_FILE"
    ok "Port OGH-UDP diubah ke $NP."
    read -p "  Restart sekarang? (y/n): " R; [ "$R" = "y" ] && ogh_restart
}
ogh_log() { title "LOG OGH-UDP (60 baris terakhir)"; tail -n 60 "$OGH_LOG" 2>/dev/null || warn "Log kosong."; line; }

ziv_change_port() {
    title "GANTI PORT ZivPN"
    echo -e "  Port saat ini: ${Y}$(ziv_port)${NC}"
    read -p "  Port baru: " NP
    [[ ! "$NP" =~ ^[0-9]+$ ]] || [ "$NP" -lt 1 ] || [ "$NP" -gt 65535 ] && err "Port tidak valid." && return
    sed -i "s/\"listen\": *\":[0-9]*\"/\"listen\": \":$NP\"/" "$ZIV_CFG"
    ok "Port ZivPN diubah ke $NP."
    read -p "  Restart sekarang? (y/n): " R; [ "$R" = "y" ] && ziv_restart
}
ziv_view_cfg()  { title "CONFIG.JSON ZivPN"; cat "$ZIV_CFG" 2>/dev/null || err "File tidak ada."; line; }
ziv_edit_cfg()  {
    local ED=${EDITOR:-nano}; command -v $ED &>/dev/null || ED=vi
    $ED "$ZIV_CFG"; ok "Config disimpan."
    read -p "  Restart? (y/n): " R; [ "$R" = "y" ] && ziv_restart
}
ziv_reset_cfg() {
    warn "Reset config.json dari GitHub? (yes/no)"; read -p "  Konfirmasi: " C
    if [ "$C" = "yes" ]; then
        _dl "$ZIV_CFG_URL" "$ZIV_CFG"
        ok "config.json direset."
        read -p "  Restart? (y/n): " R; [ "$R" = "y" ] && ziv_restart
    else
        warn "Dibatalkan."
    fi
}
ziv_change_pass() {
    read -s -p "  Password config baru: " NP; echo
    [ -z "$NP" ] && err "Password kosong." && return
    sed -i "s/\"password\": *\"[^\"]*\"/\"password\": \"$NP\"/" "$ZIV_CFG"
    ok "Password config ZivPN diubah."
    read -p "  Restart? (y/n): " R; [ "$R" = "y" ] && ziv_restart
}
ziv_change_bw() {
    title "GANTI BANDWIDTH ZivPN"
    grep -E '"up"|"down"' "$ZIV_CFG" | head -4
    read -p "  Upload baru   [cth: 100 mbps]: " UP
    read -p "  Download baru [cth: 100 mbps]: " DN
    [ -n "$UP" ] && sed -i "s/\"up\": *\"[^\"]*\"/\"up\": \"$UP\"/" "$ZIV_CFG"
    [ -n "$DN" ] && sed -i "s/\"down\": *\"[^\"]*\"/\"down\": \"$DN\"/" "$ZIV_CFG"
    ok "Bandwidth ZivPN diupdate."
    read -p "  Restart? (y/n): " R; [ "$R" = "y" ] && ziv_restart
}
ziv_log() { title "LOG ZivPN-UDP (60 baris terakhir)"; tail -n 60 "$ZIV_LOG" 2>/dev/null || warn "Log kosong."; line; }

# ══════════════════════════════════════════════════════════════
#  MONITORING & TOOLS
# ══════════════════════════════════════════════════════════════
monitor_live() {
    local SVC="$1" LOG="$2" LABEL="$3"
    info "Monitor LIVE $LABEL — Ctrl+C untuk keluar"
    while true; do
        clear; title "MONITOR LIVE — $LABEL  $(date '+%H:%M:%S')"
        systemctl status $SVC --no-pager | head -18
        sline; echo -e "  ${C}Log terbaru:${NC}"
        tail -n 12 "$LOG" 2>/dev/null
        sleep 3
    done
}

stats_all_users() {
    local DB="$1" LABEL="$2" QDIR="$3" SDIR="$4"
    title "STATISTIK AKUN $LABEL"
    local TODAY; TODAY=$(date +%Y-%m-%d)
    local TOTAL=0 AKTIF=0 EXPIRED=0 LOCKED=0 TOTAL_USED=0
    while IFS='|' read -r U P EXP CR ML QB USED ST; do
        ((TOTAL++))
        [ "$ST" = "locked" ] && ((LOCKED++))
        [[ "$EXP" < "$TODAY" ]] && ((EXPIRED++)) || ((AKTIF++))
        local UB; UB=$(get_used "$QDIR" "$U")
        TOTAL_USED=$(( TOTAL_USED + UB ))
    done < "$DB" 2>/dev/null
    echo -e "\n  ${C}Total Akun    :${NC} ${W}$TOTAL${NC}"
    echo -e "  ${G}Aktif         :${NC} ${W}$AKTIF${NC}"
    echo -e "  ${R}Expired       :${NC} ${W}$EXPIRED${NC}"
    echo -e "  ${Y}Terkunci      :${NC} ${W}$LOCKED${NC}"
    echo -e "  ${C}Total Traffic :${NC} ${W}$(bytes_human "$TOTAL_USED")${NC}"
    sline
    printf "  ${C}%-15s %-11s %-8s %-12s %-10s %s${NC}\n" "Username" "Expired" "MaxLogin" "Kuota" "Terpakai" "Status"
    sline
    while IFS='|' read -r U P EXP CR ML QB USED ST; do
        local QB_H USED_H ML_L ST_C
        [ "$QB" = "0" ] && QB_H="Unlimited" || QB_H=$(bytes_human "$QB")
        USED_H=$(bytes_human "$(get_used "$QDIR" "$U")")
        [ "$ML" = "0" ] && ML_L="Unlim" || ML_L="$ML"
        [ "$ST" = "locked" ] && ST_C="${R}LOCKED${NC}" || ST_C="${G}AKTIF${NC}"
        printf "  %-15s %-11s %-8s %-12s %-10s " "$U" "$EXP" "$ML_L" "$QB_H" "$USED_H"
        echo -e "$ST_C"
    done < "$DB" 2>/dev/null
    line
}

check_soon_expired() {
    title "AKUN AKAN EXPIRED (7 HARI KE DEPAN)"
    local TODAY SOON FOUND=0
    TODAY=$(date +%Y-%m-%d)
    SOON=$(date -d "+7 days" +%Y-%m-%d 2>/dev/null || date -v+7d +%Y-%m-%d)
    echo -e "\n  ${Y}OGH-UDP:${NC}"
    while IFS='|' read -r U P EXP _; do
        if [[ "$EXP" > "$TODAY" ]] && [[ "$EXP" <= "$SOON" ]]; then
            local S=$(( ($(date -d "$EXP" +%s 2>/dev/null) - $(date +%s)) / 86400 ))
            echo -e "  ${Y}►${NC} $U  —  $EXP  (${R}$S hari${NC})"; ((FOUND++))
        fi
    done < "$OGH_DB" 2>/dev/null
    echo -e "\n  ${M}ZivPN-UDP:${NC}"
    while IFS='|' read -r U P EXP _; do
        if [[ "$EXP" > "$TODAY" ]] && [[ "$EXP" <= "$SOON" ]]; then
            local S=$(( ($(date -d "$EXP" +%s 2>/dev/null) - $(date +%s)) / 86400 ))
            echo -e "  ${M}►${NC} $U  —  $EXP  (${R}$S hari${NC})"; ((FOUND++))
        fi
    done < "$ZIV_DB" 2>/dev/null
    [ "$FOUND" = "0" ] && ok "Tidak ada akun akan expired dalam 7 hari."
    line
}

backup_db() {
    local BK="/root/ogh-backup"
    mkdir -p "$BK"
    local TS; TS=$(date +%Y%m%d_%H%M%S)
    cp "$OGH_DB"  "$BK/ogh_users_$TS.db"    2>/dev/null
    cp "$ZIV_DB"  "$BK/ziv_users_$TS.db"    2>/dev/null
    cp "$ZIV_CFG" "$BK/ziv_config_$TS.json" 2>/dev/null
    ok "Backup disimpan di $BK/"
    ls -lh "$BK/" | tail -6
}

restore_db() {
    local BK="/root/ogh-backup"
    title "RESTORE DATABASE"
    ls "$BK/"*.db 2>/dev/null || { err "Tidak ada backup di $BK/"; return; }
    echo ""; ls -lh "$BK/"*.db; echo ""
    read -p "  File OGH DB  [kosong=skip]: " F1
    read -p "  File ZIV DB  [kosong=skip]: " F2
    [ -n "$F1" ] && [ -f "$BK/$F1" ] && cp "$BK/$F1" "$OGH_DB" && ok "OGH DB direstored."
    [ -n "$F2" ] && [ -f "$BK/$F2" ] && cp "$BK/$F2" "$ZIV_DB" && ok "ZIV DB direstored."
}

export_users() {
    local OUT="/root/ogh-export-$(date +%Y%m%d_%H%M%S).txt"
    local IP; IP=$(get_ip)
    {
        echo "=================================="
        echo "  OGH-UDP ACCOUNT EXPORT"
        echo "  Tanggal: $(date)"
        echo "=================================="
        echo ""
        echo "── OGH-UDP (Port: $(ogh_port)) ──"
        while IFS='|' read -r U P EXP CR ML QB _ ST; do
            local QB_H ML_L; [ "$QB" = "0" ] && QB_H="Unlimited" || QB_H=$(bytes_human "$QB")
            [ "$ML" = "0" ] && ML_L="Unlimited" || ML_L="$ML"
            echo "Username : $U | Password : $P | Host : $IP | Port : $(ogh_port)"
            echo "Expired  : $EXP | MaxLogin : $ML_L | Kuota : $QB_H | Status : $ST"
            echo "---"
        done < "$OGH_DB" 2>/dev/null
        echo ""
        echo "── ZivPN-UDP (Port: $(ziv_port)) ──"
        while IFS='|' read -r U P EXP CR ML QB _ ST; do
            local QB_H ML_L; [ "$QB" = "0" ] && QB_H="Unlimited" || QB_H=$(bytes_human "$QB")
            [ "$ML" = "0" ] && ML_L="Unlimited" || ML_L="$ML"
            echo "Username : $U | Password : $P | Host : $IP | Port : $(ziv_port)"
            echo "Expired  : $EXP | MaxLogin : $ML_L | Kuota : $QB_H | Status : $ST"
            echo "Link     : zivpn://${U}:${P}@${IP}:$(ziv_port)"
            echo "---"
        done < "$ZIV_DB" 2>/dev/null
    } > "$OUT"
    ok "Export disimpan: $OUT"
}

sys_info() {
    title "INFO SISTEM LENGKAP"
    echo -e "  ${C}Tanggal    :${NC} $(get_date)"
    echo -e "  ${C}Hostname   :${NC} $(hostname)"
    echo -e "  ${C}OS         :${NC} $(get_os)"
    echo -e "  ${C}Kernel     :${NC} $(get_kernel)"
    echo -e "  ${C}IP Public  :${NC} $(get_ip)"
    echo -e "  ${C}ISP        :${NC} $(get_isp)"
    echo -e "  ${C}Uptime     :${NC} $(get_uptime)"
    echo -e "  ${C}Load Avg   :${NC} $(get_load)"
    echo -e "  ${C}CPU        :${NC} $(get_cpu)"
    echo -e "  ${C}RAM        :${NC} $(get_ram)"
    echo -e "  ${C}Disk       :${NC} $(get_disk)"
    sline
    echo -e "  ${C}OGH Binary :${NC} $OGH_BIN  $(ls -lh "$OGH_BIN" 2>/dev/null | awk '{print "("$5")"}')"
    echo -e "  ${C}ZIV Binary :${NC} $ZIV_BIN  $(ls -lh "$ZIV_BIN" 2>/dev/null | awk '{print "("$5")"}')"
    echo -e "  ${C}OGH Svc    :${NC} $(ogh_stlabel)"
    echo -e "  ${C}ZivPN Svc  :${NC} $(ziv_stlabel)"
    line
}

# ══════════════════════════════════════════════════════════════
#  UPDATE
# ══════════════════════════════════════════════════════════════
update_ogh() {
    info "Update OGH-UDP binary..."
    systemctl stop $OGH_SVC 2>/dev/null; rm -f "$OGH_BIN"
    _dl "$OGH_BIN_URL" "$OGH_BIN"; chmod +x "$OGH_BIN"
    ok "OGH-UDP diperbarui."
    read -p "  Start service? (y/n): " R; [ "$R" = "y" ] && ogh_start
}
update_ziv() {
    info "Update ZivPN-UDP binary..."
    systemctl stop $ZIV_SVC 2>/dev/null; rm -f "$ZIV_BIN"
    _dl "$ZIV_BIN_URL" "$ZIV_BIN"; chmod +x "$ZIV_BIN"
    ok "ZivPN diperbarui."
    read -p "  Start service? (y/n): " R; [ "$R" = "y" ] && ziv_start
}
update_all() { update_ogh; update_ziv; }

check_version() {
    title "VERSI BINARY"
    echo -e "  ${C}OGH-UDP  :${NC} $OGH_BIN"
    ls -lh "$OGH_BIN" 2>/dev/null | awk '{print "  Size:"$5"  Modified:"$6" "$7}'
    echo ""
    echo -e "  ${C}ZivPN    :${NC} $ZIV_BIN"
    ls -lh "$ZIV_BIN" 2>/dev/null | awk '{print "  Size:"$5"  Modified:"$6" "$7}'
    line
}

# ══════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════
auto_install
show_header

while true; do
    echo ""
    read -p "  Pilihan » " CH

    case "$CH" in
        menu|MENU) show_header ;;

        # OGH Akun
        1)  _create_user      "$OGH_DB" "OGH-UDP"  ogh_port "$OGH_QUOTA_DIR" "$OGH_SESSION_DIR" ;;
        2)  _delete_user      "$OGH_DB" "OGH-UDP"           "$OGH_QUOTA_DIR" "$OGH_SESSION_DIR" ;;
        3)  _list_users       "$OGH_DB" "OGH-UDP"           "$OGH_QUOTA_DIR" "$OGH_SESSION_DIR" ;;
        4)  _check_user       "$OGH_DB" "OGH-UDP"  ogh_port "$OGH_QUOTA_DIR" "$OGH_SESSION_DIR" ;;
        5)  _renew_user       "$OGH_DB" "OGH-UDP"           "$OGH_QUOTA_DIR" "$OGH_SESSION_DIR" ;;
        6)  _toggle_lock      "$OGH_DB" "OGH-UDP" ;;
        7)  _set_maxlogin     "$OGH_DB" "OGH-UDP" ;;
        8)  _set_quota        "$OGH_DB" "OGH-UDP"           "$OGH_QUOTA_DIR" ;;
        9)  _reset_quota      "$OGH_DB" "OGH-UDP"           "$OGH_QUOTA_DIR" ;;
        10) _reset_session    "$OGH_DB" "OGH-UDP"                             "$OGH_SESSION_DIR" ;;
        11) _delete_expired   "$OGH_DB" "OGH-UDP"           "$OGH_QUOTA_DIR" "$OGH_SESSION_DIR" ;;
        12) _delete_all_users "$OGH_DB" "OGH-UDP"           "$OGH_QUOTA_DIR" "$OGH_SESSION_DIR" ;;

        # OGH Service
        13) ogh_start ;;       14) ogh_stop ;;
        15) ogh_restart ;;     16) ogh_status ;;
        17) ogh_change_port ;; 18) ogh_log ;;

        # ZivPN Akun
        21) _create_user      "$ZIV_DB" "ZivPN-UDP" ziv_port "$ZIV_QUOTA_DIR" "$ZIV_SESSION_DIR" ;;
        22) _delete_user      "$ZIV_DB" "ZivPN-UDP"          "$ZIV_QUOTA_DIR" "$ZIV_SESSION_DIR" ;;
        23) _list_users       "$ZIV_DB" "ZivPN-UDP"          "$ZIV_QUOTA_DIR" "$ZIV_SESSION_DIR" ;;
        24) _check_user       "$ZIV_DB" "ZivPN-UDP" ziv_port "$ZIV_QUOTA_DIR" "$ZIV_SESSION_DIR" ;;
        25) _renew_user       "$ZIV_DB" "ZivPN-UDP"          "$ZIV_QUOTA_DIR" "$ZIV_SESSION_DIR" ;;
        26) _toggle_lock      "$ZIV_DB" "ZivPN-UDP" ;;
        27) _set_maxlogin     "$ZIV_DB" "ZivPN-UDP" ;;
        28) _set_quota        "$ZIV_DB" "ZivPN-UDP"          "$ZIV_QUOTA_DIR" ;;
        29) _reset_quota      "$ZIV_DB" "ZivPN-UDP"          "$ZIV_QUOTA_DIR" ;;
        30) _reset_session    "$ZIV_DB" "ZivPN-UDP"                            "$ZIV_SESSION_DIR" ;;
        31) _delete_expired   "$ZIV_DB" "ZivPN-UDP"          "$ZIV_QUOTA_DIR" "$ZIV_SESSION_DIR" ;;
        32) _delete_all_users "$ZIV_DB" "ZivPN-UDP"          "$ZIV_QUOTA_DIR" "$ZIV_SESSION_DIR" ;;

        # ZivPN Service
        33) ziv_start ;;       34) ziv_stop ;;
        35) ziv_restart ;;     36) ziv_status ;;
        37) ziv_change_port ;; 38) ziv_log ;;
        39) ziv_view_cfg ;;    40) ziv_edit_cfg ;;
        41) ziv_reset_cfg ;;   42) ziv_change_pass ;;
        43) ziv_change_bw ;;

        # Monitoring
        51) monitor_live   "$OGH_SVC" "$OGH_LOG" "OGH-UDP" ;;
        52) monitor_live   "$ZIV_SVC" "$ZIV_LOG" "ZivPN-UDP" ;;
        53) stats_all_users "$OGH_DB" "OGH-UDP"  "$OGH_QUOTA_DIR" "$OGH_SESSION_DIR" ;;
        54) stats_all_users "$ZIV_DB" "ZivPN-UDP" "$ZIV_QUOTA_DIR" "$ZIV_SESSION_DIR" ;;
        55) check_soon_expired ;;
        56) backup_db ;;
        57) restore_db ;;
        58) export_users ;;

        # System
        61) update_all ;;      62) update_ogh ;;
        63) update_ziv ;;      64) check_version ;;
        65) start_all ;;       66) stop_all ;;
        67) restart_all ;;     68) sys_info ;;

        0) echo -e "${C}  Sampai jumpa!${NC}"; break ;;
        *) err "Pilihan tidak valid. Ketik 'menu' untuk tampil ulang." ;;
    esac
done
