#!/usr/bin/env python3
# ============================================================
#   OGH-ZIV PREMIUM — Telegram Bot Auto Create Akun
#   Terintegrasi dengan OGH-ZIV Panel (ogh-ziv.sh)
#   Pembayaran via DANA / QRIS — Cek Screenshot Otomatis
#   GitHub: https://github.com/chanelog/Cek-bot
# ============================================================

import os
import re
import json
import logging
import subprocess
import random
import string
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional, Tuple

# ── Telegram Bot Library ─────────────────────────────────────
try:
    from telegram import (
        Update, InlineKeyboardButton, InlineKeyboardMarkup,
        ReplyKeyboardMarkup, KeyboardButton
    )
    from telegram.ext import (
        ApplicationBuilder, CommandHandler, MessageHandler,
        CallbackQueryHandler, ContextTypes, filters,
        ConversationHandler
    )
except ImportError:
    print("Install dulu: pip3 install python-telegram-bot --break-system-packages")
    exit(1)

# ── OCR Library untuk cek screenshot ─────────────────────────
try:
    from PIL import Image
    import pytesseract
    OCR_AVAILABLE = True
except ImportError:
    OCR_AVAILABLE = False
    print("[WARN] pytesseract/Pillow tidak tersedia. OCR tidak aktif.")

# ============================================================
#  KONFIGURASI — Lokasi file
# ============================================================
CONFIG_FILE = "/etc/zivpn/bot_store.conf"
USERS_DB    = "/etc/zivpn/users.db"
DOMAIN_CONF = "/etc/zivpn/domain.conf"
BOT_CONF    = "/etc/zivpn/bot.conf"
MLDB        = "/etc/zivpn/maxlogin.db"
QRIS_IMG    = "/etc/zivpn/qris.jpg"   # Gambar QRIS (opsional)

# Paket berbayar
PAKET = {
    "1": {"nama": "3 Hari",  "hari": 3,  "harga": 3000,  "kuota": 0, "maxlogin": 2},
    "2": {"nama": "15 Hari", "hari": 15, "harga": 6000,  "kuota": 0, "maxlogin": 2},
    "3": {"nama": "30 Hari", "hari": 30, "harga": 10000, "kuota": 0, "maxlogin": 2},
}

TRIAL_MENIT = 120

# ── Logger ───────────────────────────────────────────────────
logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    level=logging.INFO
)
log = logging.getLogger(__name__)

# ============================================================
#  LOAD & SAVE KONFIGURASI
# ============================================================
def load_config() -> dict:
    cfg = {
        "BOT_TOKEN":    "",
        "ADMIN_IDS":    [],
        "DANA_NUMBER":  "08xxxxxxxxxx",
        "DANA_NAME":    "Nama Pemilik",
        "QRIS_ENABLED": "0",
        "BRAND":        "OGH-ZIV",
        "ADMIN_TG":     "@admin",
    }
    if Path(CONFIG_FILE).exists():
        for line in Path(CONFIG_FILE).read_text().splitlines():
            if "=" in line and not line.strip().startswith("#"):
                k, _, v = line.partition("=")
                k = k.strip(); v = v.strip().strip('"').strip("'")
                if k == "BOT_TOKEN":    cfg["BOT_TOKEN"]    = v
                if k == "ADMIN_IDS":
                    try: cfg["ADMIN_IDS"] = [int(x) for x in v.split(",") if x.strip().isdigit()]
                    except: pass
                if k == "DANA_NUMBER":  cfg["DANA_NUMBER"]  = v
                if k == "DANA_NAME":    cfg["DANA_NAME"]    = v
                if k == "QRIS_ENABLED": cfg["QRIS_ENABLED"] = v
                if k == "BRAND":        cfg["BRAND"]        = v
                if k == "ADMIN_TG":     cfg["ADMIN_TG"]     = v
    # Fallback token
    if not cfg["BOT_TOKEN"] and Path(BOT_CONF).exists():
        for line in Path(BOT_CONF).read_text().splitlines():
            if line.startswith("BOT_TOKEN="):
                cfg["BOT_TOKEN"] = line.split("=", 1)[1].strip()
                break
    return cfg

CFG = load_config()

def save_config_key(key: str, value: str):
    """Update satu key di config file dan langsung refresh CFG global."""
    global CFG
    p = Path(CONFIG_FILE)
    p.parent.mkdir(parents=True, exist_ok=True)
    lines  = p.read_text().splitlines() if p.exists() else []
    found  = False
    result = []
    for line in lines:
        if line.strip().startswith(f"{key}=") or line.strip().startswith(f"{key} ="):
            result.append(f"{key}={value}")
            found = True
        else:
            result.append(line)
    if not found:
        result.append(f"{key}={value}")
    p.write_text("\n".join(result) + "\n")
    # Sync ke CFG
    if key == "ADMIN_IDS":
        try: CFG["ADMIN_IDS"] = [int(x) for x in value.split(",") if x.strip().isdigit()]
        except: pass
    else:
        CFG[key] = value

# ============================================================
#  HELPERS — Panel OGH-ZIV
# ============================================================
def get_ip() -> str:
    try:
        r = subprocess.check_output(
            ["curl", "-s4", "--max-time", "5", "ifconfig.me"],
            stderr=subprocess.DEVNULL
        ).decode().strip()
        if re.match(r"^\d+\.\d+\.\d+\.\d+$", r): return r
    except: pass
    try:
        return subprocess.check_output(
            ["hostname", "-I"], stderr=subprocess.DEVNULL
        ).decode().split()[0]
    except: return "0.0.0.0"

def get_domain() -> str:
    if Path(DOMAIN_CONF).exists(): return Path(DOMAIN_CONF).read_text().strip()
    return get_ip()

def get_port() -> str:
    cfg_file = "/etc/zivpn/config.json"
    if Path(cfg_file).exists():
        try:
            data   = json.loads(Path(cfg_file).read_text())
            listen = data.get("listen", ":5667")
            return listen.lstrip(":")
        except: pass
    return "5667"

def rand_pass(length: int = 12) -> str:
    return "".join(random.choices(string.ascii_letters + string.digits, k=length))

def rand_user(prefix: str = "ziv") -> str:
    return f"{prefix}{''.join(random.choices(string.digits, k=5))}"

def user_exists(username: str) -> bool:
    if not Path(USERS_DB).exists(): return False
    for line in Path(USERS_DB).read_text().splitlines():
        if line.startswith(f"{username}|"): return True
    return False

def create_account(username: str, password: str, days: int, kuota: int,
                   maxlogin: int, note: str = "-") -> dict:
    exp = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")
    Path(USERS_DB).parent.mkdir(parents=True, exist_ok=True)
    with open(USERS_DB, "a") as f:
        f.write(f"{username}|{password}|{exp}|{kuota}|{note}\n")
    mldb  = Path(MLDB)
    mldb.parent.mkdir(parents=True, exist_ok=True)
    lines = mldb.read_text().splitlines() if mldb.exists() else []
    lines = [l for l in lines if not l.startswith(f"{username}|")]
    lines.append(f"{username}|{maxlogin}")
    mldb.write_text("\n".join(lines) + "\n")
    _reload_pw()
    return {
        "username": username, "password": password, "exp": exp,
        "ip": get_ip(), "domain": get_domain(), "port": get_port(),
        "kuota": "Unlimited" if kuota == 0 else f"{kuota} GB",
        "maxlogin": maxlogin, "note": note,
    }

def _reload_pw():
    cfg_file = "/etc/zivpn/config.json"
    if not Path(USERS_DB).exists() or not Path(cfg_file).exists(): return
    try:
        pws = []
        for line in Path(USERS_DB).read_text().splitlines():
            parts = line.split("|")
            if len(parts) >= 2: pws.append(f'"{parts[1]}"')
        data = json.loads(Path(cfg_file).read_text())
        data["auth"]["config"] = json.loads(f"[{','.join(pws)}]")
        Path(cfg_file).write_text(json.dumps(data, indent=2))
        subprocess.run(["systemctl", "restart", "zivpn"], capture_output=True, timeout=10)
    except Exception as e: log.warning(f"reload_pw error: {e}")

def delete_account(username: str) -> bool:
    if not Path(USERS_DB).exists(): return False
    lines     = Path(USERS_DB).read_text().splitlines()
    new_lines = [l for l in lines if not l.startswith(f"{username}|")]
    if len(new_lines) == len(lines): return False
    Path(USERS_DB).write_text("\n".join(new_lines) + "\n" if new_lines else "")
    if Path(MLDB).exists():
        ml = [l for l in Path(MLDB).read_text().splitlines() if not l.startswith(f"{username}|")]
        Path(MLDB).write_text("\n".join(ml) + "\n")
    _reload_pw()
    return True

def get_account_info(username: str) -> Optional[dict]:
    if not Path(USERS_DB).exists(): return None
    for line in Path(USERS_DB).read_text().splitlines():
        parts = line.split("|")
        if len(parts) >= 5 and parts[0] == username:
            ml = "2"
            if Path(MLDB).exists():
                for ml_line in Path(MLDB).read_text().splitlines():
                    if ml_line.startswith(f"{username}|"): ml = ml_line.split("|")[1]
            return {"username": parts[0], "password": parts[1], "exp": parts[2],
                    "kuota": parts[3], "note": parts[4], "maxlogin": ml,
                    "ip": get_ip(), "domain": get_domain(), "port": get_port()}
    return None

def is_admin(user_id: int) -> bool:
    return user_id in CFG.get("ADMIN_IDS", [])

def qris_aktif() -> bool:
    return CFG.get("QRIS_ENABLED", "0") == "1" and Path(QRIS_IMG).exists()

# ============================================================
#  OCR — Verifikasi Screenshot Pembayaran
# ============================================================
def verify_payment_screenshot(image_path: str, expected_amount: int) -> Tuple[bool, str]:
    if not OCR_AVAILABLE: return (None, "ocr_unavailable")
    try:
        img     = Image.open(image_path)
        text    = pytesseract.image_to_string(img, lang="ind+eng")
        text_up = text.upper()
        log.info(f"OCR result: {text[:300]}")

        has_payment = any(kw in text_up for kw in [
            "DANA", "BERHASIL", "SUKSES", "TRANSFER", "SELESAI",
            "SUCCESS", "PEMBAYARAN", "QRIS", "GOPAY", "OVO", "SHOPEEPAY"
        ])
        dana_num   = CFG.get("DANA_NUMBER", "").replace("-", "").replace(" ", "")
        has_number = dana_num in text.replace(" ", "").replace("-", "")

        has_amount = False
        for amt_str in re.findall(r"[\d.,]+", text):
            try:
                amt = int(amt_str.replace(".", "").replace(",", ""))
                if amt == expected_amount: has_amount = True; break
            except: pass

        if has_payment and has_number and has_amount:
            return (True, "✅ Pembayaran terverifikasi otomatis")
        elif has_payment and has_amount:
            return (True, "✅ Pembayaran terverifikasi (nominal cocok)")
        elif has_payment and has_number:
            return (False, "❌ Nominal tidak cocok dengan paket")
        elif not has_payment:
            return (False, "❌ Screenshot bukan dari aplikasi pembayaran yang valid")
        else:
            return (False, "❌ Screenshot tidak dapat diverifikasi")
    except Exception as e:
        log.error(f"OCR error: {e}")
        return (None, f"OCR error: {e}")

# ============================================================
#  FORMAT PESAN
# ============================================================
def format_akun_message(akun: dict) -> str:
    brand    = CFG.get("BRAND", "OGH-ZIV")
    admin_tg = CFG.get("ADMIN_TG", "@admin")
    hari_sisa = ""
    try:
        exp_dt = datetime.strptime(akun["exp"], "%Y-%m-%d")
        sisa   = (exp_dt - datetime.now()).days
        hari_sisa = f"({sisa} hari lagi)" if sisa >= 0 else "(EXPIRED)"
    except: pass
    kuota_str = "Unlimited" if str(akun.get("kuota", "0")) == "0" else akun["kuota"]
    return (
        f"🎉 <b>{brand} — Akun VPN Premium</b>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"🖥 <b>IP Publik</b>  : <code>{akun['ip']}</code>\n"
        f"🌐 <b>Host</b>      : <code>{akun['domain']}</code>\n"
        f"🔌 <b>Port</b>      : <code>{akun['port']}</code>\n"
        f"📡 <b>Obfs</b>      : <code>zivpn</code>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"👤 <b>Username</b>  : <code>{akun['username']}</code>\n"
        f"🔑 <b>Password</b>  : <code>{akun['password']}</code>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"📦 <b>Kuota</b>     : {kuota_str}\n"
        f"🔒 <b>Max Login</b> : {akun['maxlogin']} device\n"
        f"📅 <b>Expired</b>   : {akun['exp']} {hari_sisa}\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"📱 Download ZiVPN → Play Store / App Store\n"
        f"⚠️  Jangan share akun ini ke orang lain!\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"💬 Keluhan & bantuan: {admin_tg}"
    )

def format_paket_list() -> str:
    brand    = CFG.get("BRAND", "OGH-ZIV")
    dana_num = CFG.get("DANA_NUMBER", "")
    dana_name= CFG.get("DANA_NAME", "")
    lines = [
        f"🛒 <b>{brand} — Daftar Paket UDP VPN</b>\n",
        "━━━━━━━━━━━━━━━━━━━━━━━",
        f"1️⃣  <b>3 Hari</b>   — Rp 3.000  | Unlimited | 2 device",
        f"2️⃣  <b>15 Hari</b>  — Rp 6.000  | Unlimited | 2 device",
        f"3️⃣  <b>30 Hari</b>  — Rp 10.000 | Unlimited | 2 device",
        "━━━━━━━━━━━━━━━━━━━━━━━",
        f"🎁  <b>Trial Gratis</b> — 120 Menit | 1 device",
        "━━━━━━━━━━━━━━━━━━━━━━━",
        f"💳 <b>Metode Pembayaran:</b>",
        f"📱 DANA : <code>{dana_num}</code>  |  A/N: <b>{dana_name}</b>",
    ]
    if qris_aktif():
        lines.append(f"🔲 QRIS : <b>Tersedia</b> (pilih saat checkout)")
    return "\n".join(lines)

# ============================================================
#  HANDLERS — USER
# ============================================================
async def cmd_start(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    user     = update.effective_user
    brand    = CFG.get("BRAND", "OGH-ZIV")
    admin_tg = CFG.get("ADMIN_TG", "@admin")
    keyboard = [
        [InlineKeyboardButton("🛒 Beli Akun VPN",          callback_data="beli")],
        [InlineKeyboardButton("🎁 Trial Gratis 120 Menit", callback_data="trial")],
        [InlineKeyboardButton("📋 Cek Akun Saya",          callback_data="cek_akun")],
        [InlineKeyboardButton("📞 Hubungi Admin", url=f"https://t.me/{admin_tg.lstrip('@')}")],
    ]
    if is_admin(user.id):
        keyboard.append([InlineKeyboardButton("⚙️ Admin Panel", callback_data="admin")])
    await update.message.reply_text(
        f"👋 Selamat datang di <b>{brand} VPN Bot</b>!\n\n"
        f"Bot ini membantu kamu membeli akun VPN premium dengan mudah.\n"
        f"Pembayaran via DANA / QRIS — otomatis diproses setelah konfirmasi.\n\n"
        f"Pilih menu di bawah:",
        reply_markup=InlineKeyboardMarkup(keyboard), parse_mode="HTML"
    )

async def cb_back_start(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query    = update.callback_query
    await query.answer()
    user     = update.effective_user
    brand    = CFG.get("BRAND", "OGH-ZIV")
    admin_tg = CFG.get("ADMIN_TG", "@admin")
    keyboard = [
        [InlineKeyboardButton("🛒 Beli Akun VPN",          callback_data="beli")],
        [InlineKeyboardButton("🎁 Trial Gratis 120 Menit", callback_data="trial")],
        [InlineKeyboardButton("📋 Cek Akun Saya",          callback_data="cek_akun")],
        [InlineKeyboardButton("📞 Hubungi Admin", url=f"https://t.me/{admin_tg.lstrip('@')}")],
    ]
    if is_admin(user.id):
        keyboard.append([InlineKeyboardButton("⚙️ Admin Panel", callback_data="admin")])
    await query.edit_message_text(
        f"👋 Selamat datang di <b>{brand} VPN Bot</b>!\n\n"
        f"Bot ini membantu kamu membeli akun VPN premium dengan mudah.\n"
        f"Pembayaran via DANA / QRIS — otomatis diproses setelah konfirmasi.\n\n"
        f"Pilih menu di bawah:",
        reply_markup=InlineKeyboardMarkup(keyboard), parse_mode="HTML"
    )

async def cb_beli(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    keyboard = [
        [InlineKeyboardButton("1️⃣  3 Hari  — Rp 3.000",    callback_data="paket_1")],
        [InlineKeyboardButton("2️⃣  15 Hari — Rp 6.000",    callback_data="paket_2")],
        [InlineKeyboardButton("3️⃣  30 Hari — Rp 10.000",   callback_data="paket_3")],
        [InlineKeyboardButton("🎁  Trial Gratis 120 Menit", callback_data="trial")],
        [InlineKeyboardButton("🔙 Kembali",                  callback_data="back_start")],
    ]
    await query.edit_message_text(
        format_paket_list(), reply_markup=InlineKeyboardMarkup(keyboard), parse_mode="HTML"
    )

async def cb_paket(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query    = update.callback_query
    await query.answer()
    paket_id = query.data.split("_")[1]
    if paket_id not in PAKET:
        await query.edit_message_text("❌ Paket tidak valid.")
        return
    p = PAKET[paket_id]
    ctx.user_data["paket_id"]    = paket_id
    ctx.user_data["paket_nama"]  = p["nama"]
    ctx.user_data["paket_harga"] = p["harga"]

    keyboard = [[InlineKeyboardButton("💳 Bayar via DANA", callback_data=f"bayar_dana_{paket_id}")]]
    if qris_aktif():
        keyboard.append([InlineKeyboardButton("🔲 Bayar via QRIS", callback_data=f"bayar_qris_{paket_id}")])
    keyboard.append([InlineKeyboardButton("🔙 Kembali", callback_data="beli")])

    await query.edit_message_text(
        f"📦 <b>Paket {p['nama']} — Rp {p['harga']:,}</b>\n\nPilih metode pembayaran:",
        parse_mode="HTML", reply_markup=InlineKeyboardMarkup(keyboard)
    )

async def cb_bayar_dana(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query    = update.callback_query
    await query.answer()
    paket_id = query.data.split("_")[2]
    p        = PAKET.get(paket_id, PAKET["1"])
    ctx.user_data["paket_id"]     = paket_id
    ctx.user_data["metode_bayar"] = "dana"
    dana_num  = CFG.get("DANA_NUMBER", "")
    dana_name = CFG.get("DANA_NAME", "")
    await query.edit_message_text(
        f"💳 <b>Pembayaran via DANA</b>\n\n"
        f"📦 Paket    : {p['nama']}\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"📱 No. DANA : <code>{dana_num}</code>\n"
        f"👤 A/N      : <b>{dana_name}</b>\n"
        f"💰 Nominal  : <b>Rp {p['harga']:,}</b> (pas)\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"📸 Setelah transfer, kirim <b>screenshot bukti bayar</b> ke chat ini.\n\n"
        f"⚠️ Pastikan nominal <b>pas</b> sesuai paket!",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data=f"paket_{paket_id}")]])
    )

async def cb_bayar_qris(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query    = update.callback_query
    await query.answer()
    paket_id = query.data.split("_")[2]
    p        = PAKET.get(paket_id, PAKET["1"])
    ctx.user_data["paket_id"]     = paket_id
    ctx.user_data["metode_bayar"] = "qris"
    caption = (
        f"🔲 <b>Pembayaran via QRIS</b>\n\n"
        f"📦 Paket   : {p['nama']}\n"
        f"💰 Nominal : <b>Rp {p['harga']:,}</b>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"Scan QR di atas dengan DANA, GoPay, OVO, ShopeePay, atau m-Banking.\n\n"
        f"📸 Setelah bayar, kirim <b>screenshot bukti bayar</b> ke chat ini."
    )
    try:
        await query.message.reply_photo(photo=open(QRIS_IMG, "rb"), caption=caption, parse_mode="HTML")
        await query.edit_message_text(
            f"🔲 QRIS dikirim di atas. Bayar Rp {p['harga']:,} lalu kirim screenshot.", parse_mode="HTML"
        )
    except Exception as e:
        await query.edit_message_text(f"❌ Gagal tampilkan QRIS: {e}\nHubungi admin.", parse_mode="HTML")

async def cb_trial(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query    = update.callback_query
    await query.answer()
    user     = query.from_user
    trial_db = Path("/etc/zivpn/trial_used.db")
    today    = datetime.now().strftime("%Y-%m-%d")
    uid_key  = f"{user.id}_{today}"

    if trial_db.exists() and uid_key in trial_db.read_text().splitlines():
        admin_tg = CFG.get("ADMIN_TG", "@admin")
        await query.edit_message_text(
            f"⛔ <b>Trial Sudah Digunakan</b>\n\nTrial hanya bisa digunakan <b>1x per hari</b>.\n\n"
            f"Beli paket mulai <b>Rp 3.000</b> atau hubungi: {admin_tg}",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup([
                [InlineKeyboardButton("🛒 Beli Paket", callback_data="beli")],
                [InlineKeyboardButton("🔙 Kembali",    callback_data="back_start")],
            ])
        )
        return

    username = f"trial{user.id % 99999:05d}"
    if Path(USERS_DB).exists():
        lines = Path(USERS_DB).read_text().splitlines()
        lines = [l for l in lines if not l.startswith(f"{username}|")]
        Path(USERS_DB).write_text("\n".join(lines) + "\n" if lines else "")

    password  = rand_pass(8)
    exp_dt    = datetime.now() + timedelta(minutes=TRIAL_MENIT)
    exp_str   = exp_dt.strftime("%Y-%m-%d")
    exp_clock = exp_dt.strftime("%H:%M")
    exp_date  = exp_dt.strftime("%d/%m/%Y")

    Path(USERS_DB).parent.mkdir(parents=True, exist_ok=True)
    with open(USERS_DB, "a") as f:
        f.write(f"{username}|{password}|{exp_str}|1|TRIAL-TG{user.id}\n")

    mldb     = Path(MLDB)
    ml_lines = mldb.read_text().splitlines() if mldb.exists() else []
    ml_lines = [l for l in ml_lines if not l.startswith(f"{username}|")]
    ml_lines.append(f"{username}|1")
    mldb.write_text("\n".join(ml_lines) + "\n")
    _reload_pw()
    with open(trial_db, "a") as f: f.write(uid_key + "\n")

    brand    = CFG.get("BRAND", "OGH-ZIV")
    admin_tg = CFG.get("ADMIN_TG", "@admin")

    await query.edit_message_text(
        f"🎁 <b>{brand} — Akun Trial Gratis</b>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"🖥 <b>IP Publik</b>  : <code>{get_ip()}</code>\n"
        f"🌐 <b>Host</b>      : <code>{get_domain()}</code>\n"
        f"🔌 <b>Port</b>      : <code>{get_port()}</code>\n"
        f"📡 <b>Obfs</b>      : <code>zivpn</code>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"👤 <b>Username</b>  : <code>{username}</code>\n"
        f"🔑 <b>Password</b>  : <code>{password}</code>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"⏱ <b>Durasi</b>    : 120 Menit\n"
        f"🔒 <b>Max Login</b> : 1 device\n"
        f"⏰ <b>Expired</b>   : {exp_date} pukul {exp_clock}\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"⚠️  Trial 1x per hari  |  💬 Keluhan: {admin_tg}",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup([
            [InlineKeyboardButton("🛒 Beli Paket Berbayar", callback_data="beli")],
            [InlineKeyboardButton("🔙 Menu Utama",          callback_data="back_start")],
        ])
    )
    for admin_id in CFG.get("ADMIN_IDS", []):
        try:
            await ctx.bot.send_message(
                admin_id,
                f"🎁 <b>Trial Baru</b>\n👤 {user.full_name} (@{user.username or '-'}) | ID: {user.id}\n"
                f"🔑 {username} / {password}\n⏰ Expired: {exp_date} {exp_clock}",
                parse_mode="HTML"
            )
        except: pass

async def cb_cek_akun(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    ctx.user_data["action"] = "cek_akun"
    await query.edit_message_text(
        "🔍 <b>Cek Akun</b>\n\nKirim username kamu:",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data="back_start")]])
    )

# ============================================================
#  HANDLE FOTO
# ============================================================
async def handle_photo(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user

    # Admin upload gambar QRIS
    if is_admin(user.id) and ctx.user_data.get("admin_action") == "upload_qris":
        photo    = update.message.photo[-1]
        file_obj = await ctx.bot.get_file(photo.file_id)
        Path(QRIS_IMG).parent.mkdir(parents=True, exist_ok=True)
        await file_obj.download_to_drive(QRIS_IMG)
        save_config_key("QRIS_ENABLED", "1")
        ctx.user_data.pop("admin_action", None)
        await update.message.reply_text(
            "✅ <b>Gambar QRIS berhasil disimpan & diaktifkan!</b>\n\n"
            "User sekarang bisa memilih bayar via QRIS saat checkout.\n"
            "Kamu bisa nonaktifkan kapan saja dari menu Pengaturan Pembayaran.",
            parse_mode="HTML"
        )
        return

    if "paket_id" not in ctx.user_data:
        await update.message.reply_text("❓ Kamu belum memilih paket.\nKetik /start untuk memulai.")
        return
    if ctx.user_data.get("waiting_username"):
        await update.message.reply_text(
            "⏳ Pembayaran sudah diverifikasi!\nSilakan ketik <b>username</b> yang kamu inginkan:",
            parse_mode="HTML"
        )
        return

    paket_id   = ctx.user_data["paket_id"]
    paket_info = PAKET[paket_id]
    await update.message.reply_text("⏳ Memverifikasi screenshot pembayaran...")

    photo    = update.message.photo[-1]
    file_obj = await ctx.bot.get_file(photo.file_id)
    img_path = f"/tmp/ss_{user.id}_{photo.file_id[:8]}.jpg"
    await file_obj.download_to_drive(img_path)

    ok, reason = verify_payment_screenshot(img_path, paket_info["harga"])

    if ok is True:
        try: os.remove(img_path)
        except: pass
        ctx.user_data["waiting_username"] = True
        ctx.user_data["ss_verified"]      = True
        await update.message.reply_text(
            f"✅ <b>Pembayaran Terverifikasi!</b>\n\nKetik <b>username</b> yang kamu inginkan:\n"
            f"<i>(Huruf kecil, angka, minimal 4 karakter)</i>",
            parse_mode="HTML"
        )
    elif ok is None:
        ctx.user_data["waiting_username"] = False
        await update.message.reply_text("⏳ Screenshot diterima. Admin akan verifikasi dalam beberapa menit. Harap tunggu 🙏")
        for admin_id in CFG.get("ADMIN_IDS", []):
            try:
                await ctx.bot.send_photo(
                    chat_id=admin_id, photo=open(img_path, "rb"),
                    caption=(
                        f"🧾 <b>Verifikasi Manual</b>\n\n"
                        f"👤 Pembeli : {user.full_name} (@{user.username or '-'})\n"
                        f"🆔 User ID : <code>{user.id}</code>\n"
                        f"📦 Paket   : {paket_info['nama']}\n"
                        f"💰 Nominal : Rp {paket_info['harga']:,}\n\n"
                        f"✅ /konfirm_{user.id}   ❌ /tolak_{user.id}"
                    ),
                    parse_mode="HTML"
                )
            except: pass
        try: os.remove(img_path)
        except: pass
    else:
        admin_tg = CFG.get("ADMIN_TG", "@admin")
        await update.message.reply_text(
            f"❌ <b>Verifikasi Gagal</b>\n\n{reason}\n\n"
            f"Pastikan screenshot dari aplikasi pembayaran & nominal <b>Rp {paket_info['harga']:,}</b> pas.\n\n"
            f"Coba lagi atau hubungi: {admin_tg}",
            parse_mode="HTML"
        )
        try: os.remove(img_path)
        except: pass

# ============================================================
#  ADMIN: Konfirmasi Manual
# ============================================================
async def cmd_konfirm(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if not is_admin(update.effective_user.id): return
    try: target_uid = int(update.message.text.split("_")[1])
    except:
        await update.message.reply_text("Format: /konfirm_<user_id>")
        return
    pdata = ctx.bot_data.get(f"pending_{target_uid}")
    if not pdata:
        await update.message.reply_text("❌ Data pending tidak ditemukan.")
        return
    paket_id = pdata.get("paket_id", "2")
    ctx.bot_data.pop(f"pending_{target_uid}", None)
    try:
        ctx.bot_data[f"konfirm_{target_uid}"] = {"paket_id": paket_id, "ss_verified": True}
        await ctx.bot.send_message(
            chat_id=target_uid,
            text=(
                f"✅ <b>Pembayaran Dikonfirmasi!</b>\n\nKetik <b>username</b> yang kamu inginkan:\n"
                f"<i>(Huruf kecil, angka, minimal 4 karakter)</i>"
            ),
            parse_mode="HTML"
        )
        await update.message.reply_text("✅ Dikonfirmasi. Bot sudah minta user/pass ke pembeli.")
    except Exception as e:
        await update.message.reply_text(f"⚠️ Tidak bisa kirim ke user: {e}")

async def cmd_tolak(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if not is_admin(update.effective_user.id): return
    try: target_uid = int(update.message.text.split("_")[1])
    except:
        await update.message.reply_text("Format: /tolak_<user_id>")
        return
    ctx.bot_data.pop(f"pending_{target_uid}", None)
    admin_tg = CFG.get("ADMIN_TG", "@admin")
    try:
        await ctx.bot.send_message(
            target_uid,
            f"❌ <b>Pembayaran Ditolak</b>\n\nScreenshot tidak berhasil diverifikasi.\nHubungi admin: {admin_tg}",
            parse_mode="HTML"
        )
    except: pass
    await update.message.reply_text("✅ Pesanan ditolak dan user telah diberitahu.")

# ============================================================
#  ADMIN PANEL — MENU UTAMA
# ============================================================
async def cb_admin(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    if not is_admin(query.from_user.id):
        await query.edit_message_text("⛔ Akses ditolak!")
        return
    brand = CFG.get("BRAND", "OGH-ZIV")
    keyboard = [
        [InlineKeyboardButton("👤 Buat Akun Gratis",      callback_data="admin_buat_akun")],
        [InlineKeyboardButton("🗑️ Hapus Akun VPN",         callback_data="admin_del")],
        [InlineKeyboardButton("📋 List Semua Akun",         callback_data="admin_list")],
        [InlineKeyboardButton("📊 Statistik Server",        callback_data="admin_stat")],
        [InlineKeyboardButton("👥 Kelola Admin Bot",        callback_data="admin_kelola_admin")],
        [InlineKeyboardButton("💳 Pengaturan Pembayaran",  callback_data="admin_pembayaran")],
        [InlineKeyboardButton("⚙️ Pengaturan Bot",         callback_data="admin_settings")],
        [InlineKeyboardButton("🔙 Kembali",                 callback_data="back_start")],
    ]
    await query.edit_message_text(
        f"⚙️ <b>Admin Panel — {brand}</b>\n\n"
        f"Halo, <b>{query.from_user.first_name}</b>! Pilih menu:",
        reply_markup=InlineKeyboardMarkup(keyboard), parse_mode="HTML"
    )

# ============================================================
#  ADMIN — BUAT AKUN GRATIS (User+Pass Bebas / Auto)
# ============================================================
async def cb_admin_buat_akun(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    if not is_admin(query.from_user.id): return
    keyboard = [
        [InlineKeyboardButton("✏️ Manual (User & Pass sendiri)", callback_data="admin_akun_manual")],
        [InlineKeyboardButton("⚡ Generate Otomatis",             callback_data="admin_akun_auto")],
        [InlineKeyboardButton("🔙 Kembali",                       callback_data="admin")],
    ]
    await query.edit_message_text(
        "👤 <b>Buat Akun Gratis</b>\n\nPilih cara membuat akun:",
        parse_mode="HTML", reply_markup=InlineKeyboardMarkup(keyboard)
    )

async def cb_admin_akun_manual(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    """Step-by-step: admin input username, password, hari, maxlogin"""
    query = update.callback_query
    await query.answer()
    if not is_admin(query.from_user.id): return
    ctx.user_data["admin_action"]     = "akun_manual_step1"
    ctx.user_data["akun_manual_data"] = {}
    await query.edit_message_text(
        "✏️ <b>Buat Akun Manual — Langkah 1/4</b>\n\n"
        "Ketik <b>username</b> yang diinginkan:\n"
        "<i>(Huruf kecil, angka, underscore — minimal 4 karakter)</i>",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Batal", callback_data="admin_buat_akun")]])
    )

async def cb_admin_akun_auto(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    """Pilih durasi untuk akun auto-generate"""
    query = update.callback_query
    await query.answer()
    if not is_admin(query.from_user.id): return
    keyboard = [
        [InlineKeyboardButton("3 Hari",  callback_data="admin_auto_hari_3")],
        [InlineKeyboardButton("15 Hari", callback_data="admin_auto_hari_15")],
        [InlineKeyboardButton("30 Hari", callback_data="admin_auto_hari_30")],
        [InlineKeyboardButton("🔙 Batal", callback_data="admin_buat_akun")],
    ]
    await query.edit_message_text(
        "⚡ <b>Generate Akun Otomatis</b>\n\nPilih durasi aktif:",
        parse_mode="HTML", reply_markup=InlineKeyboardMarkup(keyboard)
    )

async def cb_admin_auto_hari(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    if not is_admin(query.from_user.id): return
    hari     = int(query.data.split("_")[-1])
    username = rand_user("ziv")
    password = rand_pass()
    akun     = create_account(username, password, hari, 0, 2, "ADMIN-FREE-AUTO")
    await query.edit_message_text(
        f"✅ <b>Akun Otomatis Berhasil Dibuat!</b>\n\n" + format_akun_message(akun),
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Admin Panel", callback_data="admin")]])
    )

# ============================================================
#  ADMIN — HAPUS AKUN VPN
# ============================================================
async def cb_admin_del(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    if not is_admin(query.from_user.id): return
    ctx.user_data["admin_action"] = "del_akun"
    await query.edit_message_text(
        "🗑️ <b>Hapus Akun</b>\n\nKirim username yang ingin dihapus:",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Batal", callback_data="admin")]])
    )

async def handle_admin_del(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if not is_admin(update.effective_user.id): return
    username = update.message.text.strip()
    ctx.user_data.pop("admin_action", None)
    if delete_account(username):
        await update.message.reply_text(f"✅ Akun <code>{username}</code> berhasil dihapus.", parse_mode="HTML")
    else:
        await update.message.reply_text(f"❌ Akun <code>{username}</code> tidak ditemukan.", parse_mode="HTML")

# ============================================================
#  ADMIN — LIST & STATISTIK
# ============================================================
async def cb_admin_list(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    if not is_admin(query.from_user.id): return
    if not Path(USERS_DB).exists() or Path(USERS_DB).stat().st_size == 0:
        await query.edit_message_text(
            "📋 Belum ada akun terdaftar.",
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data="admin")]])
        )
        return
    today    = datetime.now().strftime("%Y-%m-%d")
    out      = ["📋 <b>Daftar Akun</b>\n━━━━━━━━━━━━━━━━━━━━━━━"]
    for i, line in enumerate(Path(USERS_DB).read_text().splitlines(), 1):
        if not line.strip(): continue
        parts = line.split("|")
        if len(parts) < 3: continue
        status = "✅" if parts[2] >= today else "❌"
        out.append(f"{i}. {status} <code>{parts[0]}</code> | Exp: {parts[2]}")
        if i >= 30: out.append("... (max 30)"); break
    await query.edit_message_text(
        "\n".join(out), parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data="admin")]])
    )

async def cb_admin_stat(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    today   = datetime.now().strftime("%Y-%m-%d")
    total = aktif = expired = 0
    if Path(USERS_DB).exists():
        for line in Path(USERS_DB).read_text().splitlines():
            if not line.strip(): continue
            parts = line.split("|")
            if len(parts) >= 3:
                total += 1
                if parts[2] >= today: aktif += 1
                else: expired += 1
    brand = CFG.get("BRAND", "OGH-ZIV")
    await query.edit_message_text(
        f"📊 <b>Statistik — {brand}</b>\n\n"
        f"🖥 IP     : <code>{get_ip()}</code>\n"
        f"🌐 Domain : <code>{get_domain()}</code>\n"
        f"🔌 Port   : <code>{get_port()}</code>\n\n"
        f"👥 Total Akun  : <b>{total}</b>\n"
        f"✅ Aktif       : <b>{aktif}</b>\n"
        f"❌ Expired     : <b>{expired}</b>\n\n"
        f"👮 Total Admin : <b>{len(CFG.get('ADMIN_IDS', []))}</b>\n"
        f"💳 DANA        : <code>{CFG.get('DANA_NUMBER', '-')}</code>\n"
        f"🔲 QRIS        : {'✅ Aktif' if qris_aktif() else '❌ Nonaktif'}",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data="admin")]])
    )

# ============================================================
#  ADMIN — KELOLA ADMIN BOT
# ============================================================
async def cb_admin_kelola_admin(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    if not is_admin(query.from_user.id): return
    admin_ids = CFG.get("ADMIN_IDS", [])
    lines = ["👥 <b>Kelola Admin Bot</b>\n━━━━━━━━━━━━━━━━━━━━━━━"]
    for i, aid in enumerate(admin_ids, 1):
        tag = "  ← Kamu" if aid == query.from_user.id else ""
        lines.append(f"{i}. <code>{aid}</code>{tag}")
    lines += [f"\n━━━━━━━━━━━━━━━━━━━━━━━", f"Total: <b>{len(admin_ids)}</b> admin aktif"]
    keyboard = [
        [InlineKeyboardButton("➕ Tambah Admin",  callback_data="admin_tambah_admin")],
        [InlineKeyboardButton("➖ Hapus Admin",   callback_data="admin_hapus_admin")],
        [InlineKeyboardButton("🔙 Kembali",       callback_data="admin")],
    ]
    await query.edit_message_text(
        "\n".join(lines), parse_mode="HTML", reply_markup=InlineKeyboardMarkup(keyboard)
    )

async def cb_admin_tambah_admin(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    if not is_admin(query.from_user.id): return
    ctx.user_data["admin_action"] = "tambah_admin"
    await query.edit_message_text(
        "➕ <b>Tambah Admin Bot</b>\n\n"
        "Kirim <b>Chat ID Telegram</b> orang yang ingin dijadikan admin:\n"
        "<i>(Angka, contoh: 123456789)</i>\n\n"
        "💡 Cara cari Chat ID: suruh dia kirim pesan ke @userinfobot\n\n"
        "Setelah ditambahkan, admin baru cukup ketik /start untuk akses Admin Panel.",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Batal", callback_data="admin_kelola_admin")]])
    )

async def cb_admin_hapus_admin(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query     = update.callback_query
    await query.answer()
    if not is_admin(query.from_user.id): return
    admin_ids = CFG.get("ADMIN_IDS", [])
    if len(admin_ids) <= 1:
        await query.edit_message_text(
            "⚠️ Tidak bisa menghapus. Minimal harus ada <b>1 admin</b> aktif.",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data="admin_kelola_admin")]])
        )
        return
    ctx.user_data["admin_action"] = "hapus_admin"
    lines = ["➖ <b>Hapus Admin</b>\n\nDaftar admin saat ini:"]
    for i, aid in enumerate(admin_ids, 1):
        tag = " (Kamu)" if aid == query.from_user.id else ""
        lines.append(f"{i}. <code>{aid}</code>{tag}")
    lines.append("\nKirim <b>Chat ID</b> admin yang ingin dihapus:")
    await query.edit_message_text(
        "\n".join(lines), parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Batal", callback_data="admin_kelola_admin")]])
    )

# ============================================================
#  ADMIN — PENGATURAN PEMBAYARAN (DANA + QRIS)
# ============================================================
async def cb_admin_pembayaran(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    if not is_admin(query.from_user.id): return
    dana_num  = CFG.get("DANA_NUMBER", "-")
    dana_name = CFG.get("DANA_NAME", "-")
    qris_on   = qris_aktif()
    keyboard = [
        [InlineKeyboardButton("📱 Ubah Nomor DANA",     callback_data="admin_ubah_dana_num")],
        [InlineKeyboardButton("👤 Ubah Nama A/N DANA",  callback_data="admin_ubah_dana_name")],
        [InlineKeyboardButton("🔲 Upload / Ganti QRIS", callback_data="admin_upload_qris")],
        [InlineKeyboardButton("❌ Nonaktifkan QRIS" if qris_on else "✅ Aktifkan QRIS",
                              callback_data="admin_qris_off" if qris_on else "admin_qris_on")],
        [InlineKeyboardButton("🔙 Kembali", callback_data="admin")],
    ]
    await query.edit_message_text(
        f"💳 <b>Pengaturan Pembayaran</b>\n\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"📱 No. DANA : <code>{dana_num}</code>\n"
        f"👤 A/N DANA : <b>{dana_name}</b>\n"
        f"🔲 QRIS     : {'✅ Aktif' if qris_on else '❌ Nonaktif'}\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n\nPilih yang ingin diubah:",
        parse_mode="HTML", reply_markup=InlineKeyboardMarkup(keyboard)
    )

async def cb_admin_ubah_dana_num(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query; await query.answer()
    if not is_admin(query.from_user.id): return
    ctx.user_data["admin_action"] = "ubah_dana_num"
    await query.edit_message_text(
        f"📱 <b>Ubah Nomor DANA</b>\n\nNomor saat ini: <code>{CFG.get('DANA_NUMBER', '-')}</code>\n\nKirim nomor DANA baru:\n<i>(Contoh: 08123456789)</i>",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Batal", callback_data="admin_pembayaran")]])
    )

async def cb_admin_ubah_dana_name(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query; await query.answer()
    if not is_admin(query.from_user.id): return
    ctx.user_data["admin_action"] = "ubah_dana_name"
    await query.edit_message_text(
        f"👤 <b>Ubah Nama A/N DANA</b>\n\nNama saat ini: <b>{CFG.get('DANA_NAME', '-')}</b>\n\nKirim nama pemilik rekening DANA yang baru:",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Batal", callback_data="admin_pembayaran")]])
    )

async def cb_admin_upload_qris(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query; await query.answer()
    if not is_admin(query.from_user.id): return
    ctx.user_data["admin_action"] = "upload_qris"
    await query.edit_message_text(
        "🔲 <b>Upload Gambar QRIS</b>\n\n"
        "Kirim <b>foto gambar QRIS</b> kamu ke chat ini sekarang.\n\n"
        "💡 Tips:\n"
        "• Gunakan gambar QRIS yang jelas dan tidak buram\n"
        "• Format JPG atau PNG\n"
        "• Setelah diupload, QRIS langsung aktif otomatis",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Batal", callback_data="admin_pembayaran")]])
    )

async def cb_admin_qris_toggle(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query; await query.answer()
    if not is_admin(query.from_user.id): return
    if query.data == "admin_qris_on":
        if not Path(QRIS_IMG).exists():
            await query.edit_message_text(
                "⚠️ Belum ada gambar QRIS!\n\nUpload dulu melalui menu <b>Upload / Ganti QRIS</b>.",
                parse_mode="HTML",
                reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data="admin_pembayaran")]])
            )
            return
        save_config_key("QRIS_ENABLED", "1")
        msg = "✅ QRIS <b>diaktifkan!</b> User sekarang bisa memilih bayar via QRIS."
    else:
        save_config_key("QRIS_ENABLED", "0")
        msg = "❌ QRIS <b>dinonaktifkan.</b> User tidak akan melihat opsi QRIS."
    await query.edit_message_text(
        msg, parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Pengaturan Pembayaran", callback_data="admin_pembayaran")]])
    )

# ============================================================
#  ADMIN — PENGATURAN BOT
# ============================================================
async def cb_admin_settings(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query; await query.answer()
    if not is_admin(query.from_user.id): return
    keyboard = [
        [InlineKeyboardButton("🏷️ Ubah Nama Brand",       callback_data="admin_ubah_brand")],
        [InlineKeyboardButton("📣 Ubah Username Admin TG", callback_data="admin_ubah_admintg")],
        [InlineKeyboardButton("🔑 Ganti Token Bot",         callback_data="admin_ganti_token")],
        [InlineKeyboardButton("🔙 Kembali",                 callback_data="admin")],
    ]
    await query.edit_message_text(
        f"⚙️ <b>Pengaturan Bot</b>\n\n"
        f"🏷️ Brand    : <b>{CFG.get('BRAND', '-')}</b>\n"
        f"📣 Admin TG : <b>{CFG.get('ADMIN_TG', '-')}</b>\n\n"
        f"Pilih yang ingin diubah:",
        parse_mode="HTML", reply_markup=InlineKeyboardMarkup(keyboard)
    )

async def cb_admin_ubah_brand(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query; await query.answer()
    if not is_admin(query.from_user.id): return
    ctx.user_data["admin_action"] = "ubah_brand"
    await query.edit_message_text(
        f"🏷️ <b>Ubah Nama Brand</b>\n\nBrand saat ini: <b>{CFG.get('BRAND', '-')}</b>\n\nKirim nama brand baru:",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Batal", callback_data="admin_settings")]])
    )

async def cb_admin_ubah_admintg(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query; await query.answer()
    if not is_admin(query.from_user.id): return
    ctx.user_data["admin_action"] = "ubah_admintg"
    await query.edit_message_text(
        f"📣 <b>Ubah Username Admin TG</b>\n\nSaat ini: <b>{CFG.get('ADMIN_TG', '-')}</b>\n\nKirim username Telegram admin (dengan @):\n<i>Contoh: @namaadmin</i>",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Batal", callback_data="admin_settings")]])
    )

async def cb_admin_ganti_token(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query; await query.answer()
    if not is_admin(query.from_user.id): return
    ctx.user_data["admin_action"] = "ganti_token"
    await query.edit_message_text(
        "🔑 <b>Ganti Token Bot</b>\n\n"
        "⚠️ Bot perlu di-<b>restart</b> setelah token diganti.\n\n"
        "Cara dapat token baru:\n"
        "1. Buka @BotFather di Telegram\n"
        "2. Ketik /mybots → pilih bot kamu\n"
        "3. API Token → Revoke current token\n"
        "4. Copy token baru dan kirim ke sini\n\n"
        "Kirim token baru sekarang:",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Batal", callback_data="admin_settings")]])
    )

# ============================================================
#  HANDLE TEXT — Semua Input Teks
# ============================================================
async def handle_text(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    user         = update.effective_user
    text         = update.message.text.strip()
    action       = ctx.user_data.get("action")
    admin_action = ctx.user_data.get("admin_action")

    # Sync state dari konfirm manual admin
    konfirm_data = ctx.bot_data.get(f"konfirm_{user.id}")
    if konfirm_data and not ctx.user_data.get("ss_verified"):
        ctx.user_data["ss_verified"]      = True
        ctx.user_data["waiting_username"] = True
        ctx.user_data["paket_id"]         = konfirm_data.get("paket_id", "1")
        ctx.bot_data.pop(f"konfirm_{user.id}", None)

    # Routing admin actions
    if is_admin(user.id) and admin_action:
        await _handle_admin_input(update, ctx, admin_action, text)
        return

    # Flow: input username setelah bayar
    if ctx.user_data.get("waiting_username") and ctx.user_data.get("ss_verified"):
        username = text.lower().strip()
        if len(username) < 4:
            await update.message.reply_text("❌ Username minimal <b>4 karakter</b>. Coba lagi:", parse_mode="HTML"); return
        if not re.match(r"^[a-z0-9_]+$", username):
            await update.message.reply_text("❌ Username hanya huruf kecil, angka, underscore. Coba lagi:", parse_mode="HTML"); return
        if user_exists(username):
            await update.message.reply_text(f"❌ Username <code>{username}</code> sudah dipakai. Pilih lain:", parse_mode="HTML"); return
        ctx.user_data["req_username"]     = username
        ctx.user_data["waiting_username"] = False
        ctx.user_data["waiting_password"] = True
        await update.message.reply_text(
            f"✅ Username <code>{username}</code> tersedia!\n\nKetik <b>password</b> yang kamu inginkan:\n<i>(Minimal 6 karakter)</i>",
            parse_mode="HTML"
        )
        return

    # Flow: input password setelah username
    if ctx.user_data.get("waiting_password") and ctx.user_data.get("ss_verified"):
        if len(text) < 6:
            await update.message.reply_text("❌ Password minimal <b>6 karakter</b>. Coba lagi:", parse_mode="HTML"); return
        username   = ctx.user_data.get("req_username")
        paket_id   = ctx.user_data.get("paket_id")
        paket_info = PAKET.get(paket_id, PAKET["1"])
        akun       = create_account(username, text, paket_info["hari"], paket_info["kuota"],
                                    paket_info["maxlogin"], f"TG:{user.username or user.first_name}")
        ctx.user_data.clear()
        await update.message.reply_text(f"🎉 <b>Akun UDP Berhasil Dibuat!</b>\n\n" + format_akun_message(akun), parse_mode="HTML")
        brand = CFG.get("BRAND", "OGH-ZIV")
        for admin_id in CFG.get("ADMIN_IDS", []):
            try:
                await ctx.bot.send_message(
                    admin_id,
                    f"💰 <b>Pesanan Baru — {brand}</b>\n━━━━━━━━━━━━━━━━━━━\n"
                    f"👤 Pembeli  : {user.full_name} (@{user.username or '-'})\n"
                    f"📦 Paket    : {paket_info['nama']}\n"
                    f"💰 Nominal  : Rp {paket_info['harga']:,}\n"
                    f"🔑 Username : <code>{username}</code>\n"
                    f"📅 Expired  : {akun['exp']}",
                    parse_mode="HTML"
                )
            except: pass
        return

    # Cek akun user biasa
    if action == "cek_akun":
        info = get_account_info(text)
        ctx.user_data.pop("action", None)
        if not info:
            await update.message.reply_text(f"❌ Akun <code>{text}</code> tidak ditemukan.", parse_mode="HTML")
        else:
            await update.message.reply_text(format_akun_message(info), parse_mode="HTML")
        return

    await update.message.reply_text("Ketik /start untuk memulai.")

async def _handle_admin_input(update: Update, ctx: ContextTypes.DEFAULT_TYPE, admin_action: str, text: str):
    """Routing semua input teks dari admin"""

    # ── BUAT AKUN MANUAL — step 1: username ──────────────────
    if admin_action == "akun_manual_step1":
        username = text.lower().strip()
        if len(username) < 4 or not re.match(r"^[a-z0-9_]+$", username):
            await update.message.reply_text("❌ Username minimal 4 karakter (huruf kecil/angka/underscore). Coba lagi:"); return
        if user_exists(username):
            await update.message.reply_text(f"❌ Username <code>{username}</code> sudah ada. Kirim username lain:", parse_mode="HTML"); return
        ctx.user_data["akun_manual_data"]["username"] = username
        ctx.user_data["admin_action"] = "akun_manual_step2"
        await update.message.reply_text(
            f"✅ Username: <code>{username}</code>\n\n"
            f"✏️ <b>Langkah 2/4</b> — Ketik <b>password</b> yang diinginkan:\n<i>(Minimal 6 karakter)</i>",
            parse_mode="HTML"
        )
        return

    # ── BUAT AKUN MANUAL — step 2: password ──────────────────
    if admin_action == "akun_manual_step2":
        if len(text) < 6:
            await update.message.reply_text("❌ Password minimal 6 karakter. Coba lagi:"); return
        ctx.user_data["akun_manual_data"]["password"] = text
        ctx.user_data["admin_action"] = "akun_manual_step3"
        await update.message.reply_text(
            f"✅ Password disimpan.\n\n✏️ <b>Langkah 3/4</b> — Ketik <b>jumlah hari</b> aktif:\n<i>(Contoh: 30)</i>",
            parse_mode="HTML"
        )
        return

    # ── BUAT AKUN MANUAL — step 3: hari ──────────────────────
    if admin_action == "akun_manual_step3":
        try:
            hari = int(text)
            if hari < 1: raise ValueError
        except:
            await update.message.reply_text("❌ Jumlah hari harus angka positif. Coba lagi:"); return
        ctx.user_data["akun_manual_data"]["hari"] = hari
        ctx.user_data["admin_action"] = "akun_manual_step4"
        await update.message.reply_text(
            f"✅ Durasi: <b>{hari} hari</b>\n\n✏️ <b>Langkah 4/4</b> — Ketik <b>max login device</b>:\n<i>(Contoh: 2)</i>",
            parse_mode="HTML"
        )
        return

    # ── BUAT AKUN MANUAL — step 4: maxlogin → selesai ────────
    if admin_action == "akun_manual_step4":
        try:
            maxlogin = int(text)
            if maxlogin < 1: raise ValueError
        except:
            await update.message.reply_text("❌ Max login harus angka positif. Coba lagi:"); return
        data     = ctx.user_data.get("akun_manual_data", {})
        username = data.get("username")
        password = data.get("password")
        hari     = data.get("hari", 30)
        if not username or not password:
            await update.message.reply_text("❌ Data tidak lengkap. Mulai ulang dari Admin Panel.")
            ctx.user_data.pop("admin_action", None); return
        akun = create_account(username, password, hari, 0, maxlogin, "ADMIN-FREE-MANUAL")
        ctx.user_data.pop("admin_action", None)
        ctx.user_data.pop("akun_manual_data", None)
        await update.message.reply_text(
            f"🎉 <b>Akun Berhasil Dibuat!</b>\n\n" + format_akun_message(akun), parse_mode="HTML"
        )
        return

    # ── TAMBAH ADMIN ─────────────────────────────────────────
    if admin_action == "tambah_admin":
        try: new_id = int(text)
        except ValueError:
            await update.message.reply_text("❌ Chat ID harus angka! Contoh: <code>123456789</code>", parse_mode="HTML"); return
        admin_ids = CFG.get("ADMIN_IDS", [])
        if new_id in admin_ids:
            await update.message.reply_text(f"⚠️ ID <code>{new_id}</code> sudah terdaftar sebagai admin.", parse_mode="HTML")
        else:
            admin_ids.append(new_id)
            save_config_key("ADMIN_IDS", ",".join(str(x) for x in admin_ids))
            await update.message.reply_text(
                f"✅ Admin <code>{new_id}</code> berhasil ditambahkan!\nTotal admin: <b>{len(admin_ids)}</b>",
                parse_mode="HTML"
            )
            try:
                await ctx.bot.send_message(
                    new_id,
                    f"🎉 Kamu telah ditambahkan sebagai <b>Admin {CFG.get('BRAND', 'OGH-ZIV')}</b>!\n\nKetik /start untuk membuka Admin Panel.",
                    parse_mode="HTML"
                )
            except: pass
        ctx.user_data.pop("admin_action", None); return

    # ── HAPUS ADMIN ──────────────────────────────────────────
    if admin_action == "hapus_admin":
        try: del_id = int(text)
        except ValueError:
            await update.message.reply_text("❌ Chat ID harus angka!", parse_mode="HTML"); return
        admin_ids = CFG.get("ADMIN_IDS", [])
        if del_id not in admin_ids:
            await update.message.reply_text(f"❌ ID <code>{del_id}</code> tidak ditemukan.", parse_mode="HTML")
        elif len(admin_ids) <= 1:
            await update.message.reply_text("⚠️ Tidak bisa hapus — minimal 1 admin harus tersisa.", parse_mode="HTML")
        else:
            admin_ids.remove(del_id)
            save_config_key("ADMIN_IDS", ",".join(str(x) for x in admin_ids))
            await update.message.reply_text(
                f"✅ Admin <code>{del_id}</code> dihapus.\nTotal admin: <b>{len(admin_ids)}</b>", parse_mode="HTML"
            )
        ctx.user_data.pop("admin_action", None); return

    # ── HAPUS AKUN VPN ───────────────────────────────────────
    if admin_action == "del_akun":
        await handle_admin_del(update, ctx); return

    # ── UBAH NOMOR DANA ──────────────────────────────────────
    if admin_action == "ubah_dana_num":
        nomor = text.replace(" ", "").replace("-", "")
        if not re.match(r"^0\d{9,12}$", nomor):
            await update.message.reply_text("❌ Format tidak valid. Contoh: <code>08123456789</code>", parse_mode="HTML"); return
        save_config_key("DANA_NUMBER", nomor)
        ctx.user_data.pop("admin_action", None)
        await update.message.reply_text(f"✅ Nomor DANA diubah ke: <code>{nomor}</code>", parse_mode="HTML"); return

    # ── UBAH NAMA A/N DANA ───────────────────────────────────
    if admin_action == "ubah_dana_name":
        if len(text) < 3:
            await update.message.reply_text("❌ Nama terlalu pendek. Coba lagi:"); return
        save_config_key("DANA_NAME", text)
        ctx.user_data.pop("admin_action", None)
        await update.message.reply_text(f"✅ Nama A/N DANA diubah ke: <b>{text}</b>", parse_mode="HTML"); return

    # ── UBAH BRAND ───────────────────────────────────────────
    if admin_action == "ubah_brand":
        if len(text) < 2:
            await update.message.reply_text("❌ Nama brand terlalu pendek. Coba lagi:"); return
        save_config_key("BRAND", text)
        ctx.user_data.pop("admin_action", None)
        await update.message.reply_text(f"✅ Nama brand diubah ke: <b>{text}</b>", parse_mode="HTML"); return

    # ── UBAH ADMIN TG ────────────────────────────────────────
    if admin_action == "ubah_admintg":
        username_tg = text if text.startswith("@") else f"@{text}"
        save_config_key("ADMIN_TG", username_tg)
        ctx.user_data.pop("admin_action", None)
        await update.message.reply_text(f"✅ Username admin TG diubah ke: <b>{username_tg}</b>", parse_mode="HTML"); return

    # ── GANTI TOKEN BOT ──────────────────────────────────────
    if admin_action == "ganti_token":
        token = text.strip()
        if not re.match(r"^\d{8,12}:[A-Za-z0-9_-]{35,}$", token):
            await update.message.reply_text(
                "❌ Format token tidak valid.\nToken harus seperti: <code>1234567890:ABCdef...</code>",
                parse_mode="HTML"
            ); return
        save_config_key("BOT_TOKEN", token)
        ctx.user_data.pop("admin_action", None)
        await update.message.reply_text(
            "✅ <b>Token Bot berhasil disimpan!</b>\n\n"
            "⚠️ Restart bot agar token baru berlaku:\n"
            "<code>systemctl restart zivpn-bot</code>",
            parse_mode="HTML"
        ); return

# ============================================================
#  SETUP & RUN
# ============================================================
def write_default_config():
    p = Path(CONFIG_FILE)
    p.parent.mkdir(parents=True, exist_ok=True)
    if not p.exists():
        p.write_text(
            "# OGH-ZIV Bot Store Config\n"
            "BOT_TOKEN=ISI_TOKEN_BOT_TELEGRAM_DI_SINI\n"
            "# Multiple admin: pisahkan Chat ID dengan koma\n"
            "# Contoh: ADMIN_IDS=123456789,987654321\n"
            "ADMIN_IDS=ISI_CHAT_ID_ADMIN\n"
            "DANA_NUMBER=08xxxxxxxxxx\n"
            "DANA_NAME=Nama Pemilik Dana\n"
            "QRIS_ENABLED=0\n"
            "BRAND=OGH-ZIV\n"
            "ADMIN_TG=@namaadmin\n"
        )
        print(f"[INFO] Config default dibuat: {CONFIG_FILE}")
        print("[INFO] Edit file tersebut lalu jalankan kembali bot ini!")

def main():
    global CFG
    write_default_config()
    CFG = load_config()

    token = CFG.get("BOT_TOKEN", "")
    if not token or token == "ISI_TOKEN_BOT_TELEGRAM_DI_SINI":
        print(f"\n[ERROR] Token bot belum diisi!")
        print(f"Edit file: {CONFIG_FILE}")
        print("Isi BOT_TOKEN dengan token dari @BotFather")
        return

    admin_list = CFG.get("ADMIN_IDS", [])
    print(f"[INFO] OGH-ZIV Bot starting...")
    print(f"[INFO] Brand     : {CFG.get('BRAND')}")
    print(f"[INFO] DANA      : {CFG.get('DANA_NUMBER')}")
    print(f"[INFO] QRIS      : {'Aktif' if qris_aktif() else 'Nonaktif'}")
    print(f"[INFO] Admins    : {admin_list} ({len(admin_list)} admin)")
    print(f"[INFO] OCR       : {'Aktif' if OCR_AVAILABLE else 'Tidak aktif (manual mode)'}")

    app = ApplicationBuilder().token(token).build()

    # Commands
    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(MessageHandler(filters.Regex(r"^/konfirm_\d+$"), cmd_konfirm))
    app.add_handler(MessageHandler(filters.Regex(r"^/tolak_\d+$"),   cmd_tolak))

    # Callback — User
    app.add_handler(CallbackQueryHandler(cb_beli,                pattern="^beli$"))
    app.add_handler(CallbackQueryHandler(cb_trial,               pattern="^trial$"))
    app.add_handler(CallbackQueryHandler(cb_paket,               pattern="^paket_"))
    app.add_handler(CallbackQueryHandler(cb_bayar_dana,          pattern="^bayar_dana_"))
    app.add_handler(CallbackQueryHandler(cb_bayar_qris,          pattern="^bayar_qris_"))
    app.add_handler(CallbackQueryHandler(cb_cek_akun,            pattern="^cek_akun$"))
    app.add_handler(CallbackQueryHandler(cb_back_start,          pattern="^back_start$"))

    # Callback — Admin Panel
    app.add_handler(CallbackQueryHandler(cb_admin,               pattern="^admin$"))
    app.add_handler(CallbackQueryHandler(cb_admin_buat_akun,     pattern="^admin_buat_akun$"))
    app.add_handler(CallbackQueryHandler(cb_admin_akun_manual,   pattern="^admin_akun_manual$"))
    app.add_handler(CallbackQueryHandler(cb_admin_akun_auto,     pattern="^admin_akun_auto$"))
    app.add_handler(CallbackQueryHandler(cb_admin_auto_hari,     pattern="^admin_auto_hari_"))
    app.add_handler(CallbackQueryHandler(cb_admin_del,           pattern="^admin_del$"))
    app.add_handler(CallbackQueryHandler(cb_admin_list,          pattern="^admin_list$"))
    app.add_handler(CallbackQueryHandler(cb_admin_stat,          pattern="^admin_stat$"))
    app.add_handler(CallbackQueryHandler(cb_admin_kelola_admin,  pattern="^admin_kelola_admin$"))
    app.add_handler(CallbackQueryHandler(cb_admin_tambah_admin,  pattern="^admin_tambah_admin$"))
    app.add_handler(CallbackQueryHandler(cb_admin_hapus_admin,   pattern="^admin_hapus_admin$"))
    app.add_handler(CallbackQueryHandler(cb_admin_pembayaran,    pattern="^admin_pembayaran$"))
    app.add_handler(CallbackQueryHandler(cb_admin_ubah_dana_num, pattern="^admin_ubah_dana_num$"))
    app.add_handler(CallbackQueryHandler(cb_admin_ubah_dana_name,pattern="^admin_ubah_dana_name$"))
    app.add_handler(CallbackQueryHandler(cb_admin_upload_qris,   pattern="^admin_upload_qris$"))
    app.add_handler(CallbackQueryHandler(cb_admin_qris_toggle,   pattern="^admin_qris_o"))
    app.add_handler(CallbackQueryHandler(cb_admin_settings,      pattern="^admin_settings$"))
    app.add_handler(CallbackQueryHandler(cb_admin_ubah_brand,    pattern="^admin_ubah_brand$"))
    app.add_handler(CallbackQueryHandler(cb_admin_ubah_admintg,  pattern="^admin_ubah_admintg$"))
    app.add_handler(CallbackQueryHandler(cb_admin_ganti_token,   pattern="^admin_ganti_token$"))

    # Media & Text
    app.add_handler(MessageHandler(filters.PHOTO, handle_photo))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))

    print("[INFO] Bot berjalan... Tekan Ctrl+C untuk berhenti.\n")
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    main()
