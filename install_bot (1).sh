#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║        OGH-UDP INSTALL BOT v3.1                                 ║
# ║  Synced dengan: ogh-manager.sh + ogh_bot.py                     ║
# ║  GitHub       : github.com/chanelog/Bot                         ║
# ╚══════════════════════════════════════════════════════════════════╝

# ══════════════════════════════════════════════════════════════════
#  ▼▼▼  KONSTANTA — identik dengan ogh-manager.sh & ogh_bot.py  ▼▼▼
# ══════════════════════════════════════════════════════════════════
VERSION="3.1"
SYNC_KEY="OGH-SYNC-3.1"

# --- Paths (harus sama dengan kedua file lain) ---
OGH_BIN="/usr/local/bin/udpServer"
OGH_SVC="ogh-udp"
OGH_DIR="/etc/ogh-udp"
OGH_DB="$OGH_DIR/users.db"
OGH_PORT_FILE="$OGH_DIR/port.conf"
OGH_LOG="/var/log/ogh-udp.log"
OGH_QUOTA_DIR="$OGH_DIR/quota"
OGH_SESSION_DIR="$OGH_DIR/sessions"

ZIV_BIN="/usr/local/bin/udp-zivpn"
ZIV_SVC="zivpn-udp"
ZIV_DIR="/etc/zivpn-udp"
ZIV_CFG="$ZIV_DIR/config.json"
ZIV_DB="$ZIV_DIR/users.db"
ZIV_LOG="/var/log/zivpn-udp.log"
ZIV_QUOTA_DIR="$ZIV_DIR/quota"
ZIV_SESSION_DIR="$ZIV_DIR/sessions"

BOT_DIR="/opt/ogh-bot"
BOT_PY="$BOT_DIR/ogh_bot.py"
BOT_SVC="ogh-bot"
BOT_SVC_FILE="/etc/systemd/system/ogh-bot.service"
BOT_DB_DIR="/etc/ogh-bot"
BOT_RESELLER_DB="$BOT_DB_DIR/resellers.json"
BOT_CFG_FILE="$BOT_DB_DIR/config.json"
BOT_LOG="/var/log/ogh-bot.log"

# --- GitHub URLs (harus sama dengan kedua file lain) ---
MANAGER_URL="https://github.com/chanelog/Bot/raw/refs/heads/main/ogh-manager.sh"
BOT_PY_URL="https://github.com/chanelog/Bot/raw/refs/heads/main/ogh_bot.py"
INSTALL_URL="https://github.com/chanelog/Bot/raw/refs/heads/main/install_bot.sh"

OGH_BIN_URL="https://github.com/chanelog/Ogh/raw/main/udpServer"
ZIV_BIN_URL="https://github.com/fauzanihanipah/ziv-udp/releases/download/udp-zivpn/udp-zivpn-linux-amd64"
ZIV_CFG_URL="https://raw.githubusercontent.com/fauzanihanipah/ziv-udp/main/config.json"
# ══════════════════════════════════════════════════════════════════

# ─── COLORS ────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; W='\033[1;37m'; BOLD='\033[1m'; NC='\033[0m'

ok()    { echo -e "${G}  [✓] $1${NC}"; }
err()   { echo -e "${R}  [✗] $1${NC}"; }
warn()  { echo -e "${Y}  [!] $1${NC}"; }
info()  { echo -e "${C}  [*] $1${NC}"; }
title() {
    echo -e "${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

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

die() { err "$1"; exit 1; }

# ══════════════════════════════════════════════════════════════════
#  BANNER
# ══════════════════════════════════════════════════════════════════
clear
echo -e "${C}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║    OGH-UDP ALL-IN-ONE  —  Bot Installer v${VERSION}       ║"
echo "  ║    SYNC_KEY : ${SYNC_KEY}                       ║"
echo "  ║    GitHub   : github.com/chanelog/Bot               ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ══════════════════════════════════════════════════════════════════
#  PRE-CHECKS
# ══════════════════════════════════════════════════════════════════
title "1/7 · Pre-check"

[ "$EUID" -ne 0 ] && die "Jalankan sebagai root: sudo bash install_bot.sh"
ok "Running sebagai root."

command -v systemctl &>/dev/null || die "systemd tidak ditemukan."
ok "systemd tersedia."

# Cek koneksi internet
if ! curl -s --max-time 5 -o /dev/null https://github.com; then
    die "Tidak ada koneksi internet / GitHub tidak dapat dijangkau."
fi
ok "Koneksi internet OK."

# ══════════════════════════════════════════════════════════════════
#  INSTALL DEPENDENCIES
# ══════════════════════════════════════════════════════════════════
title "2/7 · Install Dependensi"

# apt / yum
if command -v apt-get &>/dev/null; then
    info "Update apt cache..."
    apt-get update -qq 2>/dev/null
    apt-get install -y python3 python3-pip bc curl wget &>/dev/null
elif command -v yum &>/dev/null; then
    yum install -y python3 python3-pip bc curl wget &>/dev/null
elif command -v dnf &>/dev/null; then
    dnf install -y python3 python3-pip bc curl wget &>/dev/null
else
    warn "Package manager tidak dikenal. Pastikan python3 & pip3 sudah terinstall."
fi

python3 --version &>/dev/null || die "Python3 tidak ditemukan."
ok "Python3: $(python3 --version)"

info "Install python-telegram-bot==20.7 & requests..."
pip3 install python-telegram-bot==20.7 requests --quiet --break-system-packages 2>/dev/null \
    || pip3 install python-telegram-bot==20.7 requests --quiet 2>/dev/null
python3 -c "import telegram" 2>/dev/null || die "python-telegram-bot gagal diinstall."
ok "python-telegram-bot siap."

# ══════════════════════════════════════════════════════════════════
#  SETUP DIREKTORI & DB (sinkron dengan ogh-manager.sh)
# ══════════════════════════════════════════════════════════════════
title "3/7 · Setup Direktori & Database"

for D in "$OGH_DIR" "$OGH_QUOTA_DIR" "$OGH_SESSION_DIR" \
          "$ZIV_DIR"  "$ZIV_QUOTA_DIR"  "$ZIV_SESSION_DIR" \
          "$BOT_DIR"  "$BOT_DB_DIR"; do
    mkdir -p "$D"
done

touch "$OGH_DB" "$ZIV_DB" "$OGH_LOG" "$ZIV_LOG" "$BOT_LOG"

# Bot config (sama format dengan ogh-manager.sh)
if [ ! -f "$BOT_CFG_FILE" ]; then
    cat > "$BOT_CFG_FILE" <<'BOTCFG'
{
  "ogh_default_days": 30,
  "ziv_default_days": 30,
  "ogh_default_quota": 0,
  "ziv_default_quota": 0,
  "ogh_default_maxlogin": 2,
  "ziv_default_maxlogin": 2,
  "maintenance": false
}
BOTCFG
    ok "Bot config dibuat: $BOT_CFG_FILE"
else
    ok "Bot config sudah ada: $BOT_CFG_FILE"
fi

# Reseller DB
[ ! -f "$BOT_RESELLER_DB" ] && echo '{}' > "$BOT_RESELLER_DB" && ok "Reseller DB dibuat."

# ZivPN default config
if [ ! -f "$ZIV_CFG" ]; then
    info "Mengunduh config.json ZivPN..."
    _dl "$ZIV_CFG_URL" "$ZIV_CFG"
    if [ ! -s "$ZIV_CFG" ]; then
        cat > "$ZIV_CFG" <<'JSON'
{
  "listen": ":7200",
  "remote": "127.0.0.1:443",
  "key": "ogh-udp-zivpn",
  "obfs": "salamander",
  "auth": { "type": "password", "password": "zivpn2024" },
  "bandwidth": { "up": "100 mbps", "down": "100 mbps" },
  "masquerade": {
    "type": "proxy",
    "proxy": { "url": "https://news.ycombinator.com/", "rewriteHost": true }
  }
}
JSON
        ok "config.json ZivPN default dibuat."
    else
        ok "config.json ZivPN diunduh dari GitHub."
    fi
else
    ok "config.json ZivPN sudah ada."
fi
ok "Semua direktori & database siap."

# ══════════════════════════════════════════════════════════════════
#  DOWNLOAD ogh-manager.sh (binary manager)
# ══════════════════════════════════════════════════════════════════
title "4/7 · Download ogh-manager.sh"

MANAGER_DEST="/usr/local/bin/ogh-manager"

info "Mengunduh ogh-manager.sh dari GitHub..."
_dl "$MANAGER_URL" "$MANAGER_DEST"

if [ -s "$MANAGER_DEST" ]; then
    chmod +x "$MANAGER_DEST"
    # Validasi SYNC_KEY
    if grep -q "$SYNC_KEY" "$MANAGER_DEST"; then
        ok "ogh-manager.sh valid (SYNC_KEY=$SYNC_KEY)."
    else
        warn "SYNC_KEY tidak cocok di ogh-manager.sh — mungkin versi berbeda."
    fi
    # Register alias 'menu'
    ln -sf "$MANAGER_DEST" /usr/local/bin/menu 2>/dev/null
    grep -q "alias menu=" ~/.bashrc 2>/dev/null \
        || echo "alias menu='bash /usr/local/bin/ogh-manager'" >> ~/.bashrc
    ok "Alias 'menu' terdaftar → /usr/local/bin/menu"
else
    err "Gagal mengunduh ogh-manager.sh!"
    warn "Anda bisa jalankan manager secara terpisah dari GitHub."
fi

# ══════════════════════════════════════════════════════════════════
#  DOWNLOAD ogh_bot.py
# ══════════════════════════════════════════════════════════════════
title "5/7 · Download ogh_bot.py"

info "Mengunduh ogh_bot.py dari GitHub..."
_dl "$BOT_PY_URL" "$BOT_PY"

if [ ! -s "$BOT_PY" ]; then
    die "Gagal mengunduh ogh_bot.py dari GitHub!"
fi
chmod +x "$BOT_PY"

# Validasi SYNC_KEY di bot
if grep -q "$SYNC_KEY" "$BOT_PY"; then
    ok "ogh_bot.py valid (SYNC_KEY=$SYNC_KEY)."
else
    warn "SYNC_KEY tidak cocok di ogh_bot.py — mungkin versi berbeda."
fi
ok "ogh_bot.py siap di $BOT_PY"

# ══════════════════════════════════════════════════════════════════
#  KONFIGURASI TOKEN & ADMIN
# ══════════════════════════════════════════════════════════════════
title "6/7 · Konfigurasi Bot"

echo ""
echo -e "  ${Y}Diperlukan TOKEN BOT dari @BotFather${NC}"
echo -e "  ${Y}dan TELEGRAM ID admin (cek di @userinfobot)${NC}"
echo ""

# Token
while true; do
    read -p "  BOT TOKEN    : " TOKEN
    [ -n "$TOKEN" ] && break
    err "Token tidak boleh kosong."
done

# Admin ID (bisa lebih dari satu, pisah koma)
while true; do
    read -p "  ADMIN ID     [cth: 123456789 atau 111,222]: " ADMIN_RAW
    [ -n "$ADMIN_RAW" ] && break
    err "Admin ID tidak boleh kosong."
done
# Format: 111,222 → [111,222]
ADMIN_FMT="[$(echo "$ADMIN_RAW" | tr -d ' ')]"

# Nama bot (opsional)
read -p "  Nama Bot     [OGH-UDP Manager]: " BOT_NAME_INPUT
BOT_NAME_INPUT="${BOT_NAME_INPUT:-OGH-UDP Manager}"

# Patch ogh_bot.py
sed -i "s|BOT_TOKEN    = \"ISI_TOKEN_BOT_DISINI\"|BOT_TOKEN    = \"$TOKEN\"|"      "$BOT_PY"
sed -i "s|ADMIN_IDS    = \[123456789\]|ADMIN_IDS    = $ADMIN_FMT|"                 "$BOT_PY"
sed -i "s|BOT_NAME     = \"OGH-UDP Manager\"|BOT_NAME     = \"$BOT_NAME_INPUT\"|"  "$BOT_PY"

# Verifikasi patch
grep -q "$TOKEN"          "$BOT_PY" && ok "Token diterapkan." || err "Gagal patch token."
grep -q "$ADMIN_FMT"      "$BOT_PY" && ok "Admin ID diterapkan: $ADMIN_FMT" || err "Gagal patch Admin ID."
ok "Nama bot: $BOT_NAME_INPUT"

# Simpan ke file config tambahan agar mudah dicek
cat > "$BOT_DB_DIR/install_info.json" <<EOF
{
  "version"   : "$VERSION",
  "sync_key"  : "$SYNC_KEY",
  "bot_name"  : "$BOT_NAME_INPUT",
  "admin_ids" : "$ADMIN_FMT",
  "installed" : "$(date '+%Y-%m-%d %H:%M:%S')",
  "manager_url"  : "$MANAGER_URL",
  "bot_py_url"   : "$BOT_PY_URL",
  "install_url"  : "$INSTALL_URL"
}
EOF
ok "Info instalasi disimpan: $BOT_DB_DIR/install_info.json"

# ══════════════════════════════════════════════════════════════════
#  SYSTEMD SERVICE
# ══════════════════════════════════════════════════════════════════
title "7/7 · Setup Systemd Service"

# Hapus service lama kalau ada
if systemctl is-active --quiet "$BOT_SVC" 2>/dev/null; then
    warn "Service '$BOT_SVC' lama berjalan → stop dulu..."
    systemctl stop "$BOT_SVC"
fi

# Tulis unit file
cat > "$BOT_SVC_FILE" <<EOF
[Unit]
Description=OGH-UDP Telegram Bot v${VERSION} [${SYNC_KEY}]
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$BOT_DIR
ExecStart=/usr/bin/python3 $BOT_PY
Restart=always
RestartSec=5
StandardOutput=append:$BOT_LOG
StandardError=append:$BOT_LOG
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$BOT_SVC" &>/dev/null
ok "Service '$BOT_SVC' didaftarkan."

systemctl start "$BOT_SVC"
sleep 3

if systemctl is-active --quiet "$BOT_SVC"; then
    ok "Bot BERJALAN! ✅"
else
    err "Bot GAGAL start. Cek log:"
    journalctl -u "$BOT_SVC" -n 20 --no-pager
fi

# ══════════════════════════════════════════════════════════════════
#  RINGKASAN AKHIR
# ══════════════════════════════════════════════════════════════════
echo ""
echo -e "${C}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${G}${BOLD}  ✅  INSTALASI SELESAI — OGH-UDP v${VERSION} [${SYNC_KEY}]${NC}"
echo -e "${C}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${C}Tiga file yang saling terhubung:${NC}"
echo -e "  ${W}① ogh-manager.sh${NC}  → $MANAGER_DEST"
echo -e "     • Manager CLI untuk OGH-UDP & ZivPN"
echo -e "     • Berisi menu 71-78 untuk kontrol bot TG"
echo -e "     • Ketik ${BOLD}menu${NC} di terminal untuk membuka"
echo ""
echo -e "  ${W}② ogh_bot.py${NC}      → $BOT_PY"
echo -e "     • Telegram Bot, baca DB yang sama dengan manager"
echo -e "     • Semua path/format DB identik"
echo ""
echo -e "  ${W}③ install_bot.sh${NC}  → Script ini"
echo -e "     • Download & sinkronkan ① dan ②"
echo -e "     • Validasi SYNC_KEY=$SYNC_KEY"
echo ""
echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${W}Perintah berguna:${NC}"
echo -e "  menu                          → Buka manager CLI"
echo -e "  systemctl status $BOT_SVC     → Status bot TG"
echo -e "  systemctl restart $BOT_SVC    → Restart bot TG"
echo -e "  tail -f $BOT_LOG         → Live log bot"
echo -e "  tail -f $OGH_LOG    → Live log OGH-UDP"
echo ""
echo -e "  ${W}File penting:${NC}"
echo -e "  $OGH_DB     → Database akun OGH"
echo -e "  $ZIV_DB     → Database akun ZivPN"
echo -e "  $BOT_RESELLER_DB  → Database reseller"
echo -e "  $BOT_CFG_FILE       → Config default bot"
echo -e "  $BOT_DB_DIR/install_info.json → Info instalasi"
echo ""
echo -e "  ${W}Update semua file dari GitHub:${NC}"
echo -e "  bash <(curl -sL ${INSTALL_URL})"
echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Buka Telegram → cari bot Anda → ketik ${BOLD}/start${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════
#  UPDATE FUNCTION — bisa dipanggil ulang untuk update saja
# ══════════════════════════════════════════════════════════════════
update_all_files() {
    echo ""
    title "UPDATE SEMUA FILE DARI GITHUB"

    # Update ogh-manager.sh
    info "Update ogh-manager.sh..."
    _dl "$MANAGER_URL" "$MANAGER_DEST"
    if [ -s "$MANAGER_DEST" ]; then
        chmod +x "$MANAGER_DEST"
        grep -q "$SYNC_KEY" "$MANAGER_DEST" \
            && ok "ogh-manager.sh updated & valid." \
            || warn "ogh-manager.sh updated tapi SYNC_KEY berbeda."
    else
        err "Gagal update ogh-manager.sh"
    fi

    # Update ogh_bot.py (pertahankan token & admin)
    info "Update ogh_bot.py (token dipertahankan)..."
    OLD_TOKEN=$(grep 'BOT_TOKEN' "$BOT_PY" 2>/dev/null | cut -d'"' -f2)
    OLD_ADMIN=$(grep 'ADMIN_IDS' "$BOT_PY" 2>/dev/null | sed 's/.*= //')
    OLD_NAME=$(grep 'BOT_NAME' "$BOT_PY" 2>/dev/null | cut -d'"' -f2)

    _dl "$BOT_PY_URL" "${BOT_PY}.new"
    if [ -s "${BOT_PY}.new" ]; then
        mv "${BOT_PY}.new" "$BOT_PY"; chmod +x "$BOT_PY"
        # Restore konfigurasi
        [ -n "$OLD_TOKEN" ] && sed -i "s|BOT_TOKEN    = \"ISI_TOKEN_BOT_DISINI\"|BOT_TOKEN    = \"$OLD_TOKEN\"|" "$BOT_PY"
        [ -n "$OLD_ADMIN" ] && sed -i "s|ADMIN_IDS    = \[123456789\]|ADMIN_IDS    = $OLD_ADMIN|" "$BOT_PY"
        [ -n "$OLD_NAME"  ] && sed -i "s|BOT_NAME     = \"OGH-UDP Manager\"|BOT_NAME     = \"$OLD_NAME\"|"  "$BOT_PY"
        grep -q "$SYNC_KEY" "$BOT_PY" \
            && ok "ogh_bot.py updated & valid (token dipertahankan)." \
            || warn "ogh_bot.py updated tapi SYNC_KEY berbeda."
    else
        err "Gagal update ogh_bot.py"
    fi

    # Restart bot
    systemctl restart "$BOT_SVC" 2>/dev/null
    sleep 2
    systemctl is-active --quiet "$BOT_SVC" \
        && ok "Bot direstart & berjalan." \
        || warn "Bot tidak berjalan setelah update. Cek: journalctl -u $BOT_SVC -n 20"
}

# Jika dipanggil dengan argumen 'update'
[ "$1" = "update" ] && update_all_files
