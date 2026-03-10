#!/bin/bash
# ============================================
#   OGH-UDP TELEGRAM BOT
#   Bot Manager untuk UDP-OGH & ZIV-UDP
# ============================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

BOT_DIR="/etc/ogh-bot"
BOT_TOKEN_FILE="$BOT_DIR/token"
BOT_ADMIN_FILE="$BOT_DIR/admin"
BOT_PID_FILE="$BOT_DIR/bot.pid"
BOT_LOG="$BOT_DIR/bot.log"

OGH_USER_DB="/etc/ogh-udp/users.db"
ZIV_USER_DB="/etc/ziv-udp/users.db"
ZIV_CONFIG="/etc/ziv-udp/config.json"

# ─────────────────────────────────────────
# SETUP BOT
# ─────────────────────────────────────────

setup_bot() {
    clear
    echo -e "${CYAN}"
    echo "  ╔═══════════════════════════════════════╗"
    echo "  ║       OGH-UDP TELEGRAM BOT SETUP      ║"
    echo "  ╚═══════════════════════════════════════╝"
    echo -e "${NC}"

    apt-get install -y curl jq -qq

    mkdir -p "$BOT_DIR"

    echo -e "${WHITE}Masukkan Bot Token dari @BotFather:${NC}"
    read -p "  Token: " bot_token
    echo "$bot_token" > "$BOT_TOKEN_FILE"

    echo ""
    echo -e "${WHITE}Masukkan Admin Chat ID Anda:${NC}"
    echo -e "${YELLOW}  (Kirim pesan ke @userinfobot untuk mendapat ID)${NC}"
    read -p "  Chat ID: " admin_id
    echo "$admin_id" > "$BOT_ADMIN_FILE"

    # Test token
    echo -e "${CYAN}[*] Mengecek token...${NC}"
    result=$(curl -s "https://api.telegram.org/bot$bot_token/getMe")
    if echo "$result" | grep -q '"ok":true'; then
        bot_name=$(echo "$result" | jq -r '.result.username')
        echo -e "${GREEN}[✓] Bot aktif: @$bot_name${NC}"
    else
        echo -e "${RED}[✗] Token tidak valid! Periksa kembali.${NC}"
        exit 1
    fi

    # Create systemd service for bot
    create_bot_service

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   ✓ BOT BERHASIL DIKONFIGURASI!         ║${NC}"
    echo -e "${GREEN}║   Kirim /start ke bot Anda              ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    sleep 3
    start_bot
}

create_bot_service() {
    local token=$(cat "$BOT_TOKEN_FILE")
    local admin=$(cat "$BOT_ADMIN_FILE")
    
    cat > /etc/systemd/system/ogh-bot.service <<EOF
[Unit]
Description=OGH-UDP Telegram Bot
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ogh-bot run
Restart=always
RestartSec=5
User=root
StandardOutput=append:$BOT_LOG
StandardError=append:$BOT_LOG

[Install]
WantedBy=multi-user.target
EOF

    cp "$0" /usr/local/bin/ogh-bot
    chmod +x /usr/local/bin/ogh-bot
    systemctl daemon-reload
    systemctl enable ogh-bot
}

start_bot() {
    systemctl start ogh-bot
    echo -e "${GREEN}[✓] Bot dimulai sebagai service!${NC}"
}

# ─────────────────────────────────────────
# TELEGRAM API HELPER
# ─────────────────────────────────────────

TOKEN=$(cat "$BOT_TOKEN_FILE" 2>/dev/null)
ADMIN_ID=$(cat "$BOT_ADMIN_FILE" 2>/dev/null)
API="https://api.telegram.org/bot$TOKEN"

send_msg() {
    local chat_id="$1"
    local text="$2"
    local keyboard="${3:-}"
    
    local data="{\"chat_id\":\"$chat_id\",\"text\":\"$text\",\"parse_mode\":\"HTML\"}"
    
    if [ -n "$keyboard" ]; then
        data="{\"chat_id\":\"$chat_id\",\"text\":\"$text\",\"parse_mode\":\"HTML\",\"reply_markup\":$keyboard}"
    fi
    
    curl -s -X POST "$API/sendMessage" \
        -H "Content-Type: application/json" \
        -d "$data" > /dev/null
}

send_msg_md() {
    local chat_id="$1"
    local text="$2"
    curl -s -X POST "$API/sendMessage" \
        -H "Content-Type: application/json" \
        -d "{\"chat_id\":\"$chat_id\",\"text\":\"$text\",\"parse_mode\":\"Markdown\"}" > /dev/null
}

answer_callback() {
    local callback_id="$1"
    local text="${2:-OK}"
    curl -s -X POST "$API/answerCallbackQuery" \
        -H "Content-Type: application/json" \
        -d "{\"callback_query_id\":\"$callback_id\",\"text\":\"$text\"}" > /dev/null
}

edit_msg() {
    local chat_id="$1"
    local msg_id="$2"
    local text="$3"
    local keyboard="${4:-}"
    
    local data="{\"chat_id\":\"$chat_id\",\"message_id\":\"$msg_id\",\"text\":\"$text\",\"parse_mode\":\"HTML\"}"
    if [ -n "$keyboard" ]; then
        data="{\"chat_id\":\"$chat_id\",\"message_id\":\"$msg_id\",\"text\":\"$text\",\"parse_mode\":\"HTML\",\"reply_markup\":$keyboard}"
    fi
    curl -s -X POST "$API/editMessageText" \
        -H "Content-Type: application/json" \
        -d "$data" > /dev/null
}

# ─────────────────────────────────────────
# KEYBOARD BUILDERS
# ─────────────────────────────────────────

main_keyboard() {
    echo '{
        "inline_keyboard": [
            [{"text":"➕ Tambah Akun OGH","callback_data":"add_ogh"},{"text":"➕ Tambah Akun ZIV","callback_data":"add_ziv"}],
            [{"text":"🗑 Hapus Akun OGH","callback_data":"del_ogh"},{"text":"🗑 Hapus Akun ZIV","callback_data":"del_ziv"}],
            [{"text":"📋 List Akun OGH","callback_data":"list_ogh"},{"text":"📋 List Akun ZIV","callback_data":"list_ziv"}],
            [{"text":"🔍 Cek Akun OGH","callback_data":"cek_ogh"},{"text":"🔍 Cek Akun ZIV","callback_data":"cek_ziv"}],
            [{"text":"⏳ Perpanjang OGH","callback_data":"renew_ogh"},{"text":"⏳ Perpanjang ZIV","callback_data":"renew_ziv"}],
            [{"text":"🧹 Hapus Expired OGH","callback_data":"exp_ogh"},{"text":"🧹 Hapus Expired ZIV","callback_data":"exp_ziv"}],
            [{"text":"⚙️ Service OGH","callback_data":"svc_ogh"},{"text":"⚙️ Service ZIV","callback_data":"svc_ziv"}],
            [{"text":"📊 Info Server","callback_data":"info"}]
        ]
    }'
}

service_keyboard() {
    local svc="$1"
    echo "{
        \"inline_keyboard\": [
            [{\"text\":\"▶ Start\",\"callback_data\":\"start_$svc\"},{\"text\":\"⏹ Stop\",\"callback_data\":\"stop_$svc\"},{\"text\":\"🔄 Restart\",\"callback_data\":\"restart_$svc\"}],
            [{\"text\":\"◀ Kembali\",\"callback_data\":\"back\"}]
        ]
    }"
}

back_keyboard() {
    echo '{"inline_keyboard":[[{"text":"◀ Menu Utama","callback_data":"back"}]]}'
}

# ─────────────────────────────────────────
# BOT STATE (file-based)
# ─────────────────────────────────────────

STATE_DIR="$BOT_DIR/state"
mkdir -p "$STATE_DIR"

set_state() {
    echo "$2" > "$STATE_DIR/$1"
}

get_state() {
    cat "$STATE_DIR/$1" 2>/dev/null || echo ""
}

clear_state() {
    rm -f "$STATE_DIR/$1"
}

# ─────────────────────────────────────────
# SERVER INFO
# ─────────────────────────────────────────

get_server_info() {
    local ip=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    local uptime=$(uptime -p 2>/dev/null || echo "N/A")
    local ram=$(free -h | awk '/^Mem:/ {print $3"/"$2}')
    local disk=$(df -h / | awk 'NR==2 {print $3"/"$2}')
    local ogh_users=$( [ -f "$OGH_USER_DB" ] && wc -l < "$OGH_USER_DB" || echo "0" )
    local ziv_users=$( [ -f "$ZIV_USER_DB" ] && wc -l < "$ZIV_USER_DB" || echo "0" )
    local ogh_status=$( systemctl is-active ogh-udp 2>/dev/null || echo "inactive" )
    local ziv_status=$( systemctl is-active ziv-udp 2>/dev/null || echo "inactive" )
    local ziv_port=$(jq -r '.listen' "$ZIV_CONFIG" 2>/dev/null | tr -d ':' || echo "7300")

    echo "📊 <b>INFO SERVER</b>
━━━━━━━━━━━━━━━━━━━━━━
🌐 IP Server  : <code>$ip</code>
⏱ Uptime     : $uptime
💾 RAM        : $ram
💿 Disk       : $disk
━━━━━━━━━━━━━━━━━━━━━━
<b>OGH-UDP</b>
👥 Total Akun : $ogh_users
🔌 Status     : $( [ "$ogh_status" = "active" ] && echo "✅ RUNNING" || echo "❌ STOPPED" )
━━━━━━━━━━━━━━━━━━━━━━
<b>ZIV-UDP</b>
👥 Total Akun : $ziv_users
🔧 Port       : $ziv_port
🔌 Status     : $( [ "$ziv_status" = "active" ] && echo "✅ RUNNING" || echo "❌ STOPPED" )"
}

# ─────────────────────────────────────────
# USER MANAGEMENT BOT FUNCTIONS
# ─────────────────────────────────────────

bot_list_users() {
    local db="$1"
    local type="$2"
    
    if [ ! -s "$db" ]; then
        echo "📋 <b>DAFTAR AKUN $type</b>
━━━━━━━━━━━━━━━━━━━━━━
❌ Belum ada akun terdaftar"
        return
    fi

    local today=$(date +"%Y-%m-%d")
    local today_ts=$(date -d "$today" +%s)
    local output="📋 <b>DAFTAR AKUN $type</b>
━━━━━━━━━━━━━━━━━━━━━━
"
    local count=1
    while IFS=: read -r user pass exp rest; do
        local exp_ts=$(date -d "$exp" +%s 2>/dev/null)
        local sisa=$(( (exp_ts - today_ts) / 86400 ))
        local icon=$( [ "$sisa" -lt 0 ] && echo "❌" || echo "✅" )
        output+="$count. $icon <b>$user</b> | exp: $exp
"
        ((count++))
    done < "$db"
    echo "$output"
}

bot_add_user() {
    local db="$1"
    local username="$2"
    local password="$3"
    local days="$4"
    local maxlogin="${5:-2}"

    if grep -q "^$username:" "$db" 2>/dev/null; then
        echo "❌ Username <b>$username</b> sudah ada!"
        return 1
    fi

    local exp_date=$(date -d "+${days} days" +"%Y-%m-%d")
    echo "$username:$password:$exp_date:$maxlogin" >> "$db"

    # If ZIV, also update config.json
    if [ "$db" = "$ZIV_USER_DB" ] && command -v jq &>/dev/null; then
        jq --arg pwd "$password" '.auth.passwords += [$pwd]' "$ZIV_CONFIG" > /tmp/zcfg.json 2>/dev/null
        mv /tmp/zcfg.json "$ZIV_CONFIG" 2>/dev/null
        systemctl restart ziv-udp 2>/dev/null
    fi

    local ip=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    local port="7300"
    [ "$db" = "$ZIV_USER_DB" ] && port=$(jq -r '.listen' "$ZIV_CONFIG" 2>/dev/null | tr -d ':' || echo "7300")

    echo "✅ <b>AKUN BERHASIL DIBUAT</b>
━━━━━━━━━━━━━━━━━━━━━━
👤 Username  : <code>$username</code>
🔑 Password  : <code>$password</code>
📅 Expired   : <code>$exp_date</code>
🔢 Max Login : <code>$maxlogin</code>
🌐 IP Server : <code>$ip</code>
🔌 Port      : <code>$port</code>"
    return 0
}

bot_check_user() {
    local db="$1"
    local type="$2"
    local username="$3"

    if ! grep -q "^$username:" "$db" 2>/dev/null; then
        echo "❌ User <b>$username</b> tidak ditemukan!"
        return
    fi

    local line=$(grep "^$username:" "$db")
    local pass=$(echo $line | cut -d: -f2)
    local exp=$(echo $line | cut -d: -f3)
    local max=$(echo $line | cut -d: -f4)

    local today=$(date +"%Y-%m-%d")
    local today_ts=$(date -d "$today" +%s)
    local exp_ts=$(date -d "$exp" +%s 2>/dev/null)
    local sisa=$(( (exp_ts - today_ts) / 86400 ))
    local status=$( [ "$sisa" -lt 0 ] && echo "❌ EXPIRED" || echo "✅ AKTIF ($sisa hari)" )
    
    local ip=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

    echo "🔍 <b>CEK AKUN $type</b>
━━━━━━━━━━━━━━━━━━━━━━
👤 Username  : <code>$username</code>
🔑 Password  : <code>$pass</code>
🌐 IP Server : <code>$ip</code>
📅 Expired   : <code>$exp</code>
⏳ Sisa      : <code>$sisa hari</code>
🔢 Max Login : <code>$max</code>
📌 Status    : $status"
}

bot_delete_user() {
    local db="$1"
    local type="$2"
    local username="$3"

    if ! grep -q "^$username:" "$db" 2>/dev/null; then
        echo "❌ User <b>$username</b> tidak ditemukan!"
        return 1
    fi

    local pass=$(grep "^$username:" "$db" | cut -d: -f2)
    sed -i "/^$username:/d" "$db"

    if [ "$db" = "$ZIV_USER_DB" ] && command -v jq &>/dev/null; then
        jq --arg pwd "$pass" '.auth.passwords -= [$pwd]' "$ZIV_CONFIG" > /tmp/zcfg.json 2>/dev/null
        mv /tmp/zcfg.json "$ZIV_CONFIG" 2>/dev/null
        systemctl restart ziv-udp 2>/dev/null
    fi

    echo "🗑 Akun <b>$username</b> berhasil dihapus dari $type!"
    return 0
}

bot_renew_user() {
    local db="$1"
    local type="$2"
    local username="$3"
    local days="$4"

    if ! grep -q "^$username:" "$db" 2>/dev/null; then
        echo "❌ User <b>$username</b> tidak ditemukan!"
        return 1
    fi

    local old_exp=$(grep "^$username:" "$db" | cut -d: -f3)
    local today=$(date +"%Y-%m-%d")
    local today_ts=$(date -d "$today" +%s)
    local exp_ts=$(date -d "$old_exp" +%s 2>/dev/null)
    local sisa=$(( (exp_ts - today_ts) / 86400 ))
    
    local new_exp
    if [ "$sisa" -lt 0 ]; then
        new_exp=$(date -d "+${days} days" +"%Y-%m-%d")
    else
        new_exp=$(date -d "$old_exp +${days} days" +"%Y-%m-%d")
    fi

    sed -i "s/^$username:\([^:]*\):[^:]*:\([^:]*\)/$username:\1:$new_exp:\2/" "$db"
    echo "⏳ Akun <b>$username</b> ($type) diperpanjang sampai <code>$new_exp</code>!"
}

bot_delete_expired() {
    local db="$1"
    local type="$2"
    local today=$(date +"%Y-%m-%d")
    local today_ts=$(date -d "$today" +%s)
    local count=0

    while IFS=: read -r user pass exp rest; do
        local exp_ts=$(date -d "$exp" +%s 2>/dev/null)
        local sisa=$(( (exp_ts - today_ts) / 86400 ))
        if [ "$sisa" -lt 0 ]; then
            sed -i "/^$user:/d" "$db"
            if [ "$db" = "$ZIV_USER_DB" ] && command -v jq &>/dev/null; then
                jq --arg pwd "$pass" '.auth.passwords -= [$pwd]' "$ZIV_CONFIG" > /tmp/zcfg.json 2>/dev/null
                mv /tmp/zcfg.json "$ZIV_CONFIG" 2>/dev/null
            fi
            ((count++))
        fi
    done < <(cat "$db" 2>/dev/null)

    [ "$count" -gt 0 ] && [ "$db" = "$ZIV_USER_DB" ] && systemctl restart ziv-udp 2>/dev/null

    echo "🧹 Berhasil menghapus <b>$count akun expired</b> dari $type!"
}

# ─────────────────────────────────────────
# MAIN BOT LOOP
# ─────────────────────────────────────────

run_bot() {
    local offset=0
    echo "[$(date)] Bot OGH-UDP dimulai..." >> "$BOT_LOG"

    while true; do
        local updates=$(curl -s "$API/getUpdates?offset=$offset&timeout=30&limit=10")
        
        if ! echo "$updates" | jq -e '.ok' > /dev/null 2>&1; then
            sleep 5
            continue
        fi

        local count=$(echo "$updates" | jq '.result | length')
        
        for (( i=0; i<count; i++ )); do
            local update=$(echo "$updates" | jq ".result[$i]")
            local update_id=$(echo "$update" | jq -r '.update_id')
            offset=$((update_id + 1))

            # Handle callback queries (button presses)
            if echo "$update" | jq -e '.callback_query' > /dev/null 2>&1; then
                handle_callback "$update"
                continue
            fi

            # Handle regular messages
            if echo "$update" | jq -e '.message' > /dev/null 2>&1; then
                handle_message "$update"
            fi
        done

        sleep 1
    done
}

handle_message() {
    local update="$1"
    local chat_id=$(echo "$update" | jq -r '.message.chat.id')
    local text=$(echo "$update" | jq -r '.message.text // ""')
    local user_id=$(echo "$update" | jq -r '.message.from.id')

    # Auth check
    if [ "$user_id" != "$ADMIN_ID" ]; then
        send_msg "$chat_id" "⛔ Anda tidak memiliki akses!"
        return
    fi

    local state=$(get_state "$chat_id")

    # Handle state-based input
    if [ -n "$state" ]; then
        handle_state_input "$chat_id" "$user_id" "$text" "$state"
        return
    fi

    case "$text" in
        /start|/menu)
            local logo="🟦🟦🟦🟦🟦🟦🟦🟦🟦🟦
<b>  OGH-UDP MANAGER BOT</b>
🟦🟦🟦🟦🟦🟦🟦🟦🟦🟦

Selamat datang di <b>OGH-UDP Bot</b>!
Pilih menu di bawah ini:"
            send_msg "$chat_id" "$logo" "$(main_keyboard)"
            ;;
        *)
            send_msg "$chat_id" "Kirim /menu untuk membuka menu utama." "$(back_keyboard)"
            ;;
    esac
}

handle_state_input() {
    local chat_id="$1"
    local user_id="$2"
    local text="$3"
    local state="$4"

    case "$state" in
        # ── OGH: ADD USER ──
        ogh_add_user)
            set_state "${chat_id}_ogh_user" "$text"
            set_state "$chat_id" "ogh_add_pass"
            send_msg "$chat_id" "🔑 Masukkan <b>Password</b>:"
            ;;
        ogh_add_pass)
            set_state "${chat_id}_ogh_pass" "$text"
            set_state "$chat_id" "ogh_add_days"
            send_msg "$chat_id" "📅 Masukkan <b>Masa Aktif</b> (hari):"
            ;;
        ogh_add_days)
            set_state "${chat_id}_ogh_days" "$text"
            set_state "$chat_id" "ogh_add_max"
            send_msg "$chat_id" "🔢 Masukkan <b>Max Login</b> (default 2):"
            ;;
        ogh_add_max)
            local uname=$(get_state "${chat_id}_ogh_user")
            local upass=$(get_state "${chat_id}_ogh_pass")
            local udays=$(get_state "${chat_id}_ogh_days")
            local umax="$text"
            [ "$umax" = "" ] && umax="2"

            local result=$(bot_add_user "$OGH_USER_DB" "$uname" "$upass" "$udays" "$umax")
            send_msg "$chat_id" "$result" "$(back_keyboard)"

            clear_state "$chat_id"
            clear_state "${chat_id}_ogh_user"
            clear_state "${chat_id}_ogh_pass"
            clear_state "${chat_id}_ogh_days"
            ;;

        # ── ZIV: ADD USER ──
        ziv_add_user)
            set_state "${chat_id}_ziv_user" "$text"
            set_state "$chat_id" "ziv_add_pass"
            send_msg "$chat_id" "🔑 Masukkan <b>Password</b>:"
            ;;
        ziv_add_pass)
            set_state "${chat_id}_ziv_pass" "$text"
            set_state "$chat_id" "ziv_add_days"
            send_msg "$chat_id" "📅 Masukkan <b>Masa Aktif</b> (hari):"
            ;;
        ziv_add_days)
            set_state "${chat_id}_ziv_days" "$text"
            set_state "$chat_id" "ziv_add_max"
            send_msg "$chat_id" "🔢 Masukkan <b>Max Login</b> (default 2):"
            ;;
        ziv_add_max)
            local uname=$(get_state "${chat_id}_ziv_user")
            local upass=$(get_state "${chat_id}_ziv_pass")
            local udays=$(get_state "${chat_id}_ziv_days")
            local umax="$text"
            [ "$umax" = "" ] && umax="2"

            local result=$(bot_add_user "$ZIV_USER_DB" "$uname" "$upass" "$udays" "$umax")
            send_msg "$chat_id" "$result" "$(back_keyboard)"

            clear_state "$chat_id"
            clear_state "${chat_id}_ziv_user"
            clear_state "${chat_id}_ziv_pass"
            clear_state "${chat_id}_ziv_days"
            ;;

        # ── DELETE USER ──
        ogh_del_user)
            local result=$(bot_delete_user "$OGH_USER_DB" "OGH-UDP" "$text")
            send_msg "$chat_id" "$result" "$(back_keyboard)"
            clear_state "$chat_id"
            ;;
        ziv_del_user)
            local result=$(bot_delete_user "$ZIV_USER_DB" "ZIV-UDP" "$text")
            send_msg "$chat_id" "$result" "$(back_keyboard)"
            clear_state "$chat_id"
            ;;

        # ── CHECK USER ──
        ogh_cek_user)
            local result=$(bot_check_user "$OGH_USER_DB" "OGH-UDP" "$text")
            send_msg "$chat_id" "$result" "$(back_keyboard)"
            clear_state "$chat_id"
            ;;
        ziv_cek_user)
            local result=$(bot_check_user "$ZIV_USER_DB" "ZIV-UDP" "$text")
            send_msg "$chat_id" "$result" "$(back_keyboard)"
            clear_state "$chat_id"
            ;;

        # ── RENEW USER ──
        ogh_renew_user)
            set_state "${chat_id}_renew_user" "$text"
            set_state "$chat_id" "ogh_renew_days"
            send_msg "$chat_id" "📅 Tambah berapa hari?"
            ;;
        ogh_renew_days)
            local uname=$(get_state "${chat_id}_renew_user")
            local result=$(bot_renew_user "$OGH_USER_DB" "OGH-UDP" "$uname" "$text")
            send_msg "$chat_id" "$result" "$(back_keyboard)"
            clear_state "$chat_id"
            clear_state "${chat_id}_renew_user"
            ;;
        ziv_renew_user)
            set_state "${chat_id}_renew_user" "$text"
            set_state "$chat_id" "ziv_renew_days"
            send_msg "$chat_id" "📅 Tambah berapa hari?"
            ;;
        ziv_renew_days)
            local uname=$(get_state "${chat_id}_renew_user")
            local result=$(bot_renew_user "$ZIV_USER_DB" "ZIV-UDP" "$uname" "$text")
            send_msg "$chat_id" "$result" "$(back_keyboard)"
            clear_state "$chat_id"
            clear_state "${chat_id}_renew_user"
            ;;
    esac
}

handle_callback() {
    local update="$1"
    local chat_id=$(echo "$update" | jq -r '.callback_query.message.chat.id')
    local msg_id=$(echo "$update" | jq -r '.callback_query.message.message_id')
    local cb_id=$(echo "$update" | jq -r '.callback_query.id')
    local data=$(echo "$update" | jq -r '.callback_query.data')
    local user_id=$(echo "$update" | jq -r '.callback_query.from.id')

    answer_callback "$cb_id"

    if [ "$user_id" != "$ADMIN_ID" ]; then
        return
    fi

    case "$data" in
        back)
            local logo="🟦🟦🟦🟦🟦🟦🟦🟦🟦🟦
<b>  OGH-UDP MANAGER BOT</b>
🟦🟦🟦🟦🟦🟦🟦🟦🟦🟦

Pilih menu:"
            clear_state "$chat_id"
            edit_msg "$chat_id" "$msg_id" "$logo" "$(main_keyboard)"
            ;;
        info)
            local info=$(get_server_info)
            edit_msg "$chat_id" "$msg_id" "$info" "$(back_keyboard)"
            ;;
        list_ogh)
            local result=$(bot_list_users "$OGH_USER_DB" "OGH-UDP")
            edit_msg "$chat_id" "$msg_id" "$result" "$(back_keyboard)"
            ;;
        list_ziv)
            local result=$(bot_list_users "$ZIV_USER_DB" "ZIV-UDP")
            edit_msg "$chat_id" "$msg_id" "$result" "$(back_keyboard)"
            ;;
        add_ogh)
            set_state "$chat_id" "ogh_add_user"
            edit_msg "$chat_id" "$msg_id" "➕ <b>TAMBAH AKUN OGH-UDP</b>
━━━━━━━━━━━━━━━━━━━━━━
👤 Masukkan <b>Username</b>:" "$(back_keyboard)"
            ;;
        add_ziv)
            set_state "$chat_id" "ziv_add_user"
            edit_msg "$chat_id" "$msg_id" "➕ <b>TAMBAH AKUN ZIV-UDP</b>
━━━━━━━━━━━━━━━━━━━━━━
👤 Masukkan <b>Username</b>:" "$(back_keyboard)"
            ;;
        del_ogh)
            local list=$(bot_list_users "$OGH_USER_DB" "OGH-UDP")
            set_state "$chat_id" "ogh_del_user"
            edit_msg "$chat_id" "$msg_id" "🗑 <b>HAPUS AKUN OGH-UDP</b>
━━━━━━━━━━━━━━━━━━━━━━
$list
━━━━━━━━━━━━━━━━━━━━━━
Kirim username yang ingin dihapus:" "$(back_keyboard)"
            ;;
        del_ziv)
            local list=$(bot_list_users "$ZIV_USER_DB" "ZIV-UDP")
            set_state "$chat_id" "ziv_del_user"
            edit_msg "$chat_id" "$msg_id" "🗑 <b>HAPUS AKUN ZIV-UDP</b>
━━━━━━━━━━━━━━━━━━━━━━
$list
━━━━━━━━━━━━━━━━━━━━━━
Kirim username yang ingin dihapus:" "$(back_keyboard)"
            ;;
        cek_ogh)
            set_state "$chat_id" "ogh_cek_user"
            edit_msg "$chat_id" "$msg_id" "🔍 <b>CEK AKUN OGH-UDP</b>
━━━━━━━━━━━━━━━━━━━━━━
Kirim username:" "$(back_keyboard)"
            ;;
        cek_ziv)
            set_state "$chat_id" "ziv_cek_user"
            edit_msg "$chat_id" "$msg_id" "🔍 <b>CEK AKUN ZIV-UDP</b>
━━━━━━━━━━━━━━━━━━━━━━
Kirim username:" "$(back_keyboard)"
            ;;
        renew_ogh)
            local list=$(bot_list_users "$OGH_USER_DB" "OGH-UDP")
            set_state "$chat_id" "ogh_renew_user"
            edit_msg "$chat_id" "$msg_id" "⏳ <b>PERPANJANG AKUN OGH-UDP</b>
━━━━━━━━━━━━━━━━━━━━━━
$list
━━━━━━━━━━━━━━━━━━━━━━
Kirim username:" "$(back_keyboard)"
            ;;
        renew_ziv)
            local list=$(bot_list_users "$ZIV_USER_DB" "ZIV-UDP")
            set_state "$chat_id" "ziv_renew_user"
            edit_msg "$chat_id" "$msg_id" "⏳ <b>PERPANJANG AKUN ZIV-UDP</b>
━━━━━━━━━━━━━━━━━━━━━━
$list
━━━━━━━━━━━━━━━━━━━━━━
Kirim username:" "$(back_keyboard)"
            ;;
        exp_ogh)
            local result=$(bot_delete_expired "$OGH_USER_DB" "OGH-UDP")
            edit_msg "$chat_id" "$msg_id" "$result" "$(back_keyboard)"
            ;;
        exp_ziv)
            local result=$(bot_delete_expired "$ZIV_USER_DB" "ZIV-UDP")
            edit_msg "$chat_id" "$msg_id" "$result" "$(back_keyboard)"
            ;;
        svc_ogh)
            local status=$(systemctl is-active ogh-udp 2>/dev/null || echo "inactive")
            edit_msg "$chat_id" "$msg_id" "⚙️ <b>SERVICE OGH-UDP</b>
━━━━━━━━━━━━━━━━━━━━━━
Status: $( [ "$status" = "active" ] && echo "✅ RUNNING" || echo "❌ STOPPED" )" "$(service_keyboard ogh)"
            ;;
        svc_ziv)
            local status=$(systemctl is-active ziv-udp 2>/dev/null || echo "inactive")
            edit_msg "$chat_id" "$msg_id" "⚙️ <b>SERVICE ZIV-UDP</b>
━━━━━━━━━━━━━━━━━━━━━━
Status: $( [ "$status" = "active" ] && echo "✅ RUNNING" || echo "❌ STOPPED" )" "$(service_keyboard ziv)"
            ;;
        start_ogh) systemctl start ogh-udp; send_msg "$chat_id" "✅ OGH-UDP dimulai!" ;;
        stop_ogh)  systemctl stop ogh-udp;  send_msg "$chat_id" "⏹ OGH-UDP dihentikan!" ;;
        restart_ogh) systemctl restart ogh-udp; send_msg "$chat_id" "🔄 OGH-UDP direstart!" ;;
        start_ziv) systemctl start ziv-udp; send_msg "$chat_id" "✅ ZIV-UDP dimulai!" ;;
        stop_ziv)  systemctl stop ziv-udp;  send_msg "$chat_id" "⏹ ZIV-UDP dihentikan!" ;;
        restart_ziv) systemctl restart ziv-udp; send_msg "$chat_id" "🔄 ZIV-UDP direstart!" ;;
    esac
}

# ─────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────

case "${1:-}" in
    run)
        run_bot
        ;;
    setup)
        setup_bot
        ;;
    start)
        systemctl start ogh-bot
        echo -e "${GREEN}Bot dimulai!${NC}"
        ;;
    stop)
        systemctl stop ogh-bot
        echo -e "${YELLOW}Bot dihentikan!${NC}"
        ;;
    status)
        systemctl status ogh-bot
        ;;
    log)
        tail -50 "$BOT_LOG"
        ;;
    *)
        if [ ! -f "$BOT_TOKEN_FILE" ]; then
            setup_bot
        else
            clear
            echo -e "${CYAN}"
            echo "  ╔═══════════════════════════════════════╗"
            echo "  ║       OGH-UDP TELEGRAM BOT            ║"
            echo "  ╚═══════════════════════════════════════╝"
            echo -e "${NC}"
            echo -e "  ${WHITE}1${NC} Setup Bot Baru"
            echo -e "  ${WHITE}2${NC} Start Bot"
            echo -e "  ${WHITE}3${NC} Stop Bot"
            echo -e "  ${WHITE}4${NC} Status Bot"
            echo -e "  ${WHITE}5${NC} Lihat Log"
            echo ""
            read -p "  Pilihan: " opt
            case $opt in
                1) setup_bot ;;
                2) systemctl start ogh-bot; echo -e "${GREEN}Bot dimulai!${NC}" ;;
                3) systemctl stop ogh-bot; echo -e "${YELLOW}Bot dihentikan!${NC}" ;;
                4) systemctl status ogh-bot ;;
                5) tail -50 "$BOT_LOG"; read -p "Enter..." ;;
            esac
        fi
        ;;
esac
