// Trạm Tool - tiện ích dùng chung: gọi API máy chủ, định dạng thời gian và dung lượng, biểu tượng.
import { html } from '../vendor/lit-html/lit-html.js';

export const $ = (sel, root = document) => root.querySelector(sel);
export const enc = encodeURIComponent;
// Bỏ dấu tiếng Việt để tìm "wifi", "ghi am" vẫn ra "Wi-Fi", "Ghi âm".
export const norm = (s) => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[đĐ]/g, 'd').toLowerCase();

// Biểu tượng: icons.svg được nạp một lần vào trang (loadIcons) rồi tham chiếu nội bộ "#i-<tên>".
// Tham chiếu thẳng "icons.svg#<tên>" thì trình duyệt tải lại file mỗi lúc (máy chủ gửi no-store), biểu tượng nháy trắng.
export const icon = (id, cls = '') => html`<svg class="ic ${cls}" aria-hidden="true"><use href="#i-${id}"></use></svg>`;

export async function loadIcons() {
  try {
    const text = await (await fetch('icons.svg')).text();
    const box = document.createElement('div');
    box.setAttribute('aria-hidden', 'true');
    box.style.cssText = 'position:absolute;width:0;height:0;overflow:hidden';
    box.innerHTML = text.replace(/<symbol id="/g, '<symbol id="i-'); // tiền tố để không trùng id phần tử của trang
    document.body.prepend(box);
  } catch { /* thiếu biểu tượng thì trang vẫn dùng được */ }
}

// Lưu trong trình duyệt: chỉ cho thứ không quan trọng (vd giao diện tối để khỏi nháy màn hình lúc mở).
// Ghim, chế độ đơn giản... lưu ở máy chủ vì localStorage gắn với cổng, cổng có thể đổi.
export const local = {
  get(key, fallback) {
    try { const v = localStorage.getItem('tramtool.' + key); return v == null ? fallback : JSON.parse(v); } catch { return fallback; }
  },
  set(key, value) {
    try { localStorage.setItem('tramtool.' + key, JSON.stringify(value)); } catch { /* chế độ riêng tư */ }
  },
  remove(key) {
    try { localStorage.removeItem('tramtool.' + key); } catch { /* bỏ qua */ }
  },
};

// ------------------------------------------------------------------ thời gian, dung lượng
const pad = (n) => String(n).padStart(2, '0');
export const clock = (iso) => { const d = new Date(iso); return `${pad(d.getHours())}:${pad(d.getMinutes())}`; };

export function timeAgo(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  const sec = Math.round((Date.now() - d.getTime()) / 1000);
  if (sec < 45) return 'vừa xong';
  if (sec < 3600) return `${Math.max(1, Math.round(sec / 60))} phút trước`;
  if (sec < 86400) return `${Math.round(sec / 3600)} giờ trước`;
  if (sec < 172800) return `hôm qua ${clock(iso)}`;
  return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} ${clock(iso)}`;
}

const dayStart = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
export const dayKey = (iso) => { const d = new Date(iso); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`; };
export function dayLabel(iso) {
  const d = new Date(iso);
  const diff = Math.round((dayStart(new Date()) - dayStart(d)) / 86400000);
  if (diff === 0) return 'Hôm nay';
  if (diff === 1) return 'Hôm qua';
  const s = d.toLocaleDateString('vi-VN', { weekday: 'long', day: '2-digit', month: '2-digit', year: 'numeric' });
  return s.charAt(0).toUpperCase() + s.slice(1);
}

// Gom danh sách (mới nhất trước) theo ngày: [{ key, label, items }]
export function groupByDay(items, timeOf) {
  const groups = [];
  for (const it of items) {
    const key = dayKey(timeOf(it));
    let g = groups[groups.length - 1];
    if (!g || g.key !== key) { g = { key, label: dayLabel(timeOf(it)), items: [] }; groups.push(g); }
    g.items.push(it);
  }
  return groups;
}

// Máy chủ ghi "0 ngày 22 giờ": bỏ phần 0 ngày.
export const uptimeText = (s) => String(s || '').replace(/^0 ngày /, '');
// Ổ "C:" -> "C"
export const driveName = (d) => String(d || '').replace(/:$/, '');

// "45 giây", "12 phút", "1 giờ 5 phút"
export function fmtDuration(sec) {
  if (sec == null || Number.isNaN(Number(sec))) return '';
  const s = Math.max(0, Math.round(Number(sec)));
  if (s < 60) return `${s} giây`;
  const m = Math.round(s / 60);
  if (m < 60) return `${m} phút`;
  return `${Math.floor(m / 60)} giờ${m % 60 ? ` ${m % 60} phút` : ''}`;
}

// Đồng hồ chạy: "0:45", "12:03", "1:02:03"
export function fmtElapsed(sec) {
  const s = Math.max(0, Math.floor(sec));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  return h ? `${h}:${pad(m)}:${pad(s % 60)}` : `${m}:${pad(s % 60)}`;
}

const nf1 = new Intl.NumberFormat('vi-VN', { maximumFractionDigits: 1 });
export function fmtSize(bytes) {
  const b = Number(bytes) || 0;
  if (b >= 1024 ** 3) return `${nf1.format(b / 1024 ** 3)} GB`;
  if (b >= 1024 ** 2) return `${nf1.format(b / 1024 ** 2)} MB`;
  if (b >= 1024) return `${Math.round(b / 1024)} KB`;
  return `${b} B`;
}

// ------------------------------------------------------------------ mã thông hành
// Nằm sau dấu # nên không gửi lên mạng, không vào lịch sử trình duyệt; giữ trong sessionStorage khi tải lại trang.
const TOKEN_KEY = 'tramtool.token';
let token = null;
{
  const m = location.hash.match(/(?:^#|&)t=([a-f0-9]{64})/);
  if (m) {
    token = m[1];
    try { sessionStorage.setItem(TOKEN_KEY, token); } catch { /* bỏ qua */ }
    history.replaceState(null, '', location.pathname + '#/');
  } else {
    try { token = sessionStorage.getItem(TOKEN_KEY); } catch { token = null; }
  }
}
export const hasToken = () => !!token;

// Báo cho giao diện biết kết nối: 'ok' | 'offline' | 'token'
const emit = (state) => window.dispatchEvent(new CustomEvent('tram:conn', { detail: state }));

export async function api(path, { method = 'GET', body } = {}) {
  let res;
  try {
    res = await fetch(path, {
      method,
      cache: 'no-store',
      headers: { 'X-Tram-Token': token || '', ...(body ? { 'Content-Type': 'application/json' } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
  } catch {
    emit('offline');
    throw new Error('Mất kết nối với Trạm Tool.');
  }
  emit('ok');
  let data = null;
  try { data = await res.json(); } catch { /* không phải JSON */ }
  if (res.status === 403) emit('token');
  if (!res.ok) throw new Error((data && data.error) || `Lỗi ${res.status}`);
  return data;
}
