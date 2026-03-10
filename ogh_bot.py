#!/usr/bin/env python3
# ╔══════════════════════════════════════════════════════════════╗
# ║        OGH-UDP TELEGRAM BOT — Full Manager v1.0             ║
# ║  Support: OGH-UDP + ZivPN-UDP                               ║
# ║  Level  : Admin & Reseller                                  ║
# ╚══════════════════════════════════════════════════════════════╝
# Install deps: pip3 install python-telegram-bot==20.7 requests

import os, json, time, subprocess, shlex, logging, asyncio
from datetime import datetime, timedelta
from pathlib import Path
from functools import wraps

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application, CommandHandler, CallbackQueryHandler,
    MessageHandler, filters, ContextTypes, ConversationHandler
)

# ══════════════════════════════════════════════════════════════
#  CONFIG — Edit bagian ini
# ══════════════════════════════════════════════════════════════
BOT_TOKEN    = "ISI_TOKEN_BOT_DISINI"      # Token dari @BotFather
ADMIN_IDS    = [123456789]                  # Telegram ID admin utama (bisa lebih dari 1)
BOT_NAME     = "OGH-UDP Manager"
VPS_IP       = ""                           # Kosongkan = auto detect

# Path database (harus sama dengan ogh-manager.sh)
OGH_DB       = "/etc/ogh-udp/users.db"
OGH_PORT_F   = "/etc/ogh-udp/port.conf"
OGH_QUOTA_D  = "/etc/ogh-udp/quota"
OGH_SESS_D   = "/etc/ogh-udp/sessions"
OGH_LOG      = "/var/log/ogh-udp.log"
OGH_SVC      = "ogh-udp"

ZIV_DB       = "/etc/zivpn-udp/users.db"
ZIV_CFG      = "/etc/zivpn-udp/config.json"
ZIV_QUOTA_D  = "/etc/zivpn-udp/quota"
ZIV_SESS_D   = "/etc/zivpn-udp/sessions"
ZIV_LOG      = "/var/log/zivpn-udp.log"
ZIV_SVC      = "zivpn-udp"

# Bot database (simpan reseller, config bot, dll)
BOT_DB_DIR   = "/etc/ogh-bot"
RESELLER_DB  = f"{BOT_DB_DIR}/resellers.json"
BOT_CFG_FILE = f"{BOT_DB_DIR}/config.json"

# ══════════════════════════════════════════════════════════════
#  LOGGING
# ══════════════════════════════════════════════════════════════
logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    level=logging.INFO,
    handlers=[
        logging.FileHandler("/var/log/ogh-bot.log"),
        logging.StreamHandler()
    ]
)
log = logging.getLogger(__name__)

# ══════════════════════════════════════════════════════════════
#  INIT DIRECTORIES
# ══════════════════════════════════════════════════════════════
def init_dirs():
    for d in [BOT_DB_DIR, OGH_QUOTA_D, OGH_SESS_D, ZIV_QUOTA_D, ZIV_SESS_D]:
        Path(d).mkdir(parents=True, exist_ok=True)
    for f in [OGH_DB, ZIV_DB]:
        Path(f).touch(exist_ok=True)
    if not Path(RESELLER_DB).exists():
        save_json(RESELLER_DB, {})
    if not Path(BOT_CFG_FILE).exists():
        save_json(BOT_CFG_FILE, {
            "ogh_default_days": 30,
            "ziv_default_days": 30,
            "ogh_default_quota": 0,
            "ziv_default_quota": 0,
            "ogh_default_maxlogin": 2,
            "ziv_default_maxlogin": 2,
            "maintenance": False
        })

# ══════════════════════════════════════════════════════════════
#  JSON HELPERS
# ══════════════════════════════════════════════════════════════
def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except:
        return {}

def save_json(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=2)

def bot_cfg():
    return load_json(BOT_CFG_FILE)

# ══════════════════════════════════════════════════════════════
#  RESELLER SYSTEM
# ══════════════════════════════════════════════════════════════
def get_resellers():
    return load_json(RESELLER_DB)

def is_reseller(uid):
    return str(uid) in get_resellers()

def is_admin(uid):
    return uid in ADMIN_IDS

def get_reseller(uid):
    return get_resellers().get(str(uid), {})

def reseller_can_create(uid, service):
    r = get_reseller(uid)
    if not r:
        return False, "Anda bukan reseller."
    quota_key = f"{service}_quota"
    used_key  = f"{service}_used"
    quota = r.get(quota_key, 0)
    used  = r.get(used_key, 0)
    if quota == 0:
        return True, ""
    if used >= quota:
        return False, f"Kuota reseller habis ({used}/{quota} akun)."
    return True, ""

def reseller_add_usage(uid, service):
    rs = get_resellers()
    key = str(uid)
    if key in rs:
        used_key = f"{service}_used"
        rs[key][used_key] = rs[key].get(used_key, 0) + 1
        save_json(RESELLER_DB, rs)

def reseller_remove_usage(uid, service):
    rs = get_resellers()
    key = str(uid)
    if key in rs:
        used_key = f"{service}_used"
        cur = rs[key].get(used_key, 0)
        rs[key][used_key] = max(0, cur - 1)
        save_json(RESELLER_DB, rs)

# ══════════════════════════════════════════════════════════════
#  SYSTEM HELPERS
# ══════════════════════════════════════════════════════════════
def run_cmd(cmd):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=15)
        return r.stdout.strip(), r.returncode
    except Exception as e:
        return str(e), 1

def get_public_ip():
    global VPS_IP
    if VPS_IP:
        return VPS_IP
    out, _ = run_cmd("curl -s --max-time 5 ifconfig.me")
    VPS_IP = out or "N/A"
    return VPS_IP

def get_ogh_port():
    try:
        return open(OGH_PORT_F).read().strip()
    except:
        return "7300"

def get_ziv_port():
    try:
        cfg = load_json(ZIV_CFG)
        return cfg.get("listen", ":7200").lstrip(":")
    except:
        return "7200"

def svc_status(name):
    _, rc = run_cmd(f"systemctl is-active {name}")
    return "🟢 RUNNING" if rc == 0 else "🔴 STOPPED"

def bytes_human(b):
    b = int(b or 0)
    if b >= 1_073_741_824: return f"{b/1_073_741_824:.2f} GB"
    if b >= 1_048_576:     return f"{b/1_048_576:.2f} MB"
    if b >= 1024:          return f"{b/1024:.2f} KB"
    return f"{b} B"

def human_bytes(s):
    s = s.upper().strip()
    num = ''.join(c for c in s if c.isdigit() or c == '.')
    unit = ''.join(c for c in s if c.isalpha())
    num = float(num or 0)
    if   unit in ('GB','G'): return int(num * 1_073_741_824)
    elif unit in ('MB','M'): return int(num * 1_048_576)
    elif unit in ('KB','K'): return int(num * 1024)
    return int(num)

def get_used(quota_dir, user):
    f = Path(quota_dir) / f"{user}.quota"
    try: return int(f.read_text().strip())
    except: return 0

def get_sessions(sess_dir, user):
    f = Path(sess_dir) / f"{user}.sess"
    try: return int(f.read_text().strip())
    except: return 0

def get_vps_info():
    uptime, _ = run_cmd("uptime -p")
    ram, _     = run_cmd("free -m | awk '/Mem:/{printf \"%dMB / %dMB\",$3,$2}'")
    disk, _    = run_cmd("df -h / | awk 'NR==2{printf \"%s/%s (%s)\",$3,$2,$5}'")
    cpu, _     = run_cmd("top -bn1 | grep 'Cpu(s)' | awk '{printf \"%.1f%%\",$2+$4}'")
    os_n, _    = run_cmd("grep PRETTY_NAME /etc/os-release | cut -d'\"' -f2")
    return {
        "ip":     get_public_ip(),
        "uptime": uptime or "N/A",
        "ram":    ram or "N/A",
        "disk":   disk or "N/A",
        "cpu":    cpu or "N/A",
        "os":     os_n or "N/A",
    }

# ══════════════════════════════════════════════════════════════
#  DATABASE OPERATIONS
# ══════════════════════════════════════════════════════════════
def read_db(db_path):
    users = []
    try:
        with open(db_path) as f:
            for line in f:
                line = line.strip()
                if not line: continue
                parts = line.split('|')
                while len(parts) < 8:
                    parts.append('')
                users.append({
                    'user':     parts[0],
                    'pass':     parts[1],
                    'exp':      parts[2],
                    'created':  parts[3],
                    'maxlogin': parts[4] or '0',
                    'quota':    parts[5] or '0',
                    'used':     parts[6] or '0',
                    'status':   parts[7] or 'active',
                })
    except:
        pass
    return users

def write_db(db_path, users):
    with open(db_path, 'w') as f:
        for u in users:
            line = f"{u['user']}|{u['pass']}|{u['exp']}|{u['created']}|{u['maxlogin']}|{u['quota']}|{u['used']}|{u['status']}\n"
            f.write(line)

def find_user(db_path, username):
    for u in read_db(db_path):
        if u['user'] == username:
            return u
    return None

def user_exists(db_path, username):
    return find_user(db_path, username) is not None

def create_user_db(db_path, quota_dir, sess_dir, user, pwd, days, maxlogin, quota_bytes):
    exp = (datetime.now() + timedelta(days=int(days))).strftime('%Y-%m-%d')
    now = datetime.now().strftime('%Y-%m-%d')
    row = {
        'user': user, 'pass': pwd, 'exp': exp, 'created': now,
        'maxlogin': str(maxlogin), 'quota': str(quota_bytes),
        'used': '0', 'status': 'active'
    }
    users = read_db(db_path)
    users.append(row)
    write_db(db_path, users)
    # init quota & session files
    (Path(quota_dir) / f"{user}.quota").write_text("0")
    (Path(sess_dir)  / f"{user}.sess").write_text("0")
    return row

def delete_user_db(db_path, quota_dir, sess_dir, username):
    users = read_db(db_path)
    before = len(users)
    users = [u for u in users if u['user'] != username]
    if len(users) == before:
        return False
    write_db(db_path, users)
    for ext in ['quota', 'sess']:
        f = Path(quota_dir if ext == 'quota' else sess_dir) / f"{username}.{ext}"
        f.unlink(missing_ok=True)
    return True

def update_user_field(db_path, username, **kwargs):
    users = read_db(db_path)
    for u in users:
        if u['user'] == username:
            u.update(kwargs)
    write_db(db_path, users)

def renew_user_db(db_path, username, days):
    u = find_user(db_path, username)
    if not u: return None
    today = datetime.now().strftime('%Y-%m-%d')
    try:
        base = datetime.strptime(u['exp'], '%Y-%m-%d')
        if base < datetime.now(): base = datetime.now()
    except:
        base = datetime.now()
    new_exp = (base + timedelta(days=int(days))).strftime('%Y-%m-%d')
    update_user_field(db_path, username, exp=new_exp)
    return new_exp

def get_expired_users(db_path):
    today = datetime.now().strftime('%Y-%m-%d')
    return [u for u in read_db(db_path) if u['exp'] < today]

def get_soon_expired(db_path, days=7):
    today = datetime.now()
    result = []
    for u in read_db(db_path):
        try:
            exp_d = datetime.strptime(u['exp'], '%Y-%m-%d')
            diff  = (exp_d - today).days
            if 0 <= diff <= days:
                result.append((u, diff))
        except:
            pass
    return result

# ══════════════════════════════════════════════════════════════
#  FORMATTERS
# ══════════════════════════════════════════════════════════════
def fmt_account(u, ip, port, quota_dir, sess_dir, service_name):
    today = datetime.now().strftime('%Y-%m-%d')
    exp_d = datetime.strptime(u['exp'], '%Y-%m-%d') if u['exp'] else datetime.now()
    sisa  = (exp_d - datetime.now()).days
    sisa_l = f"⏳ {sisa} hari" if sisa >= 0 else "❌ EXPIRED"
    used   = get_used(quota_dir, u['user'])
    quota  = int(u.get('quota', 0))
    ml     = u.get('maxlogin', '0')
    sess   = get_sessions(sess_dir, u['user'])
    status = "🔒 LOCKED" if u['status'] == 'locked' else ("✅ AKTIF" if u['exp'] >= today else "❌ EXPIRED")
    quota_l = "Unlimited" if quota == 0 else bytes_human(quota)
    ml_l    = "Unlimited" if ml == '0' else ml
    pct     = ""
    if quota > 0:
        pct = f" ({used*100//quota}%)"
    return (
        f"╔══════════════════════╗\n"
        f"║  📋 {service_name} Account\n"
        f"╠══════════════════════╣\n"
        f"║ 👤 Username  : `{u['user']}`\n"
        f"║ 🔑 Password  : `{u['pass']}`\n"
        f"║ 🌐 Host      : `{ip}`\n"
        f"║ 🔌 Port      : `{port}`\n"
        f"║ 📅 Expired   : `{u['exp']}`\n"
        f"║ ⏳ Sisa      : {sisa_l}\n"
        f"║ 📊 Status    : {status}\n"
        f"╠══════════════════════╣\n"
        f"║ 🔗 MaxLogin  : {ml_l}\n"
        f"║ 💻 Sesi Aktif: {sess}/{ml_l}\n"
        f"╠══════════════════════╣\n"
        f"║ 📦 Kuota     : {quota_l}\n"
        f"║ 📈 Terpakai  : {bytes_human(used)}{pct}\n"
        f"╚══════════════════════╝"
    )

def fmt_account_short(u, quota_dir, sess_dir):
    today = datetime.now().strftime('%Y-%m-%d')
    exp_d = datetime.strptime(u['exp'], '%Y-%m-%d') if u['exp'] else datetime.now()
    sisa  = (exp_d - datetime.now()).days
    used   = bytes_human(get_used(quota_dir, u['user']))
    quota  = int(u.get('quota', 0))
    quota_l = "∞" if quota == 0 else bytes_human(quota)
    st = "✅" if u['status'] == 'active' and u['exp'] >= today else ("🔒" if u['status'] == 'locked' else "❌")
    return f"{st} `{u['user']:15}` | Exp: `{u['exp']}` | {sisa}h | {used}/{quota_l}"

# ══════════════════════════════════════════════════════════════
#  ACCESS CONTROL DECORATOR
# ══════════════════════════════════════════════════════════════
def require_access(allow_reseller=True):
    def decorator(func):
        @wraps(func)
        async def wrapper(update: Update, ctx: ContextTypes.DEFAULT_TYPE, *args, **kwargs):
            uid = update.effective_user.id
            cfg = bot_cfg()
            if cfg.get("maintenance") and not is_admin(uid):
                await update.message.reply_text("🔧 Bot sedang dalam maintenance. Coba lagi nanti.")
                return
            if not is_admin(uid) and not (allow_reseller and is_reseller(uid)):
                await update.message.reply_text(
                    "⛔ *Akses Ditolak*\n\nAnda tidak memiliki akses ke bot ini.\n"
                    "Hubungi admin untuk mendapatkan akses.",
                    parse_mode="Markdown"
                )
                return
            return await func(update, ctx, *args, **kwargs)
        return wrapper
    return decorator

def admin_only(func):
    @wraps(func)
    async def wrapper(update: Update, ctx: ContextTypes.DEFAULT_TYPE, *args, **kwargs):
        uid = update.effective_user.id
        if not is_admin(uid):
            await update.message.reply_text("⛔ Perintah ini hanya untuk Admin.")
            return
        return await func(update, ctx, *args, **kwargs)
    return wrapper

# ══════════════════════════════════════════════════════════════
#  KEYBOARDS
# ══════════════════════════════════════════════════════════════
def main_keyboard(uid):
    admin = is_admin(uid)
    rows = [
        [
            InlineKeyboardButton("🟠 OGH-UDP", callback_data="menu_ogh"),
            InlineKeyboardButton("🟣 ZivPN-UDP", callback_data="menu_ziv"),
        ],
        [
            InlineKeyboardButton("📊 Statistik", callback_data="menu_stats"),
            InlineKeyboardButton("🔍 Cek Akun", callback_data="menu_check"),
        ],
        [InlineKeyboardButton("📡 Info VPS", callback_data="menu_vps")],
    ]
    if admin:
        rows += [
            [
                InlineKeyboardButton("👥 Reseller", callback_data="menu_reseller"),
                InlineKeyboardButton("⚙️ Pengaturan", callback_data="menu_settings"),
            ],
            [
                InlineKeyboardButton("🔧 Service", callback_data="menu_service"),
                InlineKeyboardButton("💾 Backup", callback_data="menu_backup"),
            ],
        ]
    return InlineKeyboardMarkup(rows)

def service_keyboard():
    return InlineKeyboardMarkup([
        [
            InlineKeyboardButton("▶️ Start OGH",   callback_data="svc_start_ogh"),
            InlineKeyboardButton("⏹ Stop OGH",    callback_data="svc_stop_ogh"),
            InlineKeyboardButton("🔄 Restart OGH", callback_data="svc_restart_ogh"),
        ],
        [
            InlineKeyboardButton("▶️ Start ZivPN",   callback_data="svc_start_ziv"),
            InlineKeyboardButton("⏹ Stop ZivPN",    callback_data="svc_stop_ziv"),
            InlineKeyboardButton("🔄 Restart ZivPN", callback_data="svc_restart_ziv"),
        ],
        [
            InlineKeyboardButton("▶️ Start Semua",   callback_data="svc_start_all"),
            InlineKeyboardButton("⏹ Stop Semua",    callback_data="svc_stop_all"),
            InlineKeyboardButton("🔄 Restart Semua", callback_data="svc_restart_all"),
        ],
        [InlineKeyboardButton("🔙 Kembali", callback_data="back_main")],
    ])

def ogh_keyboard():
    return InlineKeyboardMarkup([
        [
            InlineKeyboardButton("➕ Buat Akun",    callback_data="ogh_create"),
            InlineKeyboardButton("➖ Hapus Akun",   callback_data="ogh_delete"),
        ],
        [
            InlineKeyboardButton("📋 List Akun",    callback_data="ogh_list"),
            InlineKeyboardButton("🔎 Cek Akun",     callback_data="ogh_check"),
        ],
        [
            InlineKeyboardButton("🔄 Perpanjang",   callback_data="ogh_renew"),
            InlineKeyboardButton("🔒 Kunci/Buka",   callback_data="ogh_toggle"),
        ],
        [
            InlineKeyboardButton("⚙️ Set MaxLogin",  callback_data="ogh_maxlogin"),
            InlineKeyboardButton("📦 Set Kuota",     callback_data="ogh_setquota"),
        ],
        [
            InlineKeyboardButton("♻️ Reset Kuota",   callback_data="ogh_resetquota"),
            InlineKeyboardButton("🔗 Reset Sesi",    callback_data="ogh_resetsess"),
        ],
        [
            InlineKeyboardButton("🗑 Hapus Expired", callback_data="ogh_del_expired"),
            InlineKeyboardButton("🗑 Hapus Semua",   callback_data="ogh_del_all"),
        ],
        [InlineKeyboardButton("🔙 Kembali", callback_data="back_main")],
    ])

def ziv_keyboard():
    return InlineKeyboardMarkup([
        [
            InlineKeyboardButton("➕ Buat Akun",    callback_data="ziv_create"),
            InlineKeyboardButton("➖ Hapus Akun",   callback_data="ziv_delete"),
        ],
        [
            InlineKeyboardButton("📋 List Akun",    callback_data="ziv_list"),
            InlineKeyboardButton("🔎 Cek Akun",     callback_data="ziv_check"),
        ],
        [
            InlineKeyboardButton("🔄 Perpanjang",   callback_data="ziv_renew"),
            InlineKeyboardButton("🔒 Kunci/Buka",   callback_data="ziv_toggle"),
        ],
        [
            InlineKeyboardButton("⚙️ Set MaxLogin",  callback_data="ziv_maxlogin"),
            InlineKeyboardButton("📦 Set Kuota",     callback_data="ziv_setquota"),
        ],
        [
            InlineKeyboardButton("♻️ Reset Kuota",   callback_data="ziv_resetquota"),
            InlineKeyboardButton("🔗 Reset Sesi",    callback_data="ziv_resetsess"),
        ],
        [
            InlineKeyboardButton("🗑 Hapus Expired", callback_data="ziv_del_expired"),
            InlineKeyboardButton("🗑 Hapus Semua",   callback_data="ziv_del_all"),
        ],
        [InlineKeyboardButton("🔙 Kembali", callback_data="back_main")],
    ])

def reseller_keyboard():
    return InlineKeyboardMarkup([
        [
            InlineKeyboardButton("➕ Tambah Reseller", callback_data="rs_add"),
            InlineKeyboardButton("➖ Hapus Reseller",  callback_data="rs_delete"),
        ],
        [
            InlineKeyboardButton("📋 List Reseller",   callback_data="rs_list"),
            InlineKeyboardButton("⚙️ Set Kuota",        callback_data="rs_setquota"),
        ],
        [InlineKeyboardButton("🔙 Kembali", callback_data="back_main")],
    ])

def back_keyboard(cb):
    return InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data=cb)]])

def cancel_keyboard():
    return InlineKeyboardMarkup([[InlineKeyboardButton("❌ Batal", callback_data="cancel")]])

# Conversation states
(
    STATE_OGH_CREATE_USER, STATE_OGH_CREATE_PASS, STATE_OGH_CREATE_DAYS,
    STATE_OGH_CREATE_ML,   STATE_OGH_CREATE_QUOTA,
    STATE_OGH_DELETE,      STATE_OGH_CHECK,        STATE_OGH_RENEW_USER,
    STATE_OGH_RENEW_DAYS,  STATE_OGH_TOGGLE,       STATE_OGH_MAXLOGIN_USER,
    STATE_OGH_MAXLOGIN_VAL,STATE_OGH_QUOTA_USER,   STATE_OGH_QUOTA_VAL,
    STATE_OGH_RQUOTA,      STATE_OGH_RSESS,

    STATE_ZIV_CREATE_USER, STATE_ZIV_CREATE_PASS, STATE_ZIV_CREATE_DAYS,
    STATE_ZIV_CREATE_ML,   STATE_ZIV_CREATE_QUOTA,
    STATE_ZIV_DELETE,      STATE_ZIV_CHECK,        STATE_ZIV_RENEW_USER,
    STATE_ZIV_RENEW_DAYS,  STATE_ZIV_TOGGLE,       STATE_ZIV_MAXLOGIN_USER,
    STATE_ZIV_MAXLOGIN_VAL,STATE_ZIV_QUOTA_USER,   STATE_ZIV_QUOTA_VAL,
    STATE_ZIV_RQUOTA,      STATE_ZIV_RSESS,

    STATE_RS_ADD_ID,       STATE_RS_ADD_NAME,      STATE_RS_ADD_QUOTA_OGH,
    STATE_RS_ADD_QUOTA_ZIV,STATE_RS_DEL,           STATE_RS_SETQUOTA_ID,
    STATE_RS_SETQUOTA_VAL,
) = range(43)

# ══════════════════════════════════════════════════════════════
#  /start  /menu
# ══════════════════════════════════════════════════════════════
async def start(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    uid  = update.effective_user.id
    name = update.effective_user.first_name
    cfg  = bot_cfg()

    if cfg.get("maintenance") and not is_admin(uid):
        await update.message.reply_text("🔧 Bot sedang dalam maintenance.")
        return

    if not is_admin(uid) and not is_reseller(uid):
        await update.message.reply_text(
            f"👋 Halo *{name}*!\n\n"
            "⛔ Anda belum memiliki akses.\n"
            "Hubungi admin untuk mendapatkan akses bot ini.",
            parse_mode="Markdown"
        )
        return

    role = "👑 Admin" if is_admin(uid) else "🏪 Reseller"
    ogh_cnt = len(read_db(OGH_DB))
    ziv_cnt = len(read_db(ZIV_DB))

    txt = (
        f"╔══════════════════════╗\n"
        f"║  🌐 {BOT_NAME}\n"
        f"╠══════════════════════╣\n"
        f"║ 👤 {name} ({role})\n"
        f"║ 🟠 OGH-UDP  : {svc_status(OGH_SVC)} | {ogh_cnt} akun\n"
        f"║ 🟣 ZivPN    : {svc_status(ZIV_SVC)} | {ziv_cnt} akun\n"
        f"╚══════════════════════╝\n\n"
        f"Pilih menu di bawah:"
    )
    await update.message.reply_text(txt, parse_mode="Markdown", reply_markup=main_keyboard(uid))

# ══════════════════════════════════════════════════════════════
#  CALLBACK QUERY HANDLER
# ══════════════════════════════════════════════════════════════
async def handle_callback(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    q   = update.callback_query
    uid = q.from_user.id
    data = q.data
    await q.answer()

    if not is_admin(uid) and not is_reseller(uid):
        await q.edit_message_text("⛔ Akses ditolak.")
        return

    # ── Main menus ──
    if data == "back_main":
        ogh_cnt = len(read_db(OGH_DB))
        ziv_cnt = len(read_db(ZIV_DB))
        txt = (
            f"🌐 *{BOT_NAME}*\n\n"
            f"🟠 OGH-UDP  : {svc_status(OGH_SVC)} | {ogh_cnt} akun\n"
            f"🟣 ZivPN    : {svc_status(ZIV_SVC)} | {ziv_cnt} akun\n\n"
            "Pilih menu:"
        )
        await q.edit_message_text(txt, parse_mode="Markdown", reply_markup=main_keyboard(uid))

    elif data == "menu_ogh":
        await q.edit_message_text("🟠 *OGH-UDP Manager*\nPilih aksi:", parse_mode="Markdown", reply_markup=ogh_keyboard())

    elif data == "menu_ziv":
        await q.edit_message_text("🟣 *ZivPN-UDP Manager*\nPilih aksi:", parse_mode="Markdown", reply_markup=ziv_keyboard())

    elif data == "menu_service" and is_admin(uid):
        await q.edit_message_text(
            f"⚙️ *Service Manager*\n\n"
            f"🟠 OGH-UDP : {svc_status(OGH_SVC)}\n"
            f"🟣 ZivPN   : {svc_status(ZIV_SVC)}",
            parse_mode="Markdown", reply_markup=service_keyboard()
        )

    elif data == "menu_reseller" and is_admin(uid):
        rs = get_resellers()
        txt = f"👥 *Manajemen Reseller*\nTotal: {len(rs)} reseller\n\nPilih aksi:"
        await q.edit_message_text(txt, parse_mode="Markdown", reply_markup=reseller_keyboard())

    elif data == "menu_vps":
        vps = get_vps_info()
        txt = (
            f"📡 *Info VPS*\n\n"
            f"🌐 IP      : `{vps['ip']}`\n"
            f"💻 OS      : {vps['os']}\n"
            f"⏱ Uptime  : {vps['uptime']}\n"
            f"⚡ CPU     : {vps['cpu']}\n"
            f"💾 RAM     : {vps['ram']}\n"
            f"💿 Disk    : {vps['disk']}\n\n"
            f"🟠 OGH Port : `{get_ogh_port()}`  {svc_status(OGH_SVC)}\n"
            f"🟣 ZivPN Port: `{get_ziv_port()}`  {svc_status(ZIV_SVC)}"
        )
        await q.edit_message_text(txt, parse_mode="Markdown", reply_markup=back_keyboard("back_main"))

    elif data == "menu_stats":
        ogh_users = read_db(OGH_DB)
        ziv_users = read_db(ZIV_DB)
        today = datetime.now().strftime('%Y-%m-%d')

        def stats(users, qdir):
            aktif   = sum(1 for u in users if u['exp'] >= today and u['status'] == 'active')
            expired = sum(1 for u in users if u['exp'] < today)
            locked  = sum(1 for u in users if u['status'] == 'locked')
            total_used = sum(get_used(qdir, u['user']) for u in users)
            return aktif, expired, locked, total_used

        oa, oe, ol, ou = stats(ogh_users, OGH_QUOTA_D)
        za, ze, zl, zu = stats(ziv_users, ZIV_QUOTA_D)
        txt = (
            f"📊 *Statistik Akun*\n\n"
            f"🟠 *OGH-UDP* ({len(ogh_users)} total)\n"
            f"  ✅ Aktif   : {oa}\n  ❌ Expired : {oe}\n  🔒 Terkunci: {ol}\n"
            f"  📈 Traffic : {bytes_human(ou)}\n\n"
            f"🟣 *ZivPN-UDP* ({len(ziv_users)} total)\n"
            f"  ✅ Aktif   : {za}\n  ❌ Expired : {ze}\n  🔒 Terkunci: {zl}\n"
            f"  📈 Traffic : {bytes_human(zu)}"
        )
        await q.edit_message_text(txt, parse_mode="Markdown", reply_markup=back_keyboard("back_main"))

    elif data == "menu_check":
        ctx.user_data['check_mode'] = True
        await q.edit_message_text(
            "🔎 *Cek Akun*\n\nKirim username akun (OGH atau ZivPN):",
            parse_mode="Markdown", reply_markup=cancel_keyboard()
        )
        return STATE_OGH_CHECK

    elif data == "menu_backup" and is_admin(uid):
        ts = datetime.now().strftime('%Y%m%d_%H%M%S')
        bk = Path("/root/ogh-backup")
        bk.mkdir(exist_ok=True)
        import shutil
        msgs = []
        for src, name in [(OGH_DB, f"ogh_{ts}.db"), (ZIV_DB, f"ziv_{ts}.db"), (ZIV_CFG, f"ziv_cfg_{ts}.json")]:
            try:
                shutil.copy(src, bk / name)
                msgs.append(f"✅ {name}")
            except Exception as e:
                msgs.append(f"❌ {name}: {e}")
        await q.edit_message_text(
            f"💾 *Backup selesai*\n\n" + "\n".join(msgs) + f"\n\nLokasi: `/root/ogh-backup/`",
            parse_mode="Markdown", reply_markup=back_keyboard("back_main")
        )

    elif data == "menu_settings" and is_admin(uid):
        cfg = bot_cfg()
        maint = "🔧 ON" if cfg.get("maintenance") else "✅ OFF"
        txt = (
            f"⚙️ *Pengaturan Bot*\n\n"
            f"Maintenance: {maint}\n"
            f"OGH default hari  : {cfg.get('ogh_default_days',30)}\n"
            f"ZivPN default hari: {cfg.get('ziv_default_days',30)}\n"
            f"OGH default MaxLogin  : {cfg.get('ogh_default_maxlogin',2)}\n"
            f"ZivPN default MaxLogin: {cfg.get('ziv_default_maxlogin',2)}\n\n"
            "Gunakan /setcfg untuk ubah pengaturan."
        )
        kb = InlineKeyboardMarkup([
            [InlineKeyboardButton(
                "🔧 Maintenance ON" if not cfg.get("maintenance") else "✅ Maintenance OFF",
                callback_data="toggle_maint"
            )],
            [InlineKeyboardButton("🔙 Kembali", callback_data="back_main")]
        ])
        await q.edit_message_text(txt, parse_mode="Markdown", reply_markup=kb)

    elif data == "toggle_maint" and is_admin(uid):
        cfg = bot_cfg()
        cfg["maintenance"] = not cfg.get("maintenance", False)
        save_json(BOT_CFG_FILE, cfg)
        st = "🔧 AKTIF" if cfg["maintenance"] else "✅ NONAKTIF"
        await q.edit_message_text(f"Maintenance mode: {st}", reply_markup=back_keyboard("back_main"))

    # ── Service controls ──
    elif data.startswith("svc_") and is_admin(uid):
        parts = data.split("_")
        action, target = parts[1], parts[2]
        cmds = {
            "start":   lambda t: run_cmd(f"systemctl start {t}"),
            "stop":    lambda t: run_cmd(f"systemctl stop {t}"),
            "restart": lambda t: run_cmd(f"systemctl restart {t}"),
        }
        svc_map = {"ogh": OGH_SVC, "ziv": ZIV_SVC}
        if target == "all":
            for svc in [OGH_SVC, ZIV_SVC]:
                cmds[action](svc)
            await q.edit_message_text(f"✅ {action.title()} semua service.", reply_markup=back_keyboard("menu_service"))
        elif target in svc_map:
            _, rc = cmds[action](svc_map[target])
            st = "✅" if rc == 0 else "❌"
            await q.edit_message_text(
                f"{st} {action.title()} {target.upper()}: {svc_status(svc_map[target])}",
                reply_markup=back_keyboard("menu_service")
            )

    # ── OGH List ──
    elif data == "ogh_list":
        users = read_db(OGH_DB)
        if not users:
            await q.edit_message_text("📋 Belum ada akun OGH-UDP.", reply_markup=back_keyboard("menu_ogh"))
            return
        lines = [f"📋 *OGH-UDP* ({len(users)} akun)\n"]
        for u in users:
            lines.append(fmt_account_short(u, OGH_QUOTA_D, OGH_SESS_D))
        await q.edit_message_text("\n".join(lines), parse_mode="Markdown", reply_markup=back_keyboard("menu_ogh"))

    elif data == "ziv_list":
        users = read_db(ZIV_DB)
        if not users:
            await q.edit_message_text("📋 Belum ada akun ZivPN.", reply_markup=back_keyboard("menu_ziv"))
            return
        lines = [f"📋 *ZivPN-UDP* ({len(users)} akun)\n"]
        for u in users:
            lines.append(fmt_account_short(u, ZIV_QUOTA_D, ZIV_SESS_D))
        await q.edit_message_text("\n".join(lines), parse_mode="Markdown", reply_markup=back_keyboard("menu_ziv"))

    # ── OGH Delete Expired / All ──
    elif data == "ogh_del_expired":
        if not is_admin(uid):
            await q.edit_message_text("⛔ Hanya admin."); return
        expired = get_expired_users(OGH_DB)
        for u in expired:
            delete_user_db(OGH_DB, OGH_QUOTA_D, OGH_SESS_D, u['user'])
        await q.edit_message_text(f"🗑 {len(expired)} akun expired OGH dihapus.", reply_markup=back_keyboard("menu_ogh"))

    elif data == "ziv_del_expired":
        if not is_admin(uid):
            await q.edit_message_text("⛔ Hanya admin."); return
        expired = get_expired_users(ZIV_DB)
        for u in expired:
            delete_user_db(ZIV_DB, ZIV_QUOTA_D, ZIV_SESS_D, u['user'])
        await q.edit_message_text(f"🗑 {len(expired)} akun expired ZivPN dihapus.", reply_markup=back_keyboard("menu_ziv"))

    elif data == "ogh_del_all":
        if not is_admin(uid):
            await q.edit_message_text("⛔ Hanya admin."); return
        kb = InlineKeyboardMarkup([[
            InlineKeyboardButton("✅ Ya, Hapus Semua", callback_data="ogh_del_all_confirm"),
            InlineKeyboardButton("❌ Batal", callback_data="menu_ogh"),
        ]])
        await q.edit_message_text("⚠️ Yakin hapus SEMUA akun OGH-UDP?", reply_markup=kb)

    elif data == "ogh_del_all_confirm" and is_admin(uid):
        with open(OGH_DB, 'w'): pass
        await q.edit_message_text("✅ Semua akun OGH-UDP dihapus.", reply_markup=back_keyboard("menu_ogh"))

    elif data == "ziv_del_all":
        if not is_admin(uid):
            await q.edit_message_text("⛔ Hanya admin."); return
        kb = InlineKeyboardMarkup([[
            InlineKeyboardButton("✅ Ya, Hapus Semua", callback_data="ziv_del_all_confirm"),
            InlineKeyboardButton("❌ Batal", callback_data="menu_ziv"),
        ]])
        await q.edit_message_text("⚠️ Yakin hapus SEMUA akun ZivPN?", reply_markup=kb)

    elif data == "ziv_del_all_confirm" and is_admin(uid):
        with open(ZIV_DB, 'w'): pass
        await q.edit_message_text("✅ Semua akun ZivPN dihapus.", reply_markup=back_keyboard("menu_ziv"))

    # ── Reseller list ──
    elif data == "rs_list" and is_admin(uid):
        rs = get_resellers()
        if not rs:
            await q.edit_message_text("👥 Belum ada reseller.", reply_markup=back_keyboard("menu_reseller"))
            return
        lines = ["👥 *List Reseller*\n"]
        for rid, r in rs.items():
            lines.append(
                f"• ID: `{rid}` | {r.get('name','?')}\n"
                f"  OGH: {r.get('ogh_used',0)}/{r.get('ogh_quota',0) or '∞'}  "
                f"ZivPN: {r.get('ziv_used',0)}/{r.get('ziv_quota',0) or '∞'}"
            )
        await q.edit_message_text("\n".join(lines), parse_mode="Markdown", reply_markup=back_keyboard("menu_reseller"))

    elif data == "cancel":
        ctx.user_data.clear()
        await q.edit_message_text("❌ Dibatalkan.", reply_markup=back_keyboard("back_main"))
        return ConversationHandler.END

    # ── Trigger conversation states via callback ──
    triggers = {
        "ogh_create":     (STATE_OGH_CREATE_USER, "menu_ogh",   "🟠 *Buat Akun OGH-UDP*\n\nKirim username:"),
        "ogh_delete":     (STATE_OGH_DELETE,       "menu_ogh",   "🟠 *Hapus Akun OGH-UDP*\n\nKirim username yang ingin dihapus:"),
        "ogh_check":      (STATE_OGH_CHECK,        "menu_ogh",   "🟠 *Cek Akun OGH-UDP*\n\nKirim username:"),
        "ogh_renew_user": (STATE_OGH_RENEW_USER,   "menu_ogh",   "🟠 *Perpanjang Akun OGH*\n\nKirim username:"),
        "ogh_renew":      (STATE_OGH_RENEW_USER,   "menu_ogh",   "🟠 *Perpanjang Akun OGH*\n\nKirim username:"),
        "ogh_toggle":     (STATE_OGH_TOGGLE,       "menu_ogh",   "🟠 *Kunci/Buka Akun OGH*\n\nKirim username:"),
        "ogh_maxlogin":   (STATE_OGH_MAXLOGIN_USER,"menu_ogh",   "🟠 *Set MaxLogin OGH*\n\nKirim username:"),
        "ogh_setquota":   (STATE_OGH_QUOTA_USER,   "menu_ogh",   "🟠 *Set Kuota OGH*\n\nKirim username:"),
        "ogh_resetquota": (STATE_OGH_RQUOTA,       "menu_ogh",   "🟠 *Reset Kuota OGH*\n\nKirim username (atau `all`):"),
        "ogh_resetsess":  (STATE_OGH_RSESS,        "menu_ogh",   "🟠 *Reset Sesi OGH*\n\nKirim username (atau `all`):"),

        "ziv_create":     (STATE_ZIV_CREATE_USER,  "menu_ziv",   "🟣 *Buat Akun ZivPN*\n\nKirim username:"),
        "ziv_delete":     (STATE_ZIV_DELETE,       "menu_ziv",   "🟣 *Hapus Akun ZivPN*\n\nKirim username yang ingin dihapus:"),
        "ziv_check":      (STATE_ZIV_CHECK,        "menu_ziv",   "🟣 *Cek Akun ZivPN*\n\nKirim username:"),
        "ziv_renew":      (STATE_ZIV_RENEW_USER,   "menu_ziv",   "🟣 *Perpanjang Akun ZivPN*\n\nKirim username:"),
        "ziv_toggle":     (STATE_ZIV_TOGGLE,       "menu_ziv",   "🟣 *Kunci/Buka Akun ZivPN*\n\nKirim username:"),
        "ziv_maxlogin":   (STATE_ZIV_MAXLOGIN_USER,"menu_ziv",   "🟣 *Set MaxLogin ZivPN*\n\nKirim username:"),
        "ziv_setquota":   (STATE_ZIV_QUOTA_USER,   "menu_ziv",   "🟣 *Set Kuota ZivPN*\n\nKirim username:"),
        "ziv_resetquota": (STATE_ZIV_RQUOTA,       "menu_ziv",   "🟣 *Reset Kuota ZivPN*\n\nKirim username (atau `all`):"),
        "ziv_resetsess":  (STATE_ZIV_RSESS,        "menu_ziv",   "🟣 *Reset Sesi ZivPN*\n\nKirim username (atau `all`):"),

        "rs_add":         (STATE_RS_ADD_ID,        "menu_reseller","👥 *Tambah Reseller*\n\nKirim Telegram ID reseller:"),
        "rs_delete":      (STATE_RS_DEL,           "menu_reseller","👥 *Hapus Reseller*\n\nKirim Telegram ID reseller:"),
        "rs_setquota":    (STATE_RS_SETQUOTA_ID,   "menu_reseller","👥 *Set Kuota Reseller*\n\nKirim Telegram ID reseller:"),
    }
    if data in triggers:
        state, back_cb, prompt = triggers[data]
        ctx.user_data['back_cb'] = back_cb
        await q.edit_message_text(prompt, parse_mode="Markdown", reply_markup=cancel_keyboard())
        return state

# ══════════════════════════════════════════════════════════════
#  CONVERSATION — OGH CREATE
# ══════════════════════════════════════════════════════════════
async def ogh_create_user(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    u = update.message.text.strip()
    if not u.replace('_','').isalnum():
        await update.message.reply_text("❌ Username tidak valid. Hanya huruf, angka, underscore.")
        return STATE_OGH_CREATE_USER
    if user_exists(OGH_DB, u):
        await update.message.reply_text(f"❌ Username `{u}` sudah ada.", parse_mode="Markdown")
        return STATE_OGH_CREATE_USER
    ctx.user_data['ogh_new_user'] = u
    cfg = bot_cfg()
    await update.message.reply_text(
        f"✅ Username: `{u}`\n\nKirim password:",
        parse_mode="Markdown", reply_markup=cancel_keyboard()
    )
    return STATE_OGH_CREATE_PASS

async def ogh_create_pass(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    ctx.user_data['ogh_new_pass'] = update.message.text.strip()
    cfg = bot_cfg()
    await update.message.reply_text(
        f"✅ Password disimpan.\n\nKirim lama expired (hari) [default: {cfg.get('ogh_default_days',30)}]:",
        reply_markup=cancel_keyboard()
    )
    return STATE_OGH_CREATE_DAYS

async def ogh_create_days(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    txt = update.message.text.strip()
    cfg = bot_cfg()
    days = int(txt) if txt.isdigit() else cfg.get('ogh_default_days', 30)
    ctx.user_data['ogh_new_days'] = days
    await update.message.reply_text(
        f"✅ Expired: {days} hari.\n\nKirim MaxLogin (0=unlimited) [default: {cfg.get('ogh_default_maxlogin',2)}]:",
        reply_markup=cancel_keyboard()
    )
    return STATE_OGH_CREATE_ML

async def ogh_create_ml(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    txt = update.message.text.strip()
    cfg = bot_cfg()
    ml = int(txt) if txt.isdigit() else cfg.get('ogh_default_maxlogin', 2)
    ctx.user_data['ogh_new_ml'] = ml
    dq = cfg.get('ogh_default_quota', 0)
    dq_l = "Unlimited" if dq == 0 else bytes_human(dq)
    await update.message.reply_text(
        f"✅ MaxLogin: {ml}.\n\nKirim kuota data (cth: 10GB, 500MB, 0=unlimited) [default: {dq_l}]:",
        reply_markup=cancel_keyboard()
    )
    return STATE_OGH_CREATE_QUOTA

async def ogh_create_quota(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    uid = update.effective_user.id
    txt = update.message.text.strip()
    if txt == '0' or txt.lower() in ('0', 'unlimited', '∞'):
        qb = 0
    else:
        qb = human_bytes(txt)

    # Check reseller quota
    if not is_admin(uid):
        ok_rs, msg = reseller_can_create(uid, 'ogh')
        if not ok_rs:
            await update.message.reply_text(f"❌ {msg}")
            return ConversationHandler.END

    u    = ctx.user_data['ogh_new_user']
    p    = ctx.user_data['ogh_new_pass']
    days = ctx.user_data['ogh_new_days']
    ml   = ctx.user_data['ogh_new_ml']
    row  = create_user_db(OGH_DB, OGH_QUOTA_D, OGH_SESS_D, u, p, days, ml, qb)

    if not is_admin(uid):
        reseller_add_usage(uid, 'ogh')

    ip   = get_public_ip()
    port = get_ogh_port()
    txt_out = fmt_account(row, ip, port, OGH_QUOTA_D, OGH_SESS_D, "OGH-UDP")
    await update.message.reply_text(
        f"✅ *Akun OGH-UDP Berhasil Dibuat!*\n\n{txt_out}",
        parse_mode="Markdown", reply_markup=back_keyboard("menu_ogh")
    )
    ctx.user_data.clear()
    return ConversationHandler.END

# ══════════════════════════════════════════════════════════════
#  CONVERSATION — ZivPN CREATE
# ══════════════════════════════════════════════════════════════
async def ziv_create_user(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    u = update.message.text.strip()
    if not u.replace('_','').isalnum():
        await update.message.reply_text("❌ Username tidak valid.")
        return STATE_ZIV_CREATE_USER
    if user_exists(ZIV_DB, u):
        await update.message.reply_text(f"❌ Username `{u}` sudah ada.", parse_mode="Markdown")
        return STATE_ZIV_CREATE_USER
    ctx.user_data['ziv_new_user'] = u
    await update.message.reply_text(f"✅ Username: `{u}`\n\nKirim password:", parse_mode="Markdown", reply_markup=cancel_keyboard())
    return STATE_ZIV_CREATE_PASS

async def ziv_create_pass(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    ctx.user_data['ziv_new_pass'] = update.message.text.strip()
    cfg = bot_cfg()
    await update.message.reply_text(
        f"✅ Password disimpan.\n\nKirim lama expired (hari) [default: {cfg.get('ziv_default_days',30)}]:",
        reply_markup=cancel_keyboard()
    )
    return STATE_ZIV_CREATE_DAYS

async def ziv_create_days(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    txt = update.message.text.strip()
    cfg = bot_cfg()
    days = int(txt) if txt.isdigit() else cfg.get('ziv_default_days', 30)
    ctx.user_data['ziv_new_days'] = days
    await update.message.reply_text(
        f"✅ Expired: {days} hari.\n\nKirim MaxLogin (0=unlimited) [default: {cfg.get('ziv_default_maxlogin',2)}]:",
        reply_markup=cancel_keyboard()
    )
    return STATE_ZIV_CREATE_ML

async def ziv_create_ml(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    txt = update.message.text.strip()
    cfg = bot_cfg()
    ml = int(txt) if txt.isdigit() else cfg.get('ziv_default_maxlogin', 2)
    ctx.user_data['ziv_new_ml'] = ml
    await update.message.reply_text(
        f"✅ MaxLogin: {ml}.\n\nKirim kuota data (cth: 10GB, 0=unlimited):",
        reply_markup=cancel_keyboard()
    )
    return STATE_ZIV_CREATE_QUOTA

async def ziv_create_quota(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    uid = update.effective_user.id
    txt = update.message.text.strip()
    qb  = 0 if txt in ('0','unlimited','∞') else human_bytes(txt)

    if not is_admin(uid):
        ok_rs, msg = reseller_can_create(uid, 'ziv')
        if not ok_rs:
            await update.message.reply_text(f"❌ {msg}")
            return ConversationHandler.END

    u    = ctx.user_data['ziv_new_user']
    p    = ctx.user_data['ziv_new_pass']
    days = ctx.user_data['ziv_new_days']
    ml   = ctx.user_data['ziv_new_ml']
    row  = create_user_db(ZIV_DB, ZIV_QUOTA_D, ZIV_SESS_D, u, p, days, ml, qb)

    if not is_admin(uid):
        reseller_add_usage(uid, 'ziv')

    ip   = get_public_ip()
    port = get_ziv_port()
    txt_out = fmt_account(row, ip, port, ZIV_QUOTA_D, ZIV_SESS_D, "ZivPN-UDP")
    txt_out += f"\n\n🔗 Link: `zivpn://{u}:{p}@{ip}:{port}`"
    await update.message.reply_text(
        f"✅ *Akun ZivPN Berhasil Dibuat!*\n\n{txt_out}",
        parse_mode="Markdown", reply_markup=back_keyboard("menu_ziv")
    )
    ctx.user_data.clear()
    return ConversationHandler.END

# ══════════════════════════════════════════════════════════════
#  GENERIC SINGLE-INPUT CONVERSATIONS
# ══════════════════════════════════════════════════════════════
async def ogh_delete_input(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    u = update.message.text.strip()
    uid = update.effective_user.id
    if not user_exists(OGH_DB, u):
        await update.message.reply_text(f"❌ Akun `{u}` tidak ditemukan.", parse_mode="Markdown")
        return ConversationHandler.END
    delete_user_db(OGH_DB, OGH_QUOTA_D, OGH_SESS_D, u)
    if not is_admin(uid):
        reseller_remove_usage(uid, 'ogh')
    await update.message.reply_text(f"✅ Akun OGH `{u}` dihapus.", parse_mode="Markdown", reply_markup=back_keyboard("menu_ogh"))
    return ConversationHandler.END

async def ziv_delete_input(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    u = update.message.text.strip()
    uid = update.effective_user.id
    if not user_exists(ZIV_DB, u):
        await update.message.reply_text(f"❌ Akun `{u}` tidak ditemukan.", parse_mode="Markdown")
        return ConversationHandler.END
    delete_user_db(ZIV_DB, ZIV_QUOTA_D, ZIV_SESS_D, u)
    if not is_admin(uid):
        reseller_remove_usage(uid, 'ziv')
    await update.message.reply_text(f"✅ Akun ZivPN `{u}` dihapus.", parse_mode="Markdown", reply_markup=back_keyboard("menu_ziv"))
    return ConversationHandler.END

async def ogh_check_input(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    u = update.message.text.strip()
    row = find_user(OGH_DB, u)
    if not row:
        row = find_user(ZIV_DB, u)
        if row:
            txt = fmt_account(row, get_public_ip(), get_ziv_port(), ZIV_QUOTA_D, ZIV_SESS_D, "ZivPN-UDP")
            await update.message.reply_text(txt, parse_mode="Markdown", reply_markup=back_keyboard("back_main"))
            return ConversationHandler.END
        await update.message.reply_text(f"❌ Akun `{u}` tidak ditemukan di OGH maupun ZivPN.", parse_mode="Markdown")
        return ConversationHandler.END
    txt = fmt_account(row, get_public_ip(), get_ogh_port(), OGH_QUOTA_D, OGH_SESS_D, "OGH-UDP")
    await update.message.reply_text(txt, parse_mode="Markdown", reply_markup=back_keyboard("back_main"))
    return ConversationHandler.END

async def ziv_check_input(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    u = update.message.text.strip()
    row = find_user(ZIV_DB, u)
    if not row:
        await update.message.reply_text(f"❌ Akun `{u}` tidak ditemukan.", parse_mode="Markdown")
        return ConversationHandler.END
    txt = fmt_account(row, get_public_ip(), get_ziv_port(), ZIV_QUOTA_D, ZIV_SESS_D, "ZivPN-UDP")
    await update.message.reply_text(txt, parse_mode="Markdown", reply_markup=back_keyboard("menu_ziv"))
    return ConversationHandler.END

async def ogh_renew_user_input(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    u = update.message.text.strip()
    if not user_exists(OGH_DB, u):
        await update.message.reply_text(f"❌ Akun `{u}` tidak ditemukan.", parse_mode="Markdown")
        return ConversationHandler.END
    ctx.user_data['renew_user'] = u
    row = find_user(OGH_DB, u)
    await update.message.reply_text(f"📅 Expired saat ini: `{row['exp']}`\n\nKirim berapa hari tambahan:", parse_mode="Markdown", reply_markup=cancel_keyboard())
    return STATE_OGH_RENEW_DAYS

async def ogh_renew_days_input(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    txt = update.message.text.strip()
    if not txt.isdigit():
        await update.message.reply_text("❌ Kirim angka hari.")
        return STATE_OGH_RENEW_DAYS
    u = ctx.user_data['renew_user']
    new_exp = renew_user_db(OGH_DB, u, int(txt))
    await update.message.reply_text(f"✅ Akun `{u}` diperpanjang hingga `{new_exp}` (+{txt} hari).", parse_mode="Markdown", reply_markup=back_keyboard("menu_ogh"))
    return ConversationHandler.END

async def ziv_renew_user_input(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    u = update.message.text.strip()
    if not user_exists(ZIV_DB, u):
        await update.message.reply_text(f"❌ Akun `{u}` tidak ditemukan.", parse_mode="Markdown")
        return ConversationHandler.END
    ctx.user_data['renew_user'] = u
    row = find_user(ZIV_DB, u)
    await update.message.reply_text(f"📅 Expired saat ini: `{row['exp']}`\n\nKirim berapa hari tambahan:", parse_mode="Markdown", reply_markup=cancel_keyboard())
    return STATE_ZIV_RENEW_DAYS

async def ziv_renew_days_input(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    txt = update.message.text.strip()
    if not txt.isdigit():
        await update.message.reply_text("❌ Kirim angka hari.")
        return STATE_ZIV_RENEW_DAYS
    u = ctx.user_data['renew_user']
    new_exp = renew_user_db(ZIV_DB, u, int(txt))
    await update.message.reply_text(f"✅ Akun `{u}` diperpanjang hingga `{new_exp}` (+{txt} hari).", parse_mode="Markdown", reply_markup=back_keyboard("menu_ziv"))
    return ConversationHandler.END

async def ogh_toggle_input(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    u = update.message.text.strip()
    row = find_user(OGH_DB, u)
    if not row:
        await update.message.reply_text(f"❌ Akun `{u}` tidak ditemukan.", parse_mode="Markdown")
        return ConversationHandler.END
    new_st = 'active' if row['status'] == 'locked' else 'locked'
    update_user_field(OGH_DB, u, status=new_st)
    st_l = "🔓 Dibuka" if new_st == 'active' else "🔒 Dikunci"
    await update.message.reply_text(f"✅ Akun OGH `{u}` {st_l}.", parse_mode="Markdown", reply_markup=back_keyboard("menu_ogh"))
    return ConversationHandler.END

async def ziv_toggle_input(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    u = update.message.text.strip()
    row = find_user(ZIV_DB, u)
    if not row:
        await update.message.reply_text(f"❌ Akun `{u}` tidak ditemukan.", parse_mode="Markdown")
        return ConversationHandler.END
    new_st = 'active' if row['status'] == 'locked' else 'locked'
    update_user_field(ZIV_DB, u, status=new_st)
    st_l = "🔓 Dibuka" if new_st == 'active' else "🔒 Dikunci"
    await update.message.reply_text(f"✅ Akun ZivPN `{u}` {st_l}.", parse_mode="Markdown", reply_markup=back_keyboard("menu_ziv"))
    return ConversationHandler.END

async def ogh_maxlogin_user(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    u = update.message.text.strip()
    if not user_exists(OGH_DB, u):
        await update.message.reply_text(f"❌ Akun `{u}` tidak ditemukan.", parse_mode="Markdown")
        return ConversationHandler.END
    ctx.user_data['ml_user'] = u
    row = find_user(OGH_DB, u)
    await update.message.reply_text(f"MaxLogin saat ini: `{row['maxlogin']}`\n\nKirim nilai baru (0=unlimited):", parse_mode="Markdown", reply_markup=cancel_keyboard())
    return STATE_OGH_MAXLOGIN_VAL

async def ogh_maxlogin_val(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    txt = update.message.text.strip()
    if not txt.isdigit():
        await update.message.reply_text("❌ Kirim angka.")
        return STATE_OGH_MAXLOGIN_VAL
    u = ctx.user_data['ml_user']
    update_user_field(OGH_DB, u, maxlogin=txt)
    l = "Unlimited" if txt == '0' else f"{txt} device"
    await update.message.reply_text(f"✅ MaxLogin OGH `{u}` = {l}.", parse_mode="Markdown", reply_markup=back_keyboard("menu_ogh"))
    return ConversationHandler.END

async def ziv_maxlogin_user(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    u = update.message.text.strip()
    if not user_exists(ZIV_DB, u):
        await update.message.reply_text(f"❌ Akun `{u}` tidak ditemukan.", parse_mode="Markdown")
        return ConversationHandler.END
    ctx.user_data['ml_user'] = u
    row = find_user(ZIV_DB, u)
    await update.message.reply_text(f"MaxLogin saat ini: `{row['maxlogin']}`\n\nKirim nilai baru:", parse_mode="Markdown", reply_markup=cancel_keyboard())
    return STATE_ZIV_MAXLOGIN_VAL

async def ziv_maxlogin_val(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    txt = update.message.text.strip()
    if not txt.isdigit():
        await update.message.reply_text("❌ Kirim angka.")
        return STATE_ZIV_MAXLOGIN_VAL
    u = ctx.user_data['ml_user']
    update_user_field(ZIV_DB, u, maxlogin=txt)
    l = "Unlimited" if txt == '0' else f"{txt} device"
    await update.message.reply_text(f"✅ MaxLogin ZivPN `{u}` = {l}.", parse_mode="Markdown", reply_markup=back_keyboard("menu_ziv"))
    return ConversationHandler.END

async def ogh_quota_user(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    u = update.message.text.strip()
    if not user_exists(OGH_DB, u):
        await update.message.reply_text(f"❌ Akun `{u}` tidak ditemukan.", parse_mode="Markdown")
        return ConversationHandler.END
    ctx.user_data['quota_user'] = u
    row = find_user(OGH_DB, u)
    q = int(row['quota'])
    ql = "Unlimited" if q == 0 else bytes_human(q)
    await update.message.reply_text(f"Kuota saat ini: `{ql}`\n\nKirim kuota baru (cth: 10GB, 0=unlimited):", parse_mode="Markdown", reply_markup=cancel_keyboard())
    return STATE_OGH_QUOTA_VAL

async def ogh_quota_val(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    txt = update.message.text.strip()
    u   = ctx.user_data['quota_user']
    qb  = 0 if txt in ('0','unlimited') else human_bytes(txt)
    update_user_field(OGH_DB, u, quota=str(qb))
    l = "Unlimited" if qb == 0 else bytes_human(qb)
    await update.message.reply_text(f"✅ Kuota OGH `{u}` = {l}.", parse_mode="Markdown", reply_markup=back_keyboard("menu_ogh"))
    return ConversationHandler.END

async def ziv_quota_user(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    u = update.message.text.strip()
    if not user_exists(ZIV_DB, u):
        await update.message.reply_text(f"❌ Akun `{u}` tidak ditemukan.", parse_mode="Markdown")
        return ConversationHandler.END
    ctx.user_data['quota_user'] = u
    row = find_user(ZIV_DB, u)
    q = int(row['quota'])
    ql = "Unlimited" if q == 0 else bytes_human(q)
    await update.message.reply_text(f"Kuota saat ini: `{ql}`\n\nKirim kuota baru:", parse_mode="Markdown", reply_markup=cancel_keyboard())
    return STATE_ZIV_QUOTA_VAL

async def ziv_quota_val(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    txt = update.message.text.strip()
    u   = ctx.user_data['quota_user']
    qb  = 0 if txt in ('0','unlimited') else human_bytes(txt)
    update_user_field(ZIV_DB, u, quota=str(qb))
    l = "Unlimited" if qb == 0 else bytes_human(qb)
    await update.message.reply_text(f"✅ Kuota ZivPN `{u}` = {l}.", parse_mode="Markdown", reply_markup=back_keyboard("menu_ziv"))
    return ConversationHandler.END

async def ogh_rquota_input(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    u = update.message.text.strip()
    if u == 'all':
        for row in read_db(OGH_DB):
            (Path(OGH_QUOTA_D) / f"{row['user']}.quota").write_text("0")
        await update.message.reply_text("✅ Semua kuota OGH direset.", reply_markup=back_keyboard("menu_ogh"))
    elif user_exists(OGH_DB, u):
        (Path(OGH_QUOTA_D) / f"{u}.quota").write_text("0")
        await update.message.reply_text(f"✅ Kuota OGH `{u}` direset.", parse_mode="Markdown", reply_markup=back_keyboard("menu_ogh"))
    else:
        await update.message.reply_text("❌ User tidak ditemukan.")
    return ConversationHandler.END

async def ziv_rquota_input(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    u = update.message.text.strip()
    if u == 'all':
        for row in read_db(ZIV_DB):
            (Path(ZIV_QUOTA_D) / f"{row['user']}.quota").write_text("0")
        await update.message.reply_text("✅ Semua kuota ZivPN direset.", reply_markup=back_keyboard("menu_ziv"))
    elif user_exists(ZIV_DB, u):
        (Path(ZIV_QUOTA_D) / f"{u}.quota").write_text("0")
        await update.message.reply_text(f"✅ Kuota ZivPN `{u}` direset.", parse_mode="Markdown", reply_markup=back_keyboard("menu_ziv"))
    else:
        await update.message.reply_text("❌ User tidak ditemukan.")
    return ConversationHandler.END

async def ogh_rsess_input(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    u = update.message.text.strip()
    if u == 'all':
        for row in read_db(OGH_DB):
            (Path(OGH_SESS_D) / f"{row['user']}.sess").write_text("0")
        await update.message.reply_text("✅ Semua sesi OGH direset.", reply_markup=back_keyboard("menu_ogh"))
    elif user_exists(OGH_DB, u):
        (Path(OGH_SESS_D) / f"{u}.sess").write_text("0")
        await update.message.reply_text(f"✅ Sesi OGH `{u}` direset.", parse_mode="Markdown", reply_markup=back_keyboard("menu_ogh"))
    else:
        await update.message.reply_text("❌ User tidak ditemukan.")
    return ConversationHandler.END

async def ziv_rsess_input(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    u = update.message.text.strip()
    if u == 'all':
        for row in read_db(ZIV_DB):
            (Path(ZIV_SESS_D) / f"{row['user']}.sess").write_text("0")
        await update.message.reply_text("✅ Semua sesi ZivPN direset.", reply_markup=back_keyboard("menu_ziv"))
    elif user_exists(ZIV_DB, u):
        (Path(ZIV_SESS_D) / f"{u}.sess").write_text("0")
        await update.message.reply_text(f"✅ Sesi ZivPN `{u}` direset.", parse_mode="Markdown", reply_markup=back_keyboard("menu_ziv"))
    else:
        await update.message.reply_text("❌ User tidak ditemukan.")
    return ConversationHandler.END

# ══════════════════════════════════════════════════════════════
#  RESELLER CONVERSATIONS
# ══════════════════════════════════════════════════════════════
async def rs_add_id(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    txt = update.message.text.strip()
    if not txt.isdigit():
        await update.message.reply_text("❌ Kirim Telegram ID (angka).")
        return STATE_RS_ADD_ID
    ctx.user_data['rs_new_id'] = txt
    await update.message.reply_text("Kirim nama reseller:", reply_markup=cancel_keyboard())
    return STATE_RS_ADD_NAME

async def rs_add_name(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    ctx.user_data['rs_new_name'] = update.message.text.strip()
    await update.message.reply_text("Kuota akun OGH (0=unlimited):", reply_markup=cancel_keyboard())
    return STATE_RS_ADD_QUOTA_OGH

async def rs_add_quota_ogh(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    txt = update.message.text.strip()
    ctx.user_data['rs_ogh_quota'] = int(txt) if txt.isdigit() else 0
    await update.message.reply_text("Kuota akun ZivPN (0=unlimited):", reply_markup=cancel_keyboard())
    return STATE_RS_ADD_QUOTA_ZIV

async def rs_add_quota_ziv(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    txt = update.message.text.strip()
    rid  = ctx.user_data['rs_new_id']
    name = ctx.user_data['rs_new_name']
    oq   = ctx.user_data['rs_ogh_quota']
    zq   = int(txt) if txt.isdigit() else 0
    rs   = get_resellers()
    rs[rid] = {
        "name": name, "added": datetime.now().strftime('%Y-%m-%d'),
        "ogh_quota": oq, "ogh_used": 0,
        "ziv_quota": zq, "ziv_used": 0,
    }
    save_json(RESELLER_DB, rs)
    oql = str(oq) if oq > 0 else "∞"
    zql = str(zq) if zq > 0 else "∞"
    await update.message.reply_text(
        f"✅ *Reseller Ditambahkan!*\n\n"
        f"ID: `{rid}`\nNama: {name}\nKuota OGH: {oql}\nKuota ZivPN: {zql}",
        parse_mode="Markdown", reply_markup=back_keyboard("menu_reseller")
    )
    ctx.user_data.clear()
    return ConversationHandler.END

async def rs_del_input(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    rid = update.message.text.strip()
    rs  = get_resellers()
    if rid in rs:
        del rs[rid]
        save_json(RESELLER_DB, rs)
        await update.message.reply_text(f"✅ Reseller `{rid}` dihapus.", parse_mode="Markdown", reply_markup=back_keyboard("menu_reseller"))
    else:
        await update.message.reply_text("❌ Reseller tidak ditemukan.")
    return ConversationHandler.END

async def rs_setquota_id(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    rid = update.message.text.strip()
    rs  = get_resellers()
    if rid not in rs:
        await update.message.reply_text("❌ Reseller tidak ditemukan.")
        return ConversationHandler.END
    ctx.user_data['rs_edit_id'] = rid
    r = rs[rid]
    await update.message.reply_text(
        f"Reseller: {r['name']}\n"
        f"OGH quota: {r.get('ogh_quota',0)} | ZivPN quota: {r.get('ziv_quota',0)}\n\n"
        "Kirim `ogh:N` atau `ziv:N` (cth: `ogh:50` atau `ziv:0` untuk unlimited):",
        parse_mode="Markdown", reply_markup=cancel_keyboard()
    )
    return STATE_RS_SETQUOTA_VAL

async def rs_setquota_val(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    txt = update.message.text.strip().lower()
    rid = ctx.user_data['rs_edit_id']
    rs  = get_resellers()
    if ':' not in txt:
        await update.message.reply_text("❌ Format salah. Gunakan `ogh:N` atau `ziv:N`.", parse_mode="Markdown")
        return STATE_RS_SETQUOTA_VAL
    svc, val = txt.split(':', 1)
    if not val.isdigit() or svc not in ('ogh','ziv'):
        await update.message.reply_text("❌ Format salah.")
        return STATE_RS_SETQUOTA_VAL
    rs[rid][f"{svc}_quota"] = int(val)
    save_json(RESELLER_DB, rs)
    l = "Unlimited" if val == '0' else val
    await update.message.reply_text(
        f"✅ Kuota {svc.upper()} reseller `{rid}` = {l}.",
        parse_mode="Markdown", reply_markup=back_keyboard("menu_reseller")
    )
    return ConversationHandler.END

# ══════════════════════════════════════════════════════════════
#  COMMANDS
# ══════════════════════════════════════════════════════════════
@admin_only
async def cmd_soon(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    lines = ["⏰ *Akun Akan Expired (7 hari)*\n\n🟠 OGH-UDP:"]
    for u, d in get_soon_expired(OGH_DB):
        lines.append(f"  • `{u['user']}` — {u['exp']} ({d} hari)")
    lines.append("\n🟣 ZivPN-UDP:")
    for u, d in get_soon_expired(ZIV_DB):
        lines.append(f"  • `{u['user']}` — {u['exp']} ({d} hari)")
    if len(lines) <= 3:
        lines.append("  Tidak ada.")
    await update.message.reply_text("\n".join(lines), parse_mode="Markdown")

@admin_only
async def cmd_setcfg(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    args = ctx.args
    if len(args) < 2:
        cfg = bot_cfg()
        txt = "⚙️ *Pengaturan Bot*\n\n"
        for k, v in cfg.items():
            txt += f"`{k}` = `{v}`\n"
        txt += "\nGunakan: `/setcfg key value`"
        await update.message.reply_text(txt, parse_mode="Markdown")
        return
    key, val = args[0], args[1]
    cfg = bot_cfg()
    try:
        if val.lower() == 'true':
            cfg[key] = True
        elif val.lower() == 'false':
            cfg[key] = False
        elif val.isdigit():
            cfg[key] = int(val)
        else:
            cfg[key] = val
        save_json(BOT_CFG_FILE, cfg)
        await update.message.reply_text(f"✅ `{key}` = `{cfg[key]}`", parse_mode="Markdown")
    except Exception as e:
        await update.message.reply_text(f"❌ Error: {e}")

async def cmd_myid(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    uid = update.effective_user.id
    name = update.effective_user.first_name
    await update.message.reply_text(
        f"👤 Nama: {name}\n🆔 ID  : `{uid}`",
        parse_mode="Markdown"
    )

@admin_only
async def cmd_broadcast(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if not ctx.args:
        await update.message.reply_text("Gunakan: /broadcast pesan"); return
    msg = " ".join(ctx.args)
    rs  = get_resellers()
    count = 0
    for rid in rs:
        try:
            await ctx.bot.send_message(int(rid), f"📢 *Broadcast dari Admin:*\n\n{msg}", parse_mode="Markdown")
            count += 1
        except:
            pass
    await update.message.reply_text(f"✅ Pesan terkirim ke {count} reseller.")

# cancel fallback
async def conv_cancel(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    ctx.user_data.clear()
    await update.message.reply_text("❌ Dibatalkan.", reply_markup=back_keyboard("back_main"))
    return ConversationHandler.END

# ══════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════
def main():
    init_dirs()
    log.info("Starting OGH-UDP Telegram Bot...")

    app = Application.builder().token(BOT_TOKEN).build()

    # Conversation handler — satu handler untuk semua states
    conv = ConversationHandler(
        entry_points=[CallbackQueryHandler(handle_callback)],
        states={
            # OGH Create
            STATE_OGH_CREATE_USER:  [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_create_user)],
            STATE_OGH_CREATE_PASS:  [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_create_pass)],
            STATE_OGH_CREATE_DAYS:  [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_create_days)],
            STATE_OGH_CREATE_ML:    [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_create_ml)],
            STATE_OGH_CREATE_QUOTA: [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_create_quota)],
            # OGH other
            STATE_OGH_DELETE:       [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_delete_input)],
            STATE_OGH_CHECK:        [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_check_input)],
            STATE_OGH_RENEW_USER:   [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_renew_user_input)],
            STATE_OGH_RENEW_DAYS:   [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_renew_days_input)],
            STATE_OGH_TOGGLE:       [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_toggle_input)],
            STATE_OGH_MAXLOGIN_USER:[MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_maxlogin_user)],
            STATE_OGH_MAXLOGIN_VAL: [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_maxlogin_val)],
            STATE_OGH_QUOTA_USER:   [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_quota_user)],
            STATE_OGH_QUOTA_VAL:    [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_quota_val)],
            STATE_OGH_RQUOTA:       [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_rquota_input)],
            STATE_OGH_RSESS:        [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_rsess_input)],
            # ZivPN Create
            STATE_ZIV_CREATE_USER:  [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_create_user)],
            STATE_ZIV_CREATE_PASS:  [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_create_pass)],
            STATE_ZIV_CREATE_DAYS:  [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_create_days)],
            STATE_ZIV_CREATE_ML:    [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_create_ml)],
            STATE_ZIV_CREATE_QUOTA: [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_create_quota)],
            # ZivPN other
            STATE_ZIV_DELETE:       [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_delete_input)],
            STATE_ZIV_CHECK:        [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_check_input)],
            STATE_ZIV_RENEW_USER:   [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_renew_user_input)],
            STATE_ZIV_RENEW_DAYS:   [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_renew_days_input)],
            STATE_ZIV_TOGGLE:       [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_toggle_input)],
            STATE_ZIV_MAXLOGIN_USER:[MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_maxlogin_user)],
            STATE_ZIV_MAXLOGIN_VAL: [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_maxlogin_val)],
            STATE_ZIV_QUOTA_USER:   [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_quota_user)],
            STATE_ZIV_QUOTA_VAL:    [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_quota_val)],
            STATE_ZIV_RQUOTA:       [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_rquota_input)],
            STATE_ZIV_RSESS:        [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_rsess_input)],
            # Reseller
            STATE_RS_ADD_ID:        [MessageHandler(filters.TEXT & ~filters.COMMAND, rs_add_id)],
            STATE_RS_ADD_NAME:      [MessageHandler(filters.TEXT & ~filters.COMMAND, rs_add_name)],
            STATE_RS_ADD_QUOTA_OGH: [MessageHandler(filters.TEXT & ~filters.COMMAND, rs_add_quota_ogh)],
            STATE_RS_ADD_QUOTA_ZIV: [MessageHandler(filters.TEXT & ~filters.COMMAND, rs_add_quota_ziv)],
            STATE_RS_DEL:           [MessageHandler(filters.TEXT & ~filters.COMMAND, rs_del_input)],
            STATE_RS_SETQUOTA_ID:   [MessageHandler(filters.TEXT & ~filters.COMMAND, rs_setquota_id)],
            STATE_RS_SETQUOTA_VAL:  [MessageHandler(filters.TEXT & ~filters.COMMAND, rs_setquota_val)],
        },
        fallbacks=[
            CommandHandler("cancel", conv_cancel),
            CallbackQueryHandler(handle_callback, pattern="^cancel$"),
        ],
        per_user=True,
        per_chat=False,
    )

    app.add_handler(CommandHandler("start",      start))
    app.add_handler(CommandHandler("menu",       start))
    app.add_handler(CommandHandler("myid",       cmd_myid))
    app.add_handler(CommandHandler("soon",       cmd_soon))
    app.add_handler(CommandHandler("setcfg",     cmd_setcfg))
    app.add_handler(CommandHandler("broadcast",  cmd_broadcast))
    app.add_handler(conv)

    log.info("Bot berjalan. Tekan Ctrl+C untuk berhenti.")
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    main()
