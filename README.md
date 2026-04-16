# 🤖 Bot WhatsApp OGH-ZIV UDP ZiVPN

Bot WhatsApp Business otomatis untuk jualan akun UDP ZiVPN dengan pembayaran **DANA** dan **QRIS**.

---

## ✨ Fitur Lengkap

### 👤 Untuk Pembeli
- 🛒 **Beli akun** dengan pilih paket (15 hari / 30 hari)
- 💳 **Pilih metode bayar**: DANA atau QRIS
- 📸 **Kirim bukti bayar** (screenshot)
- 🔑 **Buat username & password sendiri**
- 🎁 **Trial gratis** 1x per hari (1 hari / 1 GB)
- 📋 **Cek status akun** yang sudah beli
- ❓ **Menu bantuan** & cara setting VPN

### 👑 Untuk Admin
- ✅ `!approve <id>` — Setujui order & akun langsung aktif otomatis
- ❌ `!reject <id> [alasan]` — Tolak order dengan alasan
- 📋 `!listorder` — Lihat semua order pending
- 🎁 `!trial <nomor>` — Beri trial gratis ke user
- 🆓 `!gratis <nomor> <user> <pass> <hari>` — Buat akun gratis
- 🔁 `!renew <username> <hari>` — Perpanjang akun VPN
- 🗑️ `!hapusakun <username>` — Hapus akun VPN
- 📊 `!stats` — Statistik lengkap (order, pendapatan, akun)
- 📢 `!broadcast <pesan>` — Kirim pesan ke semua pembeli
- 🌅 `!setqris` — Set gambar QRIS (kirim foto + caption !setqris)
- ⚙️ `!setdana <nomor>` — Ubah nomor DANA
- 📱 `!infowa <nomor>` — Info detail seorang pembeli

---

## 📋 Syarat & Kebutuhan

- VPS dengan **OGH-ZIV ZiVPN** sudah terinstall
- OS: **Debian** atau **Ubuntu**
- RAM minimal 512 MB (rekomendasi 1 GB+)
- Node.js 18+ (diinstall otomatis)
- Akun **WhatsApp Business** (atau WA biasa) aktif

---

## 🚀 Cara Install

### Opsi 1: Install Otomatis (Recommended)

```bash
# Upload folder ini ke VPS, lalu jalankan:
chmod +x install.sh
bash install.sh
```

### Opsi 2: Install Manual

```bash
# 1. Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# 2. Install dependensi sistem
apt-get install -y chromium-browser libnss3 libatk1.0-0

# 3. Masuk ke folder bot
cd /path/ke/wa-bot-zivpn

# 4. Install npm packages
npm install

# 5. Edit konfigurasi
nano config.js
```

---

## ⚙️ Konfigurasi

Edit file `config.js`:

```js
module.exports = {
    BRAND: 'NAMA TOKO KAMU',

    ADMIN_NUMBERS: [
        '6281234567890',   // Nomor WA admin (tanpa + dan -)
    ],

    DANA_NUMBER: '081234567890',
    DANA_NAME: 'Nama Pemilik DANA',

    // PAKET sudah ada default, bisa diubah sesuai kebutuhan
};
```

---

## 📱 Cara Pakai (Pertama Kali)

### 1. Scan QR Code
```bash
# Jalankan bot dalam mode interaktif untuk scan QR
bot-wa qr
```
Scan QR code yang muncul menggunakan WA yang ingin dijadikan bot.

### 2. Jalankan sebagai Service
```bash
bot-wa start    # Mulai bot
bot-wa status   # Cek status
bot-wa log      # Lihat log
```

### 3. Set QRIS (Opsional)
Kirim pesan ke bot dari nomor admin:
- Kirim **foto QRIS** dengan caption **`!setqris`**

---

## 💬 Alur Order Pembeli

```
Pembeli kirim "menu" / "halo"
    ↓
Bot tampilkan menu utama
    ↓
Pembeli pilih "1" (Beli)
    ↓
Bot tampilkan pilihan paket (15hr / 30hr)
    ↓
Pembeli pilih paket
    ↓
Bot tampilkan metode bayar (DANA / QRIS)
    ↓
Pembeli pilih metode → Bot kirim info pembayaran
    ↓
Pembeli transfer → Kirim SCREENSHOT bukti bayar
    ↓
Bot minta USERNAME yang diinginkan
    ↓
Bot minta PASSWORD yang diinginkan
    ↓
Bot tampilkan ringkasan order → Pembeli konfirmasi
    ↓
Bot kirim notifikasi + screenshot ke ADMIN
    ↓
Admin ketik !approve <id>
    ↓
Akun VPN OTOMATIS AKTIF → Detail dikirim ke pembeli ✅
```

---

## 🎁 Alur Trial

```
Pembeli kirim "trial" / "2"
    ↓
Bot cek: sudah trial hari ini? (1x per hari)
    ↓ Belum
Bot buat akun trial otomatis
    ↓
Akun trial langsung aktif (tanpa approval admin)
    ↓
Detail akun dikirim ke pembeli ✅
```

---

## 📁 Struktur File

```
wa-bot-zivpn/
├── bot.js          ← Bot utama (entry point)
├── config.js       ← Konfigurasi (EDIT INI)
├── database.js     ← Database SQLite helper
├── vpn.js          ← Integrasi ZiVPN
├── install.sh      ← Script install otomatis
├── package.json    ← npm dependencies
├── bot.db          ← Database (auto-dibuat)
├── screenshots/    ← Folder bukti bayar
├── qris.jpg        ← Gambar QRIS (upload via !setqris)
└── .wwebjs_auth/   ← Session WhatsApp (auto-dibuat)
```

---

## 🔧 Perintah Berguna

```bash
bot-wa start     # Mulai bot
bot-wa stop      # Stop bot
bot-wa restart   # Restart bot
bot-wa status    # Cek status
bot-wa log       # Lihat 50 baris log terakhir
bot-wa qr        # Scan QR ulang (jika session expired)
```

---

## ⚠️ Catatan Penting

1. **Bot harus dijalankan di VPS yang sama** dengan OGH-ZIV ZiVPN karena perlu akses ke `/etc/zivpn/users.db`
2. **Jalankan sebagai root** agar bisa baca/tulis file system dan restart service zivpn
3. **Backup `bot.db`** secara berkala untuk data order dan pembeli
4. **Session WhatsApp** tersimpan di `.wwebjs_auth/` — jangan dihapus
5. Jika session expired, jalankan `bot-wa qr` untuk scan ulang

---

## 💰 Harga Default

| Paket | Durasi | Harga |
|-------|--------|-------|
| Starter | 15 hari | Rp 5.000 |
| Premium | 30 hari | Rp 10.000 |

Ubah di `config.js` bagian `PAKET`.

---

**Made for OGH-ZIV VPN Panel** 🔐
