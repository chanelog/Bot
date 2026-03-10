#!/bin/bash
# ══════════════════════════════════════════════
#  OGH-UDP BOT INSTALLER
# ══════════════════════════════════════════════
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

ok()   { echo -e "${GREEN}[✓] $1${NC}"; }
info() { echo -e "${CYAN}[*] $1${NC}"; }
warn() { echo -e "${YELLOW}[!] $1${NC}"; }
err()  { echo -e "${RED}[✗] $1${NC}"; exit 1; }

echo -e "${CYAN}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║    OGH-UDP Bot Telegram Installer    ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"

# Check root
[ "$EUID" -ne 0 ] && err "Jalankan sebagai root!"

# Install Python3 & pip
info "Install Python3 dan pip..."
if command -v apt-get &>/dev/null; then
    apt-get update -qq && apt-get install -y python3 python3-pip &>/dev/null
elif command -v yum &>/dev/null; then
    yum install -y python3 python3-pip &>/dev/null
fi
ok "Python3 siap: $(python3 --version)"

# Install library
info "Install python-telegram-bot..."
pip3 install python-telegram-bot==20.7 requests --quiet
ok "Library terinstall."

# Copy bot file
BOT_DIR="/opt/ogh-bot"
mkdir -p "$BOT_DIR"
cp ogh_bot.py "$BOT_DIR/ogh_bot.py"
chmod +x "$BOT_DIR/ogh_bot.py"
ok "File bot disalin ke $BOT_DIR/"

# Minta token dan admin ID
echo ""
warn "Konfigurasi awal:"
read -p "  Masukkan BOT TOKEN dari @BotFather: " TOKEN
read -p "  Masukkan Telegram ID Admin (angka): " ADMIN_ID
read -p "  Nama Bot [OGH-UDP Manager]: " BOT_NAME_INPUT
BOT_NAME_INPUT="${BOT_NAME_INPUT:-OGH-UDP Manager}"

# Patch konfigurasi
sed -i "s|BOT_TOKEN    = \"ISI_TOKEN_BOT_DISINI\"|BOT_TOKEN    = \"$TOKEN\"|" "$BOT_DIR/ogh_bot.py"
sed -i "s|ADMIN_IDS    = \[123456789\]|ADMIN_IDS    = [$ADMIN_ID]|" "$BOT_DIR/ogh_bot.py"
sed -i "s|BOT_NAME     = \"OGH-UDP Manager\"|BOT_NAME     = \"$BOT_NAME_INPUT\"|" "$BOT_DIR/ogh_bot.py"
ok "Konfigurasi diterapkan."

# Buat systemd service
cat > /etc/systemd/system/ogh-bot.service <<EOF
[Unit]
Description=OGH-UDP Telegram Bot
After=network.target

[Service]
Type=simple
WorkingDirectory=$BOT_DIR
ExecStart=/usr/bin/python3 $BOT_DIR/ogh_bot.py
Restart=always
RestartSec=5
StandardOutput=append:/var/log/ogh-bot.log
StandardError=append:/var/log/ogh-bot.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ogh-bot
systemctl start ogh-bot
sleep 2

if systemctl is-active --quiet ogh-bot; then
    ok "Bot berjalan!"
else
    err "Gagal start bot. Cek: journalctl -u ogh-bot -n 30"
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✅ Instalasi Selesai!${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Bot file  : $BOT_DIR/ogh_bot.py"
echo -e "  Log file  : /var/log/ogh-bot.log"
echo -e "  Cek status: systemctl status ogh-bot"
echo -e "  Stop bot  : systemctl stop ogh-bot"
echo -e "  Lihat log : tail -f /var/log/ogh-bot.log"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Buka Telegram dan ketik /start ke bot Anda!"
echo ""
