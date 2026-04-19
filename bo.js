'use strict';

// ============================================================
//   BOT WHATSAPP PRIBADI — ZIVPN MANAGER
//   Perintah: !create, !trial, !backup, !restore
// ============================================================

const { Client, LocalAuth, MessageMedia } = require('whatsapp-web.js');
const qrcode  = require('qrcode-terminal');
const fs      = require('fs');
const path    = require('path');

const config  = require('./config');
const vpn     = require('./vpn');

// ─────────────────────────────────────────────────────────────
//   HELPERS
// ─────────────────────────────────────────────────────────────
const fmt     = p => p.replace('@c.us', '').replace('@s.whatsapp.net', '');
const isAdmin = p => config.ADMIN_NUMBERS.includes(fmt(p));
const sleep   = ms => new Promise(r => setTimeout(r, ms));
const nowDate = () => new Date().toLocaleString('id-ID', { timeZone: 'Asia/Jakarta' });

// ─────────────────────────────────────────────────────────────
//   STATE MACHINE
// ─────────────────────────────────────────────────────────────
const userStates = new Map();
function getState(phone)             { return userStates.get(phone) || { step: 'idle', data: {} }; }
function setState(phone, step, data) { userStates.set(phone, { step, data: data || {} }); }
function resetState(phone)           { userStates.set(phone, { step: 'idle', data: {} }); }

// ─────────────────────────────────────────────────────────────
//   WHATSAPP CLIENT
// ─────────────────────────────────────────────────────────────
const client = new Client({
    authStrategy: new LocalAuth({ clientId: 'zivpn-wa-bot', dataPath: './.wwebjs_auth' }),
    puppeteer: {
        headless: true,
        args: [
            '--no-sandbox', '--disable-setuid-sandbox',
            '--disable-dev-shm-usage', '--disable-gpu',
            '--no-first-run', '--no-zygote', '--single-process',
        ],
    },
});

// ─────────────────────────────────────────────────────────────
//   TEMPLATE PESAN
// ─────────────────────────────────────────────────────────────
function msgMenu() {
    return (
`╔══════════════════════════╗
║   🔐 *ZIVPN MANAGER*
╚══════════════════════════╝

Perintah yang tersedia:

🆕 *!create* — Buat akun VPN baru
⏱️ *!trial* — Buat akun trial (menit)
💾 *!backup* — Backup database akun
♻️ *!restore* — Restore database dari file
📋 *!listakun* — Daftar semua akun
🔍 *!info <user>* — Detail akun
🗑️ *!hapus <user>* — Hapus akun
🔄 *!renew <user> <hari>* — Perpanjang akun

━━━━━━━━━━━━━━━━━━━━━━
Ketik *batal* kapan saja untuk membatalkan.`
    );
}

function msgAkun(akun) {
    return (
`╔═══════════════════════════╗
║  ✅ *AKUN VPN BERHASIL DIBUAT*
╚═══════════════════════════╝

🌐 *IP/Host*   : \`${akun.domain}\`
🔌 *Port*      : \`${akun.port}\`
👤 *Username*  : \`${akun.username}\`
🔑 *Password*  : \`${akun.password}\`
📱 *Max Login* : ${akun.max_login || '-'} perangkat
📅 *Expired*   : ${akun.exp}
📦 *Kuota*     : ${akun.quota}
📡 *Obfs*      : \`zivpn\`

━━━━━━━━━━━━━━━━━━━━━━
⚙️ *Cara setting ZiVPN:*
1. Buka app ZiVPN
2. Tambah server baru
3. Isi Host, Port, Username, Password
4. Obfs: \`zivpn\`
5. Connect!`
    );
}

// ─────────────────────────────────────────────────────────────
//   QR & READY
// ─────────────────────────────────────────────────────────────
client.on('qr', qr => {
    console.clear();
    console.log('\n🔷 Scan QR Code berikut di WhatsApp:\n');
    qrcode.generate(qr, { small: true });
    console.log('\n📲 WhatsApp → Perangkat Tertaut → Tautkan Perangkat\n');
});

client.on('ready', () => {
    console.log(`\n✅ Bot ZIVPN Manager siap!`);
    console.log(`📅 ${nowDate()}\n`);
    config.ADMIN_NUMBERS.forEach(num => {
        client.sendMessage(`${num}@c.us`,
            `✅ *Bot ZIVPN Manager aktif!*\n📅 ${nowDate()}\n\nKetik *!help* untuk daftar perintah.`
        ).catch(() => {});
    });
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
    if (msg.from.includes('@g.us')) return;

    const phone = msg.from;
    const body  = (msg.body || '').trim();
    const lower = body.toLowerCase();

    // Hanya admin yang bisa pakai bot
    if (!isAdmin(phone)) {
        await msg.reply('⛔ Akses ditolak. Bot ini hanya untuk penggunaan pribadi.');
        return;
    }

    try {
        await handleAdmin(msg, phone, body, lower);
    } catch (e) {
        console.error('❌ Error:', e.message);
        await msg.reply(`❌ Terjadi error: ${e.message}`);
    }
});

// ─────────────────────────────────────────────────────────────
//   ADMIN HANDLER
// ─────────────────────────────────────────────────────────────
async function handleAdmin(msg, phone, body, lower) {
    const state = getState(phone);
    const parts = body.trim().split(/\s+/);
    const cmd   = parts[0].toLowerCase();

    // Batal di manapun
    if (['batal', 'cancel', '!batal'].includes(lower)) {
        resetState(phone);
        await msg.reply('❌ Dibatalkan.\n\n' + msgMenu());
        return;
    }

    // Jika sedang dalam state aktif, teruskan ke state handler
    if (state.step !== 'idle') {
        await handleState(msg, phone, body, lower, state);
        return;
    }

    // Perintah utama
    switch (cmd) {

        case '!help':
        case 'menu':
        case 'halo':
        case 'hi':
        case '/start': {
            await msg.reply(msgMenu());
            break;
        }

        case '!create': {
            setState(phone, 'create_username', {});
            await msg.reply(
`🆕 *BUAT AKUN VPN BARU*
━━━━━━━━━━━━━━━━━━━━━━

Langkah 1/4 — *Username*

Ketik username untuk akun VPN:
• Hanya huruf, angka, underscore (_)
• Minimal 4, maksimal 20 karakter
• Contoh: \`user_vpn\`, \`john123\`

Ketik *batal* untuk membatalkan.`
            );
            break;
        }

        case '!trial': {
            setState(phone, 'trial_username', {});
            await msg.reply(
`⏱️ *BUAT AKUN TRIAL*
━━━━━━━━━━━━━━━━━━━━━━

Langkah 1/4 — *Username*

Ketik username untuk akun trial:
• Hanya huruf, angka, underscore (_)
• Minimal 4, maksimal 20 karakter

Ketik *batal* untuk membatalkan.`
            );
            break;
        }

        case '!backup': {
            await doBackup(msg);
            break;
        }

        case '!restore': {
            setState(phone, 'waiting_restore', {});
            await msg.reply(
`♻️ *RESTORE DATABASE*
━━━━━━━━━━━━━━━━━━━━━━

Kirim file backup (.db) di chat ini.

⚠️ Data akun yang ada sekarang akan ditimpa dengan data dari backup.

Ketik *batal* untuk membatalkan.`
            );
            break;
        }

        case '!listakun': {
            const users = vpn.listUsers();
            if (users.length === 0) { await msg.reply('📋 Belum ada akun VPN.'); return; }
            const today = new Date().toISOString().split('T')[0];
            let txt = `📋 *DAFTAR AKUN VPN (${users.length}):*\n━━━━━━━━━━━━━━━━━\n`;
            users.forEach((u, i) => {
                const isExp = u.exp < today;
                txt += `${i+1}. ${isExp ? '🔴' : '🟢'} \`${u.username}\` — exp: ${u.exp}\n`;
            });
            await msg.reply(txt);
            break;
        }

        case '!hapus': {
            const uname = parts[1];
            if (!uname) { await msg.reply('❌ Format: !hapus <username>'); return; }
            const result = vpn.deleteUser(uname);
            if (result.success) {
                await msg.reply(`✅ Akun *${uname}* berhasil dihapus.`);
            } else {
                await msg.reply(`❌ Gagal hapus: ${result.error}`);
            }
            break;
        }

        case '!renew': {
            const [, uname, hariStr] = parts;
            if (!uname || !hariStr) { await msg.reply('❌ Format: !renew <username> <hari>'); return; }
            const result = vpn.renewUser(uname, parseInt(hariStr));
            if (result.success) {
                await msg.reply(`✅ Akun *${uname}* diperpanjang!\n📅 Expired baru: *${result.newExp}*`);
            } else {
                await msg.reply(`❌ Gagal: ${result.error}`);
            }
            break;
        }

        case '!info': {
            const uname = parts[1];
            if (!uname) { await msg.reply('❌ Format: !info <username>'); return; }
            const akun = vpn.getAccountInfo(uname);
            if (!akun) { await msg.reply(`❌ Akun *${uname}* tidak ditemukan.`); return; }
            await msg.reply(msgAkun(akun));
            break;
        }

        default: {
            await msg.reply(msgMenu());
        }
    }
}

// ─────────────────────────────────────────────────────────────
//   STATE HANDLER
// ─────────────────────────────────────────────────────────────
async function handleState(msg, phone, body, lower, state) {

    switch (state.step) {

        // ══ FLOW !create ══════════════════════════════════════

        case 'create_username': {
            const un = body.replace(/[^a-zA-Z0-9_]/g, '').toLowerCase();
            if (un.length < 4 || un.length > 20) {
                await msg.reply('❌ Username harus 4-20 karakter, hanya huruf/angka/underscore.\nCoba lagi:');
                return;
            }
            if (vpn.userExists(un)) {
                await msg.reply(`❌ Username *${un}* sudah dipakai.\nCoba username lain:`);
                return;
            }
            setState(phone, 'create_password', { username: un });
            await msg.reply(
`✅ Username: \`${un}\`

Langkah 2/4 — *Password*

Ketik password untuk akun ini:
• Minimal 6 karakter
• Boleh huruf, angka, simbol
• Tidak boleh ada spasi`
            );
            break;
        }

        case 'create_password': {
            if (body.length < 6) {
                await msg.reply('❌ Password minimal 6 karakter.\nCoba lagi:');
                return;
            }
            if (body.includes(' ')) {
                await msg.reply('❌ Password tidak boleh ada spasi.\nCoba lagi:');
                return;
            }
            setState(phone, 'create_days', { ...state.data, password: body });
            await msg.reply(
`✅ Password diterima.

Langkah 3/4 — *Masa Aktif*

Berapa hari akun ini aktif?
• Ketik angka saja
• Contoh: \`30\` untuk 30 hari`
            );
            break;
        }

        case 'create_days': {
            const hari = parseInt(body);
            if (isNaN(hari) || hari < 1) {
                await msg.reply('❌ Masukkan angka yang valid (minimal 1).\nCoba lagi:');
                return;
            }
            setState(phone, 'create_maxlogin', { ...state.data, days: hari });
            await msg.reply(
`✅ Masa aktif: *${hari} hari*

Langkah 4/4 — *Max Login*

Berapa perangkat yang boleh login bersamaan?
• Ketik angka saja
• Contoh: \`2\` untuk 2 perangkat`
            );
            break;
        }

        case 'create_maxlogin': {
            const maxLogin = parseInt(body);
            if (isNaN(maxLogin) || maxLogin < 1) {
                await msg.reply('❌ Masukkan angka yang valid (minimal 1).\nCoba lagi:');
                return;
            }
            const d = { ...state.data, max_login: maxLogin };
            setState(phone, 'create_confirm', d);
            await msg.reply(
`📋 *RINGKASAN AKUN BARU*
━━━━━━━━━━━━━━━━━━━━━━
👤 Username  : \`${d.username}\`
🔑 Password  : \`${d.password}\`
📅 Masa aktif: *${d.days} hari*
📱 Max login : *${d.max_login} perangkat*
━━━━━━━━━━━━━━━━━━━━━━

Balas *ya* untuk buat akun
Balas *batal* untuk membatalkan`
            );
            break;
        }

        case 'create_confirm': {
            if (['ya', 'yes', 'iya', 'ok', 'y'].includes(lower)) {
                const d = state.data;
                await msg.reply('⏳ Membuat akun VPN...');
                const result = vpn.createUser(d.username, d.password, d.days, 'Unlimited', `maxlogin:${d.max_login}`);
                if (!result.success) {
                    resetState(phone);
                    await msg.reply(`❌ Gagal membuat akun:\n${result.error}`);
                    return;
                }
                resetState(phone);
                const akun = vpn.getAccountInfo(d.username);
                if (akun) {
                    akun.max_login = d.max_login;
                    await msg.reply(msgAkun(akun));
                } else {
                    await msg.reply(
`✅ *Akun berhasil dibuat!*
👤 Username : \`${d.username}\`
🔑 Password : \`${d.password}\`
📅 Expired  : ${result.exp}
📱 Max Login: ${d.max_login} perangkat`
                    );
                }
            } else {
                resetState(phone);
                await msg.reply('❌ Dibatalkan.\n\n' + msgMenu());
            }
            break;
        }

        // ══ FLOW !trial ═══════════════════════════════════════

        case 'trial_username': {
            const un = body.replace(/[^a-zA-Z0-9_]/g, '').toLowerCase();
            if (un.length < 4 || un.length > 20) {
                await msg.reply('❌ Username harus 4-20 karakter.\nCoba lagi:');
                return;
            }
            if (vpn.userExists(un)) {
                await msg.reply(`❌ Username *${un}* sudah dipakai.\nCoba username lain:`);
                return;
            }
            setState(phone, 'trial_password', { username: un });
            await msg.reply(
`✅ Username: \`${un}\`

Langkah 2/4 — *Password*

Ketik password untuk akun trial:
• Minimal 6 karakter, tidak boleh ada spasi`
            );
            break;
        }

        case 'trial_password': {
            if (body.length < 6) {
                await msg.reply('❌ Password minimal 6 karakter.\nCoba lagi:');
                return;
            }
            if (body.includes(' ')) {
                await msg.reply('❌ Password tidak boleh ada spasi.\nCoba lagi:');
                return;
            }
            setState(phone, 'trial_minutes', { ...state.data, password: body });
            await msg.reply(
`✅ Password diterima.

Langkah 3/4 — *Durasi Trial (Menit)*

Berapa menit akun trial ini aktif?
• Ketik angka saja
• Contoh: \`60\` = 1 jam | \`1440\` = 1 hari | \`30\` = 30 menit`
            );
            break;
        }

        case 'trial_minutes': {
            const menit = parseInt(body);
            if (isNaN(menit) || menit < 1) {
                await msg.reply('❌ Masukkan angka menit yang valid (minimal 1).\nCoba lagi:');
                return;
            }
            setState(phone, 'trial_maxlogin', { ...state.data, minutes: menit });
            await msg.reply(
`✅ Durasi: *${menit} menit*

Langkah 4/4 — *Max Login*

Berapa perangkat yang boleh login bersamaan?
• Contoh: \`1\` atau \`2\``
            );
            break;
        }

        case 'trial_maxlogin': {
            const maxLogin = parseInt(body);
            if (isNaN(maxLogin) || maxLogin < 1) {
                await msg.reply('❌ Masukkan angka yang valid.\nCoba lagi:');
                return;
            }
            const d = { ...state.data, max_login: maxLogin };
            setState(phone, 'trial_confirm', d);
            const jamStr = formatMenit(d.minutes);
            await msg.reply(
`📋 *RINGKASAN AKUN TRIAL*
━━━━━━━━━━━━━━━━━━━━━━
👤 Username  : \`${d.username}\`
🔑 Password  : \`${d.password}\`
⏱️ Durasi    : *${jamStr}*
📱 Max login : *${d.max_login} perangkat*
━━━━━━━━━━━━━━━━━━━━━━

Balas *ya* untuk buat akun trial
Balas *batal* untuk membatalkan`
            );
            break;
        }

        case 'trial_confirm': {
            if (['ya', 'yes', 'iya', 'ok', 'y'].includes(lower)) {
                const d = state.data;
                await msg.reply('⏳ Membuat akun trial...');

                const hariVpn = Math.max(1, Math.ceil(d.minutes / 1440));
                const result  = vpn.createUser(d.username, d.password, hariVpn, 'Unlimited', `trial maxlogin:${d.max_login}`);

                if (!result.success) {
                    resetState(phone);
                    await msg.reply(`❌ Gagal membuat akun trial:\n${result.error}`);
                    return;
                }

                resetState(phone);
                const jamStr = formatMenit(d.minutes);
                const akun   = vpn.getAccountInfo(d.username);

                if (akun) {
                    akun.max_login = d.max_login;
                    await msg.reply(`⏱️ *AKUN TRIAL — ${jamStr}*\n\n` + msgAkun(akun));
                } else {
                    await msg.reply(
`✅ *Akun trial berhasil dibuat!*
👤 Username  : \`${d.username}\`
🔑 Password  : \`${d.password}\`
⏱️ Durasi    : ${jamStr}
📱 Max Login : ${d.max_login} perangkat`
                    );
                }

                // Auto-hapus akun setelah durasi habis
                setTimeout(async () => {
                    try {
                        vpn.deleteUser(d.username);
                        console.log(`🗑️ Trial expired & dihapus: ${d.username}`);
                        for (const adminNum of config.ADMIN_NUMBERS) {
                            await client.sendMessage(`${adminNum}@c.us`,
                                `⏱️ *Akun trial expired & dihapus otomatis*\n` +
                                `👤 Username: \`${d.username}\`\n` +
                                `⏱️ Durasi: ${jamStr}`
                            ).catch(() => {});
                        }
                    } catch (e) {
                        console.error('❌ Gagal hapus trial:', e.message);
                    }
                }, d.minutes * 60 * 1000);

            } else {
                resetState(phone);
                await msg.reply('❌ Dibatalkan.\n\n' + msgMenu());
            }
            break;
        }

        // ══ FLOW !restore ══════════════════════════════════════

        case 'waiting_restore': {
            if (msg.hasMedia) {
                try {
                    await msg.reply('⏳ Memproses file backup...');
                    const media   = await msg.downloadMedia();
                    const tmpPath = path.join(__dirname, 'restore_tmp.db');
                    fs.writeFileSync(tmpPath, Buffer.from(media.data, 'base64'));

                    const udbPath = config.UDB_PATH || '/etc/zivpn/users.db';
                    if (fs.existsSync(udbPath)) {
                        fs.copyFileSync(udbPath, udbPath + '.before_restore');
                    }
                    fs.copyFileSync(tmpPath, udbPath);
                    fs.unlinkSync(tmpPath);

                    resetState(phone);
                    await msg.reply(
`✅ *Restore berhasil!*

Database akun sudah dipulihkan dari file backup.
Data lama disimpan di server sebagai cadangan.

Ketik *!listakun* untuk cek hasilnya.`
                    );
                } catch (e) {
                    resetState(phone);
                    await msg.reply(`❌ Restore gagal: ${e.message}`);
                }
            } else {
                await msg.reply(`📁 Kirim *file backup* (.db) di chat ini.\n\nKetik *batal* untuk membatalkan.`);
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
//   FUNGSI BACKUP
// ─────────────────────────────────────────────────────────────
async function doBackup(msg) {
    try {
        await msg.reply('⏳ Membuat backup...');
        const udbPath = config.UDB_PATH || '/etc/zivpn/users.db';
        const now     = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);

        if (fs.existsSync(udbPath)) {
            const backupPath = path.join(__dirname, `backup_${now}.db`);
            fs.copyFileSync(udbPath, backupPath);
            const media = MessageMedia.fromFilePath(backupPath);
            await client.sendMessage(msg.from, media, {
                caption: `💾 *Backup Database VPN*\n📅 ${nowDate()}\n📁 backup_${now}.db`
            });
            setTimeout(() => { try { fs.unlinkSync(backupPath); } catch {} }, 5000);
            await msg.reply(`✅ *Backup berhasil!*\n\nSimpan file tersebut dengan aman.\nGunakan *!restore* untuk memulihkan.`);
        } else {
            await msg.reply(`❌ File database tidak ditemukan:\n\`${udbPath}\``);
        }
    } catch (e) {
        await msg.reply(`❌ Backup gagal: ${e.message}`);
    }
}

// ─────────────────────────────────────────────────────────────
//   HELPER FORMAT MENIT
// ─────────────────────────────────────────────────────────────
function formatMenit(menit) {
    if (menit < 60) return `${menit} menit`;
    const jam  = Math.floor(menit / 60);
    const sisa = menit % 60;
    if (sisa === 0) return `${jam} jam`;
    return `${jam} jam ${sisa} menit`;
}

// ─────────────────────────────────────────────────────────────
//   JALANKAN BOT
// ─────────────────────────────────────────────────────────────
console.log(`\n🚀 Memulai ZIVPN Manager Bot...`);
console.log('📦 Menginisialisasi WhatsApp Web...\n');

client.initialize();

process.on('SIGINT', async () => {
    console.log('\n⚠️  Bot dihentikan.');
    await client.destroy().catch(() => {});
    process.exit(0);
});

process.on('unhandledRejection', (reason) => {
    console.error('❌ Unhandled rejection:', reason);
});
