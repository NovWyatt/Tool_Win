// Trạm Tool - giao diện (ES module, không cần build). Máy chủ: hub/TramTool.ps1
import { setTheme } from './vendor/fluent-web-components.min.js';
import { webLightTheme, webDarkTheme } from './vendor/fluent-tokens.min.js';
import { marked } from './vendor/marked.min.js';
import DOMPurify from './vendor/purify.min.js';

// ------------------------------------------------------------------ tiện ích
const $ = (sel, root = document) => root.querySelector(sel);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const icon = (id, cls = '') => `<svg class="ic ${cls}" aria-hidden="true"><use href="icons.svg#${esc(id)}"></use></svg>`;
const enc = encodeURIComponent;
const norm = (s) => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').replace(/Đ/g, 'D').toLowerCase();

const store = {
  get(key, fallback) {
    try { const v = localStorage.getItem('tramtool.' + key); return v == null ? fallback : JSON.parse(v); } catch { return fallback; }
  },
  set(key, value) {
    try { localStorage.setItem('tramtool.' + key, JSON.stringify(value)); } catch { /* chế độ riêng tư */ }
  },
};

function timeAgo(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  const sec = Math.round((Date.now() - d.getTime()) / 1000);
  if (sec < 45) return 'vừa xong';
  if (sec < 3600) return `${Math.round(sec / 60)} phút trước`;
  if (sec < 86400) return `${Math.round(sec / 3600)} giờ trước`;
  if (sec < 172800) return `hôm qua ${d.toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' })}`;
  return d.toLocaleString('vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
}

// ------------------------------------------------------------------ mã thông hành (nằm sau dấu # nên không gửi lên mạng, không lưu lịch sử)
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

async function api(path, { method = 'GET', body } = {}) {
  let res;
  try {
    res = await fetch(path, {
      method,
      cache: 'no-store',
      headers: { 'X-Tram-Token': token || '', ...(body ? { 'Content-Type': 'application/json' } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
  } catch {
    showOverlay('offline');
    throw new Error('Mất kết nối với Trạm Tool.');
  }
  hideOverlay();
  let data = null;
  try { data = await res.json(); } catch { /* không phải JSON */ }
  if (res.status === 403) { showOverlay('token'); }
  if (!res.ok) throw new Error((data && data.error) || `Lỗi ${res.status}`);
  return data;
}

// ------------------------------------------------------------------ trạng thái
const S = {
  hub: null,
  categories: [],
  tools: [],
  byId: new Map(),
  deps: {},
  depsLoaded: false,
  history: null,
  pins: new Set(store.get('pins', [])),
  simple: store.get('simple', false),
  theme: store.get('theme', 'system'),
  query: '',
  route: { name: 'home' },
};

const RISK = {
  'read-only': { label: 'Chỉ đọc', color: 'success', icon: 'eye' },
  'asks-before-change': { label: 'Hỏi trước khi sửa', color: 'informative', icon: 'question' },
  'modifies-system': { label: 'Thay đổi hệ thống', color: 'warning', icon: 'edit' },
};

const PAGES = [
  { id: 'outputs', label: 'Kết quả gần đây', icon: 'document-search' },
  { id: 'history', label: 'Lịch sử chạy', icon: 'history' },
  { id: 'system', label: 'Máy này', icon: 'desktop-pulse' },
  { id: 'roadmap', label: 'Phân tích và nâng cấp', icon: 'map', tech: true },
  { id: 'settings', label: 'Cài đặt', icon: 'settings' },
];

function setCatalog(state) {
  S.hub = state.hub;
  S.categories = state.categories || [];
  S.tools = (state.tools || []).map((t) => ({
    ...t,
    _hay: norm([t.name, t.summary, t.description, (t.tags || []).join(' '), (t.actions || []).map((a) => `${a.label} ${a.file}`).join(' '), catLabel(t.category, state.categories)].join(' ')),
  }));
  S.byId = new Map(S.tools.map((t) => [t.id, t]));
  for (const id of [...S.pins]) if (!S.byId.has(id)) S.pins.delete(id);
}

function catLabel(id, cats = S.categories) {
  return (cats.find((c) => c.id === id) || {}).label || 'Khác';
}

const visibleTools = () => S.tools.filter((t) => !S.simple || t.audience !== 'tech');

function matches(tool, query) {
  const words = norm(query).split(/\s+/).filter(Boolean);
  return words.every((w) => tool._hay.includes(w));
}

function depsStatus(tool) {
  const items = S.deps[tool.id];
  if (!items) return 'unknown';
  return items.some((r) => !r.ok && !r.optional) ? 'missing' : 'ok';
}

function primaryAction(tool) {
  return (tool.actions || []).find((a) => a.primary) || (tool.actions || [])[0];
}

// ------------------------------------------------------------------ giao diện chung
const mq = matchMedia('(prefers-color-scheme: dark)');
function applyTheme() {
  const dark = S.theme === 'dark' || (S.theme === 'system' && mq.matches);
  setTheme(dark ? webDarkTheme : webLightTheme);
  document.documentElement.dataset.theme = dark ? 'dark' : 'light';
  document.documentElement.style.colorScheme = dark ? 'dark' : 'light';
}
mq.addEventListener('change', () => { if (S.theme === 'system') applyTheme(); });

function toast(intent, text, ms = 6000) {
  const el = document.createElement('fluent-message-bar');
  el.setAttribute('intent', intent);
  el.setAttribute('layout', 'multiline');
  el.innerHTML = `${esc(text)}<fluent-button slot="dismiss" appearance="transparent" icon-only aria-label="Đóng">${icon('dismiss', 'ic-16')}</fluent-button>`;
  el.addEventListener('click', (e) => { if (e.target.closest('[slot="dismiss"]')) el.remove(); });
  $('#toasts').append(el);
  setTimeout(() => el.remove(), ms);
}

let overlayKind = null;
function showOverlay(kind) {
  overlayKind = kind;
  const o = $('#overlay');
  if (kind === 'token') {
    $('#overlay-title').textContent = 'Hãy mở Trạm Tool bằng TramTool.bat';
    $('#overlay-text').textContent = 'Trang này thiếu mã thông hành của phiên đang chạy. Bấm đúp file TramTool.bat trong thư mục Tool_Win, trạm sẽ tự mở đúng cửa sổ.';
  } else {
    $('#overlay-title').textContent = 'Mất kết nối với Trạm Tool';
    $('#overlay-text').textContent = 'Có thể cửa sổ máy chủ của trạm đã bị đóng hoặc tự tắt vì để lâu. Mở lại bằng TramTool.bat rồi bấm Thử lại.';
  }
  o.hidden = false;
}
function hideOverlay() {
  if (overlayKind === 'offline') { $('#overlay').hidden = true; overlayKind = null; }
}

// Hộp thoại dùng chung; trả về value của nút được bấm, hoặc null nếu đóng.
// validate(value): trả về câu báo lỗi thì giữ hộp thoại mở và hiện lỗi, trả về rỗng thì đóng.
let dialogResolve = null;
function openDialog({ title, html, buttons, validate }) {
  const dlg = $('#dlg');
  $('#dlg-title').textContent = title;
  $('#dlg-body').innerHTML = `${html}<div class="form-error" id="dlg-error" role="alert" hidden></div>`;
  $('#dlg-actions').innerHTML = buttons
    .map((b, i) => `<fluent-button data-dlg="${i}" appearance="${b.appearance || 'secondary'}">${b.icon ? icon(b.icon, 'ic-16') + ' ' : ''}${esc(b.label)}</fluent-button>`)
    .join('');
  return new Promise((resolve) => {
    if (dialogResolve) dialogResolve(null);
    dialogResolve = (v) => { dialogResolve = null; resolve(v); };
    $('#dlg-actions').onclick = (e) => {
      const btn = e.target.closest('[data-dlg]');
      if (!btn) return;
      const b = buttons[Number(btn.dataset.dlg)];
      if (validate && b.value) {
        const err = validate(b.value);
        if (err) {
          const box = $('#dlg-error');
          box.textContent = err;
          box.hidden = false;
          box.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
          return;
        }
      }
      if (dialogResolve) dialogResolve(b.value);
      dlg.hide();
    };
    dlg.show();
  });
}
$('#dlg').addEventListener('toggle', () => {
  const open = $('#dlg').dialog && $('#dlg').dialog.open;
  if (!open && dialogResolve) dialogResolve(null);
});

function badge(color, text, ic) {
  return `<fluent-badge appearance="tint" color="${color}" size="medium">${ic ? icon(ic) + ' ' : ''}${esc(text)}</fluent-badge>`;
}
const riskBadge = (risk) => { const r = RISK[risk] || RISK['modifies-system']; return badge(r.color, r.label); };
const adminBadge = () => badge('brand', 'Cần Admin');

function toolBadges(tool) {
  const a = primaryAction(tool);
  const out = [];
  if (tool.auto) out.push(badge('subtle', 'Chưa có tool.json'));
  if (tool.status === 'broken') out.push(badge('danger', 'Đang hỏng'));
  else if (tool.status === 'warning') out.push(badge('severe', 'Cần xem lại'));
  if (depsStatus(tool) === 'missing') out.push(badge('danger', 'Cần cài thêm'));
  if (a) out.push(riskBadge(a.risk));
  if (a && a.admin) out.push(adminBadge());
  return out.slice(0, 3).join('');
}

// ------------------------------------------------------------------ thanh điều hướng
function renderNav() {
  const tools = visibleTools();
  const r = S.route;
  const cur = (cond) => (cond ? ' aria-current="page"' : '');
  let html = `<button class="nav-item" data-go="#/"${cur(r.name === 'home')}>${icon('apps')}<span>Tất cả công cụ</span><span class="count">${tools.length}</span></button>`;
  const pinned = tools.filter((t) => S.pins.has(t.id));
  if (pinned.length) html += `<button class="nav-item" data-go="#/pinned"${cur(r.name === 'pinned')}>${icon('star')}<span>Đã ghim</span><span class="count">${pinned.length}</span></button>`;
  html += `<div class="nav-group-title">Nhóm công cụ</div>`;
  for (const c of S.categories) {
    const n = tools.filter((t) => t.category === c.id).length;
    if (!n) continue;
    const active = (r.name === 'category' && r.id === c.id) || (r.name === 'tool' && S.byId.get(r.id)?.category === c.id);
    html += `<button class="nav-item" data-go="#/c/${enc(c.id)}"${cur(active)}>${icon(c.icon)}<span>${esc(c.label)}</span><span class="count">${n}</span></button>`;
  }
  $('#nav-tools').innerHTML = html;
  $('#nav-pages').innerHTML = PAGES.filter((p) => !(p.tech && S.simple))
    .map((p) => `<button class="nav-item" data-go="#/${p.id}"${cur(r.name === p.id)}>${icon(p.icon)}<span>${esc(p.label)}</span></button>`)
    .join('');
  if (S.hub) $('#foot-machine').textContent = `${S.hub.computer}${S.hub.isAdmin ? ' · Admin' : ''}`;
  const sw = $('#sw-simple');
  if (sw && sw.checked !== S.simple) sw.checked = S.simple;
}

// ------------------------------------------------------------------ các trang
function toolRow(t) {
  const a = primaryAction(t);
  const pinned = S.pins.has(t.id);
  return `<div class="row clickable" role="link" tabindex="0" data-go="#/tool/${enc(t.id)}">
    <div class="tile${t.auto ? ' muted' : ''}">${icon(t.icon || 'toolbox')}</div>
    <div>
      <div class="row-title"><span class="name">${esc(t.name)}</span>${toolBadges(t)}</div>
      <div class="row-sub">${esc(t.summary)}</div>
    </div>
    <div class="row-side">
      ${a ? `<fluent-button appearance="${a.risk === 'modifies-system' ? 'outline' : 'primary'}" data-act="run" data-tool="${esc(t.id)}" data-action="${esc(a.id)}" title="${esc(a.label)}">${icon('play', 'ic-16')} Chạy</fluent-button>` : ''}
      <button class="icon-btn${pinned ? ' on' : ''}" data-act="pin" data-tool="${esc(t.id)}" aria-pressed="${pinned}" aria-label="${pinned ? 'Bỏ ghim' : 'Ghim'}" title="${pinned ? 'Bỏ ghim' : 'Ghim lên đầu'}">${icon(pinned ? 'star-filled' : 'star')}</button>
      ${icon('chevron-right', 'chev')}
    </div>
  </div>`;
}

function section(title, desc, body, tools = '') {
  return `<section class="section"><div class="section-head"><div><h2>${esc(title)}</h2>${desc ? `<p>${esc(desc)}</p>` : ''}</div>${tools ? `<div class="tools">${tools}</div>` : ''}</div>${body}</section>`;
}

function emptyState(ic, title, text, extra = '') {
  return `<div class="card empty">${icon(ic)}<strong>${esc(title)}</strong><span>${esc(text)}</span>${extra}</div>`;
}

function recentChips() {
  if (!S.history) return '';
  const seen = new Set();
  const items = [];
  for (const h of S.history) {
    if (!h.ok || seen.has(h.toolId) || !S.byId.has(h.toolId)) continue;
    const t = S.byId.get(h.toolId);
    if (S.simple && t.audience === 'tech') continue;
    seen.add(h.toolId);
    items.push(`<button class="chip" data-go="#/tool/${enc(t.id)}">${icon(t.icon || 'toolbox')}${esc(t.name)}<span class="muted small">${esc(timeAgo(h.time))}</span></button>`);
    if (items.length >= 6) break;
  }
  return items.length ? section('Dùng gần đây', '', `<div class="chips">${items.join('')}</div>`) : '';
}

function pageTools(title, desc, groups, { showRecent = false } = {}) {
  const q = S.query.trim();
  let body = '';
  if (q) {
    const hits = visibleTools().filter((t) => matches(t, q));
    body = hits.length
      ? section(`Kết quả cho "${q}"`, `${hits.length} công cụ`, `<div class="stack">${hits.map(toolRow).join('')}</div>`)
      : emptyState('search', 'Không tìm thấy công cụ nào', `Thử từ khoá khác, ví dụ "wifi", "excel", "ghi âm", "ổ cứng".`, `<fluent-button data-act="clear-search">Xoá tìm kiếm</fluent-button>`);
  } else {
    if (showRecent) body += recentChips();
    for (const g of groups) {
      if (!g.tools.length) continue;
      body += section(g.title, g.desc, `<div class="stack">${g.tools.map(toolRow).join('')}</div>`);
    }
    if (!body) body = emptyState('toolbox', 'Chưa có công cụ nào', 'Thả thư mục công cụ vào tools\\ rồi bấm Làm mới.', `<fluent-button data-act="reload">Làm mới</fluent-button>`);
  }
  return `<div class="page">
    <div class="page-head"><div><h1>${esc(title)}</h1>${desc ? `<p>${esc(desc)}</p>` : ''}</div>
    <div class="actions"><fluent-button appearance="subtle" data-act="reload" title="Quét lại thư mục tools">${icon('refresh', 'ic-16')} Làm mới</fluent-button></div></div>
    ${body}
  </div>`;
}

function renderHome() {
  const tools = visibleTools();
  const groups = [];
  const pinned = tools.filter((t) => S.pins.has(t.id));
  if (pinned.length) groups.push({ title: 'Đã ghim', desc: '', tools: pinned });
  for (const c of S.categories) groups.push({ title: c.label, desc: c.description, tools: tools.filter((t) => t.category === c.id) });
  const cats = new Set(tools.map((t) => t.category)).size;
  return pageTools('Tất cả công cụ', `${tools.length} công cụ trong ${cats} nhóm. Bấm vào một dòng để xem chi tiết, hoặc bấm Chạy để mở ngay.`, groups, { showRecent: true });
}

function renderCategory(id) {
  const c = S.categories.find((x) => x.id === id);
  if (!c) return renderHome();
  return pageTools(c.label, c.description, [{ title: '', desc: '', tools: visibleTools().filter((t) => t.category === id) }]);
}

function renderPinned() {
  const tools = visibleTools().filter((t) => S.pins.has(t.id));
  if (!tools.length && !S.query) {
    return `<div class="page"><div class="page-head"><div><h1>Đã ghim</h1></div></div>${emptyState('star', 'Chưa ghim công cụ nào', 'Bấm biểu tượng ngôi sao ở một công cụ để đưa nó lên đầu danh sách.')}</div>`;
  }
  return pageTools('Đã ghim', 'Các công cụ bạn dùng thường xuyên.', [{ title: '', desc: '', tools }]);
}

// ---------- trang chi tiết công cụ
function renderTool(id) {
  const t = S.byId.get(id);
  if (!t) return `<div class="page">${emptyState('warning', 'Không tìm thấy công cụ', 'Có thể thư mục công cụ đã bị đổi tên hoặc xoá.', `<fluent-button data-go="#/">Về danh sách</fluent-button>`)}</div>`;
  const pinned = S.pins.has(t.id);
  const notes = [];
  for (const p of t.problems || []) notes.push(['warning', p]);
  if (t.statusNote) notes.push([t.status === 'broken' ? 'error' : 'warning', t.statusNote]);
  if (t.auto) notes.push(['info', 'Công cụ này chưa có tool.json nên trạm đoán các nút chạy từ file .bat/.ps1. Bấm "Tạo tool.json" để đặt tên, nhóm, mức rủi ro và quyền Admin cho đúng.']);

  const actions = (t.actions || []).map((a) => `
    <div class="row action-row">
      <div>
        <div class="row-title"><span class="name">${esc(a.label)}</span>${riskBadge(a.risk)}${a.admin ? adminBadge() : ''}${!a.exists ? badge('danger', 'Thiếu file') : ''}</div>
        ${a.description ? `<div class="desc">${esc(a.description)}</div>` : ''}
        <div class="row-meta small muted">${a.duration ? `<span>${icon('clock', 'ic-16')} ${esc(a.duration)}</span>` : ''}${a.file ? `<span class="mono">${esc(a.file)}</span>` : ''}</div>
      </div>
      <div class="row-side">
        <fluent-button appearance="${a.primary ? 'primary' : 'outline'}" data-act="run" data-tool="${esc(t.id)}" data-action="${esc(a.id)}"${a.exists ? '' : ' disabled'}>${icon('play', 'ic-16')} Chạy</fluent-button>
      </div>
    </div>`).join('');

  const extra = [];
  if ((t.issues || []).length || (t.upgrades || []).length) {
    if (!S.simple) {
      const issues = (t.issues || []).map((x) => `<li>${esc(x)}</li>`).join('');
      const ups = (t.upgrades || []).map((x) => `<li>${esc(x)}</li>`).join('');
      extra.push(section('Lỗi đã biết và hướng nâng cấp', 'Tóm tắt từ bản phân tích; chi tiết ở trang Phân tích và nâng cấp.', `<div class="two-col">
        <div class="card"><div class="kv"><span class="k">${icon('warning', 'ic-16')} Lỗi, rủi ro đã biết</span></div><ul class="list-plain">${issues || '<li class="muted">Chưa ghi nhận.</li>'}</ul></div>
        <div class="card"><div class="kv"><span class="k">${icon('lightbulb', 'ic-16')} Hướng nâng cấp</span></div><ul class="list-plain">${ups || '<li class="muted">Chưa có.</li>'}</ul></div>
      </div>`));
    }
  }

  return `<div class="page" data-tool="${esc(t.id)}">
    <div class="crumbs"><button data-go="#/">Tất cả công cụ</button>${icon('chevron-right', 'ic-16')}<button data-go="#/c/${enc(t.category)}">${esc(catLabel(t.category))}</button></div>
    <div class="card hero">
      <div class="tile lg${t.auto ? ' muted' : ''}">${icon(t.icon || 'toolbox')}</div>
      <div>
        <h1>${esc(t.name)}</h1>
        <p>${esc(t.summary)}</p>
        ${t.description ? `<p class="small muted">${esc(t.description)}</p>` : ''}
        <div class="badges">${toolBadges(t)}${t.version ? badge('subtle', 'Bản ' + t.version) : ''}</div>
        <div class="bar">
          <fluent-button data-act="open-folder" data-tool="${esc(t.id)}">${icon('folder', 'ic-16')} Mở thư mục</fluent-button>
          ${t.hasDocs ? `<fluent-button data-act="scroll-docs">${icon('book', 'ic-16')} Hướng dẫn</fluent-button>` : ''}
          ${!t.auto ? `<fluent-button data-act="pack" data-tool="${esc(t.id)}" title="Tạo file .zip trên Desktop để gửi qua Zalo, email, USB">${icon('box', 'ic-16')} Đóng gói gửi khách</fluent-button>` : `<fluent-button appearance="primary" data-act="scaffold" data-tool="${esc(t.id)}">${icon('document', 'ic-16')} Tạo tool.json</fluent-button>`}
          <fluent-button appearance="subtle" data-act="pin" data-tool="${esc(t.id)}" aria-pressed="${pinned}">${icon(pinned ? 'star-filled' : 'star', 'ic-16')} ${pinned ? 'Bỏ ghim' : 'Ghim'}</fluent-button>
        </div>
      </div>
    </div>
    ${notes.map(([intent, text]) => `<fluent-message-bar intent="${intent}" layout="multiline" style="margin-top:8px">${esc(text)}</fluent-message-bar>`).join('')}
    ${section('Chạy', (t.actions || []).length > 1 ? 'Mỗi nút mở công cụ trong một cửa sổ riêng.' : '', `<div class="stack">${actions || emptyState('warning', 'Chưa có action', 'Khai báo actions trong tool.json.')}</div>`)}
    ${(t.probes || []).length ? section('Trạng thái hiện tại trên máy này', 'Chỉ đọc, không thay đổi gì.', `<div class="card" id="probes">${skeletonKv(t.probes.length)}</div>`, `<fluent-button appearance="subtle" data-act="probes" data-tool="${esc(t.id)}">${icon('refresh', 'ic-16')} Đọc lại</fluent-button>`) : ''}
    ${(t.requires || []).length ? section('Yêu cầu để chạy', 'Trạm tự kiểm tra; thiếu gì có nút cài.', `<div class="card" id="reqs">${skeletonKv(t.requires.length)}</div>`, `<fluent-button appearance="subtle" data-act="recheck" data-tool="${esc(t.id)}">${icon('refresh', 'ic-16')} Kiểm tra lại</fluent-button>`) : ''}
    ${(t.outputs || []).length ? section('Kết quả gần đây', 'File do công cụ tạo ra trên máy này.', `<div class="stack" id="outs"><div class="skeleton"></div></div>`) : ''}
    ${extra.join('')}
    ${t.hasDocs ? section('Hướng dẫn', t.docs, `<div class="card doc" id="docs"><div class="skeleton" style="height:120px;border:0"></div></div>`) : ''}
  </div>`;
}

function skeletonKv(n) {
  return Array.from({ length: Math.min(n, 4) }, () => `<div class="kv"><span class="k">&nbsp;</span><span class="v muted">Đang đọc...</span><span></span></div>`).join('');
}

async function loadToolExtras(t) {
  const page = () => document.querySelector(`.page[data-tool="${CSS.escape(t.id)}"]`);
  const jobs = [];
  if ((t.requires || []).length) jobs.push(loadReqs(t));
  if ((t.probes || []).length) jobs.push(loadProbes(t));
  if ((t.outputs || []).length) {
    jobs.push(api(`/api/outputs?id=${enc(t.id)}`).then((r) => {
      const el = page() && $('#outs', page());
      if (el) el.innerHTML = r.items.length ? r.items.slice(0, 12).map(fileRow).join('') : emptyState('document', 'Chưa có kết quả', 'Chạy công cụ xong, file kết quả sẽ hiện ở đây.');
    }).catch((e) => { const el = page() && $('#outs', page()); if (el) el.innerHTML = emptyState('warning', 'Không đọc được kết quả', e.message); }));
  }
  if (t.hasDocs) {
    jobs.push(api(`/api/docs?id=${enc(t.id)}`).then((r) => {
      const el = page() && $('#docs', page());
      if (el) el.innerHTML = /\.txt$/i.test(r.name || '') ? `<pre class="doc-txt">${esc(r.markdown)}</pre>` : renderMarkdown(r.markdown);
    }).catch((e) => { const el = page() && $('#docs', page()); if (el) el.innerHTML = `<p class="muted">${esc(e.message)}</p>`; }));
  }
  await Promise.allSettled(jobs);
}

async function loadReqs(t, fresh = false) {
  const el = () => $(`.page[data-tool="${CSS.escape(t.id)}"] #reqs`);
  try {
    const r = await api(`/api/deps?id=${enc(t.id)}${fresh ? '&fresh=1' : ''}`);
    S.deps[t.id] = r.items;
    if (el()) el().innerHTML = r.items.map((q) => reqRow(t, q)).join('');
  } catch (e) {
    if (el()) el().innerHTML = `<div class="kv"><span class="k">Lỗi</span><span class="v">${esc(e.message)}</span><span></span></div>`;
  }
}

function reqRow(t, q) {
  const state = q.ok ? 'ok' : q.optional ? 'opt' : 'bad';
  const ic = q.ok ? 'check-circle' : q.optional ? 'warning' : 'dismiss-circle';
  const fixLabel = q.fix && (q.fix.label || (q.fix.winget ? 'Cài' : 'Sửa'));
  return `<div class="kv">
    <span class="k">${esc(q.label)}${q.optional ? ' <span class="small">(không bắt buộc)</span>' : ''}</span>
    <span class="v req-${state}">${icon(ic, 'ic-16')} ${q.ok ? 'Đã có' : q.optional ? 'Chưa có' : 'Thiếu'}<small>${esc(q.detail)}</small></span>
    <span>${!q.ok && q.fix ? `<fluent-button appearance="primary" size="small" data-act="fix" data-tool="${esc(t.id)}" data-req="${esc(q.id)}">${esc(fixLabel)}</fluent-button>` : ''}</span>
  </div>`;
}

async function loadProbes(t) {
  const el = () => $(`.page[data-tool="${CSS.escape(t.id)}"] #probes`);
  try {
    const r = await api(`/api/probes?id=${enc(t.id)}`);
    if (el()) {
      el().innerHTML = r.items.map((p) => `<div class="kv">
        <span class="k">${esc(p.label)}</span>
        <span class="v">${esc(p.value)}${p.detail ? `<small>${esc(p.detail)}</small>` : ''}</span>
        <span>${p.state === 'changed' ? badge('warning', 'Đã đổi') : p.state === 'default' ? badge('subtle', 'Mặc định') : ''}</span>
      </div>`).join('');
    }
  } catch (e) {
    if (el()) el().innerHTML = `<div class="kv"><span class="k">Lỗi</span><span class="v">${esc(e.message)}</span><span></span></div>`;
  }
}

function fileRow(f) {
  return `<div class="row file-row">
    <div class="tile muted">${icon(f.isFolder ? 'folder' : /\.(docx?|txt|md)$/i.test(f.name) ? 'document-text' : /\.pdf$/i.test(f.name) ? 'pdf' : /\.(sql|gz)$/i.test(f.name) ? 'database' : /\.(json|csv)$/i.test(f.name) ? 'table' : 'document')}</div>
    <div>
      <div class="name">${esc(f.name)}</div>
      <div class="meta">${esc(f.label)} · ${esc(f.toolName)} · ${esc(f.sizeText)} · ${esc(timeAgo(f.modified))}</div>
    </div>
    <div class="row-side">
      <fluent-button appearance="subtle" data-act="open-output" data-tool="${esc(f.toolId)}" data-path="${esc(f.path)}">${icon('open', 'ic-16')} Mở</fluent-button>
      <fluent-button appearance="subtle" data-act="reveal-output" data-tool="${esc(f.toolId)}" data-path="${esc(f.path)}">${icon('folder', 'ic-16')} Thư mục</fluent-button>
    </div>
  </div>`;
}

function renderMarkdown(md) {
  const html = marked.parse(String(md || ''), { gfm: true, breaks: false });
  const clean = DOMPurify.sanitize(html, { USE_PROFILES: { html: true } });
  // Liên kết ra ngoài mở bằng trình duyệt; liên kết nội bộ (file .md) không bấm được trong trạm.
  return clean.replace(/<a href="(?!https?:)[^"]*"/g, '<a');
}

// ---------- trang Kết quả gần đây
function renderOutputs() {
  return `<div class="page"><div class="page-head"><div><h1>Kết quả gần đây</h1><p>File báo cáo và kết quả do các công cụ tạo ra trên máy này, mới nhất ở trên.</p></div>
    <div class="actions"><fluent-button appearance="subtle" data-act="reload-page">${icon('refresh', 'ic-16')} Làm mới</fluent-button></div></div>
    <div class="stack" id="all-outs">${'<div class="skeleton"></div>'.repeat(4)}</div></div>`;
}
async function loadOutputs() {
  try {
    const r = await api('/api/outputs');
    const el = $('#all-outs');
    if (el) el.innerHTML = r.items.length ? r.items.map(fileRow).join('') : emptyState('document-search', 'Chưa có kết quả nào', 'Chạy một công cụ chẩn đoán hoặc chuyển đổi, kết quả sẽ hiện ở đây.');
  } catch (e) { const el = $('#all-outs'); if (el) el.innerHTML = emptyState('warning', 'Không đọc được', e.message); }
}

// ---------- trang Lịch sử
function renderHistory() {
  const items = S.history;
  let body;
  if (!items) body = '<div class="skeleton"></div>'.repeat(4);
  else if (!items.length) body = emptyState('history', 'Chưa chạy công cụ nào', 'Mỗi lần bấm Chạy, trạm ghi lại ở đây để bạn mở lại nhanh.');
  else body = items.slice(0, 150).map((h) => {
    const t = S.byId.get(h.toolId);
    const state = h.ok ? badge('success', 'Đã mở') : /UAC|Không/.test(h.message || '') ? badge('warning', 'Đã huỷ') : badge('danger', 'Lỗi');
    const canRerun = t && (t.actions || []).some((a) => a.id === h.actionId);
    return `<div class="row">
      <div class="tile muted">${icon(t ? t.icon : 'toolbox')}</div>
      <div><div class="row-title"><span class="name">${esc(h.toolName)}</span><span class="muted" style="font-weight:400">${esc(h.actionLabel)}</span>${state}${h.elevated ? adminBadge() : ''}</div>
      <div class="row-sub">${esc(timeAgo(h.time))}${h.message ? ' · ' + esc(h.message) : ''}${(h.args || []).length ? ' · ' + esc(h.args.join(', ')) : ''}</div></div>
      <div class="row-side">${t ? `<fluent-button appearance="subtle" data-go="#/tool/${enc(t.id)}">Mở công cụ</fluent-button>` : ''}${canRerun ? `<fluent-button data-act="run" data-tool="${esc(h.toolId)}" data-action="${esc(h.actionId)}">${icon('play', 'ic-16')} Chạy lại</fluent-button>` : ''}</div>
    </div>`;
  }).join('');
  return `<div class="page"><div class="page-head"><div><h1>Lịch sử chạy</h1><p>Những lần mở công cụ từ trạm trên máy này (lưu trong hub\\data\\history.jsonl).</p></div></div><div class="stack">${body}</div></div>`;
}

// ---------- trang Máy này
function renderSystem() {
  return `<div class="page"><div class="page-head"><div><h1>Máy này</h1><p>Tóm tắt nhanh, chỉ đọc. Muốn chẩn đoán sâu hãy chạy CheckWinFix.</p></div>
    <div class="actions"><fluent-button appearance="subtle" data-act="reload-page">${icon('refresh', 'ic-16')} Đọc lại</fluent-button></div></div>
    <div class="stats" id="sys">${'<div class="skeleton" style="height:96px"></div>'.repeat(6)}</div>
    ${section('Yêu cầu của các công cụ', 'Kiểm tra Python, SQL Server, mô hình, card đồ hoạ... mà từng công cụ cần.', `<div class="stack" id="reqs-all"><div class="skeleton"></div></div>`, `<fluent-button appearance="subtle" data-act="recheck-all">${icon('refresh', 'ic-16')} Kiểm tra lại</fluent-button>`)}
  </div>`;
}
function stat(ic, label, value, note = '', warn = false) {
  return `<div class="card stat${warn ? ' warn' : ''}"><span class="label">${icon(ic, 'ic-16')} ${esc(label)}</span><span class="value">${esc(value)}</span>${note ? `<span class="note">${esc(note)}</span>` : ''}</div>`;
}
async function loadSystem(fresh = false) {
  try {
    const s = await api('/api/system');
    const el = $('#sys');
    if (el) {
      const disks = (s.disks || []).map((d) => stat('hard-drive', `Ổ ${d.drive} ${d.label || ''}`.trim(), `Còn ${d.free} / ${d.size}`, `${d.freePct}% trống`, d.freePct < 12)).join('');
      const phys = (s.physical || []).map((p) => stat('server', p.name || 'Ổ vật lý', p.health === 'Healthy' ? 'Khoẻ' : p.health || 'Không rõ', `${p.media || ''} ${p.size || ''}`.trim(), p.health && p.health !== 'Healthy')).join('');
      el.innerHTML = [
        stat('laptop', 'Máy', s.computer, s.model),
        stat('window-wrench', 'Windows', `${s.displayVersion || ''} build ${s.build}`.trim(), s.os),
        stat('clock', 'Đã bật liên tục', s.uptimeText, 'Lâu không khởi động lại dễ chậm, lỗi update.', parseInt(s.uptimeText, 10) >= 14),
        stat('cpu', 'CPU', s.cpu),
        stat('data-bar', 'RAM', `${s.ramTotal}`, `Đang dùng ${s.ramUsedPct}% · còn trống ${s.ramFree}`, s.ramUsedPct >= 90),
        stat('flash', 'Card đồ hoạ', (s.gpus || []).join(', ') || 'Không rõ'),
        stat('code', 'Python', s.python || 'Chưa có', s.pythonPath || 'Cần cho công cụ ghi âm, mdf2sql, DWG sang PDF', !s.python),
        stat('download', 'winget', s.winget ? 'Có sẵn' : 'Chưa có', 'Dùng để cài phần mềm còn thiếu', !s.winget),
        stat('person', 'Tài khoản', s.user, s.isAdmin ? 'Trạm đang chạy với quyền Admin' : 'Công cụ cần Admin sẽ hỏi UAC khi chạy'),
        disks, phys,
      ].join('');
    }
  } catch (e) { const el = $('#sys'); if (el) el.innerHTML = emptyState('warning', 'Không đọc được thông tin máy', e.message); }
  await loadDepsAll(fresh, true);
}

async function loadDepsAll(fresh = false, renderList = false) {
  try {
    const all = await api(`/api/deps-all${fresh ? '?fresh=1' : ''}`);
    S.deps = { ...S.deps, ...all };
    S.depsLoaded = true;
    if (renderList) {
      const el = $('#reqs-all');
      if (el) {
        const rows = Object.entries(all).map(([id, items]) => {
          const t = S.byId.get(id);
          if (!t) return '';
          const bad = items.filter((q) => !q.ok && !q.optional);
          return `<div class="row clickable" data-go="#/tool/${enc(id)}">
            <div class="tile${bad.length ? '' : ' muted'}">${icon(t.icon || 'toolbox')}</div>
            <div><div class="row-title"><span class="name">${esc(t.name)}</span>${bad.length ? badge('danger', `Thiếu ${bad.length}`) : badge('success', 'Đủ')}</div>
            <div class="row-sub">${esc(items.map((q) => `${q.ok ? '✓' : '✗'} ${q.label}`).join('   '))}</div></div>
            <div class="row-side">${icon('chevron-right', 'chev')}</div></div>`;
        }).join('');
        el.innerHTML = rows || emptyState('check-circle', 'Không công cụ nào khai báo yêu cầu', '');
      }
    }
    if (['home', 'category', 'pinned'].includes(S.route.name)) renderMain(false);
  } catch { /* hiển thị ở trang chi tiết */ }
}

// ---------- trang Phân tích và nâng cấp
function renderRoadmap() {
  return `<div class="page"><div class="page-head"><div><h1>Phân tích và nâng cấp</h1><p>Đánh giá từng công cụ, lỗi đã biết và lộ trình nâng cấp. Nguồn: docs\\PHAN-TICH-NANG-CAP.md</p></div></div>
    <div class="card doc" id="roadmap"><div class="skeleton" style="height:160px;border:0"></div></div></div>`;
}
async function loadRoadmap() {
  try {
    const r = await api('/api/doc?name=PHAN-TICH-NANG-CAP');
    const el = $('#roadmap');
    if (el) el.innerHTML = renderMarkdown(r.markdown);
  } catch (e) { const el = $('#roadmap'); if (el) el.innerHTML = `<p class="muted">${esc(e.message)}</p>`; }
}

// ---------- trang Cài đặt
function renderSettings() {
  const st = (S.hub && S.hub.settings) || { browser: 'auto', autoExitMinutes: 10 };
  const seg = (v, label) => `<button data-act="theme" data-value="${v}" aria-pressed="${S.theme === v}">${label}</button>`;
  const opt = (v, label) => `<option value="${v}"${st.browser === v ? ' selected' : ''}>${label}</option>`;
  return `<div class="page"><div class="page-head"><div><h1>Cài đặt</h1><p>Áp dụng cho trạm trên máy này.</p></div></div>
    <div class="stack">
      <div class="card setting">${icon('moon')}<div><div class="t">Giao diện</div><div class="d">Theo Windows, hoặc chọn cố định Sáng / Tối.</div></div>
        <div class="seg" role="group" aria-label="Giao diện">${seg('system', 'Theo hệ thống')}${seg('light', 'Sáng')}${seg('dark', 'Tối')}</div></div>
      <div class="card setting">${icon('people')}<div><div class="t">Chế độ đơn giản</div><div class="d">Ẩn công cụ kỹ thuật và phần phân tích, hợp cho nhân viên văn phòng dùng.</div></div>
        <fluent-switch id="sw-simple-2"${S.simple ? ' checked' : ''}></fluent-switch></div>
      <div class="card setting">${icon('globe')}<div><div class="t">Trình duyệt mở trạm</div><div class="d">Tự động: Brave nếu có, không thì Edge. Áp dụng từ lần mở sau.</div></div>
        <select id="set-browser">${opt('auto', 'Tự động (Brave rồi Edge)')}${opt('brave', 'Brave')}${opt('edge', 'Microsoft Edge')}${opt('chrome', 'Google Chrome')}${opt('default', 'Trình duyệt mặc định')}</select></div>
      <div class="card setting">${icon('power')}<div><div class="t">Tự tắt máy chủ trạm</div><div class="d">Khi đã đóng hết cửa sổ trạm quá số phút này. 0 = không tự tắt.</div></div>
        <input type="number" id="set-exit" min="0" max="1440" value="${Number(st.autoExitMinutes)}"></div>
      <div class="card setting">${icon('tab-desktop')}<div><div class="t">Lối tắt trên Desktop</div><div class="d">Tạo biểu tượng "Trạm Tool" để mở nhanh.</div></div>
        <fluent-button data-act="shortcut">Tạo lối tắt</fluent-button></div>
      <div class="card setting">${icon('folder')}<div><div class="t">Thư mục trạm</div><div class="d mono">${esc(S.hub ? S.hub.root : '')}</div></div>
        <fluent-button data-act="open-root">Mở thư mục</fluent-button></div>
      <div class="card setting">${icon('puzzle')}<div><div class="t">Thêm công cụ mới</div><div class="d">Thả thư mục công cụ (hoặc 1 file .bat/.ps1) vào tools\\, bấm Làm mới. Xem docs\\THEM-CONG-CU.md để viết tool.json.</div></div>
        <fluent-button data-act="reload">${icon('refresh', 'ic-16')} Làm mới</fluent-button></div>
      <div class="card setting">${icon('info')}<div><div class="t">Trạm Tool ${esc(S.hub ? S.hub.version : '')}</div><div class="d">${esc(S.tools.length)} công cụ · máy ${esc(S.hub ? S.hub.computer : '')} · mở bằng ${esc(S.hub ? S.hub.browser || 'trình duyệt' : '')}</div></div>
        <fluent-button appearance="outline" data-act="shutdown">${icon('power', 'ic-16')} Tắt trạm</fluent-button></div>
    </div></div>`;
}

// ------------------------------------------------------------------ hiển thị theo route
function parseRoute() {
  const h = location.hash.replace(/^#\/?/, '');
  const [a, b] = h.split('/').map((x) => { try { return decodeURIComponent(x); } catch { return x; } });
  if (!a) return { name: 'home' };
  if (a === 'c' && b) return { name: 'category', id: b };
  if (a === 'tool' && b) return { name: 'tool', id: b };
  if (['pinned', 'outputs', 'history', 'system', 'roadmap', 'settings'].includes(a)) return { name: a };
  return { name: 'home' };
}

function renderMain(scrollTop = true) {
  const r = S.route;
  const main = $('#main');
  const html = {
    home: renderHome, category: () => renderCategory(r.id), pinned: renderPinned, tool: () => renderTool(r.id),
    outputs: renderOutputs, history: renderHistory, system: renderSystem, roadmap: renderRoadmap, settings: renderSettings,
  }[r.name] || renderHome;
  main.innerHTML = html();
  if (scrollTop) main.scrollTop = 0;
}

function render(load = true) {
  renderNav();
  renderMain();
  $('#app').classList.remove('nav-open');
  if (!load) return;
  const r = S.route;
  if (r.name === 'tool' && S.byId.has(r.id)) loadToolExtras(S.byId.get(r.id));
  if (r.name === 'outputs') loadOutputs();
  if (r.name === 'system') loadSystem();
  if (r.name === 'roadmap') loadRoadmap();
  if (r.name === 'history') loadHistory().then(() => { if (S.route.name === 'history') renderMain(false); });
  document.title = r.name === 'tool' && S.byId.has(r.id) ? `${S.byId.get(r.id).name} · Trạm Tool` : 'Trạm Tool';
}

function go(hash) {
  if (location.hash === hash) render(); else location.hash = hash;
}

async function loadHistory() {
  try { S.history = (await api('/api/history')).items || []; } catch { S.history = S.history || []; }
}

async function reloadCatalog(silent = false) {
  await api('/api/reload', { method: 'POST' });
  setCatalog(await api('/api/state'));
  S.deps = {};
  render();
  loadDepsAll();
  if (!silent) toast('success', `Đã quét lại: ${S.tools.length} công cụ.`, 3000);
}

// ------------------------------------------------------------------ chạy công cụ
// Form nhập tham số: file/thư mục chọn bằng hộp thoại gốc của Windows (máy chủ mở), còn lại nhập ngay trên form.
const form = { toolId: '', actionId: '', picks: {} };

function argField(spec) {
  const req = spec.required ? ' <span class="req" aria-hidden="true">*</span>' : '';
  const help = spec.help ? `<div class="hint">${esc(spec.help)}</div>` : '';
  const id = `arg-${spec.id}`;
  const def = spec.default == null ? '' : String(spec.default);
  if (spec.type === 'file' || spec.type === 'folder') {
    const empty = spec.type === 'folder' ? 'Chưa chọn thư mục' : spec.multiple ? 'Chưa chọn file nào' : 'Chưa chọn file';
    return `<div class="field"><span class="field-label">${esc(spec.label)}${req}</span>
      <div class="pick"><div class="pick-value" id="${esc(id)}" data-empty="${esc(empty)}">${esc(empty)}</div>
      <fluent-button data-act="pick-arg" data-arg="${esc(spec.id)}">${icon('folder', 'ic-16')} Chọn...</fluent-button></div>${help}</div>`;
  }
  if (spec.type === 'bool') {
    return `<div class="field"><label class="check"><input type="checkbox" id="${esc(id)}"${spec.default === true ? ' checked' : ''}> ${esc(spec.label)}</label>${help}</div>`;
  }
  if (spec.type === 'choice') {
    const opts = (spec.options || []).map((o) => `<option value="${esc(o.value)}"${o.value === def ? ' selected' : ''}>${esc(o.label)}</option>`).join('');
    return `<div class="field"><label class="field-label" for="${esc(id)}">${esc(spec.label)}${req}</label><select class="inp" id="${esc(id)}">${opts}</select>${help}</div>`;
  }
  const num = spec.type === 'number';
  return `<div class="field"><label class="field-label" for="${esc(id)}">${esc(spec.label)}${req}</label>
    <input class="inp" id="${esc(id)}" type="${num ? 'number' : 'text'}"${num && spec.min != null ? ` min="${esc(spec.min)}"` : ''}${num && spec.max != null ? ` max="${esc(spec.max)}"` : ''} value="${esc(def)}" placeholder="${esc(spec.placeholder)}" autocomplete="off" spellcheck="false">${help}</div>`;
}

function collectValues(specs) {
  const values = {};
  for (const s of specs) {
    const el = document.getElementById(`arg-${s.id}`);
    let v;
    if (s.type === 'file' || s.type === 'folder') v = form.picks[s.id] || [];
    else if (s.type === 'bool') v = !!(el && el.checked);
    else v = el ? el.value.trim() : '';
    const empty = Array.isArray(v) ? !v.length : v === '' || v === false;
    if (s.required && empty) return { error: `Chưa ${s.type === 'file' || s.type === 'folder' ? 'chọn' : 'nhập'} "${s.label}".` };
    if (s.type === 'number' && v !== '') {
      const n = Number(v);
      if (!Number.isInteger(n)) return { error: `"${s.label}" phải là số nguyên.` };
      if (s.min != null && n < s.min) return { error: `"${s.label}" nhỏ nhất là ${s.min}.` };
      if (s.max != null && n > s.max) return { error: `"${s.label}" lớn nhất là ${s.max}.` };
    }
    if (s.type === 'text' && /[%"!^]/.test(v)) return { error: `"${s.label}" không được chứa các ký tự % " ! ^.` };
    values[s.id] = v;
  }
  return { values };
}

function confirmHtml(a) {
  const changes = (a.changes || []).map((c) => `<li>${esc(c)}</li>`).join('');
  return `${a.confirm ? `<div class="warnbox">${esc(a.confirm)}</div>` : ''}
    ${changes ? `<p><strong>Công cụ có thể thay đổi:</strong></p><ul>${changes}</ul>` : ''}`;
}

async function runAction(toolId, actionId) {
  const t = S.byId.get(toolId);
  const a = t && (t.actions || []).find((x) => x.id === actionId);
  if (!a) return;
  const specs = a.args || [];
  const risky = a.risk === 'modifies-system' || !!a.confirm;
  const adminNote = a.admin ? `<p class="muted">${icon('shield-lock', 'ic-16')} Windows sẽ hỏi quyền Admin (UAC), bấm "Có" để tiếp tục.</p>` : '';
  let values = {};
  if (specs.length || risky) {
    Object.assign(form, { toolId, actionId, picks: {} });
    let collected = null;
    const ok = await openDialog({
      title: specs.length ? a.label : `Chạy: ${a.label}`,
      html: `${a.description ? `<p class="${specs.length ? 'muted' : ''}">${esc(a.description)}</p>` : ''}
        ${specs.length ? `<div class="form">${specs.map(argField).join('')}</div>` : ''}
        ${risky ? confirmHtml(a) : ''}${adminNote}`,
      buttons: [{ label: 'Chạy', appearance: 'primary', value: true, icon: 'play' }, { label: 'Huỷ', value: false }],
      validate: () => {
        const r = collectValues(specs);
        if (r.error) return r.error;
        collected = r.values;
        return '';
      },
    });
    if (!ok) return;
    values = collected || {};
  }
  try {
    const r = await api('/api/run', { method: 'POST', body: { toolId, actionId, values } });
    toast(r.ok ? 'success' : r.cancelled ? 'warning' : 'error', r.ok && a.admin ? `${r.message} Nếu không thấy cửa sổ, kiểm tra thanh tác vụ.` : r.message);
    loadHistory();
  } catch (e) { toast('error', e.message); }
}

async function pickArg(argId) {
  const t = S.byId.get(form.toolId);
  const a = t && (t.actions || []).find((x) => x.id === form.actionId);
  const spec = a && (a.args || []).find((s) => s.id === argId);
  if (!spec) return;
  toast('info', 'Đang mở hộp thoại chọn của Windows. Nếu không thấy, nhìn thanh tác vụ.', 4000);
  const r = await api('/api/pick', { method: 'POST', body: { toolId: t.id, actionId: a.id, argId } });
  const paths = r.paths || [];
  if (!paths.length) return;
  form.picks[argId] = spec.multiple ? paths : [paths[0]];
  const el = document.getElementById(`arg-${argId}`);
  if (el) {
    el.textContent = form.picks[argId].length > 1 ? `${form.picks[argId].length} mục: ${form.picks[argId].join('; ')}` : form.picks[argId][0];
    el.classList.add('set');
  }
  const box = $('#dlg-error');
  if (box) box.hidden = true;
}

// ------------------------------------------------------------------ sự kiện
document.addEventListener('click', async (e) => {
  const act = e.target.closest('[data-act]');
  if (act) {
    e.preventDefault();
    e.stopPropagation();
    if (act.hasAttribute('disabled')) return;
    const d = act.dataset;
    try {
      switch (d.act) {
        case 'run': await runAction(d.tool, d.action); break;
        case 'pick-arg': await pickArg(d.arg); break;
        case 'pin': {
          if (S.pins.has(d.tool)) S.pins.delete(d.tool); else S.pins.add(d.tool);
          store.set('pins', [...S.pins]);
          render(false);
          break;
        }
        case 'open-folder': await api('/api/open', { method: 'POST', body: { toolId: d.tool, target: 'folder' } }); break;
        case 'open-output': await api('/api/open', { method: 'POST', body: { toolId: d.tool, target: 'output', path: d.path } }); break;
        case 'reveal-output': await api('/api/open', { method: 'POST', body: { toolId: d.tool, target: 'output-folder', path: d.path } }); break;
        case 'pack': {
          toast('info', 'Đang đóng gói...', 2500);
          const r = await api('/api/pack', { method: 'POST', body: { toolId: d.tool } });
          toast('success', `Đã tạo ${r.path} (${r.files} file, ${r.size}). Gửi file .zip này cho khách.`, 9000);
          break;
        }
        case 'scaffold': {
          const r = await api('/api/scaffold', { method: 'POST', body: { toolId: d.tool } });
          toast('success', `Đã tạo ${r.path}. Sửa tên, nhóm, mức rủi ro rồi bấm Làm mới.`, 9000);
          await reloadCatalog(true);
          break;
        }
        case 'fix': {
          const r = await api('/api/fix', { method: 'POST', body: { toolId: d.tool, reqId: d.req } });
          toast(r.ok === false ? 'error' : 'info', r.message || 'Đã mở cửa sổ cài đặt.', 9000);
          break;
        }
        case 'recheck': await loadReqs(S.byId.get(d.tool), true); toast('success', 'Đã kiểm tra lại.', 2500); break;
        case 'recheck-all': await loadDepsAll(true, true); toast('success', 'Đã kiểm tra lại.', 2500); break;
        case 'probes': await loadProbes(S.byId.get(d.tool)); break;
        case 'scroll-docs': { const el = $('#docs'); if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' }); break; }
        case 'reload': await reloadCatalog(); break;
        case 'reload-page': render(); break;
        case 'clear-search': setQuery(''); break;
        case 'theme': S.theme = d.value; store.set('theme', S.theme); applyTheme(); renderMain(false); break;
        case 'shortcut': { const r = await api('/api/shortcut', { method: 'POST' }); toast('success', `Đã tạo lối tắt: ${r.path}`); break; }
        case 'open-root': await api('/api/open-root', { method: 'POST' }); break;
        case 'shutdown': {
          const ok = await openDialog({ title: 'Tắt Trạm Tool?', html: '<p>Máy chủ của trạm sẽ dừng. Các công cụ đang chạy trong cửa sổ riêng không bị ảnh hưởng. Mở lại bằng TramTool.bat.</p>', buttons: [{ label: 'Tắt trạm', appearance: 'primary', value: true }, { label: 'Huỷ', value: false }] });
          if (ok) { await api('/api/shutdown', { method: 'POST' }); showOverlay('offline'); $('#overlay-title').textContent = 'Đã tắt Trạm Tool'; $('#overlay-text').textContent = 'Có thể đóng cửa sổ này. Mở lại bằng TramTool.bat.'; }
          break;
        }
        default: break;
      }
    } catch (err) { toast('error', err.message); }
    return;
  }
  const nav = e.target.closest('[data-go]');
  if (nav) { e.preventDefault(); go(nav.dataset.go); }
});

document.addEventListener('keydown', (e) => {
  if ((e.ctrlKey && e.key.toLowerCase() === 'k') || (e.key === '/' && !/input|textarea|select/i.test(document.activeElement?.tagName || '') && document.activeElement?.tagName !== 'FLUENT-TEXT-INPUT')) {
    e.preventDefault();
    $('#search').focus();
    return;
  }
  if (e.key === 'Escape' && S.query) { setQuery(''); return; }
  if ((e.key === 'Enter' || e.key === ' ') && e.target.matches?.('.row.clickable[data-go]')) { e.preventDefault(); go(e.target.dataset.go); }
});

function setQuery(q) {
  S.query = q;
  const input = $('#search');
  if (input.value !== q) input.value = q;
  if (!['home', 'category', 'pinned'].includes(S.route.name) && q) { location.hash = '#/'; return; }
  renderMain(false);
}
$('#search').addEventListener('input', (e) => setQuery(e.target.value || ''));
$('#search').addEventListener('keydown', (e) => {
  if (e.key === 'Enter') {
    const first = visibleTools().find((t) => matches(t, S.query));
    if (first) go(`#/tool/${enc(first.id)}`);
  }
});

document.addEventListener('change', async (e) => {
  const id = e.target.id;
  if (id === 'sw-simple' || id === 'sw-simple-2') {
    S.simple = !!e.target.checked;
    store.set('simple', S.simple);
    render(false);
    toast('info', S.simple ? 'Đã bật chế độ đơn giản: ẩn công cụ kỹ thuật.' : 'Đã tắt chế độ đơn giản.', 2500);
  }
  if (id === 'set-browser' || id === 'set-exit') {
    try {
      const body = { browser: $('#set-browser').value, autoExitMinutes: Number($('#set-exit').value) };
      const r = await api('/api/settings', { method: 'POST', body });
      if (S.hub) S.hub.settings = r;
      toast('success', 'Đã lưu cài đặt.', 2000);
    } catch (err) { toast('error', err.message); }
  }
});

$('#menu-btn').addEventListener('click', () => $('#app').classList.toggle('nav-open'));
$('#overlay-retry').addEventListener('click', () => location.reload());
window.addEventListener('hashchange', () => { S.route = parseRoute(); render(); });

// ------------------------------------------------------------------ khởi động
async function boot() {
  applyTheme();
  document.body.classList.add('ready');
  if (!token) { showOverlay('token'); return; }
  $('#main').innerHTML = `<div class="page"><div class="page-head"><div><h1>Tất cả công cụ</h1><p>Đang nạp danh sách...</p></div></div><div class="stack">${'<div class="skeleton"></div>'.repeat(5)}</div></div>`;
  try {
    setCatalog(await api('/api/state'));
  } catch (e) {
    if (overlayKind !== 'token') toast('error', e.message);
    return;
  }
  S.route = parseRoute();
  render();
  loadHistory().then(() => { if (S.route.name === 'home') renderMain(false); });
  loadDepsAll();
  setInterval(() => { api('/api/ping').catch(() => { /* overlay đã hiện */ }); }, 20000);
}

boot();
