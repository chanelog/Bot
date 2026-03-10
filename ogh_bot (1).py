#!/usr/bin/env python3
# ╔══════════════════════════════════════════════════════════════════╗
# ║       OGH-UDP TELEGRAM BOT v3.1                                 ║
# ║  Synced with: ogh-manager.sh + install_bot.sh                   ║
# ║  Install    : bash install_bot.sh                               ║
# ╚══════════════════════════════════════════════════════════════════╝
# pip3 install python-telegram-bot==20.7 requests

import os, json, time, subprocess, logging, shutil, asyncio
from datetime import datetime, timedelta
from pathlib import Path
from functools import wraps

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application, CommandHandler, CallbackQueryHandler,
    MessageHandler, filters, ContextTypes, ConversationHandler
)

# ══════════════════════════════════════════════════════════════════
#  ▼▼▼  BLOK KONFIGURASI — edit oleh install_bot.sh  ▼▼▼
# ══════════════════════════════════════════════════════════════════
BOT_TOKEN    = "ISI_TOKEN_BOT_DISINI"
ADMIN_IDS    = [123456789]
BOT_NAME     = "OGH-UDP Manager"
VERSION      = "3.1"
SYNC_KEY     = "OGH-SYNC-3.1"   # harus sama dengan ogh-manager.sh

# --- OGH-UDP (identik dengan ogh-manager.sh) ---
OGH_BIN      = "/usr/local/bin/udpServer"
OGH_SVC      = "ogh-udp"
OGH_DIR      = "/etc/ogh-udp"
OGH_DB       = f"{OGH_DIR}/users.db"
OGH_PORT_F   = f"{OGH_DIR}/port.conf"
OGH_LOG      = "/var/log/ogh-udp.log"
OGH_QUOTA_D  = f"{OGH_DIR}/quota"
OGH_SESS_D   = f"{OGH_DIR}/sessions"

# --- ZivPN-UDP (identik dengan ogh-manager.sh) ---
ZIV_BIN      = "/usr/local/bin/udp-zivpn"
ZIV_SVC      = "zivpn-udp"
ZIV_DIR      = "/etc/zivpn-udp"
ZIV_DB       = f"{ZIV_DIR}/users.db"
ZIV_CFG      = f"{ZIV_DIR}/config.json"
ZIV_LOG      = "/var/log/zivpn-udp.log"
ZIV_QUOTA_D  = f"{ZIV_DIR}/quota"
ZIV_SESS_D   = f"{ZIV_DIR}/sessions"

# --- Bot DB (identik dengan ogh-manager.sh) ---
BOT_DIR      = "/opt/ogh-bot"
BOT_SVC      = "ogh-bot"
BOT_DB_DIR   = "/etc/ogh-bot"
RESELLER_DB  = f"{BOT_DB_DIR}/resellers.json"
BOT_CFG_FILE = f"{BOT_DB_DIR}/config.json"
BOT_LOG      = "/var/log/ogh-bot.log"

# --- GitHub source (identik dengan ogh-manager.sh) ---
MANAGER_URL  = "https://github.com/chanelog/Bot/raw/refs/heads/main/ogh-manager.sh"
BOT_PY_URL   = "https://github.com/chanelog/Bot/raw/refs/heads/main/ogh_bot.py"
INSTALL_URL  = "https://github.com/chanelog/Bot/raw/refs/heads/main/install_bot.sh"
# ══════════════════════════════════════════════════════════════════

# ─── LOGGING ───────────────────────────────────────────────────────
logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    level=logging.INFO,
    handlers=[
        logging.FileHandler(BOT_LOG),
        logging.StreamHandler()
    ]
)
log = logging.getLogger(__name__)

# ══════════════════════════════════════════════════════════════════
#  INIT
# ══════════════════════════════════════════════════════════════════
def init_dirs():
    for d in [BOT_DB_DIR, OGH_QUOTA_D, OGH_SESS_D, ZIV_QUOTA_D, ZIV_SESS_D]:
        Path(d).mkdir(parents=True, exist_ok=True)
    for f in [OGH_DB, ZIV_DB]:
        Path(f).touch(exist_ok=True)
    if not Path(RESELLER_DB).exists():
        save_json(RESELLER_DB, {})
    if not Path(BOT_CFG_FILE).exists():
        save_json(BOT_CFG_FILE, {
            "ogh_default_days": 30,  "ziv_default_days": 30,
            "ogh_default_quota": 0,  "ziv_default_quota": 0,
            "ogh_default_maxlogin": 2, "ziv_default_maxlogin": 2,
            "maintenance": False
        })

# ══════════════════════════════════════════════════════════════════
#  JSON HELPERS
# ══════════════════════════════════════════════════════════════════
def load_json(path):
    try:
        with open(path) as f: return json.load(f)
    except: return {}

def save_json(path, data):
    with open(path, "w") as f: json.dump(data, f, indent=2)

def bot_cfg(): return load_json(BOT_CFG_FILE)

# ══════════════════════════════════════════════════════════════════
#  RESELLER SYSTEM
# ══════════════════════════════════════════════════════════════════
def get_resellers():    return load_json(RESELLER_DB)
def is_reseller(uid):   return str(uid) in get_resellers()
def is_admin(uid):      return uid in ADMIN_IDS
def get_reseller(uid):  return get_resellers().get(str(uid), {})

def reseller_can_create(uid, service):
    r = get_reseller(uid)
    if not r: return False, "Anda bukan reseller."
    quota = r.get(f"{service}_quota", 0)
    used  = r.get(f"{service}_used",  0)
    if quota == 0: return True, ""
    if used >= quota: return False, f"Kuota reseller habis ({used}/{quota} akun)."
    return True, ""

def reseller_add_usage(uid, service):
    rs = get_resellers(); key = str(uid)
    if key in rs:
        k = f"{service}_used"
        rs[key][k] = rs[key].get(k, 0) + 1
        save_json(RESELLER_DB, rs)

def reseller_remove_usage(uid, service):
    rs = get_resellers(); key = str(uid)
    if key in rs:
        k = f"{service}_used"
        rs[key][k] = max(0, rs[key].get(k, 0) - 1)
        save_json(RESELLER_DB, rs)

# ══════════════════════════════════════════════════════════════════
#  SYSTEM HELPERS
# ══════════════════════════════════════════════════════════════════
_cached_ip = ""

def run_cmd(cmd):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=15)
        return r.stdout.strip(), r.returncode
    except Exception as e:
        return str(e), 1

def get_public_ip():
    global _cached_ip
    if _cached_ip: return _cached_ip
    out, _ = run_cmd("curl -s --max-time 5 ifconfig.me")
    _cached_ip = out or "N/A"
    return _cached_ip

def get_ogh_port():
    try: return open(OGH_PORT_F).read().strip()
    except: return "7300"

def get_ziv_port():
    try:
        cfg = load_json(ZIV_CFG)
        return cfg.get("listen", ":7200").lstrip(":")
    except: return "7200"

def svc_status_label(name):
    _, rc = run_cmd(f"systemctl is-active {name}")
    return "🟢 RUNNING" if rc == 0 else "🔴 STOPPED"

def bytes_human(b):
    b = int(b or 0)
    if b >= 1_073_741_824: return f"{b/1_073_741_824:.2f} GB"
    if b >= 1_048_576:     return f"{b/1_048_576:.2f} MB"
    if b >= 1024:          return f"{b/1024:.2f} KB"
    return f"{b} B"

def human_bytes(s):
    s = str(s).upper().strip()
    num = float(''.join(c for c in s if c.isdigit() or c == '.') or 0)
    unit = ''.join(c for c in s if c.isalpha())
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
    ram, _    = run_cmd("free -m | awk '/Mem:/{printf \"%dMB / %dMB\",$3,$2}'")
    disk, _   = run_cmd("df -h / | awk 'NR==2{printf \"%s/%s (%s)\",$3,$2,$5}'")
    cpu, _    = run_cmd("top -bn1 | grep 'Cpu(s)' | awk '{printf \"%.1f%%\",$2+$4}'")
    os_n, _   = run_cmd("grep PRETTY_NAME /etc/os-release | cut -d'\"' -f2")
    kern, _   = run_cmd("uname -r")
    return {"ip": get_public_ip(), "uptime": uptime or "N/A", "ram": ram or "N/A",
            "disk": disk or "N/A", "cpu": cpu or "N/A", "os": os_n or "N/A", "kernel": kern or "N/A"}

# ══════════════════════════════════════════════════════════════════
#  DATABASE — format identik dengan ogh-manager.sh
#  user|pass|expired|created|maxlogin|quota_bytes|used_bytes|status
# ══════════════════════════════════════════════════════════════════
def read_db(db_path):
    users = []
    try:
        with open(db_path) as f:
            for line in f:
                line = line.strip()
                if not line: continue
                p = line.split('|')
                while len(p) < 8: p.append('')
                users.append({
                    'user': p[0], 'pass': p[1], 'exp': p[2], 'created': p[3],
                    'maxlogin': p[4] or '0', 'quota': p[5] or '0',
                    'used': p[6] or '0', 'status': p[7] or 'active',
                })
    except: pass
    return users

def write_db(db_path, users):
    with open(db_path, 'w') as f:
        for u in users:
            f.write(f"{u['user']}|{u['pass']}|{u['exp']}|{u['created']}|"
                    f"{u['maxlogin']}|{u['quota']}|{u['used']}|{u['status']}\n")

def find_user(db_path, username):
    for u in read_db(db_path):
        if u['user'] == username: return u
    return None

def user_exists(db_path, username):
    return find_user(db_path, username) is not None

def create_user_db(db_path, quota_dir, sess_dir, user, pwd, days, maxlogin, quota_bytes):
    exp = (datetime.now() + timedelta(days=int(days))).strftime('%Y-%m-%d')
    now = datetime.now().strftime('%Y-%m-%d')
    row = {'user': user, 'pass': pwd, 'exp': exp, 'created': now,
           'maxlogin': str(maxlogin), 'quota': str(quota_bytes), 'used': '0', 'status': 'active'}
    users = read_db(db_path); users.append(row); write_db(db_path, users)
    (Path(quota_dir) / f"{user}.quota").write_text("0")
    (Path(sess_dir)  / f"{user}.sess").write_text("0")
    return row

def delete_user_db(db_path, quota_dir, sess_dir, username):
    users = read_db(db_path); before = len(users)
    users = [u for u in users if u['user'] != username]
    if len(users) == before: return False
    write_db(db_path, users)
    for qd, ext in [(quota_dir, 'quota'), (sess_dir, 'sess')]:
        (Path(qd) / f"{username}.{ext}").unlink(missing_ok=True)
    return True

def update_user_field(db_path, username, **kwargs):
    users = read_db(db_path)
    for u in users:
        if u['user'] == username: u.update(kwargs)
    write_db(db_path, users)

def renew_user_db(db_path, username, days):
    u = find_user(db_path, username)
    if not u: return None
    try:
        base = datetime.strptime(u['exp'], '%Y-%m-%d')
        if base < datetime.now(): base = datetime.now()
    except: base = datetime.now()
    new_exp = (base + timedelta(days=int(days))).strftime('%Y-%m-%d')
    update_user_field(db_path, username, exp=new_exp)
    return new_exp

def get_expired_users(db_path):
    today = datetime.now().strftime('%Y-%m-%d')
    return [u for u in read_db(db_path) if u['exp'] < today]

def get_soon_expired(db_path, days=7):
    today = datetime.now(); result = []
    for u in read_db(db_path):
        try:
            diff = (datetime.strptime(u['exp'], '%Y-%m-%d') - today).days
            if 0 <= diff <= days: result.append((u, diff))
        except: pass
    return result

# ══════════════════════════════════════════════════════════════════
#  FORMATTERS
# ══════════════════════════════════════════════════════════════════
def fmt_account(u, ip, port, quota_dir, sess_dir, service_name):
    today = datetime.now().strftime('%Y-%m-%d')
    try: exp_d = datetime.strptime(u['exp'], '%Y-%m-%d')
    except: exp_d = datetime.now()
    sisa = (exp_d - datetime.now()).days
    sisa_l = f"⏳ {sisa} hari" if sisa >= 0 else "❌ EXPIRED"
    used   = get_used(quota_dir, u['user'])
    quota  = int(u.get('quota', 0))
    ml     = u.get('maxlogin', '0')
    sess   = get_sessions(sess_dir, u['user'])
    status = ("🔒 LOCKED" if u['status'] == 'locked'
              else ("✅ AKTIF" if u.get('exp', '') >= today else "❌ EXPIRED"))
    quota_l = "Unlimited" if quota == 0 else bytes_human(quota)
    ml_l    = "Unlimited" if ml == '0' else ml
    pct = f" ({used*100//quota}%)" if quota > 0 else ""
    return (
        f"```\n"
        f"╔══════════════════════╗\n"
        f"║  {service_name}\n"
        f"╠══════════════════════╣\n"
        f"║ Username  : {u['user']}\n"
        f"║ Password  : {u['pass']}\n"
        f"║ Host      : {ip}\n"
        f"║ Port      : {port}\n"
        f"║ Expired   : {u['exp']}\n"
        f"║ Sisa      : {sisa_l}\n"
        f"║ Status    : {status}\n"
        f"╠══════════════════════╣\n"
        f"║ MaxLogin  : {ml_l}\n"
        f"║ Sesi Aktif: {sess}/{ml_l}\n"
        f"╠══════════════════════╣\n"
        f"║ Kuota     : {quota_l}\n"
        f"║ Terpakai  : {bytes_human(used)}{pct}\n"
        f"╚══════════════════════╝\n"
        f"```"
    )

def fmt_account_short(u, quota_dir, sess_dir):
    today = datetime.now().strftime('%Y-%m-%d')
    try: sisa = (datetime.strptime(u['exp'], '%Y-%m-%d') - datetime.now()).days
    except: sisa = -1
    used  = bytes_human(get_used(quota_dir, u['user']))
    quota = int(u.get('quota', 0))
    ql    = "∞" if quota == 0 else bytes_human(quota)
    st    = "✅" if (u['status'] == 'active' and u.get('exp','') >= today) else ("🔒" if u['status'] == 'locked' else "❌")
    return f"{st} `{u['user']:15}` | `{u['exp']}` | {sisa}h | {used}/{ql}"

# ══════════════════════════════════════════════════════════════════
#  ACCESS CONTROL
# ══════════════════════════════════════════════════════════════════
def require_access(allow_reseller=True):
    def decorator(func):
        @wraps(func)
        async def wrapper(update: Update, ctx: ContextTypes.DEFAULT_TYPE, *args, **kwargs):
            uid = update.effective_user.id
            if bot_cfg().get("maintenance") and not is_admin(uid):
                await update.message.reply_text("🔧 Bot sedang maintenance."); return
            if not is_admin(uid) and not (allow_reseller and is_reseller(uid)):
                await update.message.reply_text("⛔ Anda tidak memiliki akses."); return
            return await func(update, ctx, *args, **kwargs)
        return wrapper
    return decorator

def admin_only(func):
    @wraps(func)
    async def wrapper(update: Update, ctx: ContextTypes.DEFAULT_TYPE, *args, **kwargs):
        if not is_admin(update.effective_user.id):
            await update.message.reply_text("⛔ Hanya untuk Admin."); return
        return await func(update, ctx, *args, **kwargs)
    return wrapper

# ══════════════════════════════════════════════════════════════════
#  KEYBOARDS
# ══════════════════════════════════════════════════════════════════
def main_keyboard(uid):
    rows = [
        [InlineKeyboardButton("🟠 OGH-UDP",    callback_data="menu_ogh"),
         InlineKeyboardButton("🟣 ZivPN-UDP",  callback_data="menu_ziv")],
        [InlineKeyboardButton("📊 Statistik",  callback_data="menu_stats"),
         InlineKeyboardButton("🔎 Cek Akun",   callback_data="prompt_check")],
        [InlineKeyboardButton("📡 Info VPS",   callback_data="menu_vps"),
         InlineKeyboardButton("⏰ Akan Expired",callback_data="menu_soon")],
    ]
    if is_admin(uid):
        rows += [
            [InlineKeyboardButton("👥 Reseller",   callback_data="menu_reseller"),
             InlineKeyboardButton("⚙️ Bot Settings",callback_data="menu_settings")],
            [InlineKeyboardButton("🔧 Service",    callback_data="menu_service"),
             InlineKeyboardButton("💾 Backup",     callback_data="menu_backup")],
        ]
    return InlineKeyboardMarkup(rows)

def ogh_keyboard():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("➕ Buat Akun",     callback_data="ogh_create"),
         InlineKeyboardButton("➖ Hapus Akun",    callback_data="ogh_delete")],
        [InlineKeyboardButton("📋 List Akun",     callback_data="ogh_list"),
         InlineKeyboardButton("🔎 Cek Akun",      callback_data="ogh_check")],
        [InlineKeyboardButton("🔄 Perpanjang",    callback_data="ogh_renew"),
         InlineKeyboardButton("🔒 Kunci/Buka",    callback_data="ogh_toggle")],
        [InlineKeyboardButton("⚙️ Set MaxLogin",   callback_data="ogh_maxlogin"),
         InlineKeyboardButton("📦 Set Kuota",      callback_data="ogh_setquota")],
        [InlineKeyboardButton("♻️ Reset Kuota",    callback_data="ogh_rquota"),
         InlineKeyboardButton("🔗 Reset Sesi",     callback_data="ogh_rsess")],
        [InlineKeyboardButton("🗑 Hapus Expired",  callback_data="ogh_del_expired"),
         InlineKeyboardButton("🗑 Hapus Semua",    callback_data="ogh_del_all")],
        [InlineKeyboardButton("🔙 Kembali",        callback_data="back_main")],
    ])

def ziv_keyboard():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("➕ Buat Akun",     callback_data="ziv_create"),
         InlineKeyboardButton("➖ Hapus Akun",    callback_data="ziv_delete")],
        [InlineKeyboardButton("📋 List Akun",     callback_data="ziv_list"),
         InlineKeyboardButton("🔎 Cek Akun",      callback_data="ziv_check")],
        [InlineKeyboardButton("🔄 Perpanjang",    callback_data="ziv_renew"),
         InlineKeyboardButton("🔒 Kunci/Buka",    callback_data="ziv_toggle")],
        [InlineKeyboardButton("⚙️ Set MaxLogin",   callback_data="ziv_maxlogin"),
         InlineKeyboardButton("📦 Set Kuota",      callback_data="ziv_setquota")],
        [InlineKeyboardButton("♻️ Reset Kuota",    callback_data="ziv_rquota"),
         InlineKeyboardButton("🔗 Reset Sesi",     callback_data="ziv_rsess")],
        [InlineKeyboardButton("🗑 Hapus Expired",  callback_data="ziv_del_expired"),
         InlineKeyboardButton("🗑 Hapus Semua",    callback_data="ziv_del_all")],
        [InlineKeyboardButton("🔙 Kembali",        callback_data="back_main")],
    ])

def service_keyboard():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("▶ Start OGH",     callback_data="svc_start_ogh"),
         InlineKeyboardButton("⏹ Stop OGH",      callback_data="svc_stop_ogh"),
         InlineKeyboardButton("🔄 Restart OGH",  callback_data="svc_restart_ogh")],
        [InlineKeyboardButton("▶ Start ZivPN",   callback_data="svc_start_ziv"),
         InlineKeyboardButton("⏹ Stop ZivPN",    callback_data="svc_stop_ziv"),
         InlineKeyboardButton("🔄 Restart ZivPN",callback_data="svc_restart_ziv")],
        [InlineKeyboardButton("▶ Start Semua",   callback_data="svc_start_all"),
         InlineKeyboardButton("⏹ Stop Semua",    callback_data="svc_stop_all"),
         InlineKeyboardButton("🔄 Restart Semua",callback_data="svc_restart_all")],
        [InlineKeyboardButton("🔙 Kembali",       callback_data="back_main")],
    ])

def reseller_keyboard():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("➕ Tambah Reseller",callback_data="rs_add"),
         InlineKeyboardButton("➖ Hapus Reseller", callback_data="rs_del")],
        [InlineKeyboardButton("📋 List Reseller",  callback_data="rs_list"),
         InlineKeyboardButton("⚙️ Set Kuota",       callback_data="rs_setquota")],
        [InlineKeyboardButton("🔙 Kembali",         callback_data="back_main")],
    ])

def back_kb(cb):   return InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data=cb)]])
def cancel_kb():   return InlineKeyboardMarkup([[InlineKeyboardButton("❌ Batal",   callback_data="cancel")]])
def confirm_kb(yes_cb, no_cb="back_main"):
    return InlineKeyboardMarkup([[
        InlineKeyboardButton("✅ Ya",  callback_data=yes_cb),
        InlineKeyboardButton("❌ Batal",callback_data=no_cb),
    ]])

# ── conversation states ──
(
    S_OGH_CU, S_OGH_CP, S_OGH_CD, S_OGH_CM, S_OGH_CQ,
    S_OGH_DEL, S_OGH_CHK, S_OGH_RU, S_OGH_RD, S_OGH_TGL,
    S_OGH_MLU, S_OGH_MLV, S_OGH_QU, S_OGH_QV, S_OGH_RQU, S_OGH_RSU,
    S_ZIV_CU, S_ZIV_CP, S_ZIV_CD, S_ZIV_CM, S_ZIV_CQ,
    S_ZIV_DEL, S_ZIV_CHK, S_ZIV_RU, S_ZIV_RD, S_ZIV_TGL,
    S_ZIV_MLU, S_ZIV_MLV, S_ZIV_QU, S_ZIV_QV, S_ZIV_RQU, S_ZIV_RSU,
    S_RS_ID, S_RS_NAME, S_RS_OOGH, S_RS_OZIV, S_RS_DEL,
    S_RS_SQID, S_RS_SQVAL, S_GLOBAL_CHECK,
) = range(39)

# ══════════════════════════════════════════════════════════════════
#  /start  /menu
# ══════════════════════════════════════════════════════════════════
async def start(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    uid  = update.effective_user.id
    name = update.effective_user.first_name
    if bot_cfg().get("maintenance") and not is_admin(uid):
        await update.message.reply_text("🔧 Bot sedang maintenance."); return
    if not is_admin(uid) and not is_reseller(uid):
        await update.message.reply_text(
            f"👋 Halo *{name}*!\n\n⛔ Anda belum memiliki akses.\n"
            "Hubungi admin untuk mendapatkan akses.",
            parse_mode="Markdown"); return
    role = "👑 Admin" if is_admin(uid) else "🏪 Reseller"
    txt = (
        f"```\n"
        f"╔══════════════════════╗\n"
        f"║  🌐 {BOT_NAME}\n"
        f"║  v{VERSION}  [{SYNC_KEY}]\n"
        f"╠══════════════════════╣\n"
        f"║  👤 {name} ({role})\n"
        f"║  🟠 OGH   : {svc_status_label(OGH_SVC)} | {len(read_db(OGH_DB))} akun\n"
        f"║  🟣 ZivPN : {svc_status_label(ZIV_SVC)} | {len(read_db(ZIV_DB))} akun\n"
        f"╚══════════════════════╝\n"
        f"```\nPilih menu di bawah:"
    )
    await update.message.reply_text(txt, parse_mode="Markdown", reply_markup=main_keyboard(uid))

# ══════════════════════════════════════════════════════════════════
#  CALLBACK ROUTER
# ══════════════════════════════════════════════════════════════════
async def handle_callback(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    q    = update.callback_query
    uid  = q.from_user.id
    data = q.data
    await q.answer()

    if not is_admin(uid) and not is_reseller(uid):
        await q.edit_message_text("⛔ Akses ditolak."); return

    # ── Back to main ──
    if data == "back_main":
        txt = (
            f"*{BOT_NAME}* v{VERSION}\n\n"
            f"🟠 OGH   : {svc_status_label(OGH_SVC)} | {len(read_db(OGH_DB))} akun\n"
            f"🟣 ZivPN : {svc_status_label(ZIV_SVC)} | {len(read_db(ZIV_DB))} akun\n\n"
            "Pilih menu:"
        )
        await q.edit_message_text(txt, parse_mode="Markdown", reply_markup=main_keyboard(uid))

    elif data == "menu_ogh":
        await q.edit_message_text("🟠 *OGH-UDP Manager*", parse_mode="Markdown", reply_markup=ogh_keyboard())

    elif data == "menu_ziv":
        await q.edit_message_text("🟣 *ZivPN-UDP Manager*", parse_mode="Markdown", reply_markup=ziv_keyboard())

    elif data == "menu_service" and is_admin(uid):
        await q.edit_message_text(
            f"⚙️ *Service Manager*\n\n"
            f"🟠 OGH   : {svc_status_label(OGH_SVC)}\n"
            f"🟣 ZivPN : {svc_status_label(ZIV_SVC)}",
            parse_mode="Markdown", reply_markup=service_keyboard()
        )

    elif data == "menu_reseller" and is_admin(uid):
        rs  = get_resellers()
        txt = f"👥 *Manajemen Reseller* — {len(rs)} reseller\n\nPilih aksi:"
        await q.edit_message_text(txt, parse_mode="Markdown", reply_markup=reseller_keyboard())

    elif data == "menu_vps":
        v = get_vps_info()
        txt = (
            f"📡 *Info VPS*\n\n"
            f"`IP      :` `{v['ip']}`\n"
            f"`OS      :` {v['os']}\n"
            f"`Kernel  :` {v['kernel']}\n"
            f"`Uptime  :` {v['uptime']}\n"
            f"`CPU     :` {v['cpu']}\n"
            f"`RAM     :` {v['ram']}\n"
            f"`Disk    :` {v['disk']}\n\n"
            f"🟠 OGH Port  : `{get_ogh_port()}`  {svc_status_label(OGH_SVC)}\n"
            f"🟣 ZivPN Port: `{get_ziv_port()}`  {svc_status_label(ZIV_SVC)}"
        )
        await q.edit_message_text(txt, parse_mode="Markdown", reply_markup=back_kb("back_main"))

    elif data == "menu_stats":
        today = datetime.now().strftime('%Y-%m-%d')
        def s(users, qd):
            a = sum(1 for u in users if u['exp'] >= today and u['status'] == 'active')
            e = sum(1 for u in users if u['exp'] < today)
            l = sum(1 for u in users if u['status'] == 'locked')
            t = sum(get_used(qd, u['user']) for u in users)
            return a, e, l, t
        ou = read_db(OGH_DB); zu = read_db(ZIV_DB)
        oa,oe,ol,ot = s(ou, OGH_QUOTA_D); za,ze,zl,zt = s(zu, ZIV_QUOTA_D)
        txt = (
            f"📊 *Statistik Akun*\n\n"
            f"🟠 *OGH-UDP* ({len(ou)} total)\n"
            f"  ✅ Aktif: {oa}  ❌ Expired: {oe}  🔒 Locked: {ol}\n"
            f"  📈 Traffic: {bytes_human(ot)}\n\n"
            f"🟣 *ZivPN-UDP* ({len(zu)} total)\n"
            f"  ✅ Aktif: {za}  ❌ Expired: {ze}  🔒 Locked: {zl}\n"
            f"  📈 Traffic: {bytes_human(zt)}"
        )
        await q.edit_message_text(txt, parse_mode="Markdown", reply_markup=back_kb("back_main"))

    elif data == "menu_soon":
        lines = ["⏰ *Akan Expired (7 hari)*\n\n🟠 OGH-UDP:"]
        for u, d in get_soon_expired(OGH_DB):
            lines.append(f"  • `{u['user']}` — {u['exp']} ({d}h)")
        lines.append("\n🟣 ZivPN-UDP:")
        for u, d in get_soon_expired(ZIV_DB):
            lines.append(f"  • `{u['user']}` — {u['exp']} ({d}h)")
        if len(lines) <= 3: lines.append("  Tidak ada.")
        await q.edit_message_text("\n".join(lines), parse_mode="Markdown", reply_markup=back_kb("back_main"))

    elif data == "menu_backup" and is_admin(uid):
        ts = datetime.now().strftime('%Y%m%d_%H%M%S')
        bk = Path("/root/ogh-backup"); bk.mkdir(exist_ok=True)
        msgs = []
        for src, name in [
            (OGH_DB,       f"ogh_{ts}.db"),
            (ZIV_DB,       f"ziv_{ts}.db"),
            (ZIV_CFG,      f"ziv_cfg_{ts}.json"),
            (RESELLER_DB,  f"resellers_{ts}.json"),
        ]:
            try: shutil.copy(src, bk / name); msgs.append(f"✅ {name}")
            except Exception as e: msgs.append(f"❌ {name}: {e}")
        await q.edit_message_text(
            f"💾 *Backup selesai*\n\n" + "\n".join(msgs) + f"\n\n📁 `/root/ogh-backup/`",
            parse_mode="Markdown", reply_markup=back_kb("back_main")
        )

    elif data == "menu_settings" and is_admin(uid):
        cfg = bot_cfg()
        maint = "🔧 ON" if cfg.get("maintenance") else "✅ OFF"
        kb = InlineKeyboardMarkup([
            [InlineKeyboardButton(
                "🔧 Aktifkan Maintenance" if not cfg.get("maintenance") else "✅ Matikan Maintenance",
                callback_data="toggle_maint"
            )],
            [InlineKeyboardButton("🔙 Kembali", callback_data="back_main")]
        ])
        await q.edit_message_text(
            f"⚙️ *Pengaturan Bot*\n\nMaintenance : {maint}\n"
            f"OGH default hari   : {cfg.get('ogh_default_days',30)}\n"
            f"ZivPN default hari : {cfg.get('ziv_default_days',30)}\n"
            f"OGH MaxLogin def   : {cfg.get('ogh_default_maxlogin',2)}\n"
            f"ZivPN MaxLogin def : {cfg.get('ziv_default_maxlogin',2)}\n\n"
            "Gunakan `/setcfg key value` untuk ubah nilai.",
            parse_mode="Markdown", reply_markup=kb
        )

    elif data == "toggle_maint" and is_admin(uid):
        cfg = bot_cfg(); cfg["maintenance"] = not cfg.get("maintenance", False)
        save_json(BOT_CFG_FILE, cfg)
        await q.edit_message_text(
            f"Maintenance: {'🔧 AKTIF' if cfg['maintenance'] else '✅ NONAKTIF'}",
            reply_markup=back_kb("back_main")
        )

    # ── Service controls ──
    elif data.startswith("svc_") and is_admin(uid):
        parts = data.split("_"); action, target = parts[1], parts[2]
        svc_map = {"ogh": OGH_SVC, "ziv": ZIV_SVC}
        def do(svc):
            if action == "start":   run_cmd(f"systemctl start {svc}")
            elif action == "stop":  run_cmd(f"systemctl stop {svc}")
            elif action == "restart": run_cmd(f"systemctl restart {svc}")
        if target == "all":
            do(OGH_SVC); do(ZIV_SVC)
            msg = f"✅ {action.title()} semua service."
        elif target in svc_map:
            do(svc_map[target])
            msg = f"✅ {action.title()} {target.upper()}: {svc_status_label(svc_map[target])}"
        else: msg = "❌ Target tidak dikenal."
        await q.edit_message_text(msg, reply_markup=back_kb("menu_service"))

    # ── OGH list ──
    elif data == "ogh_list":
        users = read_db(OGH_DB)
        if not users:
            await q.edit_message_text("📋 Belum ada akun OGH-UDP.", reply_markup=back_kb("menu_ogh")); return
        lines = [f"📋 *OGH-UDP* ({len(users)} akun)\n"]
        lines += [fmt_account_short(u, OGH_QUOTA_D, OGH_SESS_D) for u in users]
        await q.edit_message_text("\n".join(lines), parse_mode="Markdown", reply_markup=back_kb("menu_ogh"))

    elif data == "ziv_list":
        users = read_db(ZIV_DB)
        if not users:
            await q.edit_message_text("📋 Belum ada akun ZivPN.", reply_markup=back_kb("menu_ziv")); return
        lines = [f"📋 *ZivPN-UDP* ({len(users)} akun)\n"]
        lines += [fmt_account_short(u, ZIV_QUOTA_D, ZIV_SESS_D) for u in users]
        await q.edit_message_text("\n".join(lines), parse_mode="Markdown", reply_markup=back_kb("menu_ziv"))

    # ── Hapus expired / semua ──
    elif data == "ogh_del_expired" and is_admin(uid):
        exp = get_expired_users(OGH_DB)
        for u in exp: delete_user_db(OGH_DB, OGH_QUOTA_D, OGH_SESS_D, u['user'])
        await q.edit_message_text(f"🗑 {len(exp)} akun expired OGH dihapus.", reply_markup=back_kb("menu_ogh"))

    elif data == "ziv_del_expired" and is_admin(uid):
        exp = get_expired_users(ZIV_DB)
        for u in exp: delete_user_db(ZIV_DB, ZIV_QUOTA_D, ZIV_SESS_D, u['user'])
        await q.edit_message_text(f"🗑 {len(exp)} akun expired ZivPN dihapus.", reply_markup=back_kb("menu_ziv"))

    elif data == "ogh_del_all" and is_admin(uid):
        await q.edit_message_text("⚠️ Yakin hapus *SEMUA* akun OGH?", parse_mode="Markdown",
                                  reply_markup=confirm_kb("ogh_del_all_ok", "menu_ogh"))
    elif data == "ogh_del_all_ok" and is_admin(uid):
        open(OGH_DB, 'w').close()
        await q.edit_message_text("✅ Semua akun OGH dihapus.", reply_markup=back_kb("menu_ogh"))

    elif data == "ziv_del_all" and is_admin(uid):
        await q.edit_message_text("⚠️ Yakin hapus *SEMUA* akun ZivPN?", parse_mode="Markdown",
                                  reply_markup=confirm_kb("ziv_del_all_ok", "menu_ziv"))
    elif data == "ziv_del_all_ok" and is_admin(uid):
        open(ZIV_DB, 'w').close()
        await q.edit_message_text("✅ Semua akun ZivPN dihapus.", reply_markup=back_kb("menu_ziv"))

    # ── Reseller list ──
    elif data == "rs_list" and is_admin(uid):
        rs = get_resellers()
        if not rs:
            await q.edit_message_text("👥 Belum ada reseller.", reply_markup=back_kb("menu_reseller")); return
        lines = ["👥 *List Reseller*\n"]
        for rid, r in rs.items():
            lines.append(
                f"• `{rid}` | {r.get('name','?')} | Bergabung: {r.get('added','?')}\n"
                f"  🟠 OGH: {r.get('ogh_used',0)}/{r.get('ogh_quota',0) or '∞'}  "
                f"🟣 ZivPN: {r.get('ziv_used',0)}/{r.get('ziv_quota',0) or '∞'}"
            )
        await q.edit_message_text("\n".join(lines), parse_mode="Markdown", reply_markup=back_kb("menu_reseller"))

    elif data == "cancel":
        ctx.user_data.clear()
        await q.edit_message_text("❌ Dibatalkan.", reply_markup=back_kb("back_main"))
        return ConversationHandler.END

    # ── Conversation entry triggers ──
    TRIGGERS = {
        "ogh_create":  (S_OGH_CU,  "menu_ogh",  "🟠 *Buat Akun OGH-UDP*\n\nKirim username:"),
        "ogh_delete":  (S_OGH_DEL, "menu_ogh",  "🟠 *Hapus Akun OGH-UDP*\n\nKirim username:"),
        "ogh_check":   (S_OGH_CHK, "menu_ogh",  "🟠 *Cek Akun OGH*\n\nKirim username:"),
        "prompt_check":(S_GLOBAL_CHECK,"back_main","🔎 *Cek Akun (OGH/ZivPN)*\n\nKirim username:"),
        "ogh_renew":   (S_OGH_RU,  "menu_ogh",  "🟠 *Perpanjang Akun OGH*\n\nKirim username:"),
        "ogh_toggle":  (S_OGH_TGL, "menu_ogh",  "🟠 *Kunci/Buka Akun OGH*\n\nKirim username:"),
        "ogh_maxlogin":(S_OGH_MLU, "menu_ogh",  "🟠 *Set MaxLogin OGH*\n\nKirim username:"),
        "ogh_setquota":(S_OGH_QU,  "menu_ogh",  "🟠 *Set Kuota OGH*\n\nKirim username:"),
        "ogh_rquota":  (S_OGH_RQU, "menu_ogh",  "🟠 *Reset Kuota OGH*\n\nKirim username atau `all`:"),
        "ogh_rsess":   (S_OGH_RSU, "menu_ogh",  "🟠 *Reset Sesi OGH*\n\nKirim username atau `all`:"),
        "ziv_create":  (S_ZIV_CU,  "menu_ziv",  "🟣 *Buat Akun ZivPN*\n\nKirim username:"),
        "ziv_delete":  (S_ZIV_DEL, "menu_ziv",  "🟣 *Hapus Akun ZivPN*\n\nKirim username:"),
        "ziv_check":   (S_ZIV_CHK, "menu_ziv",  "🟣 *Cek Akun ZivPN*\n\nKirim username:"),
        "ziv_renew":   (S_ZIV_RU,  "menu_ziv",  "🟣 *Perpanjang Akun ZivPN*\n\nKirim username:"),
        "ziv_toggle":  (S_ZIV_TGL, "menu_ziv",  "🟣 *Kunci/Buka Akun ZivPN*\n\nKirim username:"),
        "ziv_maxlogin":(S_ZIV_MLU, "menu_ziv",  "🟣 *Set MaxLogin ZivPN*\n\nKirim username:"),
        "ziv_setquota":(S_ZIV_QU,  "menu_ziv",  "🟣 *Set Kuota ZivPN*\n\nKirim username:"),
        "ziv_rquota":  (S_ZIV_RQU, "menu_ziv",  "🟣 *Reset Kuota ZivPN*\n\nKirim username atau `all`:"),
        "ziv_rsess":   (S_ZIV_RSU, "menu_ziv",  "🟣 *Reset Sesi ZivPN*\n\nKirim username atau `all`:"),
        "rs_add":      (S_RS_ID,   "menu_reseller","👥 *Tambah Reseller*\n\nKirim Telegram ID:"),
        "rs_del":      (S_RS_DEL,  "menu_reseller","👥 *Hapus Reseller*\n\nKirim Telegram ID:"),
        "rs_setquota": (S_RS_SQID, "menu_reseller","👥 *Set Kuota Reseller*\n\nKirim Telegram ID:"),
    }
    if data in TRIGGERS:
        state, back_cb, prompt = TRIGGERS[data]
        ctx.user_data['back_cb'] = back_cb
        await q.edit_message_text(prompt, parse_mode="Markdown", reply_markup=cancel_kb())
        return state

# ══════════════════════════════════════════════════════════════════
#  CONVERSATION HANDLERS
# ══════════════════════════════════════════════════════════════════
# ── OGH Create (5 steps) ──
async def ogh_cu(u, ctx):
    txt = u.message.text.strip()
    if not txt.replace('_','').isalnum():
        await u.message.reply_text("❌ Username tidak valid."); return S_OGH_CU
    if user_exists(OGH_DB, txt):
        await u.message.reply_text(f"❌ `{txt}` sudah ada.", parse_mode="Markdown"); return S_OGH_CU
    ctx.user_data['nu'] = txt
    await u.message.reply_text(f"✅ `{txt}`\n\nKirim password:", parse_mode="Markdown", reply_markup=cancel_kb())
    return S_OGH_CP

async def ogh_cp(u, ctx):
    ctx.user_data['np'] = u.message.text.strip()
    cfg = bot_cfg()
    await u.message.reply_text(f"✅ Pass ok.\n\nExpired hari [def:{cfg.get('ogh_default_days',30)}]:", reply_markup=cancel_kb())
    return S_OGH_CD

async def ogh_cd(u, ctx):
    t = u.message.text.strip(); cfg = bot_cfg()
    ctx.user_data['nd'] = int(t) if t.isdigit() else cfg.get('ogh_default_days', 30)
    await u.message.reply_text(f"✅ {ctx.user_data['nd']} hari.\n\nMaxLogin [0=∞, def:{cfg.get('ogh_default_maxlogin',2)}]:", reply_markup=cancel_kb())
    return S_OGH_CM

async def ogh_cm(u, ctx):
    t = u.message.text.strip(); cfg = bot_cfg()
    ctx.user_data['nm'] = int(t) if t.isdigit() else cfg.get('ogh_default_maxlogin', 2)
    await u.message.reply_text(f"✅ MaxLogin:{ctx.user_data['nm']}.\n\nKuota [cth:10GB, 0=∞]:", reply_markup=cancel_kb())
    return S_OGH_CQ

async def ogh_cq(u, ctx):
    uid = u.effective_user.id
    t   = u.message.text.strip()
    qb  = 0 if t in ('0','unlimited') else human_bytes(t)
    if not is_admin(uid):
        ok_rs, msg = reseller_can_create(uid, 'ogh')
        if not ok_rs: await u.message.reply_text(f"❌ {msg}"); return ConversationHandler.END
    row = create_user_db(OGH_DB, OGH_QUOTA_D, OGH_SESS_D,
                         ctx.user_data['nu'], ctx.user_data['np'],
                         ctx.user_data['nd'], ctx.user_data['nm'], qb)
    if not is_admin(uid): reseller_add_usage(uid, 'ogh')
    txt = fmt_account(row, get_public_ip(), get_ogh_port(), OGH_QUOTA_D, OGH_SESS_D, "OGH-UDP")
    await u.message.reply_text(f"✅ *Akun OGH Dibuat!*\n{txt}", parse_mode="Markdown", reply_markup=back_kb("menu_ogh"))
    ctx.user_data.clear(); return ConversationHandler.END

# ── ZivPN Create (5 steps) ──
async def ziv_cu(u, ctx):
    txt = u.message.text.strip()
    if not txt.replace('_','').isalnum():
        await u.message.reply_text("❌ Username tidak valid."); return S_ZIV_CU
    if user_exists(ZIV_DB, txt):
        await u.message.reply_text(f"❌ `{txt}` sudah ada.", parse_mode="Markdown"); return S_ZIV_CU
    ctx.user_data['nu'] = txt
    await u.message.reply_text(f"✅ `{txt}`\n\nKirim password:", parse_mode="Markdown", reply_markup=cancel_kb())
    return S_ZIV_CP

async def ziv_cp(u, ctx):
    ctx.user_data['np'] = u.message.text.strip()
    cfg = bot_cfg()
    await u.message.reply_text(f"✅ Pass ok.\n\nExpired hari [def:{cfg.get('ziv_default_days',30)}]:", reply_markup=cancel_kb())
    return S_ZIV_CD

async def ziv_cd(u, ctx):
    t = u.message.text.strip(); cfg = bot_cfg()
    ctx.user_data['nd'] = int(t) if t.isdigit() else cfg.get('ziv_default_days', 30)
    await u.message.reply_text(f"✅ {ctx.user_data['nd']} hari.\n\nMaxLogin [0=∞, def:{cfg.get('ziv_default_maxlogin',2)}]:", reply_markup=cancel_kb())
    return S_ZIV_CM

async def ziv_cm(u, ctx):
    t = u.message.text.strip(); cfg = bot_cfg()
    ctx.user_data['nm'] = int(t) if t.isdigit() else cfg.get('ziv_default_maxlogin', 2)
    await u.message.reply_text(f"✅ MaxLogin:{ctx.user_data['nm']}.\n\nKuota [cth:10GB, 0=∞]:", reply_markup=cancel_kb())
    return S_ZIV_CQ

async def ziv_cq(u, ctx):
    uid = u.effective_user.id
    t   = u.message.text.strip()
    qb  = 0 if t in ('0','unlimited') else human_bytes(t)
    if not is_admin(uid):
        ok_rs, msg = reseller_can_create(uid, 'ziv')
        if not ok_rs: await u.message.reply_text(f"❌ {msg}"); return ConversationHandler.END
    row = create_user_db(ZIV_DB, ZIV_QUOTA_D, ZIV_SESS_D,
                         ctx.user_data['nu'], ctx.user_data['np'],
                         ctx.user_data['nd'], ctx.user_data['nm'], qb)
    if not is_admin(uid): reseller_add_usage(uid, 'ziv')
    ip   = get_public_ip(); port = get_ziv_port()
    txt  = fmt_account(row, ip, port, ZIV_QUOTA_D, ZIV_SESS_D, "ZivPN-UDP")
    txt += f"\n\n🔗 `zivpn://{row['user']}:{row['pass']}@{ip}:{port}`"
    await u.message.reply_text(f"✅ *Akun ZivPN Dibuat!*\n{txt}", parse_mode="Markdown", reply_markup=back_kb("menu_ziv"))
    ctx.user_data.clear(); return ConversationHandler.END

# ── Generic 1-input helpers ──
async def _del(db, qd, sd, lbl, back, uid_fn=None):
    async def h(u, ctx):
        name = u.message.text.strip()
        uid  = u.effective_user.id
        if not user_exists(db, name):
            await u.message.reply_text(f"❌ `{name}` tidak ditemukan.", parse_mode="Markdown")
            return ConversationHandler.END
        delete_user_db(db, qd, sd, name)
        if uid_fn and not is_admin(uid): uid_fn(uid, lbl)
        await u.message.reply_text(f"✅ Akun `{name}` dihapus.", parse_mode="Markdown", reply_markup=back_kb(back))
        return ConversationHandler.END
    return h

async def ogh_del(u, ctx):
    return await (await _del(OGH_DB, OGH_QUOTA_D, OGH_SESS_D, 'ogh', 'menu_ogh',
                             lambda uid, s: reseller_remove_usage(uid, s)))(u, ctx)

async def ziv_del(u, ctx):
    return await (await _del(ZIV_DB, ZIV_QUOTA_D, ZIV_SESS_D, 'ziv', 'menu_ziv',
                             lambda uid, s: reseller_remove_usage(uid, s)))(u, ctx)

async def ogh_chk(u, ctx):
    name = u.message.text.strip()
    row  = find_user(OGH_DB, name)
    if not row:
        await u.message.reply_text(f"❌ `{name}` tidak ditemukan di OGH.", parse_mode="Markdown")
        return ConversationHandler.END
    txt = fmt_account(row, get_public_ip(), get_ogh_port(), OGH_QUOTA_D, OGH_SESS_D, "OGH-UDP")
    await u.message.reply_text(txt, parse_mode="Markdown", reply_markup=back_kb("menu_ogh"))
    return ConversationHandler.END

async def ziv_chk(u, ctx):
    name = u.message.text.strip()
    row  = find_user(ZIV_DB, name)
    if not row:
        await u.message.reply_text(f"❌ `{name}` tidak ditemukan di ZivPN.", parse_mode="Markdown")
        return ConversationHandler.END
    txt = fmt_account(row, get_public_ip(), get_ziv_port(), ZIV_QUOTA_D, ZIV_SESS_D, "ZivPN-UDP")
    await u.message.reply_text(txt, parse_mode="Markdown", reply_markup=back_kb("menu_ziv"))
    return ConversationHandler.END

async def global_check(u, ctx):
    name = u.message.text.strip()
    row  = find_user(OGH_DB, name)
    if row:
        txt = fmt_account(row, get_public_ip(), get_ogh_port(), OGH_QUOTA_D, OGH_SESS_D, "OGH-UDP")
        await u.message.reply_text(txt, parse_mode="Markdown", reply_markup=back_kb("back_main"))
        return ConversationHandler.END
    row = find_user(ZIV_DB, name)
    if row:
        txt = fmt_account(row, get_public_ip(), get_ziv_port(), ZIV_QUOTA_D, ZIV_SESS_D, "ZivPN-UDP")
        await u.message.reply_text(txt, parse_mode="Markdown", reply_markup=back_kb("back_main"))
        return ConversationHandler.END
    await u.message.reply_text(f"❌ `{name}` tidak ditemukan di OGH maupun ZivPN.", parse_mode="Markdown")
    return ConversationHandler.END

def _mk_renew(db, back):
    async def step1(u, ctx):
        name = u.message.text.strip()
        if not user_exists(db, name):
            await u.message.reply_text(f"❌ `{name}` tidak ditemukan.", parse_mode="Markdown")
            return ConversationHandler.END
        ctx.user_data['rn'] = name
        row = find_user(db, name)
        await u.message.reply_text(f"Expired: `{row['exp']}`\n\nTambah berapa hari:", parse_mode="Markdown", reply_markup=cancel_kb())
        return S_OGH_RD if back == 'menu_ogh' else S_ZIV_RD
    return step1

def _mk_renew_days(db, back):
    async def step2(u, ctx):
        t = u.message.text.strip()
        if not t.isdigit(): await u.message.reply_text("❌ Kirim angka."); return S_OGH_RD if back == 'menu_ogh' else S_ZIV_RD
        new_exp = renew_user_db(db, ctx.user_data['rn'], int(t))
        await u.message.reply_text(f"✅ Diperpanjang hingga `{new_exp}` (+{t} hari).", parse_mode="Markdown", reply_markup=back_kb(back))
        return ConversationHandler.END
    return step2

ogh_ru = _mk_renew(OGH_DB, 'menu_ogh');  ogh_rd = _mk_renew_days(OGH_DB, 'menu_ogh')
ziv_ru = _mk_renew(ZIV_DB, 'menu_ziv');  ziv_rd = _mk_renew_days(ZIV_DB, 'menu_ziv')

def _mk_toggle(db, back):
    async def h(u, ctx):
        name = u.message.text.strip()
        row  = find_user(db, name)
        if not row: await u.message.reply_text(f"❌ `{name}` tidak ditemukan.", parse_mode="Markdown"); return ConversationHandler.END
        new_st = 'active' if row['status'] == 'locked' else 'locked'
        update_user_field(db, name, status=new_st)
        l = "🔓 Dibuka" if new_st == 'active' else "🔒 Dikunci"
        await u.message.reply_text(f"✅ `{name}` {l}.", parse_mode="Markdown", reply_markup=back_kb(back))
        return ConversationHandler.END
    return h

ogh_tgl = _mk_toggle(OGH_DB, 'menu_ogh')
ziv_tgl = _mk_toggle(ZIV_DB, 'menu_ziv')

def _mk_ml_user(db, back, nxt):
    async def h(u, ctx):
        name = u.message.text.strip()
        row  = find_user(db, name)
        if not row: await u.message.reply_text(f"❌ `{name}` tidak ditemukan.", parse_mode="Markdown"); return ConversationHandler.END
        ctx.user_data['mlu'] = name
        await u.message.reply_text(f"MaxLogin saat ini: `{row['maxlogin']}`\n\nKirim nilai baru (0=∞):", parse_mode="Markdown", reply_markup=cancel_kb())
        return nxt
    return h

def _mk_ml_val(db, back):
    async def h(u, ctx):
        t = u.message.text.strip()
        if not t.isdigit(): await u.message.reply_text("❌ Kirim angka."); return S_OGH_MLV if back == 'menu_ogh' else S_ZIV_MLV
        update_user_field(db, ctx.user_data['mlu'], maxlogin=t)
        l = "Unlimited" if t == '0' else f"{t} device"
        await u.message.reply_text(f"✅ MaxLogin `{ctx.user_data['mlu']}` = {l}.", parse_mode="Markdown", reply_markup=back_kb(back))
        return ConversationHandler.END
    return h

ogh_mlu = _mk_ml_user(OGH_DB, 'menu_ogh', S_OGH_MLV); ogh_mlv = _mk_ml_val(OGH_DB, 'menu_ogh')
ziv_mlu = _mk_ml_user(ZIV_DB, 'menu_ziv', S_ZIV_MLV); ziv_mlv = _mk_ml_val(ZIV_DB, 'menu_ziv')

def _mk_qu_user(db, back, nxt):
    async def h(u, ctx):
        name = u.message.text.strip()
        row  = find_user(db, name)
        if not row: await u.message.reply_text(f"❌ `{name}` tidak ditemukan.", parse_mode="Markdown"); return ConversationHandler.END
        ctx.user_data['quu'] = name
        q = int(row['quota']); ql = "Unlimited" if q == 0 else bytes_human(q)
        await u.message.reply_text(f"Kuota saat ini: `{ql}`\n\nKirim kuota baru (cth:10GB, 0=∞):", parse_mode="Markdown", reply_markup=cancel_kb())
        return nxt
    return h

def _mk_qu_val(db, back):
    async def h(u, ctx):
        t = u.message.text.strip()
        qb = 0 if t in ('0','unlimited') else human_bytes(t)
        update_user_field(db, ctx.user_data['quu'], quota=str(qb))
        l = "Unlimited" if qb == 0 else bytes_human(qb)
        await u.message.reply_text(f"✅ Kuota `{ctx.user_data['quu']}` = {l}.", parse_mode="Markdown", reply_markup=back_kb(back))
        return ConversationHandler.END
    return h

ogh_quu = _mk_qu_user(OGH_DB, 'menu_ogh', S_OGH_QV); ogh_quv = _mk_qu_val(OGH_DB, 'menu_ogh')
ziv_quu = _mk_qu_user(ZIV_DB, 'menu_ziv', S_ZIV_QV); ziv_quv = _mk_qu_val(ZIV_DB, 'menu_ziv')

def _mk_rquota(qd, db, back):
    async def h(u, ctx):
        name = u.message.text.strip()
        if name == 'all':
            for row in read_db(db):
                (Path(qd) / f"{row['user']}.quota").write_text("0")
            await u.message.reply_text("✅ Semua kuota direset.", reply_markup=back_kb(back))
        elif user_exists(db, name):
            (Path(qd) / f"{name}.quota").write_text("0")
            await u.message.reply_text(f"✅ Kuota `{name}` direset.", parse_mode="Markdown", reply_markup=back_kb(back))
        else:
            await u.message.reply_text("❌ User tidak ditemukan.")
        return ConversationHandler.END
    return h

def _mk_rsess(sd, db, back):
    async def h(u, ctx):
        name = u.message.text.strip()
        if name == 'all':
            for row in read_db(db):
                (Path(sd) / f"{row['user']}.sess").write_text("0")
            await u.message.reply_text("✅ Semua sesi direset.", reply_markup=back_kb(back))
        elif user_exists(db, name):
            (Path(sd) / f"{name}.sess").write_text("0")
            await u.message.reply_text(f"✅ Sesi `{name}` direset.", parse_mode="Markdown", reply_markup=back_kb(back))
        else:
            await u.message.reply_text("❌ User tidak ditemukan.")
        return ConversationHandler.END
    return h

ogh_rqu = _mk_rquota(OGH_QUOTA_D, OGH_DB, 'menu_ogh')
ziv_rqu = _mk_rquota(ZIV_QUOTA_D, ZIV_DB, 'menu_ziv')
ogh_rsu = _mk_rsess(OGH_SESS_D, OGH_DB, 'menu_ogh')
ziv_rsu = _mk_rsess(ZIV_SESS_D, ZIV_DB, 'menu_ziv')

# ── Reseller conversations ──
async def rs_id(u, ctx):
    t = u.message.text.strip()
    if not t.isdigit(): await u.message.reply_text("❌ Kirim angka ID."); return S_RS_ID
    ctx.user_data['rs_id'] = t
    await u.message.reply_text("Nama reseller:", reply_markup=cancel_kb()); return S_RS_NAME

async def rs_name(u, ctx):
    ctx.user_data['rs_name'] = u.message.text.strip()
    await u.message.reply_text("Kuota akun OGH (0=∞):", reply_markup=cancel_kb()); return S_RS_OOGH

async def rs_oq(u, ctx):
    t = u.message.text.strip()
    ctx.user_data['rs_oq'] = int(t) if t.isdigit() else 0
    await u.message.reply_text("Kuota akun ZivPN (0=∞):", reply_markup=cancel_kb()); return S_RS_OZIV

async def rs_zq(u, ctx):
    t   = u.message.text.strip()
    rid = ctx.user_data['rs_id']; name = ctx.user_data['rs_name']
    oq  = ctx.user_data['rs_oq']; zq   = int(t) if t.isdigit() else 0
    rs  = get_resellers()
    rs[rid] = {"name": name, "added": datetime.now().strftime('%Y-%m-%d'),
               "ogh_quota": oq, "ogh_used": 0, "ziv_quota": zq, "ziv_used": 0}
    save_json(RESELLER_DB, rs)
    await u.message.reply_text(
        f"✅ *Reseller Ditambahkan!*\n\nID: `{rid}`\nNama: {name}\n"
        f"Kuota OGH: {oq or '∞'}  ZivPN: {zq or '∞'}",
        parse_mode="Markdown", reply_markup=back_kb("menu_reseller")
    )
    ctx.user_data.clear(); return ConversationHandler.END

async def rs_del_h(u, ctx):
    rid = u.message.text.strip()
    rs  = get_resellers()
    if rid in rs:
        del rs[rid]; save_json(RESELLER_DB, rs)
        await u.message.reply_text(f"✅ Reseller `{rid}` dihapus.", parse_mode="Markdown", reply_markup=back_kb("menu_reseller"))
    else:
        await u.message.reply_text("❌ Tidak ditemukan.")
    return ConversationHandler.END

async def rs_sqid(u, ctx):
    rid = u.message.text.strip()
    rs  = get_resellers()
    if rid not in rs:
        await u.message.reply_text("❌ Tidak ditemukan."); return ConversationHandler.END
    ctx.user_data['rs_sqid'] = rid
    r   = rs[rid]
    await u.message.reply_text(
        f"Reseller: {r['name']}\nOGH: {r.get('ogh_quota',0)}  ZivPN: {r.get('ziv_quota',0)}\n\n"
        "Kirim `ogh:N` atau `ziv:N`:",
        parse_mode="Markdown", reply_markup=cancel_kb()
    )
    return S_RS_SQVAL

async def rs_sqval(u, ctx):
    txt = u.message.text.strip().lower(); rid = ctx.user_data['rs_sqid']
    if ':' not in txt: await u.message.reply_text("❌ Format: `ogh:50`", parse_mode="Markdown"); return S_RS_SQVAL
    svc, val = txt.split(':', 1)
    if not val.isdigit() or svc not in ('ogh','ziv'):
        await u.message.reply_text("❌ Format salah."); return S_RS_SQVAL
    rs = get_resellers(); rs[rid][f"{svc}_quota"] = int(val); save_json(RESELLER_DB, rs)
    await u.message.reply_text(f"✅ Kuota {svc.upper()} reseller `{rid}` = {val or '∞'}.",
                               parse_mode="Markdown", reply_markup=back_kb("menu_reseller"))
    return ConversationHandler.END

async def conv_cancel(u, ctx):
    ctx.user_data.clear()
    await u.message.reply_text("❌ Dibatalkan.", reply_markup=back_kb("back_main"))
    return ConversationHandler.END

# ══════════════════════════════════════════════════════════════════
#  COMMANDS
# ══════════════════════════════════════════════════════════════════
async def cmd_myid(u, ctx):
    uid = u.effective_user.id
    await u.message.reply_text(
        f"👤 Nama : {u.effective_user.first_name}\n🆔 ID   : `{uid}`\n"
        f"🔑 Role : {'👑 Admin' if is_admin(uid) else ('🏪 Reseller' if is_reseller(uid) else '👤 User')}",
        parse_mode="Markdown"
    )

@admin_only
async def cmd_soon(u, ctx):
    lines = ["⏰ *Akan Expired (7 hari)*\n\n🟠 OGH:"]
    for usr, d in get_soon_expired(OGH_DB):
        lines.append(f"  • `{usr['user']}` — {usr['exp']} ({d}h)")
    lines.append("\n🟣 ZivPN:")
    for usr, d in get_soon_expired(ZIV_DB):
        lines.append(f"  • `{usr['user']}` — {usr['exp']} ({d}h)")
    if len(lines) <= 3: lines.append("  Tidak ada.")
    await u.message.reply_text("\n".join(lines), parse_mode="Markdown")

@admin_only
async def cmd_setcfg(u, ctx):
    args = ctx.args
    if len(args) < 2:
        cfg = bot_cfg()
        lines = ["⚙️ *Config Bot*\n"] + [f"`{k}` = `{v}`" for k, v in cfg.items()]
        lines.append("\nGunakan: `/setcfg key value`")
        await u.message.reply_text("\n".join(lines), parse_mode="Markdown"); return
    key, val = args[0], args[1]
    cfg = bot_cfg()
    cfg[key] = True if val == 'true' else (False if val == 'false' else (int(val) if val.isdigit() else val))
    save_json(BOT_CFG_FILE, cfg)
    await u.message.reply_text(f"✅ `{key}` = `{cfg[key]}`", parse_mode="Markdown")

@admin_only
async def cmd_broadcast(u, ctx):
    if not ctx.args: await u.message.reply_text("Gunakan: /broadcast pesan"); return
    msg = " ".join(ctx.args); count = 0
    for rid in get_resellers():
        try:
            await ctx.bot.send_message(int(rid), f"📢 *Broadcast Admin:*\n\n{msg}", parse_mode="Markdown")
            count += 1
        except: pass
    await u.message.reply_text(f"✅ Terkirim ke {count} reseller.")

@admin_only
async def cmd_synccheck(u, ctx):
    await u.message.reply_text(
        f"🔄 *Sync Check*\n\n"
        f"Bot VERSION : `{VERSION}`\n"
        f"SYNC_KEY    : `{SYNC_KEY}`\n\n"
        f"Path OGH DB  : `{OGH_DB}` {'✅' if Path(OGH_DB).exists() else '❌'}\n"
        f"Path ZIV DB  : `{ZIV_DB}` {'✅' if Path(ZIV_DB).exists() else '❌'}\n"
        f"Path ZIV CFG : `{ZIV_CFG}` {'✅' if Path(ZIV_CFG).exists() else '❌'}\n"
        f"Path BOT CFG : `{BOT_CFG_FILE}` {'✅' if Path(BOT_CFG_FILE).exists() else '❌'}\n"
        f"Path RESELLER: `{RESELLER_DB}` {'✅' if Path(RESELLER_DB).exists() else '❌'}\n\n"
        f"OGH Svc : `{OGH_SVC}` — {svc_status_label(OGH_SVC)}\n"
        f"ZIV Svc : `{ZIV_SVC}` — {svc_status_label(ZIV_SVC)}\n"
        f"BOT Svc : `{BOT_SVC}` — {svc_status_label(BOT_SVC)}",
        parse_mode="Markdown"
    )

# ══════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════
def main():
    init_dirs()
    log.info(f"OGH-UDP Bot v{VERSION} [{SYNC_KEY}] starting...")

    app = Application.builder().token(BOT_TOKEN).build()

    conv = ConversationHandler(
        entry_points=[CallbackQueryHandler(handle_callback)],
        states={
            S_OGH_CU:  [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_cu)],
            S_OGH_CP:  [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_cp)],
            S_OGH_CD:  [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_cd)],
            S_OGH_CM:  [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_cm)],
            S_OGH_CQ:  [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_cq)],
            S_OGH_DEL: [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_del)],
            S_OGH_CHK: [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_chk)],
            S_OGH_RU:  [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_ru)],
            S_OGH_RD:  [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_rd)],
            S_OGH_TGL: [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_tgl)],
            S_OGH_MLU: [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_mlu)],
            S_OGH_MLV: [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_mlv)],
            S_OGH_QU:  [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_quu)],
            S_OGH_QV:  [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_quv)],
            S_OGH_RQU: [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_rqu)],
            S_OGH_RSU: [MessageHandler(filters.TEXT & ~filters.COMMAND, ogh_rsu)],
            S_ZIV_CU:  [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_cu)],
            S_ZIV_CP:  [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_cp)],
            S_ZIV_CD:  [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_cd)],
            S_ZIV_CM:  [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_cm)],
            S_ZIV_CQ:  [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_cq)],
            S_ZIV_DEL: [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_del)],
            S_ZIV_CHK: [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_chk)],
            S_ZIV_RU:  [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_ru)],
            S_ZIV_RD:  [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_rd)],
            S_ZIV_TGL: [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_tgl)],
            S_ZIV_MLU: [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_mlu)],
            S_ZIV_MLV: [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_mlv)],
            S_ZIV_QU:  [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_quu)],
            S_ZIV_QV:  [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_quv)],
            S_ZIV_RQU: [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_rqu)],
            S_ZIV_RSU: [MessageHandler(filters.TEXT & ~filters.COMMAND, ziv_rsu)],
            S_RS_ID:   [MessageHandler(filters.TEXT & ~filters.COMMAND, rs_id)],
            S_RS_NAME: [MessageHandler(filters.TEXT & ~filters.COMMAND, rs_name)],
            S_RS_OOGH: [MessageHandler(filters.TEXT & ~filters.COMMAND, rs_oq)],
            S_RS_OZIV: [MessageHandler(filters.TEXT & ~filters.COMMAND, rs_zq)],
            S_RS_DEL:  [MessageHandler(filters.TEXT & ~filters.COMMAND, rs_del_h)],
            S_RS_SQID: [MessageHandler(filters.TEXT & ~filters.COMMAND, rs_sqid)],
            S_RS_SQVAL:[MessageHandler(filters.TEXT & ~filters.COMMAND, rs_sqval)],
            S_GLOBAL_CHECK: [MessageHandler(filters.TEXT & ~filters.COMMAND, global_check)],
        },
        fallbacks=[
            CommandHandler("cancel", conv_cancel),
            CallbackQueryHandler(handle_callback, pattern="^cancel$"),
        ],
        per_user=True, per_chat=False,
    )

    app.add_handler(CommandHandler("start",      start))
    app.add_handler(CommandHandler("menu",       start))
    app.add_handler(CommandHandler("myid",       cmd_myid))
    app.add_handler(CommandHandler("soon",       cmd_soon))
    app.add_handler(CommandHandler("setcfg",     cmd_setcfg))
    app.add_handler(CommandHandler("broadcast",  cmd_broadcast))
    app.add_handler(CommandHandler("sync",       cmd_synccheck))
    app.add_handler(conv)

    log.info("Bot berjalan.")
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    main()
