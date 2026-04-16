// ============================================================
//   KONFIGURASI BOT WHATSAPP - OGH-ZIV UDP ZIVPN
//   Edit file ini sesuai dengan data kamu!
// ============================================================

module.exports = {

    // ── IDENTITAS BOT ────────────────────────────────────────
    BRAND: 'OGH-ZIV VPN',          // Nama toko/brand kamu

    // ── ADMIN ────────────────────────────────────────────────
    // Format: nomor WA tanpa + dan tanpa simbol
    // Contoh: '6281234567890' untuk +62 812-3456-7890
    ADMIN_NUMBERS: [
        '6281234567890',            // Admin utama (WAJIB DIISI)
        // '6289876543210',         // Admin tambahan (opsional, hapus // untuk aktifkan)
    ],

    // ── PEMBAYARAN ───────────────────────────────────────────
    // DANA
    DANA_NUMBER: '081234567890',    // Nomor DANA kamu
    DANA_NAME: 'Nama Pemilik DANA', // Nama pemilik akun DANA

    // QRIS — kirim gambar QRIS via WA dengan caption !setqris
    //        atau letakkan file gambar di folder ini dengan nama qris.jpg
    QRIS_PATH: '',                  // Otomatis diisi saat !setqris

    // ── HARGA PAKET ─────────────────────────────────────────
    PAKET: [
        {
            id: '15hari',
            nama: '15 Hari',
            hari: 15,
            harga: 5000,
            kuota: 'Unlimited',
            max_login: 2,
        },
        {
            id: '30hari',
            nama: '30 Hari',
            hari: 30,
            harga: 10000,
            kuota: 'Unlimited',
            max_login: 2,
        },
    ],

    // ── TRIAL ────────────────────────────────────────────────
    TRIAL_HARI: 1,          // Durasi trial dalam hari
    TRIAL_KUOTA_GB: 1,      // Kuota trial dalam GB (1 = 1GB)
    TRIAL_MAX_LOGIN: 1,     // Maks perangkat untuk trial

    // ── PATH FILE ZIVPN (jangan ubah jika pakai script OGH-ZIV) ──
    UDB_PATH: '/etc/zivpn/users.db',     // Database akun VPN
    CFG_PATH: '/etc/zivpn/config.json',  // Konfigurasi ZiVPN
    DOMAIN_PATH: '/etc/zivpn/domain.conf',
    LOG_PATH: '/etc/zivpn/zivpn.log',

    // ── PESAN SELAMAT DATANG ─────────────────────────────────
    WELCOME_MSG: '',    // Kosongkan untuk pakai default

    // ── WAKTU TIMEOUT ORDER (jam) ────────────────────────────
    ORDER_TIMEOUT_JAM: 24,    // Order otomatis expired setelah 24 jam

};
