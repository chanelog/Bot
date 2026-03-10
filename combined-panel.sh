#!/bin/bash
# ============================================================
#   OGH-ZIV COMBINED PANEL
#   Creator : OGH-ZIV Team
#   Ketik   : menu  untuk membuka panel
#   Support : Debian (all version) & Ubuntu (all version)
#   Panel   : UDP Request (UDPserver) + UDP ZiVPN
# ============================================================

# ════════════════════════════════════════════════════════════
#  CEK OS & ROOT
# ════════════════════════════════════════════════════════════
check_os() {
    if [[ ! -f /etc/os-release ]]; then
        echo -e "\n\033[1;31m✘ OS tidak dikenali! Script ini hanya untuk Debian & Ubuntu.\033[0m\n"
        exit 1
    fi
    source /etc/os-release 2>/dev/null
    local os_name; os_name=$(echo "${ID}" | tr '[:upper:]' '[:lower:]')
    local os_like; os_like=$(echo "${ID_LIKE:-}" | tr '[:upper:]' '[:lower:]')
    if [[ "$os_name" != "debian" && "$os_name" != "ubuntu" ]] \
       && [[ "$os_like" != *"debian"* && "$os_like" != *"ubuntu"* ]]; then
        echo ""
        echo -e "\033[1;31m  ╔══════════════════════════════════════════════════════╗\033[0m"
        echo -e "\033[1;31m  ║   ✘  OS TIDAK DIDUKUNG!                              ║\033[0m"
        echo -e "\033[1;31m  ╠══════════════════════════════════════════════════════╣\033[0m"
        echo -e "\033[1;31m  ║\033[0m  OS kamu : \033[1;33m${PRETTY_NAME:-$ID}\033[0m"
        echo -e "\033[1;31m  ╠══════════════════════════════════════════════════════╣\033[0m"
        echo -e "\033[1;31m  ║\033[0m  Script ini hanya mendukung:                        \033[1;31m║\033[0m"
        echo -e "\033[1;31m  ║\033[0m  \033[1;32m✔\033[0m  Debian (semua versi)                          \033[1;31m║\033[0m"
        echo -e "\033[1;31m  ║\033[0m  \033[1;32m✔\033[0m  Ubuntu (semua versi)                          \033[1;31m║\033[0m"
        echo -e "\033[1;31m  ╚══════════════════════════════════════════════════════╝\033[0m"
        echo ""
        exit 1
    fi
    OS_NAME="${PRETTY_NAME:-$ID $VERSION_ID}"
    OS_ID="$os_name"
}

check_root() {
    [[ $EUID -ne 0 ]] && { echo -e "\n\033[1;31m✘ Jalankan sebagai root!\033[0m\n"; exit 1; }
}

# ════════════════════════════════════════════════════════════
#  ══════════════ BAGIAN 1: UDP ZiVPN (OGH-ZIV) ══════════════
# ════════════════════════════════════════════════════════════

# ── KONSTANTA & PATH (ZiVPN) ────────────────────────────────
DIR="/etc/zivpn"
CFG="$DIR/config.json"
BIN="/usr/local/bin/zivpn-bin"
SVC="/etc/systemd/system/zivpn.service"
LOG="$DIR/zivpn.log"
UDB="$DIR/users.db"
DOMF="$DIR/domain.conf"
BOTF="$DIR/bot.conf"
STRF="$DIR/store.conf"
THEMEF="$DIR/theme.conf"
MLDB="$DIR/maxlogin.db"
BINARY_URL="https://github.com/fauzanihanipah/ziv-udp/releases/download/udp-zivpn/udp-zivpn-linux-amd64"
CONFIG_URL="https://raw.githubusercontent.com/fauzanihanipah/ziv-udp/main/config.json"

# ── UTILS ZiVPN ─────────────────────────────────────────────
ok()    { echo -e "  ${A2}✔${NC}  $*"; }
inf()   { echo -e "  ${A3}➜${NC}  $*"; }
warn()  { echo -e "  ${A4}⚠${NC}  $*"; }
err()   { echo -e "  \033[1;31m✘${NC}  $*"; }
pause() { echo ""; echo -ne "  ${DIM}╰─ [ Enter ] kembali ke menu...${NC}"; read -r; }

get_ip()     { curl -s4 --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'; }
get_port()   { grep -o '"listen":":[0-9]*"\|"listen": *":[0-9]*"' "$CFG" 2>/dev/null | grep -o '[0-9]*' || echo "5667"; }
get_domain() { cat "$DOMF" 2>/dev/null || get_ip; }
is_up()      { systemctl is-active --quiet zivpn 2>/dev/null; }
total_user() { [[ -f "$UDB" ]] && grep -c '' "$UDB" 2>/dev/null || echo 0; }
exp_count()  {
    local t; t=$(date +%Y-%m-%d)
    [[ -f "$UDB" ]] && awk -F'|' -v d="$t" '$3<d{c++}END{print c+0}' "$UDB" || echo 0
}
rand_pass()  { tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12; }

# ── MAXLOGIN HELPERS ────────────────────────────────────────
get_maxlogin() { grep "^${1}|" "$MLDB" 2>/dev/null | cut -d'|' -f2; }
set_maxlogin() { sed -i "/^${1}|/d" "$MLDB" 2>/dev/null; echo "${1}|${2}" >> "$MLDB"; }
del_maxlogin() { sed -i "/^${1}|/d" "$MLDB" 2>/dev/null; }

count_active_conn() {
    local u="$1"; local port; port=$(get_port)
    ss -u -n -p 2>/dev/null | grep ":$port" | grep -c "$u" 2>/dev/null || echo 0
}

check_maxlogin_all() {
    [[ ! -f "$MLDB" || ! -f "$UDB" ]] && return
    local port; port=$(get_port)
    local today; today=$(date +%Y-%m-%d)
    while IFS='|' read -r uname maxdev; do
        [[ -z "$uname" || -z "$maxdev" ]] && continue
        local active=0
        [[ -f "$LOG" ]] && active=$(grep -c "user=$uname" "$LOG" 2>/dev/null || echo 0)
        if [[ "$active" -gt "$maxdev" ]]; then
            sed -i "/^${uname}|/d" "$UDB"
            del_maxlogin "$uname"
            _reload_pw
            _tg_send "🚫 <b>Auto-Delete MaxLogin</b>
👤 User: <code>$uname</code>
⚠️ Melebihi batas ${maxdev} device — akun otomatis dihapus!"
        fi
    done < "$MLDB"
}

# ── TEMA WARNA ──────────────────────────────────────────────
load_theme() {
    local theme=1
    [[ -f "$THEMEF" ]] && theme=$(cat "$THEMEF" 2>/dev/null)
    case "$theme" in
        2) A1='\033[38;5;51m'; A2='\033[1;36m'; A3='\033[0;36m'; A4='\033[1;33m'
           AL='\033[38;5;87m'; AT='\033[1;37m'; THEME_NAME="CYAN" ;;
        3) A1='\033[38;5;46m'; A2='\033[1;32m'; A3='\033[0;32m'; A4='\033[1;33m'
           AL='\033[38;5;82m'; AT='\033[1;37m'; THEME_NAME="GREEN" ;;
        4) A1='\033[38;5;220m'; A2='\033[1;33m'; A3='\033[38;5;214m'; A4='\033[0;33m'
           AL='\033[38;5;226m'; AT='\033[1;37m'; THEME_NAME="GOLD" ;;
        5) A1='\033[38;5;196m'; A2='\033[1;31m'; A3='\033[0;31m'; A4='\033[1;33m'
           AL='\033[38;5;203m'; AT='\033[1;37m'; THEME_NAME="RED" ;;
        6) A1='\033[38;5;213m'; A2='\033[1;35m'; A3='\033[0;35m'; A4='\033[1;33m'
           AL='\033[38;5;219m'; AT='\033[1;37m'; THEME_NAME="PINK" ;;
        7) A1='\033[1;37m'; A2='\033[1;37m'; A3='\033[38;5;51m'; A4='\033[1;33m'
           AL='\033[38;5;196m'; AT='\033[1;37m'; THEME_NAME="RAINBOW" ;;
        *) A1='\033[38;5;135m'; A2='\033[1;35m'; A3='\033[38;5;141m'; A4='\033[1;33m'
           AL='\033[38;5;141m'; AT='\033[38;5;231m'; THEME_NAME="VIOLET" ;;
    esac
    NC='\033[0m'; BLD='\033[1m'; DIM='\033[2m'; IT='\033[3m'
    W='\033[1;37m'; LG='\033[1;32m'; LR='\033[1;31m'; LC='\033[1;36m'; Y='\033[1;33m'
}

menu_tema() {
    while true; do
        clear; load_theme
        local cur_theme; cur_theme=$(cat "$THEMEF" 2>/dev/null || echo 1)
        echo ""
        echo -e "  ${A1}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "  ${A1}║${NC}  ${IT}${AL}  🎨  PILIH TEMA WARNA${NC}                           ${A1}║${NC}"
        echo -e "  ${A1}╠══════════════════════════════════════════════════════╣${NC}"
        echo -e "  ${A1}║${NC}                                                      ${A1}║${NC}"
        local themes=("VIOLET  — Ungu Premium" "CYAN    — Neon Biru" "GREEN   — Matrix Hijau"
                      "GOLD    — Emas Mewah"   "RED     — Merah Elegan" "PINK    — Pink Pastel"
                      "RAINBOW — Pelangi Cantik")
        local icons=("💜" "🩵" "💚" "💛" "❤️" "🩷" "🌈")
        for i in "${!themes[@]}"; do
            local n=$((i+1))
            local mark="   "
            [[ "$cur_theme" == "$n" ]] && mark="${A2}▶${NC} "
            if [[ $n -eq 7 ]]; then
                printf "  ${A1}║${NC}    %b🌈  ${A1}[7]${NC}  \033[38;5;196mR\033[38;5;208mA\033[38;5;226mI\033[38;5;82mN\033[38;5;51mB\033[38;5;171mO\033[38;5;213mW\033[0m  — Pelangi Cantik              ${A1}║${NC}\n" "$mark"
            else
                printf "  ${A1}║${NC}    %b${icons[$i]}  ${A1}[%s]${NC}  %-30s        ${A1}║${NC}\n" "$mark" "$n" "${themes[$i]}"
            fi
        done
        echo -e "  ${A1}╠══════════════════════════════════════════════════════╣${NC}"
        echo -e "  ${A1}║${NC}  ${DIM}Tema aktif sekarang : ${AT}${THEME_NAME}${NC}                        ${A1}║${NC}"
        echo -e "  ${A1}╠══════════════════════════════════════════════════════╣${NC}"
        echo -e "  ${A1}║${NC}  ${LR}[0]${NC}  ◀  Kembali ke menu utama                      ${A1}║${NC}"
        echo -e "  ${A1}╚══════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -ne "  ${A1}›${NC} Pilih tema [0-7]: "; read -r ch
        case $ch in
            [1-7]) echo "$ch" > "$THEMEF"; load_theme; ok "Tema ${AT}${THEME_NAME}${NC} aktif!"; sleep 0.8 ;;
            0) break ;;
            *) warn "Pilihan tidak valid!"; sleep 0.5 ;;
        esac
    done
}

draw_logo() {
    local cur_theme; cur_theme=$(cat "$THEMEF" 2>/dev/null || echo 1)
    local L1 L2 L3 L4 L5
    if [[ "$cur_theme" == "7" ]]; then
        L1='\033[38;5;196m'; L2='\033[38;5;214m'; L3='\033[38;5;226m'
        L4='\033[38;5;82m';  L5='\033[38;5;51m'
    else
        L1="$AL"; L2="$AL"; L3="$A3"; L4="$AL"; L5="$A3"
    fi
    echo ""
    echo -e "  ${A1}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${A1}║${NC}  ${L1}${BLD}  ██████╗  ██████╗ ██╗  ██╗    ███████╗██╗██╗   ██╗${NC}  ${A1}║${NC}"
    echo -e "  ${A1}║${NC}  ${L2}${BLD} ██╔═══██╗██╔════╝ ██║  ██║    ╚══███╔╝██║██║   ██║${NC}  ${A1}║${NC}"
    echo -e "  ${A1}║${NC}  ${L3}${BLD} ██║   ██║██║  ███╗███████║      ███╔╝ ██║██║   ██║${NC}  ${A1}║${NC}"
    echo -e "  ${A1}║${NC}  ${L4}${BLD} ██║   ██║██║   ██║██╔══██║     ███╔╝  ██║╚██╗ ██╔╝${NC}  ${A1}║${NC}"
    echo -e "  ${A1}║${NC}  ${L5}${BLD} ╚██████╔╝╚██████╔╝██║  ██║    ███████╗██║ ╚████╔╝ ${NC}  ${A1}║${NC}"
    echo -e "  ${A1}║${NC}  ${DIM}      ╚═════╝  ╚═════╝ ╚═╝  ╚═╝    ╚══════╝╚═╝  ╚═══╝  ${NC}  ${A1}║${NC}"
    echo -e "  ${A1}╠══════════════════════════════════════════════════════════╣${NC}"
    printf  "  ${A1}║${NC}%*s${A4}★  SECURE VPN MANAGEMENT SYSTEM  ★${NC}%*s${A1}║${NC}\n" 11 "" 11 ""
    printf  "  ${A1}║${NC}%*s${DIM}◈ ─────────── ${A2}[ PREMIUM ]${DIM} ─────────── ◈${NC}%*s${A1}║${NC}\n" 8 "" 8 ""
    echo -e "  ${A1}╚══════════════════════════════════════════════════════════╝${NC}"
}

draw_vps() {
    local ip;     ip=$(get_ip)
    local port;   port=$(get_port)
    local domain; domain=$(get_domain)
    local ram_u;  ram_u=$(free -m | awk '/^Mem/{print $3}')
    local ram_t;  ram_t=$(free -m | awk '/^Mem/{print $2}')
    local cpu;    cpu=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{printf "%.1f",$2}' || echo "0.0")
    local du;     du=$(df -h / | awk 'NR==2{print $3}')
    local dt;     dt=$(df -h / | awk 'NR==2{print $2}')
    local du_pct; du_pct=$(df / | awk 'NR==2{print $5}' | tr -d '%')
    local os;     os=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo "Linux")
    local hn;     hn=$(hostname)
    local total;  total=$(total_user)
    local expc;   expc=$(exp_count)
    local now_time; now_time=$(date "+%H:%M")
    local now_date; now_date=$(date "+%d/%m/%Y")

    local ram_pct=0
    [[ $ram_t -gt 0 ]] && ram_pct=$(( ram_u * 100 / ram_t ))

    local svc_ic svc_txt svc_col
    if is_up; then svc_col="${LG}"; svc_ic="●"; svc_txt="RUNNING"
    else           svc_col="${LR}"; svc_ic="●"; svc_txt="STOPPED"; fi

    # Status UDPserver
    local udp_svc_col udp_svc_txt udp_svc_ic
    if systemctl is-active --quiet UDPserver 2>/dev/null; then
        udp_svc_col="${LG}"; udp_svc_ic="●"; udp_svc_txt="UDP-ON"
    else
        udp_svc_col="${LR}"; udp_svc_ic="●"; udp_svc_txt="UDP-OFF"
    fi

    local bot_txt="Belum setup"; local bot_col="${LR}"
    if [[ -f "$BOTF" ]]; then
        source "$BOTF" 2>/dev/null
        local bot_count=0
        [[ -n "$BOT_TOKEN"  ]] && ((bot_count++))
        [[ -n "$BOT_TOKEN2" ]] && ((bot_count++))
        [[ -n "$BOT_TOKEN3" ]] && ((bot_count++))
        if [[ $bot_count -gt 0 ]]; then bot_txt="${bot_count} Bot Aktif"; bot_col="${LG}"; fi
    fi

    local brand="OGH-ZIV"
    [[ -f "$STRF" ]] && { source "$STRF" 2>/dev/null; brand="${BRAND:-OGH-ZIV}"; }

    local tema_display
    if [[ "$THEME_NAME" == "RAINBOW" ]]; then
        tema_display="\033[38;5;196mR\033[38;5;208mA\033[38;5;226mI\033[38;5;82mN\033[38;5;51mB\033[38;5;171mO\033[38;5;213mW\033[0m"
    else
        tema_display="${AL}${THEME_NAME}${NC}"
    fi

    echo ""
    echo -e "  ${A1}╔══════════════════════════════════════════════════════════╗${NC}"
    _btn "  ${A4}◈${NC} ${BLD}${A4}INFO VPS${NC}  ${DIM}${now_time}  │  ${now_date}${NC}"
    echo -e "  ${A1}╠══════════════════════════════════════════════════════════╣${NC}"
    local os_short; os_short=$(echo "$os" | cut -c1-14)
    local domain_short; domain_short=$(echo "$domain" | cut -c1-14)
    _btn "  ${DIM}HOST    ${NC}${A1}│${NC} ${A3}$(printf '%-16s' "$hn")${NC}  ${DIM}OS      ${NC}${A1}│${NC} ${W}${os_short}${NC}"
    echo -e "  ${A1}╠╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╣${NC}"
    _btn "  ${DIM}IP ADDR ${NC}${A1}│${NC} ${A3}$(printf '%-16s' "$ip")${NC}  ${DIM}DOMAIN  ${NC}${A1}│${NC} ${W}${domain_short}${NC}"
    echo -e "  ${A1}╠╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╣${NC}"
    _btn "  ${DIM}PORT    ${NC}${A1}│${NC} ${Y}$(printf '%-16s' "$port")${NC}  ${DIM}BRAND   ${NC}${A1}│${NC} ${A4}${brand}${NC}"
    echo -e "  ${A1}╠══════════════════════════════════════════════════════════╣${NC}"

    local cpu_bar; cpu_bar=$(
        pct=${cpu%.*}; [[ -z "$pct" || "$pct" == "?" ]] && pct=0
        filled=$(( pct * 10 / 100 )); [[ $filled -gt 10 ]] && filled=10; empty=$(( 10 - filled ))
        bar=""; for ((i=0;i<filled;i++)); do bar+="█"; done
        for ((i=0;i<empty;i++)); do bar+="░"; done; echo "$bar")
    local ram_bar; ram_bar=$(
        pct=$ram_pct; filled=$(( pct * 10 / 100 )); [[ $filled -gt 10 ]] && filled=10; empty=$(( 10 - filled ))
        bar=""; for ((i=0;i<filled;i++)); do bar+="█"; done
        for ((i=0;i<empty;i++)); do bar+="░"; done; echo "$bar")
    local disk_bar; disk_bar=$(
        pct=${du_pct:-3}; filled=$(( pct * 10 / 100 )); [[ $filled -gt 10 ]] && filled=10; empty=$(( 10 - filled ))
        bar=""; for ((i=0;i<filled;i++)); do bar+="█"; done
        for ((i=0;i<empty;i++)); do bar+="░"; done; echo "$bar")

    _btn "  ${DIM}CPU${NC} ${LG}${cpu}%${NC}  ${LG}${cpu_bar}${NC}  ${A1}│${NC}  ${DIM}RAM${NC} ${A3}${ram_u}/${ram_t}MB${NC}  ${A3}${ram_bar}${NC}"
    echo -e "  ${A1}╠╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╣${NC}"
    _btn "  ${DIM}DISK${NC} ${Y}${du}/${dt}${NC}  ${Y}${disk_bar}${NC}"
    echo -e "  ${A1}╠══════════════════════════════════════════════════════════╣${NC}"
    _btn "  ${svc_col}${svc_ic} ZiVPN:${svc_txt}${NC}  ${A1}│${NC}  ${udp_svc_col}${udp_svc_ic} ${udp_svc_txt}${NC}  ${A1}│${NC}  ${DIM}AKUN${NC} ${A3}${total}${NC}  ${A1}│${NC}  ${DIM}EXP${NC} ${LR}${expc}${NC}"
    echo -e "  ${A1}╠╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╣${NC}"
    _btn "  ${DIM}TEMA${NC}  ${tema_display}  ${A1}│${NC}  ${DIM}BOT${NC} ${bot_col}${bot_txt}${NC}"
    echo -e "  ${A1}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_header() { clear; load_theme; draw_logo; draw_vps; }

# ── BOX AKUN ────────────────────────────────────────────────
show_akun_box() {
    local u="$1" p="$2" dom="$3" prt="$4" ql="$5" exp="$6" note="$7" ip_pub="$8" maxl="${9:-2}"
    echo ""
    echo -e "  ${A1}┌──────────────┬───────────────────────────────────────────┐${NC}"
    echo -e "  ${A1}│${NC}  ${LG}✔  Akun Berhasil!${NC}                                      ${A1}│${NC}"
    echo -e "  ${A1}├──────────────┼───────────────────────────────────────────┤${NC}"
    printf  "  ${A1}│${NC} ${DIM} Username  ${NC} ${A1}│${NC}  ${W}%-41s${NC}  ${A1}│${NC}\n" "$u"
    printf  "  ${A1}│${NC} ${DIM} Password  ${NC} ${A1}│${NC}  ${A3}%-41s${NC}  ${A1}│${NC}\n" "$p"
    echo -e "  ${A1}├╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┤${NC}"
    printf  "  ${A1}│${NC} ${DIM} IP Publik ${NC} ${A1}│${NC}  ${W}%-41s${NC}  ${A1}│${NC}\n" "$ip_pub"
    printf  "  ${A1}│${NC} ${DIM} Host/Domain${NC}${A1}│${NC}  ${W}%-41s${NC}  ${A1}│${NC}\n" "$dom"
    printf  "  ${A1}│${NC} ${DIM} Port      ${NC} ${A1}│${NC}  ${Y}%-41s${NC}  ${A1}│${NC}\n" "$prt"
    printf  "  ${A1}│${NC} ${DIM} Obfs      ${NC} ${A1}│${NC}  ${A3}%-41s${NC}  ${A1}│${NC}\n" "zivpn"
    echo -e "  ${A1}├╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┤${NC}"
    printf  "  ${A1}│${NC} ${DIM} Kuota     ${NC} ${A1}│${NC}  ${A4}%-41s${NC}  ${A1}│${NC}\n" "$ql"
    printf  "  ${A1}│${NC} ${DIM} MaxLogin  ${NC} ${A1}│${NC}  ${A4}%-41s${NC}  ${A1}│${NC}\n" "${maxl} device"
    printf  "  ${A1}│${NC} ${DIM} Expired   ${NC} ${A1}│${NC}  ${LR}%-41s${NC}  ${A1}│${NC}\n" "$exp"
    printf  "  ${A1}│${NC} ${DIM} Pembeli   ${NC} ${A1}│${NC}  ${DIM}%-41s${NC}  ${A1}│${NC}\n" "$note"
    echo -e "  ${A1}└──────────────┴───────────────────────────────────────────┘${NC}"
}

_reload_pw() {
    [[ ! -f "$UDB" || ! -f "$CFG" ]] && return
    local pws=()
    while IFS='|' read -r u p _; do
        pws+=("\"${u}:${p}\"")
    done < "$UDB"
    local pwl; pwl=$(IFS=','; echo "${pws[*]}")
    python3 - <<PYEOF 2>/dev/null
import json
with open('$CFG') as f: c=json.load(f)
c['auth']['config']=[${pwl}]
with open('$CFG','w') as f: json.dump(c,f,indent=2)
PYEOF
    systemctl restart zivpn &>/dev/null
}

_tg_send() {
    [[ ! -f "$BOTF" ]] && return
    source "$BOTF" 2>/dev/null
    local msg="$1"
    [[ -n "$BOT_TOKEN"  && -n "$CHAT_ID"  ]] && curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"  -d "chat_id=${CHAT_ID}"  -d "text=${msg}" -d "parse_mode=HTML" &>/dev/null
    [[ -n "$BOT_TOKEN2" && -n "$CHAT_ID2" ]] && curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN2}/sendMessage" -d "chat_id=${CHAT_ID2}" -d "text=${msg}" -d "parse_mode=HTML" &>/dev/null
    [[ -n "$BOT_TOKEN3" && -n "$CHAT_ID3" ]] && curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN3}/sendMessage" -d "chat_id=${CHAT_ID3}" -d "text=${msg}" -d "parse_mode=HTML" &>/dev/null
}

_tg_raw() {
    local tok="$1" cid="$2" msg="$3"
    curl -s -X POST "https://api.telegram.org/bot${tok}/sendMessage" \
        -d "chat_id=${cid}" -d "text=${msg}" -d "parse_mode=HTML" &>/dev/null
}

# ── HELPER PANEL BUTTONS ─────────────────────────────────────
_BOX_W=56
_LINE="════════════════════════════════════════════════════════"
_LINED="╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌"

_top()  { echo -e "  ${A1}╔${_LINE}╗${NC}"; }
_bot()  { echo -e "  ${A1}╚${_LINE}╝${NC}"; }
_sep()  { echo -e "  ${A1}╠${_LINE}╣${NC}"; }
_sep0() { echo -e "  ${A1}╠${_LINED}╣${NC}"; }

_displen() {
    local raw="$1"
    local clean; clean=$(printf '%b' "$raw" 2>/dev/null | \
        sed 's/\x1b\[[0-9;]*[mJKHfABCDsuhlp]//g; s/\x1b[()][AB012]//g; s/\x1b//g' 2>/dev/null)
    python3 -c "
import unicodedata, sys
s = sys.argv[1]
w = sum(2 if unicodedata.east_asian_width(c) in ('W','F') else 1 for c in s)
print(w)
" "$clean" 2>/dev/null || echo "${#clean}"
}

_btn() {
    local raw="$1"
    local dlen; dlen=$(_displen "$raw")
    local pad=$(( _BOX_W - dlen ))
    [[ $pad -lt 0 ]] && pad=0
    local spaces; spaces=$(printf '%*s' "$pad" '')
    printf "  ${A1}║${NC}%b%s${A1}║${NC}\n" "$raw" "$spaces"
}

# ────────────────────────────────────────────────────────────
# INSTALL ZiVPN
# ────────────────────────────────────────────────────────────
do_install() {
    show_header
    _top; _btn "  ${IT}${AL}🚀  INSTALL ZIVPN${NC}"; _bot; echo ""
    inf "Membersihkan file lama (jika ada)..."
    systemctl stop    zivpn.service 2>/dev/null
    systemctl disable zivpn.service 2>/dev/null
    rm -f "$BIN" "$SVC" "$DIR/zivpn.key" "$DIR/zivpn.crt" "$DIR/config.json" "$DIR/zivpn.log"
    systemctl daemon-reload 2>/dev/null
    ok "File lama dibersihkan — data akun & konfigurasi dipertahankan"
    local sip; sip=$(get_ip)
    echo -ne "  ${A3}Domain / IP${NC}            : "; read -r inp_domain
    [[ -z "$inp_domain" ]] && inp_domain="$sip"
    echo -ne "  ${A3}Port${NC} [5667]             : "; read -r inp_port
    [[ -z "$inp_port" ]] && inp_port=5667
    echo -ne "  ${A3}Nama Brand / Toko${NC}       : "; read -r inp_brand
    [[ -z "$inp_brand" ]] && inp_brand="OGH-ZIV"
    echo -ne "  ${A3}Username Telegram Admin${NC}  : "; read -r inp_tg
    [[ -z "$inp_tg" ]] && inp_tg="-"
    echo ""
    inf "Memulai instalasi ${AL}OGH-ZIV Premium${NC}..."
    apt-get update -qq &>/dev/null
    apt-get install -y -qq curl wget openssl python3 iptables iptables-persistent netfilter-persistent &>/dev/null
    ok "Dependensi terpasang"
    mkdir -p "$DIR"; touch "$UDB" "$LOG"
    echo "$inp_domain" > "$DOMF"
    printf "BRAND=%s\nADMIN_TG=%s\n" "$inp_brand" "$inp_tg" > "$STRF"
    ok "Direktori & konfigurasi dibuat"
    inf "Downloading UDP Service..."
    wget "$BINARY_URL" -O "$BIN"
    if [[ ! -s "$BIN" ]]; then
        err "Gagal download binary ZiVPN!"; rm -f "$BIN"; pause; return 1
    fi
    chmod +x "$BIN"; ok "Binary ZiVPN siap"
    inf "Mengunduh config.json..."
    wget "$CONFIG_URL" -O "$CFG"
    if [[ ! -s "$CFG" ]]; then
        cat > "$CFG" <<CFEOF
{"listen":":${inp_port}","cert":"/etc/zivpn/zivpn.crt","key":"/etc/zivpn/zivpn.key","obfs":"zivpn","auth":{"mode":"passwords","config":[]}}
CFEOF
    else
        python3 - <<PYEOF 2>/dev/null
import json
try:
    with open('$CFG') as f: c = json.load(f)
    c['listen'] = ':${inp_port}'
    with open('$CFG','w') as f: json.dump(c, f, indent=2)
except: pass
PYEOF
    fi
    ok "config.json siap"
    inf "Generating SSL Certificate..."
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
        -subj "/C=US/ST=California/L=Los Angeles/O=Example Corp/OU=IT Department/CN=zivpn" \
        -keyout "$DIR/zivpn.key" -out "$DIR/zivpn.crt" &>/dev/null
    ok "SSL Certificate RSA-4096 dibuat"
    sysctl -w net.core.rmem_max=16777216 &>/dev/null
    sysctl -w net.core.wmem_max=16777216 &>/dev/null
    grep -q 'rmem_max' /etc/sysctl.conf 2>/dev/null || \
        printf "net.core.rmem_max=16777216\nnet.core.wmem_max=16777216\n" >> /etc/sysctl.conf
    ok "Buffer UDP dioptimasi"
    cat > "$SVC" <<SVEOF
[Unit]
Description=zivpn VPN Server
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=$DIR
ExecStart=$BIN server -c $CFG
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true
LimitNOFILE=1048576
StandardOutput=append:$LOG
StandardError=append:$LOG
[Install]
WantedBy=multi-user.target
SVEOF
    ok "Systemd service dibuat"
    local IFACE; IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    while iptables -t nat -D PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :${inp_port} 2>/dev/null; do :; done
    iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :${inp_port}
    iptables -A FORWARD -p udp -d 127.0.0.1 --dport "${inp_port}" -j ACCEPT
    iptables -t nat -A POSTROUTING -s 127.0.0.1/32 -o "$IFACE" -j MASQUERADE
    netfilter-persistent save &>/dev/null
    iptables -I INPUT -p udp --dport "${inp_port}" -j ACCEPT 2>/dev/null
    ok "IPTables: UDP 6000-19999 → ${inp_port}"
    systemctl daemon-reload
    systemctl enable zivpn.service &>/dev/null
    systemctl start  zivpn.service
    sleep 1
    systemctl is-active --quiet zivpn && ok "Service ZiVPN aktif & berjalan" || warn "Service gagal start"
    echo ""
    echo -e "  ${A1}┌──────────────┬───────────────────────────────────────────┐${NC}"
    echo -e "  ${A1}│${NC}  ${LG}${BLD}  ✦ OGH-ZIV PREMIUM BERHASIL DIINSTALL!${NC}                ${A1}│${NC}"
    echo -e "  ${A1}├──────────────┼───────────────────────────────────────────┤${NC}"
    printf  "  ${A1}│${NC} ${DIM} Domain    ${NC} ${A1}│${NC}  ${W}%-41s${NC}  ${A1}│${NC}\n" "$inp_domain"
    printf  "  ${A1}│${NC} ${DIM} Port      ${NC} ${A1}│${NC}  ${Y}%-41s${NC}  ${A1}│${NC}\n" "$inp_port"
    printf  "  ${A1}│${NC} ${DIM} Brand     ${NC} ${A1}│${NC}  ${AL}%-41s${NC}  ${A1}│${NC}\n" "$inp_brand"
    echo -e "  ${A1}└──────────────┴───────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${DIM}Ketik ${A1}menu${NC}${DIM} untuk membuka panel kapan saja.${NC}"
    pause
}

do_uninstall() {
    show_header
    _top; _btn "  ${IT}${LR}🗑️   UNINSTALL ZIVPN${NC}"; _bot; echo ""
    echo -ne "  ${LR}Yakin ingin uninstall ZiVPN? [y/N]${NC}: "; read -r yn
    [[ ! "$yn" =~ ^[Yy]$ ]] && return
    systemctl stop zivpn 2>/dev/null; systemctl disable zivpn 2>/dev/null
    rm -f "$BIN" "$SVC" "$DIR/zivpn.key" "$DIR/zivpn.crt" "$CFG" "$LOG"
    systemctl daemon-reload 2>/dev/null
    ok "ZiVPN berhasil di-uninstall."; pause
}

# ────────────────────────────────────────────────────────────
# MANAJEMEN USER ZiVPN
# ────────────────────────────────────────────────────────────
u_add() {
    show_header; _top; _btn "  ${IT}${AL}➕  TAMBAH AKUN BARU${NC}"; _bot; echo ""
    echo -ne "  ${A3}Username${NC}               : "; read -r un
    [[ -z "$un" ]] && { err "Username kosong!"; pause; return; }
    grep -q "^${un}|" "$UDB" 2>/dev/null && { err "Username sudah ada!"; pause; return; }
    echo -ne "  ${A3}Password${NC} [auto]         : "; read -r up; [[ -z "$up" ]] && up=$(rand_pass)
    echo -ne "  ${A3}Masa aktif (hari)${NC} [30]  : "; read -r ud; [[ -z "$ud" ]] && ud=30
    local ue; ue=$(date -d "+${ud} days" +"%Y-%m-%d")
    echo -ne "  ${A3}Kuota GB${NC} (0=unlimited)  : "; read -r uq; [[ -z "$uq" ]] && uq=0
    echo -ne "  ${A3}Catatan / Nama Pembeli${NC}  : "; read -r note; [[ -z "$note" ]] && note="-"
    echo -ne "  ${A3}Max Login Device${NC} [2]    : "; read -r uml
    [[ -z "$uml" || ! "$uml" =~ ^[0-9]+$ ]] && uml=2
    echo "${un}|${up}|${ue}|${uq}|${note}" >> "$UDB"
    set_maxlogin "$un" "$uml"; _reload_pw
    local domain; domain=$(get_domain); local port; port=$(get_port); local ip_pub; ip_pub=$(get_ip)
    local ql; [[ "$uq" == "0" ]] && ql="Unlimited" || ql="${uq} GB"
    [[ -f "$STRF" ]] && source "$STRF" 2>/dev/null
    _tg_send "✅ <b>Akun Baru — ${BRAND:-OGH-ZIV}</b>
│ 👤 User: <code>$un</code> | 🔑 Pass: <code>$up</code>
│ 🌐 Host: <code>$domain</code> | 🔌 Port: <code>$port</code>
│ 📅 Expired: $ue | 🔒 MaxLogin: ${uml} device"
    show_akun_box "$un" "$up" "$domain" "$port" "$ql" "$ue" "$note" "$ip_pub" "$uml"; pause
}

u_list() {
    show_header; _top; _btn "  ${IT}${AL}📋  LIST SEMUA AKUN${NC}"; _bot; echo ""
    [[ ! -s "$UDB" ]] && { warn "Belum ada akun terdaftar."; pause; return; }
    local today; today=$(date +"%Y-%m-%d"); local n=1
    echo -e "  ${A1}┌────┬──────────────────┬────────────┬────────────┬──────────┬─────────┐${NC}"
    printf  "  ${A1}│${NC}${BLD} %-2s ${A1}│${NC}${BLD} %-16s ${A1}│${NC}${BLD} %-10s ${A1}│${NC}${BLD} %-10s ${A1}│${NC}${BLD} %-8s ${A1}│${NC}${BLD} %-7s ${A1}│${NC}\n" \
        "#" "Username" "Password" "Expired" "Kuota" "Status"
    echo -e "  ${A1}├────┼──────────────────┼────────────┼────────────┼──────────┼─────────┤${NC}"
    while IFS='|' read -r u p e q _; do
        local sc sl; [[ "$e" < "$today" ]] && sc="$LR" sl="EXPIRED" || sc="$LG" sl="AKTIF  "
        local ql; [[ "$q" == "0" ]] && ql="Unlim   " || ql="${q}GB     "
        printf "  ${A1}│${NC} ${DIM}%-2s${NC} ${A1}│${NC} ${W}%-16s${NC} ${A1}│${NC} ${A3}%-10s${NC} ${A1}│${NC} ${Y}%-10s${NC} ${A1}│${NC} %-8s ${A1}│${NC} ${sc}%-7s${NC} ${A1}│${NC}\n" \
            "$n" "$u" "$p" "$e" "$ql" "$sl"; ((n++))
    done < "$UDB"
    echo -e "  ${A1}└────┴──────────────────┴────────────┴────────────┴──────────┴─────────┘${NC}"
    echo ""; echo -e "  ${DIM}  Total: $((n-1)) akun  │  Expired: $(exp_count) akun${NC}"; pause
}

u_info() {
    show_header; _top; _btn "  ${IT}${AL}🔍  INFO DETAIL AKUN${NC}"; _bot; echo ""
    echo -ne "  ${A3}Username${NC}: "; read -r un
    local ln; ln=$(grep "^${un}|" "$UDB" 2>/dev/null)
    [[ -z "$ln" ]] && { err "User tidak ditemukan!"; pause; return; }
    IFS='|' read -r u p e q note <<< "$ln"
    local domain; domain=$(get_domain); local port; port=$(get_port); local ip_pub; ip_pub=$(get_ip)
    local ql; [[ "$q" == "0" ]] && ql="Unlimited" || ql="${q} GB"
    local maxl; maxl=$(get_maxlogin "$un"); [[ -z "$maxl" ]] && maxl=2
    show_akun_box "$u" "$p" "$domain" "$port" "$ql" "$e" "$note" "$ip_pub" "$maxl"; pause
}

u_del() {
    show_header; _top; _btn "  ${IT}${AL}🗑️   HAPUS AKUN${NC}"; _bot; echo ""
    [[ ! -s "$UDB" ]] && { warn "Tidak ada akun."; pause; return; }
    local n=1
    while IFS='|' read -r u _ e _ _; do
        printf "  ${DIM}%3s.${NC}  ${W}%-22s${NC}  ${DIM}exp: %s${NC}\n" "$n" "$u" "$e"; ((n++))
    done < "$UDB"
    echo ""; echo -ne "  ${A3}Username yang dihapus${NC}: "; read -r du
    grep -q "^${du}|" "$UDB" 2>/dev/null || { err "User tidak ditemukan!"; pause; return; }
    sed -i "/^${du}|/d" "$UDB"; del_maxlogin "$du"; _reload_pw
    _tg_send "🗑 <b>Akun Dihapus</b> : <code>$du</code>"
    ok "Akun '${W}$du${NC}' berhasil dihapus."; pause
}

u_renew() {
    show_header; _top; _btn "  ${IT}${AL}🔁  PERPANJANG AKUN${NC}"; _bot; echo ""
    echo -ne "  ${A3}Username${NC}    : "; read -r ru
    grep -q "^${ru}|" "$UDB" 2>/dev/null || { err "User tidak ditemukan!"; pause; return; }
    echo -ne "  ${A3}Tambah hari${NC} : "; read -r rd; [[ -z "$rd" ]] && rd=30
    local ce; ce=$(grep "^${ru}|" "$UDB" | cut -d'|' -f3)
    local today; today=$(date +%Y-%m-%d)
    [[ "$ce" < "$today" ]] && ce="$today"
    local ne; ne=$(date -d "${ce} +${rd} days" +"%Y-%m-%d")
    sed -i "s/^\(${ru}|[^|]*|\)[^|]*/\1${ne}/" "$UDB"
    _tg_send "🔁 <b>Akun Diperpanjang</b>
👤 User: <code>$ru</code> | 📅 Expired: <b>$ne</b> (+${rd} hari)"
    ok "Akun ${W}$ru${NC} diperpanjang hingga ${Y}$ne${NC}"; pause
}

u_chpass() {
    show_header; _top; _btn "  ${IT}${AL}🔑  GANTI PASSWORD${NC}"; _bot; echo ""
    echo -ne "  ${A3}Username${NC}           : "; read -r pu
    grep -q "^${pu}|" "$UDB" 2>/dev/null || { err "User tidak ditemukan!"; pause; return; }
    echo -ne "  ${A3}Password baru${NC} [auto]: "; read -r pp; [[ -z "$pp" ]] && pp=$(rand_pass)
    sed -i "s/^${pu}|[^|]*/${pu}|${pp}/" "$UDB"; _reload_pw
    ok "Password akun ${W}$pu${NC} berhasil diubah menjadi: ${A3}$pp${NC}"; pause
}

u_trial() {
    show_header; _top; _btn "  ${IT}${AL}🎁  BUAT AKUN TRIAL${NC}"; _bot; echo ""
    local tu="trial$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"
    local tp; tp=$(rand_pass)
    local te; te=$(date -d "+1 day" +"%Y-%m-%d")
    local ip_pub; ip_pub=$(get_ip)
    echo "${tu}|${tp}|${te}|1|TRIAL" >> "$UDB"; _reload_pw
    local domain; domain=$(get_domain); local port; port=$(get_port)
    _tg_send "🎁 <b>Akun Trial Dibuat</b>
👤 User: <code>$tu</code> | 🔑 Pass: <code>$tp</code>
🖥 IP: <code>$ip_pub</code> | 📅 Exp: $te (1 hari / 1 GB)"
    show_akun_box "$tu" "$tp" "$domain" "$port" "1 GB" "$te" "TRIAL" "$ip_pub"; pause
}

u_clean() {
    show_header; _top; _btn "  ${IT}${AL}🧹  HAPUS AKUN EXPIRED${NC}"; _bot; echo ""
    local today; today=$(date +"%Y-%m-%d"); local cnt=0
    while IFS='|' read -r u _ e _ _; do
        if [[ "$e" < "$today" ]]; then
            sed -i "/^${u}|/d" "$UDB"; del_maxlogin "$u"
            ok "Dihapus: ${W}$u${NC}  ${DIM}(exp: $e)${NC}"; ((cnt++))
        fi
    done < <(cat "$UDB" 2>/dev/null)
    echo ""
    [[ $cnt -gt 0 ]] && { _reload_pw; ok "Total ${W}$cnt${NC} akun expired dihapus."; } \
                     || inf "Tidak ada akun expired."; pause
}

# ── JUALAN ──────────────────────────────────────────────────
t_akun() {
    show_header; _top; _btn "  ${IT}${AL}📨  TEMPLATE PESAN AKUN${NC}"; _bot; echo ""
    [[ -f "$STRF" ]] && source "$STRF" 2>/dev/null
    echo -ne "  ${A3}Username${NC}: "; read -r tu
    local ln; ln=$(grep "^${tu}|" "$UDB" 2>/dev/null)
    [[ -z "$ln" ]] && { err "User tidak ditemukan!"; pause; return; }
    IFS='|' read -r u p e q note <<< "$ln"
    local domain; domain=$(get_domain); local port; port=$(get_port); local ip_pub; ip_pub=$(get_ip)
    local ql; [[ "$q" == "0" ]] && ql="Unlimited" || ql="${q} GB"
    show_akun_box "$u" "$p" "$domain" "$port" "$ql" "$e" "$note" "$ip_pub"; pause
}

set_store() {
    show_header; _top; _btn "  ${IT}${AL}⚙️   PENGATURAN TOKO${NC}"; _bot; echo ""
    [[ -f "$STRF" ]] && source "$STRF" 2>/dev/null
    echo -ne "  ${A3}Nama Brand / Toko${NC} [${BRAND:-OGH-ZIV}]: "; read -r nb
    [[ -n "$nb" ]] && BRAND="$nb"
    echo -ne "  ${A3}Username Telegram Admin${NC} [@${ADMIN_TG:--}]: "; read -r ntg
    [[ -n "$ntg" ]] && ADMIN_TG="$ntg"
    printf "BRAND=%s\nADMIN_TG=%s\n" "$BRAND" "$ADMIN_TG" > "$STRF"
    ok "Pengaturan toko disimpan!"; pause
}

tg_kirim_akun() {
    [[ ! -f "$BOTF" ]] && { warn "Bot Telegram belum dikonfigurasi."; pause; return; }
    source "$BOTF" 2>/dev/null
    [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]] && { warn "Token/Chat ID tidak ditemukan."; pause; return; }
    show_header; _top; _btn "  ${IT}${AL}📤  KIRIM AKUN KE TELEGRAM${NC}"; _bot; echo ""
    echo -ne "  ${A3}Username${NC}: "; read -r tu
    local ln; ln=$(grep "^${tu}|" "$UDB" 2>/dev/null)
    [[ -z "$ln" ]] && { err "User tidak ditemukan!"; pause; return; }
    IFS='|' read -r u p e q note <<< "$ln"
    local domain; domain=$(get_domain); local port; port=$(get_port); local ip_pub; ip_pub=$(get_ip)
    local ql; [[ "$q" == "0" ]] && ql="Unlimited" || ql="${q} GB"
    [[ -f "$STRF" ]] && source "$STRF" 2>/dev/null
    _tg_send "📦 <b>Info Akun — ${BRAND:-OGH-ZIV}</b>
┌──────────────────────────
│ 👤 <b>Username</b> : <code>$u</code>
│ 🔑 <b>Password</b> : <code>$p</code>
├──────────────────────────
│ 🖥 <b>IP Publik</b> : <code>$ip_pub</code>
│ 🌐 <b>Host</b>     : <code>$domain</code>
│ 🔌 <b>Port</b>     : <code>$port</code>
├──────────────────────────
│ 📦 <b>Kuota</b>    : $ql
│ 📅 <b>Expired</b>  : $e
│ 📝 <b>Pembeli</b>  : $note
└──────────────────────────"
    ok "Akun berhasil dikirim ke Telegram!"; pause
}

tg_setup() {
    show_header; _top; _btn "  ${IT}${AL}🔧  SETUP TELEGRAM BOT${NC}"; _bot; echo ""
    echo -ne "  ${A3}Bot Token 1${NC}       : "; read -r tk1
    echo -ne "  ${A3}Chat ID 1${NC}         : "; read -r ci1
    echo -ne "  ${A3}Nama Bot${NC}          : "; read -r bn
    echo -ne "  ${A3}Bot Token 2${NC} [opt] : "; read -r tk2
    echo -ne "  ${A3}Chat ID 2${NC}  [opt]  : "; read -r ci2
    echo -ne "  ${A3}Bot Token 3${NC} [opt] : "; read -r tk3
    echo -ne "  ${A3}Chat ID 3${NC}  [opt]  : "; read -r ci3
    cat > "$BOTF" <<BOTEOF
BOT_TOKEN="$tk1"
CHAT_ID="$ci1"
BOT_NAME="$bn"
BOT_TOKEN2="$tk2"
CHAT_ID2="$ci2"
BOT_TOKEN3="$tk3"
CHAT_ID3="$ci3"
BOTEOF
    ok "Konfigurasi bot disimpan!"; pause
}

tg_status() {
    show_header; _top; _btn "  ${IT}${AL}📡  STATUS TELEGRAM BOT${NC}"; _bot; echo ""
    [[ ! -f "$BOTF" ]] && { warn "Bot belum dikonfigurasi."; pause; return; }
    source "$BOTF" 2>/dev/null
    echo -e "  ${DIM}Bot Name  :${NC} ${W}@${BOT_NAME:-?}${NC}"
    echo -e "  ${DIM}Token 1   :${NC} ${A3}${BOT_TOKEN:0:20}...${NC}"
    echo -e "  ${DIM}Chat ID 1 :${NC} ${A3}${CHAT_ID}${NC}"
    [[ -n "$BOT_TOKEN2" ]] && echo -e "  ${DIM}Token 2   :${NC} ${A3}${BOT_TOKEN2:0:20}...${NC}"
    [[ -n "$BOT_TOKEN3" ]] && echo -e "  ${DIM}Token 3   :${NC} ${A3}${BOT_TOKEN3:0:20}...${NC}"
    pause
}

tg_broadcast() {
    show_header; _top; _btn "  ${IT}${AL}📢  BROADCAST PESAN${NC}"; _bot; echo ""
    [[ ! -f "$BOTF" ]] && { warn "Bot belum dikonfigurasi."; pause; return; }
    echo -ne "  ${A3}Pesan${NC}: "; read -r bmsg
    [[ -z "$bmsg" ]] && { warn "Pesan kosong!"; pause; return; }
    _tg_send "📢 <b>Broadcast</b>: $bmsg"
    ok "Pesan broadcast dikirim!"; pause
}

tg_guide() {
    show_header; _top; _btn "  ${IT}${AL}📖  PANDUAN BUAT BOT TELEGRAM${NC}"; _bot; echo ""
    echo -e "  ${A3}1.${NC}  Buka Telegram, cari ${W}@BotFather${NC}"
    echo -e "  ${A3}2.${NC}  Ketik ${W}/newbot${NC} dan ikuti instruksi"
    echo -e "  ${A3}3.${NC}  Salin token yang diberikan"
    echo -e "  ${A3}4.${NC}  Untuk mendapatkan Chat ID, cari ${W}@userinfobot${NC}"
    echo -e "  ${A3}5.${NC}  Masukkan token dan chat ID ke Setup Bot"
    pause
}

svc_status() {
    show_header; _top; _btn "  ${IT}${AL}🖥️   STATUS SERVICE ZIVPN${NC}"; _bot; echo ""
    systemctl status zivpn --no-pager 2>/dev/null || warn "Service tidak ditemukan"
    pause
}

svc_log() {
    show_header; _top; _btn "  ${IT}${AL}📄  LOG ZIVPN${NC}"; _bot; echo ""
    [[ -f "$LOG" ]] && tail -n 30 "$LOG" || journalctl -u zivpn -n 30 --no-pager
    pause
}

svc_port() {
    show_header; _top; _btn "  ${IT}${AL}🔧  GANTI PORT ZIVPN${NC}"; _bot; echo ""
    local cur; cur=$(get_port)
    echo -e "  ${DIM}Port saat ini:${NC} ${Y}${cur}${NC}"
    echo -ne "  ${A3}Port baru${NC}: "; read -r np
    [[ -z "$np" || ! "$np" =~ ^[0-9]+$ ]] && { err "Port tidak valid!"; pause; return; }
    python3 - <<PYEOF 2>/dev/null
import json
try:
    with open('$CFG') as f: c = json.load(f)
    c['listen'] = ':${np}'
    with open('$CFG','w') as f: json.dump(c, f, indent=2)
except: pass
PYEOF
    systemctl restart zivpn &>/dev/null; ok "Port diubah ke ${Y}$np${NC}"; pause
}

menu_domain() {
    show_header; _top; _btn "  ${IT}${AL}🌐  MANAJEMEN DOMAIN${NC}"; _bot; echo ""
    local cur; cur=$(get_domain)
    echo -e "  ${DIM}Domain saat ini:${NC} ${W}${cur}${NC}"
    echo -ne "  ${A3}Domain/IP baru${NC}: "; read -r nd
    [[ -z "$nd" ]] && { warn "Tidak ada perubahan."; pause; return; }
    echo "$nd" > "$DOMF"; ok "Domain diubah ke ${W}$nd${NC}"; pause
}

svc_backup() {
    show_header; _top; _btn "  ${IT}${AL}💾  BACKUP DATA${NC}"; _bot; echo ""
    local bf="/root/ogh-ziv-backup-$(date +%Y%m%d%H%M%S).tar.gz"
    tar -czf "$bf" "$DIR" 2>/dev/null && ok "Backup disimpan: ${W}$bf${NC}" || err "Gagal backup!"; pause
}

svc_restore() {
    show_header; _top; _btn "  ${IT}${AL}♻️   RESTORE DATA${NC}"; _bot; echo ""
    echo -ne "  ${A3}Path file backup${NC}: "; read -r bf
    [[ ! -f "$bf" ]] && { err "File tidak ditemukan!"; pause; return; }
    tar -xzf "$bf" -C / 2>/dev/null && ok "Data berhasil di-restore!" || err "Gagal restore!"; pause
}

svc_bandwidth() {
    show_header; _top; _btn "  ${IT}${AL}📊  BANDWIDTH & KONEKSI${NC}"; _bot; echo ""
    echo -e "  ${DIM}Koneksi UDP aktif:${NC}"
    ss -u -n -p 2>/dev/null | head -20
    echo ""; echo -e "  ${DIM}Total koneksi:${NC} ${W}$(ss -u -n 2>/dev/null | wc -l)${NC}"; pause
}

menu_akun() {
    while true; do
        show_header; _top; _btn "  ${IT}${AL}  👤  KELOLA AKUN USER ZIVPN${NC}"; _sep
        _btn "  ${A2}[1]${NC}  ➕  Tambah Akun Baru"
        _sep0; _btn "  ${A2}[2]${NC}  📋  List Semua Akun"
        _sep0; _btn "  ${A2}[3]${NC}  🔍  Info Detail Akun"
        _sep0; _btn "  ${A2}[4]${NC}  🗑️   Hapus Akun"
        _sep0; _btn "  ${A2}[5]${NC}  🔁  Perpanjang Akun"
        _sep0; _btn "  ${A2}[6]${NC}  🔑  Ganti Password"
        _sep0; _btn "  ${A2}[7]${NC}  🎁  Buat Akun Trial"
        _sep0; _btn "  ${A2}[8]${NC}  🧹  Hapus Akun Expired"
        _sep; _btn "  ${LR}[0]${NC}  ◀   Kembali"
        _bot; echo ""; echo -ne "  ${A1}›${NC} "; read -r ch
        case $ch in
            1) u_add;; 2) u_list;; 3) u_info;; 4) u_del;;
            5) u_renew;; 6) u_chpass;; 7) u_trial;; 8) u_clean;;
            0) break;; *) warn "Pilihan tidak valid!"; sleep 1;;
        esac
    done
}

menu_jualan() {
    while true; do
        show_header; _top; _btn "  ${IT}${AL}  🛒  MENU JUALAN${NC}"; _sep
        _btn "  ${A2}[1]${NC}  📨  Template Pesan Akun"
        _sep0; _btn "  ${A2}[2]${NC}  📤  Kirim Akun ke Telegram"
        _sep0; _btn "  ${A2}[3]${NC}  ⚙️   Pengaturan Toko"
        _sep; _btn "  ${LR}[0]${NC}  ◀   Kembali"
        _bot; echo ""; echo -ne "  ${A1}›${NC} "; read -r ch
        case $ch in
            1) t_akun;; 2) tg_kirim_akun;; 3) set_store;;
            0) break;; *) warn "Pilihan tidak valid!"; sleep 1;;
        esac
    done
}

menu_telegram() {
    while true; do
        show_header
        local bstat="${LR}Belum dikonfigurasi${NC}"
        [[ -f "$BOTF" ]] && { source "$BOTF" 2>/dev/null; bstat="${LG}@${BOT_NAME}${NC}"; }
        _top; _btn "  ${IT}${AL}  🤖  TELEGRAM BOT${NC}"; _sep
        printf "  ${A1}║${NC}  ${DIM}Status :${NC} $bstat\n"
        _sep; _btn "  ${A2}[1]${NC}  🔧  Setup / Konfigurasi Bot"
        _sep0; _btn "  ${A2}[2]${NC}  📡  Cek Status Bot"
        _sep0; _btn "  ${A2}[3]${NC}  📤  Kirim Akun ke Telegram"
        _sep0; _btn "  ${A2}[4]${NC}  📢  Broadcast Pesan"
        _sep0; _btn "  ${A2}[5]${NC}  📖  Panduan Buat Bot"
        _sep; _btn "  ${LR}[0]${NC}  ◀   Kembali"
        _bot; echo ""; echo -ne "  ${A1}›${NC} "; read -r ch
        case $ch in
            1) tg_setup;; 2) tg_status;; 3) tg_kirim_akun;;
            4) tg_broadcast;; 5) tg_guide;;
            0) break;; *) warn "Pilihan tidak valid!"; sleep 1;;
        esac
    done
}

menu_service() {
    while true; do
        show_header; _top; _btn "  ${IT}${AL}  ⚙️   MANAJEMEN SERVICE ZIVPN${NC}"; _sep
        _btn "  ${A2}[1]${NC}  🖥️   Status Service"
        _sep0; _btn "  ${A2}[2]${NC}  ▶️   Start ZiVPN"
        _sep0; _btn "  ${A2}[3]${NC}  ⏹️   Stop ZiVPN"
        _sep0; _btn "  ${A2}[4]${NC}  🔄  Restart ZiVPN"
        _sep0; _btn "  ${A2}[5]${NC}  📄  Lihat Log"
        _sep0; _btn "  ${A2}[6]${NC}  🔧  Ganti Port"
        _sep0; _btn "  ${A2}[7]${NC}  🌐  Manajemen Domain"
        _sep0; _btn "  ${A2}[8]${NC}  💾  Backup Data"
        _sep0; _btn "  ${A2}[9]${NC}  ♻️   Restore Data"
        _sep; _btn "  ${LR}[0]${NC}  ◀   Kembali"
        _bot; echo ""; echo -ne "  ${A1}›${NC} "; read -r ch
        case $ch in
            1) svc_status;;
            2) systemctl start zivpn;   ok "ZiVPN dijalankan."; pause;;
            3) systemctl stop zivpn;    ok "ZiVPN dihentikan."; pause;;
            4) systemctl restart zivpn; sleep 1; is_up && ok "Restart berhasil!" || err "Gagal restart!"; pause;;
            5) svc_log;; 6) svc_port;; 7) menu_domain;; 8) svc_backup;; 9) svc_restore;;
            0) break;; *) warn "Pilihan tidak valid!"; sleep 1;;
        esac
    done
}

# MENU UTAMA ZiVPN
menu_zivpn() {
    while true; do
        show_header
        echo -e "  ${A1}╔══════════════════════════════════════════════════════════╗${NC}"
        printf  "  ${A1}║${NC}  ${A1}◈${NC}────────── ${BLD}${AL}  🔵 UDP ZiVPN — OGH-ZIV  ${NC}──────────${A1}◈${NC}  ${A1}║${NC}\n"
        echo -e "  ${A1}╠══════════════════════════════════════════════════════════╣${NC}"
        printf  "  ${A1}║${NC}  ${A2}[1]${NC}  👤  %-40s  ${A1}║${NC}\n" "Kelola Akun User"
        echo -e "  ${A1}╠╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╣${NC}"
        printf  "  ${A1}║${NC}  ${A2}[2]${NC}  ⚙️   %-40s  ${A1}║${NC}\n" "Manajemen Service ZiVPN"
        echo -e "  ${A1}╠╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╣${NC}"
        printf  "  ${A1}║${NC}  ${A2}[3]${NC}  🤖  %-40s  ${A1}║${NC}\n" "Telegram Bot"
        echo -e "  ${A1}╠╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╣${NC}"
        printf  "  ${A1}║${NC}  ${A2}[4]${NC}  🛒  %-40s  ${A1}║${NC}\n" "Menu Jualan"
        echo -e "  ${A1}╠╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╣${NC}"
        printf  "  ${A1}║${NC}  ${A2}[5]${NC}  📊  %-40s  ${A1}║${NC}\n" "Bandwidth & Koneksi"
        echo -e "  ${A1}╠╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╣${NC}"
        printf  "  ${A1}║${NC}  ${A2}[6]${NC}  🔄  %-40s  ${A1}║${NC}\n" "Restart ZiVPN"
        echo -e "  ${A1}╠╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╣${NC}"
        printf  "  ${A1}║${NC}  ${A2}[7]${NC}  🚀  %-40s  ${A1}║${NC}\n" "Install ZiVPN"
        echo -e "  ${A1}╠╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╣${NC}"
        printf  "  ${A1}║${NC}  ${A2}[8]${NC}  🌐  %-40s  ${A1}║${NC}\n" "Manajemen Domain"
        echo -e "  ${A1}╠╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╣${NC}"
        printf  "  ${A1}║${NC}  ${A2}[9]${NC}  🎨  %-40s  ${A1}║${NC}\n" "Ganti Tema  [ ${THEME_NAME} ]"
        echo -e "  ${A1}╠══════════════════════════════════════════════════════════╣${NC}"
        printf  "  ${A1}║${NC}  ${LR}[E]${NC}  🗑️   %-40s  ${A1}║${NC}\n" "Uninstall ZiVPN"
        echo -e "  ${A1}╠╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╣${NC}"
        printf  "  ${A1}║${NC}  ${A4}[0]${NC}  ◀   %-40s  ${A1}║${NC}\n" "Kembali ke Menu Utama"
        echo -e "  ${A1}╚══════════════════════════════════════════════════════════╝${NC}"
        echo ""; echo -ne "  ${A1}›${NC} Pilih menu: "; read -r ch
        case ${ch,,} in
            1) menu_akun;; 2) menu_service;; 3) menu_telegram;;
            4) menu_jualan;; 5) svc_bandwidth;;
            6) systemctl restart zivpn; sleep 1; is_up && ok "Restart berhasil!" || err "Gagal!"; pause;;
            7) do_install;; 8) menu_domain;; 9) menu_tema;; e) do_uninstall;;
            0) break;; *) warn "Pilihan tidak valid!"; sleep 1;;
        esac
    done
}

# ════════════════════════════════════════════════════════════
#  ══════════════ BAGIAN 2: UDP Request (UDPserver) ══════════
# ════════════════════════════════════════════════════════════

udp_file='/etc/UDPserver'
BIN_URL='https://github.com/chanelog/Ogh/raw/refs/heads/main/udpServer'
UDP_SERVICE='/etc/systemd/system/UDPserver.service'

# ── UI UDPserver ─────────────────────────────────────────────
msg(){
  COLOR[0]='\033[1;37m'; COLOR[1]='\e[31m'; COLOR[2]='\e[32m'; COLOR[3]='\e[33m'
  COLOR[4]='\e[34m'; COLOR[5]='\e[91m'; COLOR[6]='\033[1;97m'; COLOR[7]='\e[36m'
  COLOR[8]='\e[30m'; COLOR[9]='\033[34m'
  NEGRITO='\e[1m'; SEMCOR='\e[0m'
  case $1 in
    -ne)   cor="${COLOR[1]}${NEGRITO}" && echo -ne "${cor}${2}${SEMCOR}";;
    -nazu) cor="${COLOR[6]}${NEGRITO}" && echo -ne "${cor}${2}${SEMCOR}";;
    -nverd)cor="${COLOR[2]}${NEGRITO}" && echo -ne "${cor}${2}${SEMCOR}";;
    -nama) cor="${COLOR[3]}${NEGRITO}" && echo -ne "${cor}${2}${SEMCOR}";;
    -ama)  cor="${COLOR[3]}${NEGRITO}" && echo -e  "${cor}${2}${SEMCOR}";;
    -verm) cor="${COLOR[3]}${NEGRITO}[!] ${COLOR[1]}" && echo -e "${cor}${2}${SEMCOR}";;
    -verm2)cor="${COLOR[1]}${NEGRITO}" && echo -e  "${cor}${2}${SEMCOR}";;
    -verm3)cor="${COLOR[1]}"           && echo -e  "${cor}${2}${SEMCOR}";;
    -teal) cor="${COLOR[7]}${NEGRITO}" && echo -e  "${cor}${2}${SEMCOR}";;
    -azu)  cor="${COLOR[6]}${NEGRITO}" && echo -e  "${cor}${2}${SEMCOR}";;
    -blu)  cor="${COLOR[9]}${NEGRITO}" && echo -e  "${cor}${2}${SEMCOR}";;
    -verd) cor="${COLOR[2]}${NEGRITO}" && echo -e  "${cor}${2}${SEMCOR}";;
    -bra)  cor="${COLOR[0]}${NEGRITO}" && echo -e  "${cor}${2}${SEMCOR}";;
    -bar)  echo -e "\e[31m=====================================================\e[0m";;
    -bar2) echo -e "\e[36m=====================================================\e[0m";;
    -bar3) echo -e "\e[31m-----------------------------------------------------\e[0m";;
    -bar4) echo -e "\e[36m-----------------------------------------------------\e[0m";;
  esac
}

udp_print_center(){
  local col text
  [[ -z $2 ]] && text="$1" col="" || { col="$1"; text="$2"; }
  while IFS= read -r line; do
    unset space
    local plain; plain=$(echo -e "$line" | sed 's/\x1B\[[0-9;]*[mK]//g')
    local x=$(( ( 54 - ${#plain} ) / 2 ))
    for (( i = 0; i < x; i++ )); do space+=' '; done
    space+="$line"
    [[ -z $col ]] && msg -azu "$space" || msg "$col" "$space"
  done <<< "$(echo -e "$text")"
}

udp_title(){
  clear; msg -bar
  [[ -z $2 ]] && udp_print_center -azu "$1" || udp_print_center "$1" "$2"
  msg -bar
}

udp_enter(){
  msg -bar
  local text="►► Tekan enter untuk melanjutkan ◄◄"
  [[ -z $1 ]] && udp_print_center -ama "$text" || udp_print_center "$1" "$text"
  read -r
}

udp_back(){
  msg -bar
  echo -ne "$(msg -verd " [0]") $(msg -verm2 ">") " && msg -bra "\033[1;41mKEMBALI"
  msg -bar
}

udp_menu_func(){
  local options=${#@}
  for((num=1; num<=$options; num++)); do
    echo -ne "$(msg -verd " [$num]") $(msg -verm2 ">") "
    local arr=(${!num})
    case ${arr[0]} in
      "-vd") echo -e "\033[1;33m[!]\033[1;32m ${arr[@]:1}";;
      "-vm") echo -e "\033[1;33m[!]\033[1;31m ${arr[@]:1}";;
      *)     echo -e "\033[1;37m${arr[@]}";;
    esac
  done
}

udp_selection(){
  local selection="null" opcion col
  [[ -z $2 ]] && opcion=$1 col="-nazu" || { opcion=$2; col=$1; }
  local range=()
  for((i=0; i<=$opcion; i++)); do range[$i]="$i "; done
  while [[ ! $(echo "${range[*]}" | grep -w "$selection") ]]; do
    msg "$col" " Pilih Opsi: " >&2; read -r selection
    tput cuu1 >&2 && tput dl1 >&2
  done
  echo "$selection"
}

in_opcion_down(){
  local dat="$1"; local length=${#dat}; local cal=$(( 22 - length / 2 )); local line=''
  for (( i = 0; i < cal; i++ )); do line+='╼'; done
  echo -e " $(msg -verm3 "╭${line}╼[")$(msg -azu "$dat")$(msg -verm3 "]")"
  echo -ne " $(msg -verm3 "╰╼")\033[37;1m> " && read -r opcion
}

udp_del(){ for (( i = 0; i < $1; i++ )); do tput cuu1 && tput dl1; done; }

numero='^[0-9]+$'

get_ip_publik(){
  ip_publik=""
  local sources=("http://ip1.dynupdate.no-ip.com/" "https://api.ipify.org" "https://ifconfig.me"
    "https://icanhazip.com" "https://ipecho.net/plain" "https://checkip.amazonaws.com" "https://api4.my-ip.io/ip")
  for src in "${sources[@]}"; do
    ip_publik=$(wget -T 5 -t 1 -4qO- "$src" 2>/dev/null | tr -d '[:space:]' \
      || curl -m 5 -4Ls "$src" 2>/dev/null | tr -d '[:space:]')
    ip_publik=$(grep -m 1 -oE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' <<< "$ip_publik")
    [[ -n "$ip_publik" ]] && break
  done
  [[ -z "$ip_publik" ]] && ip_publik="IP-TIDAK-DIKETAHUI"
}

install_deps_udp(){
  source /etc/os-release 2>/dev/null
  export DEBIAN_FRONTEND=noninteractive; export LC_ALL=C; export LANG=C
  echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections 2>/dev/null
  apt-get update -y -qq 2>/dev/null || apt-get update -y 2>/dev/null
  msg -ama "   Menginstal dependensi..."
  for pkg in wget curl openssl iproute2 procps cron; do
    apt-get install -y -qq "$pkg" 2>/dev/null || apt-get install -y "$pkg" 2>/dev/null
  done
  ufw disable 2>/dev/null; systemctl stop ufw 2>/dev/null; systemctl disable ufw 2>/dev/null
  apt-get remove -y --purge netfilter-persistent iptables-persistent 2>/dev/null
  systemctl daemon-reload 2>/dev/null
  msg -verd "   Dependensi selesai dipasang"
}

download_udpServer(){
  msg -nama "        Mengunduh binary UDPserver ....."
  local ok=0
  wget -q --tries=3 --timeout=30 -O /usr/bin/udpServer "$BIN_URL" 2>/dev/null && ok=1
  [[ $ok -eq 0 ]] && curl -fsSL --connect-timeout 30 --retry 3 -o /usr/bin/udpServer "$BIN_URL" 2>/dev/null && ok=1
  if [[ $ok -eq 1 && -s /usr/bin/udpServer ]]; then
    chmod +x /usr/bin/udpServer; msg -verd 'OK'
  else
    msg -verm2 'GAGAL'; rm -f /usr/bin/udpServer
  fi
}

udp_exclude(){
  udp_title "Kecualikan Port UDP"
  udp_print_center -ama "UDPserver mencakup semua rentang port."
  udp_print_center -ama "Anda dapat mengecualikan port tertentu"
  msg -bar3; udp_print_center -ama "Contoh: slowdns(53,5300) wireguard(51820) openvpn(1194)"
  msg -bar; udp_print_center -verd "Masukkan port dipisah spasi (Enter untuk lewati)"
  msg -bar3; in_opcion_down "Port dikecualikan"; udp_del 2
  local tmport=($opcion)
  for (( i = 0; i < ${#tmport[@]}; i++ )); do
    local num=$((${tmport[$i]}))
    if [[ $num -gt 0 && $num -le 65535 ]]; then
      echo "$(msg -ama " Port dikecualikan >") $(msg -azu "$num") $(msg -verd "OK")"; UDPPort+=" $num"
    else msg -verm2 " Bukan port valid > ${tmport[$i]}"; fi
  done
  if [[ -z $UDPPort ]]; then unset UDPPort; udp_print_center -ama "Tidak ada port yang dikecualikan"
  else UDPPort=" -exclude=$(echo "$UDPPort" | sed "s/ /,/g" | sed 's/,//')"; fi
  msg -bar3
}

buat_service_udp(){
  source /etc/os-release 2>/dev/null
  local ip_nat; ip_nat=$(ip -4 addr 2>/dev/null | grep inet | grep -vE '127(\.[0-9]{1,3}){3}' \
    | cut -d '/' -f1 | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | sed -n 1p)
  local interfas; interfas=$(ip -4 addr 2>/dev/null | grep inet | grep -vE '127(\.[0-9]{1,3}){3}' \
    | grep "$ip_nat" | awk '{print $NF}')
  get_ip_publik
  cat > "$UDP_SERVICE" <<EOF
[Unit]
Description=UDPserver Service
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=/usr/bin/udpServer -ip=${ip_publik} -net=${interfas}${UDPPort} -mode=system
Restart=always
RestartSec=3s
[Install]
WantedBy=multi-user.target
EOF
  msg -nama "        Menjalankan service UDPserver ....."
  systemctl daemon-reload 2>/dev/null; systemctl start UDPserver 2>/dev/null; sleep 2
  if [[ $(systemctl is-active UDPserver 2>/dev/null) = 'active' ]]; then
    systemctl enable UDPserver 2>/dev/null; msg -verd 'OK'
  else msg -verm2 'GAGAL'; fi
}

install_UDP(){
  udp_title "INSTALASI UDPSERVER"; udp_exclude; install_deps_udp; download_udpServer
  if [[ -x /usr/bin/udpServer ]]; then
    buat_service_udp; msg -bar3
    [[ $(systemctl is-active UDPserver 2>/dev/null) = 'active' ]] \
      && udp_print_center -verd "Instalasi berhasil!" \
      || udp_print_center -verm2 "Gagal menjalankan service — cek: journalctl -u UDPserver -n 30"
  else
    udp_print_center -verm2 "Gagal mengunduh binary UDPserver"
    udp_print_center -ama   "Periksa koneksi internet VPS"
  fi
  udp_enter
}

uninstall_UDP(){
  udp_title "HAPUS UDPSERVER"
  read -rp " $(msg -ama "Yakin ingin menghapus UDPserver? [Y/T]: ")" KONFIRM
  [[ ! $KONFIRM =~ ^[Yy]$ ]] && return
  systemctl stop UDPserver 2>/dev/null; systemctl disable UDPserver 2>/dev/null
  rm -f "$UDP_SERVICE" /usr/bin/udpServer; systemctl daemon-reload 2>/dev/null
  udp_print_center -ama "UDPserver berhasil dihapus!"; udp_enter
}

hapus_script_udp(){
  udp_title "HAPUS SCRIPT UDPSERVER"
  read -rp " $(msg -ama "Yakin ingin menghapus SEMUA script UDP? [Y/T]: ")" KONFIRM
  [[ ! $KONFIRM =~ ^[Yy]$ ]] && return
  systemctl disable UDPserver 2>/dev/null; systemctl stop UDPserver 2>/dev/null
  rm -f "$UDP_SERVICE" /usr/bin/udpServer /usr/bin/udp /usr/bin/udpc
  rm -rf "$udp_file"; systemctl daemon-reload 2>/dev/null
  crontab -l 2>/dev/null | grep -v 'limitador.sh' | crontab - 2>/dev/null
  msg -bar; udp_print_center -verd "Script berhasil dihapus sepenuhnya!"; msg -bar
}

toggle_service_udp(){
  if [[ $(systemctl is-active UDPserver 2>/dev/null) = 'active' ]]; then
    systemctl stop UDPserver 2>/dev/null; systemctl disable UDPserver 2>/dev/null
    udp_print_center -ama "UDPserver dihentikan!"
  else
    systemctl start UDPserver 2>/dev/null; sleep 2
    if [[ $(systemctl is-active UDPserver 2>/dev/null) = 'active' ]]; then
      systemctl enable UDPserver 2>/dev/null; udp_print_center -verd "UDPserver berhasil dijalankan!"
    else udp_print_center -verm2 "Gagal menjalankan UDPserver!"; fi
  fi
  udp_enter
}

tampil_pengguna(){
  cat /etc/passwd | grep '/home' | grep '/bin/false' | grep -v 'syslog\|hwid\|token\|::/' | awk -F ':' '{print $1}'
}

tabel_pengguna(){
  local cat_users; cat_users=$(cat /etc/passwd | grep '/home' | grep '/bin/false' | grep -v 'syslog\|hwid\|token\|::/')
  if [[ -z "$(echo "$cat_users" | head -1)" ]]; then udp_print_center -verm2 "BELUM ADA PENGGUNA SSH TERDAFTAR"; return 1; fi
  local header; header=$(printf '%-13s%-14s%-10s%-5s%-7s%s' "Pengguna" "Password" "Tanggal" "Hari" "Limit" "Status")
  msg -azu "  $header"; msg -bar
  local i=1
  while read -r baris; do
    local u pass limit fecha mes_dia ano stat exp EXPTIME
    u=$(echo "$baris" | awk -F ':' '{print $1}')
    fecha=$(chage -l "$u" 2>/dev/null | sed -n '4p' | awk -F ': ' '{print $2}')
    mes_dia=$(echo "$fecha" | awk -F ',' '{print $1}' | sed 's/ //g')
    ano=$(echo "$fecha" | awk -F ', ' '{printf $2}' | cut -c 3-)
    local us; us=$(printf '%-12s' "$u")
    pass=$(echo "$baris" | awk -F ':' '{print $5}' | cut -d ',' -f2)
    [[ "${#pass}" -gt '12' || -z "$pass" ]] && pass="Tidak diketahui"
    pass="$(printf '%-12s' "$pass")"
    if [[ $(passwd --status "$u" 2>/dev/null | cut -d ' ' -f2) = "P" ]]; then stat="$(msg -verd "AKT")"
    else stat="$(msg -verm2 "BLK")"; fi
    limit=$(echo "$baris" | awk -F ':' '{print $5}' | cut -d ',' -f1)
    [[ "${#limit}" = "1" ]] && limit=$(printf '%2s%-4s' "$limit") || limit=$(printf '%-6s' "$limit")
    echo -ne "$(msg -verd "$i")$(msg -verm2 "-")$(msg -azu "${us}") $(msg -azu "${pass}")"
    if [[ $(echo "$fecha" | awk '{print $2}') = "" ]]; then
      exp="$(printf '%8s%-2s' '[X]')$(printf '%-6s' '[X]')"
      echo " $(msg -verm2 "$fecha")$(msg -verd "$exp")$(echo -e "$stat")"
    else
      local ts_exp ts_now
      ts_exp=$(date '+%s' -d "${fecha}" 2>/dev/null || echo 0); ts_now=$(date +%s)
      if [[ $ts_now -gt $ts_exp ]]; then
        exp="$(printf '%-5s' "Exp")"
        echo " $(msg -verm2 "$mes_dia/$ano")  $(msg -verm2 "$exp")$(msg -ama "$limit")$(echo -e "$stat")"
      else
        EXPTIME=$(( (ts_exp - ts_now) / 86400 ))
        [[ "${#EXPTIME}" = "1" ]] && exp="$(printf '%2s%-3s' "$EXPTIME")" || exp="$(printf '%-5s' "$EXPTIME")"
        echo " $(msg -verm2 "$mes_dia/$ano")  $(msg -verd "$exp")$(msg -ama "$limit")$(echo -e "$stat")"
      fi
    fi
    let i++
  done <<< "$cat_users"
}

tambah_pengguna_sys(){
  local nama="$1" sandi="$2" hari="$3" limit="$4"
  local valid; valid=$(date '+%Y-%m-%d' -d " +$hari days")
  local osl_v; osl_v=$(openssl version 2>/dev/null | awk '{print $2}')
  local hash
  if [[ "${osl_v:0:1}" = '3' || "${osl_v:0:5}" = '1.1.1' ]]; then
    hash=$(openssl passwd -6 "$sandi")
  else hash=$(openssl passwd -1 "$sandi"); fi
  useradd -M -s /bin/false -e "${valid}" -K PASS_MAX_DAYS="$hari" -p "${hash}" -c "${limit},${sandi}" "$nama" 2>/dev/null
  msj=$?
}

buat_pengguna(){
  clear; local daftar_aktif=('' $(tampil_pengguna)); msg -bar
  udp_print_center -ama "BUAT PENGGUNA"; msg -bar; tabel_pengguna; udp_back
  local nama sandi hari limit
  shopt -s extglob
  while true; do
    msg -ne " Nama Pengguna: "; read -r nama; nama="$(echo "$nama" | sed 's/[^a-zA-Z0-9_-]//g')"
    if [[ -z "$nama" ]]; then udp_del 1; msg -verm "Nama tidak boleh kosong"; sleep 1; udp_del 1; continue
    elif [[ "$nama" = "0" ]]; then return; fi
    if [[ "${#nama}" -lt "3" ]]; then udp_del 1; msg -verm "Minimal 3 karakter"; sleep 1; udp_del 1; continue
    elif [[ "${#nama}" -gt "16" ]]; then udp_del 1; msg -verm "Maksimal 16 karakter"; sleep 1; udp_del 1; continue
    elif [[ "$(echo "${daftar_aktif[@]}" | grep -w "$nama")" ]]; then udp_del 1; msg -verm "Pengguna sudah ada"; sleep 1; udp_del 1; continue; fi
    break
  done
  while true; do
    msg -ne " Password Pengguna: "; read -r sandi
    if [[ -z "$sandi" ]]; then udp_del 1; msg -verm "Password tidak boleh kosong"; sleep 1; udp_del 1; continue
    elif [[ "${#sandi}" -lt "4" ]]; then udp_del 1; msg -verm "Minimal 4 karakter"; sleep 1; udp_del 1; continue
    elif [[ "${#sandi}" -gt "20" ]]; then udp_del 1; msg -verm "Maksimal 20 karakter"; sleep 1; udp_del 1; continue; fi
    break
  done
  while true; do
    msg -ne " Masa Aktif (Hari): "; read -r hari
    if [[ -z "$hari" ]]; then udp_del 1; continue
    elif [[ "$hari" != +([0-9]) ]]; then udp_del 1; msg -verm "Hanya angka"; sleep 1; udp_del 1; continue
    elif [[ "$hari" -lt 1 || "$hari" -gt 360 ]]; then udp_del 1; msg -verm "Rentang 1-360 hari"; sleep 1; udp_del 1; continue; fi
    break
  done
  while true; do
    msg -ne " Batas Koneksi: "; read -r limit
    if [[ -z "$limit" ]]; then udp_del 1; continue
    elif [[ "$limit" != +([0-9]) ]]; then udp_del 1; msg -verm "Hanya angka"; sleep 1; udp_del 1; continue
    elif [[ "$limit" -lt 1 || "$limit" -gt 20 ]]; then udp_del 1; msg -verm "Rentang 1-20"; sleep 1; udp_del 1; continue; fi
    break
  done
  tambah_pengguna_sys "$nama" "$sandi" "$hari" "$limit"
  if [[ $msj -ne 0 ]]; then msg -verm2 "Gagal menambah pengguna ($msj)"; udp_enter; return; fi
  get_ip_publik
  msg -bar; udp_print_center -verd "Pengguna berhasil dibuat!"
  msg -bar3
  echo " $(msg -verd 'Nama     :') $(msg -azu "$nama")"
  echo " $(msg -verd 'Password :') $(msg -azu "$sandi")"
  echo " $(msg -verd 'Masa     :') $(msg -azu "$hari hari")"
  echo " $(msg -verd 'Limit    :') $(msg -azu "$limit koneksi")"
  echo " $(msg -verd 'IP       :') $(msg -azu "$ip_publik")"
  udp_enter
}

hapus_pengguna(){
  clear; msg -bar; udp_print_center -ama "HAPUS PENGGUNA"; msg -bar; tabel_pengguna; udp_back
  msg -ne " Nama pengguna yang dihapus: "; read -r nama
  [[ "$nama" = "0" ]] && return
  if id "$nama" &>/dev/null; then
    userdel -rf "$nama" 2>/dev/null; pkill -u "$nama" 2>/dev/null
    msg -verd " Pengguna $nama berhasil dihapus!"
  else msg -verm2 " Pengguna $nama tidak ditemukan!"; fi
  udp_enter
}

perpanjang_pengguna(){
  clear; msg -bar; udp_print_center -ama "PERPANJANG PENGGUNA"; msg -bar; tabel_pengguna; udp_back
  msg -ne " Nama pengguna: "; read -r nama
  [[ "$nama" = "0" ]] && return
  if ! id "$nama" &>/dev/null; then msg -verm2 " Pengguna tidak ditemukan!"; udp_enter; return; fi
  msg -ne " Jumlah hari perpanjangan: "; read -r hari
  [[ ! "$hari" =~ ^[0-9]+$ ]] && { msg -verm2 "Input tidak valid!"; udp_enter; return; }
  local exp_now; exp_now=$(chage -l "$nama" 2>/dev/null | sed -n '4p' | awk -F ': ' '{print $2}')
  local ts_exp; ts_exp=$(date '+%s' -d "${exp_now}" 2>/dev/null || date +%s)
  local ts_now; ts_now=$(date +%s)
  [[ $ts_now -gt $ts_exp ]] && ts_exp=$ts_now
  local new_exp; new_exp=$(date '+%Y-%m-%d' -d "@$((ts_exp + hari * 86400))")
  chage -E "$new_exp" "$nama" 2>/dev/null
  msg -verd " Perpanjang $nama hingga $new_exp berhasil!"; udp_enter
}

blokir_pengguna(){
  clear; msg -bar; udp_print_center -ama "BLOKIR/BUKA BLOKIR PENGGUNA"; msg -bar; tabel_pengguna; udp_back
  msg -ne " Nama pengguna: "; read -r nama
  [[ "$nama" = "0" ]] && return
  if ! id "$nama" &>/dev/null; then msg -verm2 " Pengguna tidak ditemukan!"; udp_enter; return; fi
  local status; status=$(passwd --status "$nama" 2>/dev/null | cut -d ' ' -f2)
  if [[ "$status" = "P" ]]; then
    usermod -L "$nama" 2>/dev/null; pkill -u "$nama" 2>/dev/null
    msg -ama " Pengguna $nama berhasil DIBLOKIR!"
  else
    usermod -U "$nama" 2>/dev/null; msg -verd " Pengguna $nama berhasil DIBUKA BLOKIR!"
  fi
  udp_enter
}

detail_pengguna(){
  clear; msg -bar; udp_print_center -ama "DETAIL PENGGUNA"; msg -bar; tabel_pengguna; udp_back
  msg -ne " Nama pengguna: "; read -r nama
  [[ "$nama" = "0" ]] && return
  if ! id "$nama" &>/dev/null; then msg -verm2 " Pengguna tidak ditemukan!"; udp_enter; return; fi
  get_ip_publik
  msg -bar; msg -azu " Detail: $nama"
  msg -bar3
  chage -l "$nama" 2>/dev/null | head -5
  local status; status=$(passwd --status "$nama" 2>/dev/null | cut -d ' ' -f2)
  [[ "$status" = "P" ]] && echo " Status: $(msg -verd "AKTIF")" || echo " Status: $(msg -verm2 "BLOKIR")"
  echo " IP: $(msg -azu "$ip_publik")"
  udp_enter
}

limitador_menu(){
  clear; msg -bar; udp_print_center -ama "PEMBATAS KONEKSI"; msg -bar
  local cur_limit; cur_limit=$(cat "$udp_file/limit" 2>/dev/null || echo 1)
  local cur_unlock; cur_unlock=$(cat "$udp_file/unlimit" 2>/dev/null || echo 0)
  echo " $(msg -verd 'Batas saat ini  :') $(msg -azu "$cur_limit koneksi")"
  echo " $(msg -verd 'Buka otomatis   :') $(msg -azu "${cur_unlock} menit (0=tidak)")"
  msg -bar3
  echo " $(msg -verd "[1]") $(msg -verm2 ">") $(msg -azu "Ubah batas koneksi")"
  echo " $(msg -verd "[2]") $(msg -verm2 ">") $(msg -azu "Ubah waktu buka otomatis")"
  udp_back
  local pilihan; pilihan=$(udp_selection 2)
  case $pilihan in
    1) msg -ne " Batas koneksi baru: "; read -r nb; [[ "$nb" =~ ^[0-9]+$ ]] && { echo "$nb" > "$udp_file/limit"; msg -verd " Batas diubah ke $nb!"; } || msg -verm2 "Input tidak valid!"; udp_enter;;
    2) msg -ne " Waktu buka otomatis (menit, 0=tidak): "; read -r nu; [[ "$nu" =~ ^[0-9]+$ ]] && { echo "$nu" > "$udp_file/unlimit"; msg -verd " Waktu diubah ke $nu menit!"; } || msg -verm2 "Input tidak valid!"; udp_enter;;
    0) return;;
  esac
}

tambah_exclude(){
  udp_title "TAMBAH PORT PENGECUALIAN"
  udp_print_center -ama "Port yang sudah dikecualikan:"
  local cur_excl; cur_excl=$(grep 'exclude' "$UDP_SERVICE" 2>/dev/null | awk '{print $4}' | cut -d '=' -f2 | sed 's/,/ /g')
  [[ -n "$cur_excl" ]] && msg -azu " $cur_excl" || udp_print_center -ama "Belum ada pengecualian"
  msg -bar; in_opcion_down "Tambah port (spasi untuk beberapa)"; udp_del 2
  local tmport=($opcion); local NewPort="$cur_excl"
  for (( i = 0; i < ${#tmport[@]}; i++ )); do
    local num=$((${tmport[$i]}))
    if [[ $num -gt 0 && $num -le 65535 ]]; then
      echo "$(msg -ama " Port ditambah >") $(msg -azu "$num") $(msg -verd "OK")"; NewPort+=" $num"
    fi
  done
  NewPort=$(echo "$NewPort" | sed 's/^ //' | sed 's/ /,/g')
  local sedang_aktif=0
  [[ $(systemctl is-active UDPserver 2>/dev/null) = 'active' ]] && { sedang_aktif=1; systemctl stop UDPserver 2>/dev/null; }
  [[ -z "$NewPort" ]] && sed -i "s/ -exclude=[^ ]*//" "$UDP_SERVICE" \
    || { grep -q 'exclude' "$UDP_SERVICE" 2>/dev/null \
      && sed -i "s/-exclude=[^ ]*/-exclude=$NewPort/" "$UDP_SERVICE" \
      || sed -i "s/-mode=system/-exclude=$NewPort -mode=system/" "$UDP_SERVICE"; }
  systemctl daemon-reload 2>/dev/null
  [[ $sedang_aktif -eq 1 ]] && { systemctl start UDPserver 2>/dev/null; systemctl enable UDPserver 2>/dev/null; }
  udp_enter
}

hapus_exclude(){
  udp_title "HAPUS PORT PENGECUALIAN"
  local port_info; port_info=$(grep 'exclude' "$UDP_SERVICE" 2>/dev/null)
  [[ -z "$port_info" ]] && { udp_print_center -ama "Tidak ada port pengecualian."; udp_enter; return; }
  local port_tampil; port_tampil=$(echo "$port_info" | awk '{print $4}' | cut -d '=' -f2 | sed 's/,/ /g')
  local ports=($port_tampil); local i=1
  for p in "${ports[@]}"; do echo " $(msg -verd "[$i]") $(msg -verm2 ">") $(msg -azu "$p")"; ((i++)); done
  msg -bar; echo " $(msg -verd "[$(( ${#ports[@]}+1 ))]") $(msg -verm2 ">") $(msg -ama "Hapus semua")"
  udp_back; local pilihan; pilihan=$(udp_selection $(( ${#ports[@]}+1 )))
  local sedang_aktif=0
  [[ $(systemctl is-active UDPserver 2>/dev/null) = 'active' ]] && { sedang_aktif=1; systemctl stop UDPserver 2>/dev/null; }
  if [[ $pilihan -eq $(( ${#ports[@]}+1 )) ]]; then
    sed -i "s/ -exclude=[^ ]*//" "$UDP_SERVICE"
  else
    let pilihan--; local NewPort=""
    for (( i = 0; i < ${#ports[@]}; i++ )); do
      [[ $i = $pilihan ]] && continue
      echo "$(msg -ama " Port dikecualikan >") $(msg -azu "${ports[$i]}") $(msg -verd "OK")"
      NewPort+=" ${ports[$i]}"
    done
    NewPort=$(echo "$NewPort" | sed 's/ /,/g' | sed 's/^,//')
    [[ -z "$NewPort" ]] && sed -i "s/ -exclude=[^ ]*//" "$UDP_SERVICE" \
      || sed -i "s/-exclude=[^ ]*/-exclude=$NewPort/" "$UDP_SERVICE"
  fi
  systemctl daemon-reload 2>/dev/null
  [[ $sedang_aktif -eq 1 ]] && { systemctl start UDPserver 2>/dev/null; systemctl enable UDPserver 2>/dev/null; }
  udp_enter
}

buat_limitador(){
cat > "${udp_file}/limitador.sh" <<'LIMITADOR'
#!/bin/bash
udp_file='/etc/UDPserver'
LOG="${udp_file}/limit.log"
[[ ! -f "$LOG" ]] && touch "$LOG"
if [[ "$1" == "--ssh" ]]; then
  while IFS=: read -r u x uid gid info home shell; do
    [[ "$shell" != "/bin/false" ]] && continue; [[ "$home" != /home/* ]] && continue
    [[ "$u" =~ syslog|hwid|token ]] && continue
    exp=$(chage -l "$u" 2>/dev/null | sed -n '4p' | awk -F ': ' '{print $2}')
    [[ -z "$exp" || "$exp" == "never" ]] && continue
    ts_exp=$(date '+%s' -d "$exp" 2>/dev/null) || continue
    [[ $(date +%s) -gt $ts_exp ]] && { usermod -L "$u" 2>/dev/null; echo "$(date '+%F %T') [EXPIRED-BLOKIR] $u" >> "$LOG"; }
  done < /etc/passwd; exit 0
fi
[[ -f "${udp_file}/limit" ]] && interval=$(cat "${udp_file}/limit") || interval=1
[[ -f "${udp_file}/unlimit" ]] && buka=$(cat "${udp_file}/unlimit") || buka=0
while IFS=: read -r u x uid gid info home shell; do
  [[ "$shell" != "/bin/false" ]] && continue; [[ "$home" != /home/* ]] && continue
  [[ "$u" =~ syslog|hwid|token ]] && continue
  lim=$(echo "$info" | cut -d',' -f1); [[ ! "$lim" =~ ^[0-9]+$ ]] && continue
  koneksi=$(ps -u "$u" 2>/dev/null | grep -vc 'PID')
  if [[ $koneksi -gt $lim ]]; then
    pkill -u "$u" 2>/dev/null; usermod -L "$u" 2>/dev/null
    echo "$(date '+%F %T') [LIMIT-BLOKIR] $u (koneksi=$koneksi / batas=$lim)" >> "$LOG"
    [[ $buka -gt 0 ]] && ( sleep "${buka}m"; usermod -U "$u" 2>/dev/null; echo "$(date '+%F %T') [BUKA-OTOMATIS] $u" >> "$LOG" ) &
  fi
done < /etc/passwd
LIMITADOR
  chmod +x "${udp_file}/limitador.sh"
}

setup_awal_udp(){
  clear; msg -bar; udp_print_center -ama "SETUP AWAL UDPSERVER"; msg -bar
  mkdir -p "$udp_file"; chmod 755 "$udp_file"
  udp_print_center -ama "Memperbarui sistem & dependensi..."
  install_deps_udp; udp_print_center -verd "Dependensi selesai"
  buat_limitador
  local script_src="${BASH_SOURCE[0]}"
  if [[ -f "$script_src" && "$script_src" != "/dev/fd/"* && -s "$script_src" ]]; then
    cp "$script_src" "$udp_file/UDPserver.sh"
  fi
  chmod +x "$udp_file/UDPserver.sh" 2>/dev/null
  udp_print_center -verd "Setup selesai!"; sleep 2
}

# MENU UTAMA UDPserver
menu_udp_request() {
    source /etc/os-release 2>/dev/null
    get_ip_publik
    while true; do
        if [[ -x /usr/bin/udpServer ]]; then
            local port_info; port_info=$(grep 'exclude' "$UDP_SERVICE" 2>/dev/null)
            local port_tampil=""
            [[ -n "$port_info" ]] && port_tampil=$(echo "$port_info" | awk '{print $4}' | cut -d '=' -f2 | sed 's/,/ /g')
            local ram cpu
            ram=$(free -m 2>/dev/null | awk 'NR==2{printf "%.1f%%", $3*100/$2}')
            cpu=$(top -bn1 2>/dev/null | awk '/[Cc]pu/ {val=100-$8; printf "%.1f%%", val; exit}')
            udp_title "🟡 UDP REQUEST — MANAJER UDPSERVER"
            udp_print_center -ama 'Binary UDPserver by chanelog'
            udp_print_center -ama 'Klien Android: SocksIP'
            msg -bar
            [[ -n "$port_tampil" ]] && { udp_print_center -ama "PORT DIKECUALIKAN: $port_tampil"; msg -bar; }
            echo " $(msg -verd 'IP     :') $(msg -azu "$ip_publik")"
            echo " $(msg -verd 'RAM    :') $(msg -azu "$ram")    $(msg -verd 'CPU:') $(msg -azu "$cpu")"
            echo " $(msg -verd 'Sistem :') $(msg -azu "$NAME $VERSION_ID")"
            msg -bar
            local status_svc
            [[ $(systemctl is-active UDPserver 2>/dev/null) = 'active' ]] \
              && status_svc="\e[1m\e[32m[AKTIF]" || status_svc="\e[1m\e[31m[MATI]"
            echo " $(msg -verd "[1]")  $(msg -verm2 '>') $(msg -verm2 "HAPUS UDPSERVER")"
            echo -e " $(msg -verd "[2]")  $(msg -verm2 '>') $(msg -azu "MULAI/HENTIKAN UDPSERVER") $status_svc"
            echo " $(msg -verd "[3]")  $(msg -verm2 '>') $(msg -azu "HAPUS SCRIPT SEPENUHNYA")"
            msg -bar3
            echo " $(msg -verd "[4]")  $(msg -verm2 '>') $(msg -verd "BUAT PENGGUNA")"
            echo " $(msg -verd "[5]")  $(msg -verm2 '>') $(msg -verm2 "HAPUS PENGGUNA")"
            echo " $(msg -verd "[6]")  $(msg -verm2 '>') $(msg -ama "PERPANJANG PENGGUNA")"
            echo " $(msg -verd "[7]")  $(msg -verm2 '>') $(msg -azu "BLOKIR/BUKA BLOKIR PENGGUNA")"
            echo " $(msg -verd "[8]")  $(msg -verm2 '>') $(msg -blu "DETAIL PENGGUNA")"
            echo " $(msg -verd "[9]")  $(msg -verm2 '>') $(msg -azu "PEMBATAS KONEKSI")"
            msg -bar3
            udp_print_center -ama "PENGECUALIAN PORT"
            msg -bar3
            echo " $(msg -verd "[10]") $(msg -verm2 '>') $(msg -verd "TAMBAH PORT PENGECUALIAN")"
            local num=10
            [[ -n "$port_tampil" ]] && { echo " $(msg -verd "[11]") $(msg -verm2 '>') $(msg -verm2 "HAPUS PORT PENGECUALIAN")"; num=11; }
            msg -bar
            echo " $(msg -verd "[0]")  $(msg -verm2 '>') $(msg -azu "◀ KEMBALI KE MENU UTAMA")"
            msg -bar
            local pilihan; pilihan=$(udp_selection $num)
            case $pilihan in
                1) uninstall_UDP;; 2) toggle_service_udp;; 3) hapus_script_udp;;
                4) buat_pengguna;; 5) hapus_pengguna;; 6) perpanjang_pengguna;;
                7) blokir_pengguna;; 8) detail_pengguna;; 9) limitador_menu;;
                10) tambah_exclude;; 11) hapus_exclude;; 0) break;;
            esac
        else
            udp_title "🟡 UDP REQUEST — MANAJER UDPSERVER"
            udp_print_center -ama 'Binary UDPserver by chanelog'
            udp_print_center -ama 'Klien Android: SocksIP'
            msg -bar
            echo " $(msg -verd 'IP     :') $(msg -azu "$ip_publik")"
            echo " $(msg -verd 'Sistem :') $(msg -azu "$NAME $VERSION_ID")"
            msg -bar
            echo " $(msg -verd "[1]") $(msg -verm2 '>') $(msg -verd "INSTAL UDPSERVER")"
            msg -bar
            echo " $(msg -verd "[0]")  $(msg -verm2 '>') $(msg -azu "◀ KEMBALI KE MENU UTAMA")"
            msg -bar
            local pilihan; pilihan=$(udp_selection 1)
            case $pilihan in
                1) install_UDP;; 0) break;;
            esac
        fi
    done
}

# ════════════════════════════════════════════════════════════
#  SETUP COMMAND 'menu'
# ════════════════════════════════════════════════════════════
setup_menu_cmd() {
    local sp; sp=$(realpath "$0" 2>/dev/null || echo "$0")
    if [[ "$sp" != "/usr/local/bin/ogh-ziv" ]]; then
        cp "$0" /usr/local/bin/ogh-ziv 2>/dev/null
        chmod +x /usr/local/bin/ogh-ziv 2>/dev/null
    fi
    ln -sf /usr/local/bin/ogh-ziv /usr/local/bin/menu 2>/dev/null
    chmod +x /usr/local/bin/menu 2>/dev/null
    grep -q "alias menu=" ~/.bashrc 2>/dev/null || \
        echo "alias menu='bash /usr/local/bin/ogh-ziv'" >> ~/.bashrc
    grep -q "alias menu=" /root/.profile 2>/dev/null || \
        echo "alias menu='bash /usr/local/bin/ogh-ziv'" >> /root/.profile
    cat > /etc/profile.d/ogh-ziv.sh << 'PROFEOF'
#!/bin/bash
alias menu='bash /usr/local/bin/ogh-ziv'
alias zivpn='bash /usr/local/bin/ogh-ziv'
alias udp='bash /usr/local/bin/ogh-ziv'
PROFEOF
    chmod +x /etc/profile.d/ogh-ziv.sh 2>/dev/null
}

# ════════════════════════════════════════════════════════════
#  MENU UTAMA — COMBINED PANEL
# ════════════════════════════════════════════════════════════
main_menu() {
    while true; do
        clear; load_theme; draw_logo

        # Status kedua service
        local ziv_col ziv_txt udp_col udp_txt
        is_up && { ziv_col="${LG}"; ziv_txt="● ZiVPN  AKTIF "; } || { ziv_col="${LR}"; ziv_txt="● ZiVPN  MATI  "; }
        systemctl is-active --quiet UDPserver 2>/dev/null \
            && { udp_col="${LG}"; udp_txt="● UDP-Req AKTIF"; } \
            || { udp_col="${LR}"; udp_txt="● UDP-Req MATI "; }

        echo -e "  ${A1}╔══════════════════════════════════════════════════════════╗${NC}"
        printf  "  ${A1}║${NC}  ${A1}◈${NC}──────── ${BLD}${AL}  🌐  OGH-ZIV COMBINED PANEL  ${NC}────────${A1}◈${NC}  ${A1}║${NC}\n"
        echo -e "  ${A1}╠══════════════════════════════════════════════════════════╣${NC}"
        printf  "  ${A1}║${NC}    ${ziv_col}${ziv_txt}${NC}       ${udp_col}${udp_txt}${NC}              ${A1}║${NC}\n"
        echo -e "  ${A1}╠══════════════════════════════════════════════════════════╣${NC}"

        printf  "  ${A1}║${NC}                                                          ${A1}║${NC}\n"
        printf  "  ${A1}║${NC}  ${A2}[1]${NC}  🔵  %-42s${A1}║${NC}\n" "UDP ZiVPN  — OGH-ZIV Panel"
        echo -e "  ${A1}╠╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╣${NC}"
        printf  "  ${A1}║${NC}  ${A2}[2]${NC}  🟡  %-42s${A1}║${NC}\n" "UDP Request — UDPserver Panel"
        printf  "  ${A1}║${NC}                                                          ${A1}║${NC}\n"

        echo -e "  ${A1}╠══════════════════════════════════════════════════════════╣${NC}"
        printf  "  ${A1}║${NC}  ${A2}[3]${NC}  🎨  %-42s${A1}║${NC}\n" "Ganti Tema Warna  [ ${THEME_NAME} ]"
        echo -e "  ${A1}╠╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╣${NC}"
        printf  "  ${A1}║${NC}  ${A4}[0]${NC}  ✖   %-42s${A1}║${NC}\n" "Keluar"
        echo -e "  ${A1}╠══════════════════════════════════════════════════════════╣${NC}"
        printf  "  ${A1}║${NC}%*s${DIM}OGH-ZIV Combined v1.0 PREMIUM${NC}%*s${A1}║${NC}\n" 14 "" 14 ""
        echo -e "  ${A1}╚══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -ne "  ${A1}›${NC} Pilih menu: "; read -r ch
        case ${ch,,} in
            1) menu_zivpn ;;
            2) menu_udp_request ;;
            3) menu_tema ;;
            0) echo -e "\n  ${IT}${AL}Sampai jumpa! — OGH-ZIV Combined Panel${NC}\n"; exit 0 ;;
            *) warn "Pilihan tidak valid!"; sleep 1 ;;
        esac
    done
}

# ════════════════════════════════════════════════════════════
#  MAIN ENTRYPOINT
# ════════════════════════════════════════════════════════════
check_os
check_root
mkdir -p "$DIR"
load_theme

# Handle CLI flags
if [[ "${1:-}" == "--check-maxlogin" ]]; then
    check_maxlogin_all
    exit 0
fi

# Setup UDPserver pertama kali jika belum ada
if [[ ! -d "$udp_file" ]]; then
    mkdir -p "$udp_file"
    [[ ! -f "${udp_file}/limitador.sh" ]] && buat_limitador
fi
[[ ! -f "${udp_file}/limitador.sh" ]] && buat_limitador

setup_menu_cmd 2>/dev/null
main_menu
