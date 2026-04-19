'use strict';

// ============================================================
//   VPN.JS — ZiVPN Database Handler
//   Format DB: username|password|expired|quota|note
// ============================================================

const fs   = require('fs');
const path = require('path');

const UDB_PATH    = '/etc/zivpn/users.db';
const DOMAIN      = 'drakystem.premium';
const PORT        = '5667';
const DEFAULT_QUOTA = 'Unlimited';

// ── Baca semua user dari DB ──────────────────────────────────
function readUsers() {
    try {
        if (!fs.existsSync(UDB_PATH)) return [];
        const lines = fs.readFileSync(UDB_PATH, 'utf8')
            .split('\n')
            .map(l => l.trim())
            .filter(l => l.length > 0);
        return lines.map(line => {
            const parts = line.split('|');
            return {
                username : parts[0] || '',
                password : parts[1] || '',
                exp      : parts[2] || '',
                quota    : parts[3] || DEFAULT_QUOTA,
                note     : parts[4] || '',
            };
        }).filter(u => u.username);
    } catch (e) {
        console.error('❌ readUsers error:', e.message);
        return [];
    }
}

// ── Tulis semua user ke DB ───────────────────────────────────
function writeUsers(users) {
    try {
        const lines = users.map(u =>
            `${u.username}|${u.password}|${u.exp}|${u.quota || DEFAULT_QUOTA}|${u.note || ''}`
        );
        fs.writeFileSync(UDB_PATH, lines.join('\n') + '\n', 'utf8');
        return true;
    } catch (e) {
        console.error('❌ writeUsers error:', e.message);
        return false;
    }
}

// ── Hitung tanggal expired ───────────────────────────────────
function calcExpired(days) {
    const d = new Date();
    d.setDate(d.getDate() + days);
    return d.toISOString().split('T')[0]; // YYYY-MM-DD
}

// ── Cek user exists ──────────────────────────────────────────
function userExists(username) {
    const users = readUsers();
    return users.some(u => u.username.toLowerCase() === username.toLowerCase());
}

// ── Buat user baru ───────────────────────────────────────────
function createUser(username, password, days, quota, note) {
    try {
        if (userExists(username)) {
            return { success: false, error: `Username ${username} sudah ada.` };
        }
        const exp   = calcExpired(days);
        const users = readUsers();
        users.push({
            username,
            password,
            exp,
            quota: quota || DEFAULT_QUOTA,
            note:  note  || '',
        });
        writeUsers(users);
        return { success: true, username, exp };
    } catch (e) {
        return { success: false, error: e.message };
    }
}

// ── Hapus user ───────────────────────────────────────────────
function deleteUser(username) {
    try {
        const users    = readUsers();
        const filtered = users.filter(u => u.username.toLowerCase() !== username.toLowerCase());
        if (filtered.length === users.length) {
            return { success: false, error: `Username ${username} tidak ditemukan.` };
        }
        writeUsers(filtered);
        return { success: true };
    } catch (e) {
        return { success: false, error: e.message };
    }
}

// ── Perpanjang user ──────────────────────────────────────────
function renewUser(username, days) {
    try {
        const users = readUsers();
        const idx   = users.findIndex(u => u.username.toLowerCase() === username.toLowerCase());
        if (idx === -1) {
            return { success: false, error: `Username ${username} tidak ditemukan.` };
        }
        const today  = new Date().toISOString().split('T')[0];
        const base   = users[idx].exp > today ? users[idx].exp : today;
        const baseDate = new Date(base);
        baseDate.setDate(baseDate.getDate() + days);
        const newExp = baseDate.toISOString().split('T')[0];
        users[idx].exp = newExp;
        writeUsers(users);
        return { success: true, newExp };
    } catch (e) {
        return { success: false, error: e.message };
    }
}

// ── Info akun ────────────────────────────────────────────────
function getAccountInfo(username) {
    const users = readUsers();
    const user  = users.find(u => u.username.toLowerCase() === username.toLowerCase());
    if (!user) return null;
    return {
        username  : user.username,
        password  : user.password,
        exp       : user.exp,
        quota     : user.quota || DEFAULT_QUOTA,
        note      : user.note  || '',
        domain    : DOMAIN,
        port      : PORT,
        max_login : extractMaxLogin(user.note),
    };
}

// ── Extract max login dari note ──────────────────────────────
function extractMaxLogin(note) {
    if (!note) return '-';
    const match = note.match(/maxlogin:(\d+)/);
    return match ? match[1] : '-';
}

// ── List semua user ──────────────────────────────────────────
function listUsers() {
    return readUsers().map(u => ({
        username  : u.username,
        exp       : u.exp,
        quota     : u.quota,
        note      : u.note,
        domain    : DOMAIN,
        port      : PORT,
        max_login : extractMaxLogin(u.note),
    }));
}

// ── Stats VPN ────────────────────────────────────────────────
function getVpnStats() {
    const users = readUsers();
    const today = new Date().toISOString().split('T')[0];
    return {
        total   : users.length,
        active  : users.filter(u => u.exp >= today).length,
        expired : users.filter(u => u.exp < today).length,
    };
}

// ── Bersihkan akun expired ───────────────────────────────────
function cleanExpired() {
    const users   = readUsers();
    const today   = new Date().toISOString().split('T')[0];
    const active  = users.filter(u => u.exp >= today);
    const removed = users.length - active.length;
    if (removed > 0) writeUsers(active);
    return { removed };
}

// ── Buat trial user ──────────────────────────────────────────
function createTrialUser(phone) {
    const username = 'trial_' + phone.slice(-6) + '_' + Date.now().toString(36).slice(-4);
    const password = 'trial' + Math.random().toString(36).slice(-6);
    return createUser(username, password, 1, '1GB', 'trial maxlogin:1');
}

module.exports = {
    userExists,
    createUser,
    deleteUser,
    renewUser,
    getAccountInfo,
    listUsers,
    getVpnStats,
    cleanExpired,
    createTrialUser,
};
