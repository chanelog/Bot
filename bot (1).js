'use strict';

// ============================================================
//   BOT WHATSAPP BISNIS — OGH-ZIV UDP ZIVPN
//   Library : whatsapp-web.js
//   Fitur   : Order, Trial, Pembayaran DANA/QRIS,
//             Admin Panel, Broadcast, Auto-Approve
// ============================================================

const { Client, LocalAuth, MessageMedia } = require('whatsapp-web.js');
const qrcode  = require('qrcode-terminal');
const fs      = require('fs');
const path    = require('path');

const config  = require('./config');
const db      = require('./database');
const vpn     = require('./vpn');

// ── Pastikan folder screenshots ada ──────────────────────────
fs.mkdirSync(path.join(__dirname, 'screenshots'), { recursive: true });

// ─────────────────────────────────────────────────────────────
//   HELPERS
// ─────────────────────────────────────────────────────────────
const fmt      = p => p.replace('@c.us', '').replace('@s.whatsapp.net', '');
const isAdmin  = p => config.ADMIN_NUMBERS.includes(fmt(p));
const genId    = () => Math.random().toString(36).substr(2, 8).toUpperCase();
const rupiah   = n => 'Rp' + Number(n).toLocaleString('id-ID');
const nowDate  = () => new Date().toLocaleString('id-ID', { timeZone: 'Asia/Jakarta' });
const sleep    = ms => new Promise(r => setTimeout(r, ms));

// ─────────────────────────────────────────────────────────────
//   STATE MACHINE (per nomor WA)
// ─────────────────────────────────────────────────────────────
const userStates = new Map();

function getState(phone)              { return userStates.get(phone) || { step: 'idle', data: {} }; }
function setState(phone, step, data)  { userStates.set(phone, { step, data: data || {} }); }
function resetState(phone)            { userStates.set(phone, { step: 'idle', data: {} }); }

// ─────────────────────────────────────────────────────────────
//   TEMPLATE PESAN
// ─────────────────────────────────────────────────────────────
function msgMenu() {
    const brand = config.BRAND;
    return (
`╔══════════════════════════╗
║   🌐 *${brand}*   
╚══════════════════════════╝

Halo! Selamat datang di layanan VPN UDP terbaik! 👋

Pilih menu:

🛒 *1* — Beli Akun VPN
🎁 *2* — Akun Trial Gratis (1x/hari)
📋 *3* — Cek Status Akun Saya
💰 *4* — Info Harga & Paket
❓ *5* — Bantuan & FAQ

━━━━━━━━━━━━━━━━━━━━━━
Ketik angka atau kata kunci 👆`
    );
}

function msgPaket() {
    let txt = `📦 *PILIH PAKET VPN*\n━━━━━━━━━━━━━━━━━━━━━━\n\n`;
    config.PAKET.forEach((p, i) => {
        txt += `*${i + 1}* — 📌 ${p.nama}\n`;
        txt += `    💰 Harga  : *${rupiah(p.harga)}*\n`;
        txt += `    📅 Aktif  : *${p.hari} hari*\n`;
        txt += `    📦 Kuota  : *${p.kuota}*\n`;
        txt += `    📱 Device : *${p.max_login} perangkat*\n\n`;
    });
    txt += `━━━━━━━━━━━━━━━━━━━━━━\n`;
    txt += `Balas *1* atau *2* untuk pilih paket.\nKetik *batal* untuk kembali.`;
    return txt;
}

function msgMetodeBayar(paket) {
    return (
`💳 *PILIH METODE PEMBAYARAN*
━━━━━━━━━━━━━━━━━━━━━━

📦 Paket  : *${paket.nama}*
💰 Harga  : *${rupiah(paket.harga)}*
📅 Aktif  : *${paket.hari} hari*

Pilih metode:
*1* — 💙 DANA
*2* — 📱 QRIS

━━━━━━━━━━━━━━━━━━━━━━
Ketik *batal* untuk kembali.`
    );
}

function msgInfoDANA(amount) {
    return (
`💙 *PEMBAYARAN VIA DANA*
━━━━━━━━━━━━━━━━━━━━━━

📱 Nomor DANA : *${config.DANA_NUMBER}*
👤 Atas Nama  : *${config.DANA_NAME}*
💰 Nominal    : *${rupiah(amount)}*

⚠️ *PENTING:*
• Transfer nominal TEPAT ${rupiah(amount)}
• Jangan tambahkan angka unik
• Jangan transfer lebih/kurang

━━━━━━━━━━━━━━━━━━━━━━
Setelah transfer, *kirim screenshot bukti* pembayaran di chat ini. 📸`
    );
}

function msgInfoQRIS(amount) {
    return (
`📱 *PEMBAYARAN VIA QRIS*
━━━━━━━━━━━━━━━━━━━━━━

💰 Nominal: *${rupiah(amount)}*

Scan QRIS di atas menggunakan:
• GoPay, OVO, DANA, LinkAja
• Mobile Banking manapun
• Dompet digital lainnya

━━━━━━━━━━━━━━━━━━━━━━
Setelah scan & bayar, *kirim screenshot bukti* di chat ini. 📸`
    );
}

function msgMintaUsername() {
    return (
`✅ *Screenshot bukti bayar diterima!*

Sekarang, ketik *username* yang ingin kamu pakai untuk akun VPN:

📌 *Aturan username:*
• Hanya huruf, angka, dan _ (underscore)
• Minimal 4, maksimal 20 karakter
• Tidak boleh sudah dipakai orang lain
• Contoh: \`john_vpn\`, \`user123\`

Ketik usernamenya 👇`
    );
}

function msgMintaPassword() {
    return (
`✅ *Username tersedia!*

Sekarang, ketik *password* untuk akunmu:

📌 *Aturan password:*
• Minimal 6 karakter
• Boleh huruf, angka, dan simbol
• Contoh: \`Pass@123\`, \`VPN_ku22\`

Ketik passwordnya 👇`
    );
}

function msgKonfirmasiOrder(data) {
    return (
`📋 *RINGKASAN ORDER*
━━━━━━━━━━━━━━━━━━━━━━
📦 Paket    : *${data.package_name}* (${data.days} hari)
💰 Harga    : *${rupiah(data.amount)}*
💳 Bayar via: *${data.payment_method}*
🔑 Username : \`${data.vpn_username}\`
🔐 Password : \`${data.vpn_password}\`
━━━━━━━━━━━━━━━━━━━━━━

✅ Setelah konfirmasi, *akun langsung aktif otomatis!*

Apakah data di atas sudah benar?
Balas *ya* untuk submit & aktifkan akun
Balas *batal* untuk membatalkan`
    );
}

function msgOrderSubmitted(orderId) {
    return (
`✅ *Order berhasil dikirim!*
━━━━━━━━━━━━━━━━━━━━━━

🆔 ID Order : *${orderId}*
⏳ Status   : *Menunggu konfirmasi admin*

Admin akan mengecek bukti bayarmu dan mengaktifkan akun dalam beberapa menit.

📌 *Simpan ID order ini:* \`${orderId}\`

Ketik *menu* untuk kembali ke menu utama.`
    );
}

function msgAkun(akun, isTrial = false) {
    const trialNote = isTrial
        ? `\n⚠️ _Akun trial hanya berlaku ${config.TRIAL_HARI} hari & ${config.TRIAL_KUOTA_GB} GB_\n`
        : '';
    return (
`╔═══════════════════════════╗
║  🔐 *AKUN VPN ${config.BRAND}*
╚═══════════════════════════╝

👤 *Username* : \`${akun.username}\`
🔑 *Password* : \`${akun.password}\`

🌐 *Host/IP*  : \`${akun.domain}\`
🔌 *Port*     : \`${akun.port}\`
📡 *Obfs*     : \`zivpn\`

📦 *Kuota*    : ${akun.quota}
📅 *Expired*  : ${akun.exp}
${trialNote}
━━━━━━━━━━━━━━━━━━━━━━
📲 Download *ZiVPN* di:
• Google Play Store
• Apple App Store

⚙️ *Cara setting:*
1. Buka ZiVPN
2. Tambah server baru
3. Isi Host, Port, Username, Password
4. Obfs: \`zivpn\`
5. Connect!

⚠️ _Dilarang share akun ini ke orang lain!_`
    );
}

function msgFAQ() {
    return (
`❓ *BANTUAN & FAQ*
━━━━━━━━━━━━━━━━━━━━━━

*📱 Apa itu ZiVPN?*
ZiVPN adalah aplikasi VPN protokol UDP yang cepat & stabil untuk bypass internet.

*📲 Download ZiVPN:*
• Play Store → cari "ZiVPN"
• App Store → cari "ZiVPN"

*⚙️ Cara Setting:*
1. Buka app ZiVPN
2. Tambah server → isi data akun
3. Kolom Obfs: ketik \`zivpn\`
4. Tap Connect

*💳 Metode Bayar:*
• DANA: ${config.DANA_NUMBER} (${config.DANA_NAME})
• QRIS: scan kode QR

*🎁 Trial:*
• Gratis 1x per hari
• Berlaku ${config.TRIAL_HARI} hari, kuota ${config.TRIAL_KUOTA_GB} GB

*❌ Jika tidak bisa connect:*
• Pastikan data akun benar
• Coba port 6000-19999 (fleksibel)
• Hubungi admin jika masih error

*📞 Hubungi Admin:*
wa.me/${config.ADMIN_NUMBERS[0]}
━━━━━━━━━━━━━━━━━━━━━━
Ketik *menu* untuk kembali`
    );
}

// ─────────────────────────────────────────────────────────────
//   WHATSAPP CLIENT
// ─────────────────────────────────────────────────────────────
const client = new Client({
    authStrategy: new LocalAuth({ clientId: 'zivpn-wa-bot', dataPath: './.wwebjs_auth' }),
    puppeteer: {
        headless: true,
        args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-dev-shm-usage',
            '--disable-accelerated-2d-canvas',
            '--no-first-run',
            '--no-zygote',
            '--single-process',
            '--disable-gpu',
            '--disable-extensions',
            '--disable-background-networking',
            '--disable-sync',
        ],
    },
});

// ── QR Code ──────────────────────────────────────────────────
client.on('qr', qr => {
    console.clear();
    console.log('\n🔷 Scan QR Code berikut di WhatsApp:\n');
    qrcode.generate(qr, { small: true });
    console.log('\n📲 Cara scan: WhatsApp → Perangkat Tertaut → Tautkan Perangkat\n');
});

// ── Ready ─────────────────────────────────────────────────────
client.on('ready', () => {
    console.log(`\n✅ Bot ${config.BRAND} siap digunakan!`);
    console.log(`📅 ${nowDate()}\n`);

    db.init();

    // Notifikasi ke semua admin
    config.ADMIN_NUMBERS.forEach(num => {
        client.sendMessage(`${num}@c.us`,
            `✅ *Bot ${config.BRAND} aktif!*\n` +
            `📅 ${nowDate()}\n\n` +
            `Ketik *!help* untuk daftar perintah admin.`
        ).catch(() => {});
    });

    // Cron: expire order lama setiap 30 menit
    setInterval(() => {
        db.expireOldOrders(config.ORDER_TIMEOUT_JAM || 24);
    }, 30 * 60 * 1000);

    // Cron: bersihkan akun expired setiap 6 jam
    setInterval(() => {
        const r = vpn.cleanExpired();
        if (r.removed > 0) console.log(`🧹 Auto-clean: ${r.removed} akun expired dihapus`);
    }, 6 * 60 * 60 * 1000);
});

client.on('disconnected', reason => {
    console.log('⚠️  Bot terputus:', reason);
    process.exit(1);
});

// ─────────────────────────────────────────────────────────────
//   MESSAGE HANDLER
// ─────────────────────────────────────────────────────────────
client.on('message', async msg => {
    if (msg.isStatus || msg.from === 'status@broadcast') return;
    if (msg.from.includes('@g.us')) return;  // skip grup

    const phone = msg.from;
    const body  = (msg.body || '').trim();
    const lower = body.toLowerCase();

    db.registerBuyer(fmt(phone));

    try {
        // Admin: SELALU jalankan handleAdmin jika pengirim adalah admin
        // Ini memastikan admin tidak terjebak di state user flow
        if (isAdmin(phone)) {
            // Cek apakah admin sedang dalam state !setqris (menunggu upload gambar)
            const adminState = getState(phone);
            if (adminState.step === 'admin_waiting_qris') {
                await handleAdmin(msg, phone, body, lower);
                return;
            }
            // Jika pesan dimulai dengan !, jalankan admin handler
            if (body.startsWith('!')) {
                await handleAdmin(msg, phone, body, lower);
                return;
            }
            // Jika admin ketik kata kunci user biasa (menu, halo, dll), tetap ke user handler
            // Tapi reset state admin jika ada
        }

        await handleUser(msg, phone, body, lower);
    } catch (e) {
        console.error('❌ Error:', e.message);
    }
});

// ─────────────────────────────────────────────────────────────
//   ADMIN HANDLER
// ─────────────────────────────────────────────────────────────
async function handleAdmin(msg, phone, body, lower) {
    const parts = body.trim().split(/\s+/);
    const state = getState(phone);

    // Handle state: admin sedang menunggu upload QRIS
    if (state.step === 'admin_waiting_qris') {
        const cmd = parts[0].toLowerCase();
        // Gunakan case admin_waiting_qris di switch di bawah
        // dengan cara set cmd ke state key
        switch (cmd) {
            case '!batal':
            case 'batal': {
                resetState(phone);
                await msg.reply('❌ Upload QRIS dibatalkan. Ketik *!help* untuk daftar perintah.');
                return;
            }
            default: {
                // Cek apakah ada gambar yang dikirim
                if (msg.hasMedia && (msg.type === 'image' || msg.type === 'document')) {
                    try {
                        const media    = await msg.downloadMedia();
                        const qrisPath = path.join(__dirname, 'qris.jpg');
                        fs.writeFileSync(qrisPath, Buffer.from(media.data, 'base64'));
                        config.QRIS_PATH = qrisPath;
                        resetState(phone);
                        await msg.reply(
                            `✅ *Gambar QRIS berhasil disimpan!*\n\n` +
                            `Pembeli akan melihat QRIS ini saat memilih metode pembayaran QRIS.\n\n` +
                            `Ketik *!help* untuk daftar perintah.`
                        );
                    } catch (e) {
                        await msg.reply(`❌ Gagal simpan QRIS: ${e.message}\n\nCoba kirim gambar lagi.`);
                    }
                } else {
                    await msg.reply(
                        `📸 Kirim *gambar* QRIS kamu.\n\n` +
                        `Pastikan file berupa gambar (JPG/PNG).\n` +
                        `Ketik *!batal* untuk membatalkan.`
                    );
                }
                return;
            }
        }
    }

    const cmd   = parts[0].toLowerCase();

    switch (cmd) {

        // ── !help ─────────────────────────────────────────────
        case '!help': {
            await msg.reply(
`🔧 *PERINTAH ADMIN ${config.BRAND}*
━━━━━━━━━━━━━━━━━━━━━━

*📋 Kelola Order:*
\`!listorder\` — Daftar order pending
\`!allorder\` — Semua order (20 terbaru)
\`!approve <id>\` — Setujui & aktifkan akun
\`!reject <id> [alasan]\` — Tolak order
\`!cekorder <id>\` — Detail order

*👤 Akun Manual:*
\`!trial <nomor_wa>\` — Buat trial gratis untuk user
\`!gratis <nomor> <user> <pass> <hari>\` — Buat akun gratis
\`!renew <user> <hari>\` — Perpanjang akun VPN
\`!hapusakun <username>\` — Hapus akun VPN
\`!listakun\` — Daftar semua akun VPN
\`!infoak <username>\` — Detail akun VPN

*📊 Statistik:*
\`!stats\` — Statistik bot & VPN
\`!infowa <nomor>\` — Info pembeli

*📢 Broadcast:*
\`!broadcast <pesan>\` — Kirim ke semua pembeli

*⚙️ Pengaturan:*
\`!setdana <nomor>\` — Set nomor DANA
\`!setdananame <nama>\` — Set nama DANA
\`!setbrand <nama>\` — Set nama brand
→ Kirim gambar + caption \`!setqris\` untuk set QRIS`
            );
            break;
        }

        // ── !stats ────────────────────────────────────────────
        case '!stats': {
            const s = db.getStats();
            const v = vpn.getVpnStats();
            await msg.reply(
`📊 *STATISTIK ${config.BRAND}*
━━━━━━━━━━━━━━━━━━━━━━

*💼 Order:*
• Total order  : ${s.total_orders}
• Pending      : ${s.pending_orders}
• Disetujui    : ${s.approved_orders}
• Ditolak      : ${s.rejected_orders}

*👥 Pembeli:*
• Total pembeli: ${s.total_buyers}
• Trial hari ini: ${s.today_trials}

*💰 Pendapatan:*
• Hari ini     : ${rupiah(s.today_income)}
• Total        : ${rupiah(s.total_income)}

*🔐 Akun VPN:*
• Total        : ${v.total}
• Aktif        : ${v.active}
• Expired      : ${v.expired}

📅 ${nowDate()}`
            );
            break;
        }

        // ── !listorder ────────────────────────────────────────
        case '!listorder': {
            const orders = db.getPendingOrders();
            if (orders.length === 0) {
                await msg.reply('✅ Tidak ada order pending saat ini.');
                return;
            }
            let txt = `📋 *ORDER PENDING (${orders.length}):*\n━━━━━━━━━━━━━━━━━\n`;
            orders.slice(0, 10).forEach((o, i) => {
                const tgl = new Date(o.created_at * 1000).toLocaleString('id-ID');
                txt += `\n*${i+1}. 🆔 ${o.id}*\n`;
                txt += `📱 WA    : +${o.phone}\n`;
                txt += `📦 Paket : ${o.package_name} (${rupiah(o.amount)})\n`;
                txt += `💳 Bayar : ${o.payment_method}\n`;
                txt += `🔑 User  : \`${o.vpn_username}\`\n`;
                txt += `📅 Waktu : ${tgl}\n`;
                txt += `—\`!approve ${o.id}\` | \`!reject ${o.id}\`\n`;
            });
            if (orders.length > 10) txt += `\n...dan ${orders.length - 10} order lainnya`;
            await msg.reply(txt);
            break;
        }

        // ── !allorder ─────────────────────────────────────────
        case '!allorder': {
            const orders = db.getAllOrders().slice(0, 20);
            if (orders.length === 0) { await msg.reply('📋 Belum ada order.'); return; }
            let txt = `📋 *SEMUA ORDER (${orders.length} terbaru):*\n━━━━━━━━━━━━━\n`;
            orders.forEach((o, i) => {
                const statusEmoji = { pending: '⏳', approved: '✅', rejected: '❌', expired: '💀' }[o.status] || '❓';
                txt += `${i+1}. ${statusEmoji} *${o.id}* — +${o.phone} — ${o.package_name}\n`;
            });
            await msg.reply(txt);
            break;
        }

        // ── !cekorder <id> ────────────────────────────────────
        case '!cekorder': {
            const orderId = parts[1];
            if (!orderId) { await msg.reply('❌ Format: !cekorder <id>'); return; }
            const o = db.getOrder(orderId);
            if (!o) { await msg.reply(`❌ Order *${orderId}* tidak ditemukan.`); return; }
            const tgl = new Date(o.created_at * 1000).toLocaleString('id-ID');
            await msg.reply(
`📋 *Detail Order ${orderId}*
━━━━━━━━━━━━━━━━━
📱 WA         : +${o.phone}
📦 Paket      : ${o.package_name} (${o.days} hari)
💰 Nominal    : ${rupiah(o.amount)}
💳 Metode     : ${o.payment_method}
🔑 VPN User   : \`${o.vpn_username}\`
🔐 VPN Pass   : \`${o.vpn_password}\`
📊 Status     : ${o.status}
📅 Waktu      : ${tgl}`
            );
            // Kirim screenshot jika ada
            if (o.screenshot_path && fs.existsSync(o.screenshot_path)) {
                const ssMedia = MessageMedia.fromFilePath(o.screenshot_path);
                await client.sendMessage(phone, ssMedia, { caption: `📸 Bukti bayar order ${orderId}` });
            }
            break;
        }

        // ── !approve <id> ─────────────────────────────────────
        case '!approve': {
            const orderId = parts[1];
            if (!orderId) { await msg.reply('❌ Format: !approve <id>'); return; }

            const o = db.getOrder(orderId);
            if (!o) { await msg.reply(`❌ Order *${orderId}* tidak ditemukan.`); return; }
            if (o.status !== 'pending') {
                await msg.reply(`⚠️ Order *${orderId}* sudah berstatus *${o.status}*.`);
                return;
            }

            // Buat akun VPN
            const result = vpn.createUser(o.vpn_username, o.vpn_password, o.days, 'Unlimited', `+${o.phone}`);
            if (!result.success) {
                await msg.reply(`❌ Gagal buat akun VPN:\n${result.error}`);
                return;
            }

            db.updateOrderStatus(orderId, 'approved');

            // Kirim akun ke pembeli
            const akun = vpn.getAccountInfo(o.vpn_username);
            if (akun) {
                await client.sendMessage(`${o.phone}@c.us`,
                    `🎉 *Pembayaran dikonfirmasi!*\n\n` +
                    `Terima kasih sudah order di *${config.BRAND}*!\n` +
                    `Berikut akun VPN kamu:\n\n` +
                    msgAkun(akun)
                );
            }

            await msg.reply(
                `✅ Order *${orderId}* disetujui!\n` +
                `Akun *${o.vpn_username}* aktif hingga *${result.exp}*\n` +
                `Akun sudah dikirim ke +${o.phone}`
            );
            break;
        }

        // ── !reject <id> [alasan] ─────────────────────────────
        case '!reject': {
            const orderId = parts[1];
            const alasan  = parts.slice(2).join(' ') || 'Bukti pembayaran tidak valid';
            if (!orderId) { await msg.reply('❌ Format: !reject <id> [alasan]'); return; }

            const o = db.getOrder(orderId);
            if (!o) { await msg.reply(`❌ Order *${orderId}* tidak ditemukan.`); return; }
            if (o.status !== 'pending') {
                await msg.reply(`⚠️ Order *${orderId}* sudah berstatus *${o.status}*.`);
                return;
            }

            db.updateOrderStatus(orderId, 'rejected');

            await client.sendMessage(`${o.phone}@c.us`,
                `❌ *Order Kamu Ditolak*\n━━━━━━━━━━━━━━━━\n` +
                `🆔 ID Order : ${orderId}\n` +
                `❓ Alasan   : ${alasan}\n\n` +
                `Jika ada pertanyaan, hubungi admin:\n` +
                `wa.me/${config.ADMIN_NUMBERS[0]}\n\n` +
                `Ketik *menu* untuk kembali ke menu utama.`
            );

            await msg.reply(`✅ Order *${orderId}* ditolak. Pembeli sudah diberitahu.`);
            break;
        }

        // ── !trial <nomor_wa> ─────────────────────────────────
        case '!trial': {
            const targetRaw = parts[1]?.replace(/[^0-9]/g, '');
            if (!targetRaw) { await msg.reply('❌ Format: !trial <nomor_wa>'); return; }

            const result = vpn.createTrialUser(targetRaw);
            if (!result.success) { await msg.reply(`❌ Gagal buat trial:\n${result.error}`); return; }

            db.recordTrial(targetRaw);
            db.registerBuyer(targetRaw);

            const akun = vpn.getAccountInfo(result.username);
            const targetJid = `${targetRaw}@c.us`;

            await client.sendMessage(targetJid,
                `🎁 *Admin memberimu akun Trial GRATIS!*\n\n${msgAkun(akun, true)}`
            ).catch(() => {});

            await msg.reply(`✅ Trial berhasil dikirim ke +${targetRaw}\n🔑 Username: \`${result.username}\``);
            break;
        }

        // ── !gratis <nomor> <user> <pass> <hari> ─────────────
        case '!gratis': {
            const [, nomor, vpnUser, vpnPass, hariStr] = parts;
            if (!nomor || !vpnUser || !vpnPass || !hariStr) {
                await msg.reply('❌ Format: !gratis <nomor> <username> <password> <hari>');
                return;
            }
            const cleanNum = nomor.replace(/[^0-9]/g, '');
            const hari     = parseInt(hariStr) || 30;
            const result   = vpn.createUser(vpnUser, vpnPass, hari, 'Unlimited', `+${cleanNum}-GRATIS`);
            if (!result.success) { await msg.reply(`❌ Gagal:\n${result.error}`); return; }

            const akun = vpn.getAccountInfo(vpnUser);
            db.registerBuyer(cleanNum);

            await client.sendMessage(`${cleanNum}@c.us`,
                `🎁 *Kamu mendapat akun VPN GRATIS dari Admin!*\n\n${msgAkun(akun)}`
            ).catch(() => {});

            await msg.reply(`✅ Akun gratis berhasil dikirim ke +${cleanNum}\n📅 Expired: ${result.exp}`);
            break;
        }

        // ── !renew <username> <hari> ──────────────────────────
        case '!renew': {
            const [, uname, hariStr] = parts;
            if (!uname || !hariStr) { await msg.reply('❌ Format: !renew <username> <hari>'); return; }
            const result = vpn.renewUser(uname, parseInt(hariStr));
            if (!result.success) { await msg.reply(`❌ Gagal perpanjang:\n${result.error}`); return; }
            await msg.reply(`✅ Akun *${uname}* diperpanjang!\n📅 Expired baru: *${result.newExp}*`);
            break;
        }

        // ── !hapusakun <username> ─────────────────────────────
        case '!hapusakun': {
            const uname = parts[1];
            if (!uname) { await msg.reply('❌ Format: !hapusakun <username>'); return; }
            const result = vpn.deleteUser(uname);
            if (result.success) {
                await msg.reply(`✅ Akun *${uname}* berhasil dihapus.`);
            } else {
                await msg.reply(`❌ Gagal hapus:\n${result.error}`);
            }
            break;
        }

        // ── !listakun ─────────────────────────────────────────
        case '!listakun': {
            const users = vpn.listUsers();
            if (users.length === 0) { await msg.reply('📋 Belum ada akun VPN.'); return; }
            const today = new Date().toISOString().split('T')[0];
            let txt = `📋 *AKUN VPN (${users.length} total):*\n━━━━━━━━━━━━━━━━━\n`;
            users.slice(0, 25).forEach((u, i) => {
                const isExp = u.exp < today;
                txt += `${i+1}. ${isExp ? '🔴' : '🟢'} \`${u.username}\` — ${u.exp}\n`;
            });
            if (users.length > 25) txt += `\n...dan ${users.length - 25} akun lainnya`;
            const stats = vpn.getVpnStats();
            txt += `\n━━━━━━━━━━━━━\n🟢 Aktif: ${stats.active} | 🔴 Expired: ${stats.expired}`;
            await msg.reply(txt);
            break;
        }

        // ── !infoak <username> ────────────────────────────────
        case '!infoak': {
            const uname = parts[1];
            if (!uname) { await msg.reply('❌ Format: !infoak <username>'); return; }
            const akun = vpn.getAccountInfo(uname);
            if (!akun) { await msg.reply(`❌ Akun *${uname}* tidak ditemukan.`); return; }
            await msg.reply(
`🔍 *Detail Akun VPN*
━━━━━━━━━━━━━━━━━
🔑 Username : \`${akun.username}\`
🔐 Password : \`${akun.password}\`
📅 Expired  : ${akun.exp}
📦 Kuota    : ${akun.quota}
📝 Note     : ${akun.note || '-'}`
            );
            break;
        }

        // ── !infowa <nomor> ───────────────────────────────────
        case '!infowa': {
            const nomor = parts[1]?.replace(/[^0-9]/g, '');
            if (!nomor) { await msg.reply('❌ Format: !infowa <nomor>'); return; }
            const orders     = db.getOrdersByPhone(nomor);
            const trialCount = db.getTrialCount(nomor);
            let txt = `📱 *Info WA: +${nomor}*\n━━━━━━━━━━━━━━\n`;
            txt += `🛒 Total order : ${orders.length}\n`;
            txt += `✅ Disetujui   : ${orders.filter(o => o.status === 'approved').length}\n`;
            txt += `🎁 Trial       : ${trialCount}x\n`;
            if (orders.length > 0) {
                const last = orders[0];
                txt += `\nOrder terakhir:\n`;
                txt += `• ID: ${last.id}\n`;
                txt += `• Paket: ${last.package_name}\n`;
                txt += `• Status: ${last.status}\n`;
                txt += `• Waktu: ${new Date(last.created_at * 1000).toLocaleString('id-ID')}`;
            }
            await msg.reply(txt);
            break;
        }

        // ── !broadcast <pesan> ────────────────────────────────
        case '!broadcast': {
            const pesan = parts.slice(1).join(' ');
            if (!pesan) { await msg.reply('❌ Format: !broadcast <pesan>'); return; }
            const buyers = db.getAllBuyers();
            await msg.reply(`📢 Memulai broadcast ke ${buyers.length} pembeli...`);
            let sent = 0, failed = 0;
            for (const buyer of buyers) {
                try {
                    await client.sendMessage(`${buyer.phone}@c.us`,
                        `📢 *${config.BRAND}*\n━━━━━━━━━━━━━━━━\n${pesan}`
                    );
                    sent++;
                    await sleep(2000); // delay 2 detik antar kirim
                } catch { failed++; }
            }
            await msg.reply(`✅ Broadcast selesai!\n✉️ Terkirim: ${sent} | ❌ Gagal: ${failed}`);
            break;
        }

        // ── !setdana <nomor> ──────────────────────────────────
        case '!setdana': {
            const num = parts[1];
            if (!num) { await msg.reply('❌ Format: !setdana <nomor>'); return; }
            config.DANA_NUMBER = num;
            await msg.reply(`✅ Nomor DANA diubah ke: *${num}*\n\n⚠️ Perubahan hanya berlaku selama bot berjalan.\nEdit file \`config.js\` untuk permanen.`);
            break;
        }

        // ── !setdananame <nama> ───────────────────────────────
        case '!setdananame': {
            const nama = parts.slice(1).join(' ');
            if (!nama) { await msg.reply('❌ Format: !setdananame <nama>'); return; }
            config.DANA_NAME = nama;
            await msg.reply(`✅ Nama DANA diubah ke: *${nama}*`);
            break;
        }

        // ── !setbrand <nama> ──────────────────────────────────
        case '!setbrand': {
            const nama = parts.slice(1).join(' ');
            if (!nama) { await msg.reply('❌ Format: !setbrand <nama>'); return; }
            config.BRAND = nama;
            await msg.reply(`✅ Nama brand diubah ke: *${nama}*`);
            break;
        }

        // ── !setqris (dua cara: kirim gambar+caption, atau ketik !setqris dulu lalu upload) ────
        case '!setqris': {
            if (msg.hasMedia) {
                // Cara 1: kirim gambar dengan caption !setqris
                try {
                    const media    = await msg.downloadMedia();
                    const qrisPath = path.join(__dirname, 'qris.jpg');
                    fs.writeFileSync(qrisPath, Buffer.from(media.data, 'base64'));
                    config.QRIS_PATH = qrisPath;
                    resetState(phone);
                    await msg.reply('✅ Gambar QRIS berhasil disimpan! Pembeli akan melihat QRIS ini saat order.\n\nKetik *!help* untuk daftar perintah.');
                } catch (e) {
                    await msg.reply(`❌ Gagal simpan QRIS: ${e.message}`);
                }
            } else {
                // Cara 2: ketik !setqris dulu, bot minta upload gambar
                setState(phone, 'admin_waiting_qris', {});
                await msg.reply(
                    `📸 *Upload Gambar QRIS*\n━━━━━━━━━━━━━━━━━\n\n` +
                    `Sekarang kirim *gambar QRIS* kamu di chat ini.\n\n` +
                    `Bot akan otomatis menyimpan dan mengaktifkannya.\n\n` +
                    `Ketik *!batal* untuk membatalkan.`
                );
            }
            break;
        }

        // ── State: admin sedang menunggu upload QRIS ──────────
        case 'admin_waiting_qris': {
            if (lower === '!batal' || lower === 'batal') {
                resetState(phone);
                await msg.reply('❌ Upload QRIS dibatalkan. Ketik *!help* untuk daftar perintah.');
                return;
            }
            if (msg.hasMedia && (msg.type === 'image' || msg.type === 'document')) {
                try {
                    const media    = await msg.downloadMedia();
                    const qrisPath = path.join(__dirname, 'qris.jpg');
                    fs.writeFileSync(qrisPath, Buffer.from(media.data, 'base64'));
                    config.QRIS_PATH = qrisPath;
                    resetState(phone);
                    await msg.reply(
                        `✅ *Gambar QRIS berhasil disimpan!*\n\n` +
                        `Pembeli akan melihat QRIS ini saat memilih metode pembayaran QRIS.\n\n` +
                        `Ketik *!help* untuk daftar perintah.`
                    );
                } catch (e) {
                    await msg.reply(`❌ Gagal simpan QRIS: ${e.message}\n\nCoba kirim gambar lagi.`);
                }
            } else {
                await msg.reply(
                    `📸 Kirim *gambar* QRIS kamu.\n\n` +
                    `Pastikan file berupa gambar (JPG/PNG).\n` +
                    `Ketik *!batal* untuk membatalkan.`
                );
            }
            break;
        }

        // ── !cleanexpired ─────────────────────────────────────
        case '!cleanexpired': {
            const r = vpn.cleanExpired();
            await msg.reply(`🧹 Selesai!\n${r.removed} akun expired berhasil dihapus.`);
            break;
        }

        default: {
            await msg.reply(`❌ Perintah tidak dikenal. Ketik *!help* untuk daftar perintah.`);
        }
    }
}

// ─────────────────────────────────────────────────────────────
//   USER HANDLER
// ─────────────────────────────────────────────────────────────
async function handleUser(msg, phone, body, lower) {
    const state = getState(phone);

    // Kata kunci yang RESET semua state
    const menuTriggers = ['menu', 'halo', 'hai', 'hi', 'hello', 'start',
                          'mulai', 'batal', 'cancel', '0', 'kembali', '/start'];
    if (menuTriggers.includes(lower)) {
        resetState(phone);
        await msg.reply(msgMenu());
        return;
    }

    switch (state.step) {

        // ── IDLE: Menu utama ──────────────────────────────────
        case 'idle': {
            if (['1', 'beli', 'order', 'pesan', 'buy'].includes(lower)) {
                setState(phone, 'choose_package');
                await msg.reply(msgPaket());

            } else if (['2', 'trial', 'gratis', 'coba'].includes(lower)) {
                await doTrial(msg, phone);

            } else if (['3', 'cek', 'cek akun', 'status', 'akunsaya'].includes(lower)) {
                await doCekAkun(msg, phone);

            } else if (['4', 'harga', 'paket', 'info', 'daftar harga'].includes(lower)) {
                await msg.reply(msgPaket());

            } else if (['5', 'bantuan', 'help', 'faq', 'cara'].includes(lower)) {
                await msg.reply(msgFAQ());

            } else {
                await msg.reply(msgMenu());
            }
            break;
        }

        // ── Pilih paket ───────────────────────────────────────
        case 'choose_package': {
            const idx = parseInt(body) - 1;
            if (isNaN(idx) || idx < 0 || idx >= config.PAKET.length) {
                await msg.reply(`❌ Pilih angka *1* sampai *${config.PAKET.length}*\nAtau ketik *batal* untuk kembali.`);
                return;
            }
            const paket = config.PAKET[idx];
            setState(phone, 'choose_payment', { paket });
            await msg.reply(msgMetodeBayar(paket));
            break;
        }

        // ── Pilih metode pembayaran ───────────────────────────
        case 'choose_payment': {
            const { paket } = state.data;

            if (body === '1') {
                // DANA
                setState(phone, 'waiting_screenshot', { paket, payment_method: 'DANA' });
                await msg.reply(msgInfoDANA(paket.harga));

            } else if (body === '2') {
                // QRIS
                setState(phone, 'waiting_screenshot', { paket, payment_method: 'QRIS' });
                const qrisPath = path.join(__dirname, 'qris.jpg');
                if (fs.existsSync(qrisPath)) {
                    try {
                        const qrisMedia = MessageMedia.fromFilePath(qrisPath);
                        await client.sendMessage(phone, qrisMedia, {
                            caption: `📱 Scan QRIS ini untuk membayar *${rupiah(paket.harga)}*`
                        });
                        await sleep(500);
                    } catch {}
                }
                await msg.reply(msgInfoQRIS(paket.harga));

            } else {
                await msg.reply('❌ Pilih *1* (DANA) atau *2* (QRIS)\nAtau ketik *batal* untuk kembali.');
            }
            break;
        }

        // ── Tunggu screenshot ─────────────────────────────────
        case 'waiting_screenshot': {
            if (msg.hasMedia && (msg.type === 'image' || msg.type === 'document')) {
                const media   = await msg.downloadMedia();
                const orderId = genId();
                const ssDir   = path.join(__dirname, 'screenshots');
                const ssPath  = path.join(ssDir, `${orderId}.jpg`);
                fs.mkdirSync(ssDir, { recursive: true });
                fs.writeFileSync(ssPath, Buffer.from(media.data, 'base64'));

                setState(phone, 'input_username', {
                    ...state.data,
                    order_id: orderId,
                    screenshot_path: ssPath,
                });
                await msg.reply(msgMintaUsername());
            } else {
                await msg.reply(
                    `📸 *Kirim foto/screenshot* bukti pembayaranmu.\n\n` +
                    `Pastikan screenshot jelas terlihat nominal & penerimanya.\n\n` +
                    `Ketik *batal* untuk membatalkan order.`
                );
            }
            break;
        }

        // ── Input username ────────────────────────────────────
        case 'input_username': {
            const un = body.replace(/[^a-zA-Z0-9_]/g, '').toLowerCase();

            if (un.length < 4 || un.length > 20) {
                await msg.reply('❌ Username harus *4-20 karakter*, hanya huruf/angka/underscore.\n\nCoba masukkan username lain:');
                return;
            }
            if (vpn.userExists(un)) {
                await msg.reply(`❌ Username *${un}* sudah dipakai orang lain.\n\nCoba username lain (tambahkan angka, misal: \`${un}123\`)`);
                return;
            }

            setState(phone, 'input_password', { ...state.data, vpn_username: un });
            await msg.reply(msgMintaPassword());
            break;
        }

        // ── Input password ────────────────────────────────────
        case 'input_password': {
            const pw = body;
            if (pw.length < 6) {
                await msg.reply('❌ Password minimal *6 karakter*.\n\nCoba masukkan password lain:');
                return;
            }
            if (pw.includes(' ')) {
                await msg.reply('❌ Password tidak boleh mengandung spasi.\n\nCoba masukkan password lain:');
                return;
            }

            const d = { ...state.data, vpn_password: pw };
            setState(phone, 'confirm_order', d);
            await msg.reply(msgKonfirmasiOrder({
                package_name:   d.paket.nama,
                days:           d.paket.hari,
                amount:         d.paket.harga,
                payment_method: d.payment_method,
                vpn_username:   d.vpn_username,
                vpn_password:   pw,
            }));
            break;
        }

        // ── Konfirmasi order ──────────────────────────────────
        case 'confirm_order': {
            if (['ya', 'yes', 'iya', 'ok', 'y', 'confirm', 'setuju'].includes(lower)) {
                const d = state.data;

                await msg.reply(
                    `⏳ *Memproses order kamu...*\n\n` +
                    `Bot sedang memverifikasi bukti bayar dan membuat akun VPN.\n` +
                    `Mohon tunggu sebentar... 🔄`
                );

                // Buat akun VPN langsung (auto-approve)
                const result = vpn.createUser(d.vpn_username, d.vpn_password, d.paket.hari, 'Unlimited', `+${fmt(phone)}`);

                if (!result.success) {
                    await msg.reply(
                        `❌ *Gagal membuat akun VPN.*\n\n` +
                        `Alasan: ${result.error}\n\n` +
                        `Silakan hubungi admin:\nwa.me/${config.ADMIN_NUMBERS[0]}`
                    );
                    resetState(phone);
                    return;
                }

                // Simpan order ke database sebagai approved
                db.createOrder({
                    id:              d.order_id,
                    phone:           fmt(phone),
                    package_id:      d.paket.id,
                    package_name:    d.paket.nama,
                    days:            d.paket.hari,
                    amount:          d.paket.harga,
                    payment_method:  d.payment_method,
                    vpn_username:    d.vpn_username,
                    vpn_password:    d.vpn_password,
                    screenshot_path: d.screenshot_path,
                    status:          'approved',
                });

                resetState(phone);

                // Kirim info akun ke pembeli
                const akun = vpn.getAccountInfo(d.vpn_username);
                await msg.reply(
                    `✅ *Pembayaran terkonfirmasi! Akun VPN kamu sudah aktif!*\n\n` +
                    `Terima kasih sudah berlangganan *${config.BRAND}*! 🎉\n\n` +
                    (akun ? msgAkun(akun) : `🔑 Username: \`${d.vpn_username}\`\n🔐 Password: \`${d.vpn_password}\`\n📅 Aktif: ${d.paket.hari} hari`)
                );

                // Notifikasi admin (informasi saja, bukan perlu approve)
                await notifyAdminAutoApproved(d, fmt(phone), result.exp);

            } else if (['batal', 'tidak', 'no', 'n', 'cancel'].includes(lower)) {
                resetState(phone);
                await msg.reply('❌ Order dibatalkan.\n\nKetik *menu* untuk kembali ke menu utama.');
            } else {
                await msg.reply('Balas *ya* untuk konfirmasi order, atau *batal* untuk membatalkan.');
            }
            break;
        }

        default: {
            resetState(phone);
            await msg.reply(msgMenu());
        }
    }
}

// ─────────────────────────────────────────────────────────────
//   TRIAL
// ─────────────────────────────────────────────────────────────
async function doTrial(msg, phone) {
    const phoneNum = fmt(phone);

    if (db.hasTrialToday(phoneNum)) {
        await msg.reply(
            `⏳ *Trial sudah digunakan hari ini!*\n\n` +
            `Kamu hanya bisa mendapatkan *1 akun trial per hari*.\n\n` +
            `Coba lagi besok, atau langsung *beli* akun premium supaya tidak perlu tunggu.\n\n` +
            `Ketik *beli* untuk order akun premium sekarang.`
        );
        return;
    }

    const result = vpn.createTrialUser(phoneNum);
    if (!result.success) {
        await msg.reply(
            `❌ Gagal membuat akun trial.\n\n` +
            `Alasan: ${result.error}\n\n` +
            `Hubungi admin untuk bantuan:\nwa.me/${config.ADMIN_NUMBERS[0]}`
        );
        return;
    }

    db.recordTrial(phoneNum);
    const akun = vpn.getAccountInfo(result.username);

    await msg.reply(
        `🎁 *AKUN TRIAL GRATIS berhasil dibuat!*\n\n` + msgAkun(akun, true)
    );

    // Notif admin
    config.ADMIN_NUMBERS.forEach(adminNum => {
        client.sendMessage(`${adminNum}@c.us`,
            `🎁 *Trial baru:*\n📱 +${phoneNum}\n🔑 ${result.username}\n📅 Exp: ${result.exp}`
        ).catch(() => {});
    });
}

// ─────────────────────────────────────────────────────────────
//   CEK AKUN
// ─────────────────────────────────────────────────────────────
async function doCekAkun(msg, phone) {
    const phoneNum = fmt(phone);
    const orders   = db.getApprovedOrdersByPhone(phoneNum);

    if (orders.length === 0) {
        await msg.reply(
            `📋 *Tidak ada akun aktif ditemukan.*\n\n` +
            `Kemungkinan:\n` +
            `• Belum pernah beli akun\n` +
            `• Order masih pending (belum diapprove admin)\n` +
            `• Akun sudah expired\n\n` +
            `Ketik *beli* untuk order akun baru.`
        );
        return;
    }

    const today = new Date().toISOString().split('T')[0];
    let txt = `📋 *Akun kamu (${orders.length} order):*\n━━━━━━━━━━━━━━━━━\n`;

    orders.slice(0, 3).forEach((o, i) => {
        const akun = vpn.getAccountInfo(o.vpn_username);
        if (akun) {
            const isExp = akun.exp < today;
            txt += `\n*${i+1}. ${isExp ? '🔴 EXPIRED' : '🟢 AKTIF'}*\n`;
            txt += `🔑 Username : \`${akun.username}\`\n`;
            txt += `🔐 Password : \`${akun.password}\`\n`;
            txt += `📅 Expired  : ${akun.exp}\n`;
            txt += `🌐 Host     : \`${akun.domain}\`\n`;
            txt += `🔌 Port     : \`${akun.port}\`\n`;
        } else {
            txt += `\n*${i+1}.* Username: \`${o.vpn_username}\` _(data tidak ditemukan)_\n`;
        }
        txt += `────────────────\n`;
    });

    txt += `\nKetik *menu* untuk kembali ke menu utama.`;
    await msg.reply(txt);
}

// ─────────────────────────────────────────────────────────────
//   NOTIF ADMIN - AUTO APPROVED (informasi saja)
// ─────────────────────────────────────────────────────────────
async function notifyAdminAutoApproved(data, phone, exp) {
    const txt =
        `✅ *ORDER BARU — AUTO APPROVED*\n━━━━━━━━━━━━━━━━━\n` +
        `🆔 ID     : *${data.order_id}*\n` +
        `📱 WA     : +${phone}\n` +
        `📦 Paket  : ${data.paket.nama} (${data.paket.hari} hari)\n` +
        `💰 Harga  : ${rupiah(data.paket.harga)}\n` +
        `💳 Metode : ${data.payment_method}\n` +
        `🔑 User   : \`${data.vpn_username}\`\n` +
        `🔐 Pass   : \`${data.vpn_password}\`\n` +
        `📅 Exp    : ${exp || '-'}\n` +
        `━━━━━━━━━━━━━━━━━\n` +
        `✅ Akun sudah otomatis aktif.\n` +
        `📸 Bukti bayar tersimpan di server.\n\n` +
        `_Jika ada masalah, gunakan:_\n` +
        `\`!hapusakun ${data.vpn_username}\` — untuk hapus akun\n` +
        `\`!reject ${data.order_id} [alasan]\` — untuk tolak & notif pembeli`;

    for (const adminNum of config.ADMIN_NUMBERS) {
        const adminJid = `${adminNum}@c.us`;
        try {
            await client.sendMessage(adminJid, txt);
            await sleep(300);
            // Kirim screenshot bukti bayar ke admin
            if (data.screenshot_path && fs.existsSync(data.screenshot_path)) {
                const ssMedia = MessageMedia.fromFilePath(data.screenshot_path);
                await client.sendMessage(adminJid, ssMedia, {
                    caption: `📸 Bukti bayar order *${data.order_id}* (auto-approved)`
                });
            }
        } catch (e) {
            console.error(`❌ Gagal notif admin ${adminNum}:`, e.message);
        }
    }
}


async function notifyAdminOrder(data, phone) {
    const txt =
        `🔔 *ORDER BARU!*\n━━━━━━━━━━━━━━━━━\n` +
        `🆔 ID     : *${data.order_id}*\n` +
        `📱 WA     : +${phone}\n` +
        `📦 Paket  : ${data.paket.nama} (${data.paket.hari} hari)\n` +
        `💰 Harga  : ${rupiah(data.paket.harga)}\n` +
        `💳 Metode : ${data.payment_method}\n` +
        `🔑 User   : \`${data.vpn_username}\`\n` +
        `🔐 Pass   : \`${data.vpn_password}\`\n` +
        `━━━━━━━━━━━━━━━━━\n` +
        `✅ Approve: \`!approve ${data.order_id}\`\n` +
        `❌ Reject : \`!reject ${data.order_id} [alasan]\``;

    for (const adminNum of config.ADMIN_NUMBERS) {
        const adminJid = `${adminNum}@c.us`;
        try {
            await client.sendMessage(adminJid, txt);
            await sleep(300);
            // Kirim screenshot
            if (data.screenshot_path && fs.existsSync(data.screenshot_path)) {
                const ssMedia = MessageMedia.fromFilePath(data.screenshot_path);
                await client.sendMessage(adminJid, ssMedia, {
                    caption: `📸 Bukti bayar order *${data.order_id}*`
                });
            }
        } catch (e) {
            console.error(`❌ Gagal notif admin ${adminNum}:`, e.message);
        }
    }
}

// ─────────────────────────────────────────────────────────────
//   JALANKAN BOT
// ─────────────────────────────────────────────────────────────
console.log(`\n🚀 Memulai Bot ${config.BRAND}...`);
console.log('📦 Menginisialisasi WhatsApp Web...\n');

client.initialize();

// Handle shutdown gracefully
process.on('SIGINT', async () => {
    console.log('\n⚠️  Bot dihentikan.');
    await client.destroy().catch(() => {});
    process.exit(0);
});

process.on('unhandledRejection', (reason) => {
    console.error('❌ Unhandled rejection:', reason);
});
