// Trạm Tool - giao diện (ES module, không cần build). Máy chủ: hub/TramTool.ps1
// Mã giao diện chia theo trang trong js/ và js/pages/; vẽ bằng lit-html (vendor/lit-html), thành phần Fluent UI.
import { html, render } from './vendor/lit-html/lit-html.js';
import { keyed } from './vendor/lit-html/directives/keyed.js';
import { $, api, hasToken, local, loadIcons } from './js/core.js';
import { S, setRenderer, setCatalog, saveSettings } from './js/state.js';
import { applyTheme, toast, initDialog, showOverlay, overlayShown } from './js/ui.js';
import { openPalette, initPalette } from './js/palette.js';
import { refreshJobs, dockTemplate } from './js/jobs.js';
import { loadHistory, loadDepsAll, reloadCatalog } from './js/data.js';
import { navTemplate } from './js/pages/nav.js';
import { homePage, homeLoad } from './js/pages/home.js';
import { categoryPage } from './js/pages/category.js';
import { toolPage, toolLoad } from './js/pages/tool.js';
import { outputsPage, outputsLoad } from './js/pages/outputs.js';
import { historyPage, historyLoad } from './js/pages/history.js';
import { systemPage, systemLoad } from './js/pages/system.js';
import { settingsPage } from './js/pages/settings.js';
import { roadmapPage, roadmapLoad } from './js/pages/roadmap.js';

// ------------------------------------------------------------------ định tuyến (#/..., không tải lại trang)
const PAGE = {
  home: { view: () => homePage(), load: () => homeLoad() },
  category: { view: (r) => categoryPage(r.id) },
  tool: { view: (r) => toolPage(r.id), load: (r) => toolLoad(r.id) },
  outputs: { view: (r) => outputsPage(r.id), load: (r) => outputsLoad(r.id) },
  history: { view: () => historyPage(), load: () => historyLoad() },
  system: { view: () => systemPage(), load: () => systemLoad() },
  roadmap: { view: () => roadmapPage(), load: () => roadmapLoad() },
  settings: { view: () => settingsPage() },
};

function parseRoute() {
  const h = location.hash.replace(/^#\/?/, '');
  const [a, b] = h.split('/').map((x) => { try { return decodeURIComponent(x); } catch { return x; } });
  if (!a) return { name: 'home' };
  if (a === 'c' && b) return { name: 'category', id: b };
  if (a === 'tool' && b) return { name: 'tool', id: b };
  if (a === 'outputs') return { name: 'outputs', id: b || '' };
  if (['history', 'system', 'roadmap', 'settings'].includes(a)) return { name: a };
  return { name: 'home' };
}

function renderApp() {
  const r = S.route;
  const p = PAGE[r.name] || PAGE.home;
  render(navTemplate(), $('#nav'));
  // keyed: sang trang khác thì dựng mới (có hiệu ứng vào trang); cùng trang thì chỉ cập nhật chỗ thay đổi.
  render(keyed(`${r.name}/${r.id || ''}`, p.view(r)), $('#main'));
  render(dockTemplate(), $('#dock'));
  document.body.classList.toggle('has-dock', S.jobs.length > 0);
}

function onRoute() {
  S.route = parseRoute();
  const p = PAGE[S.route.name] || PAGE.home;
  $('#app').classList.remove('nav-open');
  renderApp();
  $('#main').scrollTop = 0;
  if (p.load) p.load(S.route);
  const t = S.route.name === 'tool' && S.byId.get(S.route.id);
  document.title = t ? `${t.name} · Trạm Tool` : 'Trạm Tool';
}

// ------------------------------------------------------------------ phím tắt
const dialogOpen = () => !!($('#dlg').dialog && $('#dlg').dialog.open) || $('#palette').open;
document.addEventListener('keydown', (e) => {
  if (dialogOpen()) return;
  const el = document.activeElement;
  const typing = !!el && (/^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName) || el.isContentEditable || el.tagName === 'FLUENT-TEXT-INPUT');
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); openPalette(); return; }
  if (e.key === '/' && !typing) { e.preventDefault(); openPalette(); }
});

$('#menu-btn').addEventListener('click', () => $('#app').classList.toggle('nav-open'));
// Màn hình hẹp: bấm vào lớp mờ (chính phần tử .app) hoặc Esc thì đóng menu.
$('#app').addEventListener('click', (e) => { if (e.target === e.currentTarget) e.currentTarget.classList.remove('nav-open'); });
document.addEventListener('keydown', (e) => { if (e.key === 'Escape') $('#app').classList.remove('nav-open'); });
$('#overlay-retry').addEventListener('click', () => location.reload());
window.addEventListener('tram:reload', () => reloadCatalog());

// Bản trước lưu ghim, chế độ đơn giản, giao diện trong localStorage của trình duyệt; chuyển một lần lên máy chủ.
async function migrateLocalPrefs() {
  const patch = {};
  const pins = local.get('pins', null);
  if (Array.isArray(pins) && pins.length && !S.settings.pins.length) patch.pins = pins.filter((id) => S.byId.has(id));
  if (local.get('simple', null) === true && !S.settings.simple) patch.simple = true;
  const theme = local.get('theme', null);
  if ((theme === 'dark' || theme === 'light') && S.settings.theme === 'system') patch.theme = theme;
  for (const k of ['pins', 'simple', 'theme']) local.remove(k);
  if (Object.keys(patch).length) { try { await saveSettings(patch); } catch { /* giữ mặc định */ } }
}

// Thông báo nhanh nằm trên thanh Đang chạy.
const dockObserver = new ResizeObserver(() => {
  document.body.style.setProperty('--dock-h', `${$('#dock').offsetHeight}px`);
});

// ------------------------------------------------------------------ khởi động
async function boot() {
  const icons = loadIcons();
  initDialog();
  initPalette();
  applyTheme();
  dockObserver.observe($('#dock'));
  document.body.classList.add('ready');
  if (!hasToken()) { showOverlay('token'); return; }
  render(html`<div class="page"><header class="page-head"><div><h1>Tổng quan</h1><p>Đang nạp danh sách công cụ...</p></div></header>
    <div class="stack">${[1, 2, 3, 4, 5].map(() => html`<div class="skeleton"></div>`)}</div></div>`, $('#main'));
  try {
    setCatalog(await api('/api/state'));
  } catch (e) {
    if (overlayShown() !== 'token') toast('error', e.message);
    return;
  }
  await icons;
  applyTheme();
  await migrateLocalPrefs();
  applyTheme();
  setRenderer(renderApp);
  window.addEventListener('hashchange', onRoute);
  onRoute();
  if (!S.history) loadHistory();
  if (!S.depsLoaded) loadDepsAll();
  refreshJobs();
  setInterval(() => { api('/api/ping').catch(() => { /* lớp phủ đã hiện */ }); }, 20000);
}

boot();
