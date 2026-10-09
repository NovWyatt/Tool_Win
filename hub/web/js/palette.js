// Trạm Tool - ô tìm nhanh (Ctrl+K): tìm công cụ, chạy action, mở trang, mở kết quả gần đây.
// Gõ ">" ở đầu để chỉ hiện việc có thể chạy. Enter: mở; Ctrl+Enter: chạy ngay việc chính của công cụ.
import { html, render, nothing } from '../vendor/lit-html/lit-html.js';
import { live } from '../vendor/lit-html/directives/live.js';
import { $, api, icon, enc, norm, timeAgo } from './core.js';
import { S, go, visibleTools, pinnedTools, primaryAction, catLabel, matches, saveSettings, PAGES } from './state.js';
import { runAction } from './run.js';
import { applyTheme, toast } from './ui.js';

let query = '';
let active = 0;
let items = [];

function toolItem(t, why = '') {
  const a = primaryAction(t);
  return {
    key: `t:${t.id}`, group: 'Công cụ', icon: t.icon || 'toolbox', title: t.name, sub: why || t.summary,
    hint: a ? 'Ctrl+Enter chạy' : '',
    run: () => go(`#/tool/${enc(t.id)}`),
    alt: a ? () => runAction(t.id, a.id) : null,
    hay: t._hay,
  };
}

function actionItems(tools) {
  const out = [];
  for (const t of tools) {
    for (const a of t.actions || []) {
      if (!a.exists) continue;
      out.push({
        key: `a:${t.id}:${a.id}`, group: 'Chạy nhanh', icon: a.admin ? 'shield' : 'play', title: a.label, sub: t.name,
        run: () => runAction(t.id, a.id), hay: norm(`${a.label} ${t.name} chay`),
      });
    }
  }
  return out;
}

function commandItems() {
  const dark = document.documentElement.dataset.theme === 'dark';
  return [
    { key: 'c:reload', group: 'Lệnh', icon: 'refresh', title: 'Làm mới danh sách công cụ', run: () => window.dispatchEvent(new CustomEvent('tram:reload')), hay: 'lam moi danh sach cong cu quet lai reload' },
    { key: 'c:simple', group: 'Lệnh', icon: 'people', title: S.settings.simple ? 'Tắt chế độ đơn giản' : 'Bật chế độ đơn giản', run: () => saveSettings({ simple: !S.settings.simple }), hay: 'che do don gian an cong cu ky thuat simple' },
    { key: 'c:theme', group: 'Lệnh', icon: dark ? 'sun' : 'moon', title: dark ? 'Chuyển sang giao diện sáng' : 'Chuyển sang giao diện tối', run: () => saveSettings({ theme: dark ? 'light' : 'dark' }).then(applyTheme), hay: 'giao dien sang toi dark light theme' },
  ];
}

function pageItems() {
  return PAGES.filter((p) => !(p.tech && S.settings.simple)).map((p) => ({
    key: `p:${p.id}`, group: 'Trang', icon: p.icon, title: p.label, run: () => go(`#/${p.id}`), hay: norm(`${p.label} trang`),
  }));
}

function outputItems() {
  return (S.outputs || []).slice(0, 30).map((f) => ({
    key: `o:${f.path}`, group: 'Kết quả gần đây', icon: f.isFolder ? 'folder' : 'document', title: f.name, sub: `${f.toolName}, ${timeAgo(f.modified)}`,
    run: () => api('/api/open', { method: 'POST', body: { toolId: f.toolId, target: 'output', path: f.path } }).catch((e) => toast('error', e.message)),
    hay: norm(`${f.name} ${f.toolName} ${f.label}`),
  }));
}

function compute() {
  const tools = visibleTools();
  const raw = query.trim();
  const onlyActions = raw.startsWith('>');
  const q = norm(onlyActions ? raw.slice(1) : raw).trim();
  const words = q.split(/\s+/).filter(Boolean);
  const hit = (it) => words.every((w) => it.hay.includes(w));
  let list;
  if (!q && !onlyActions) {
    // Chưa gõ gì: công cụ đã ghim, dùng gần đây, rồi các trang.
    const seen = new Set();
    const first = [];
    for (const t of pinnedTools()) { seen.add(t.id); first.push(toolItem(t, 'Đã ghim')); }
    for (const h of S.history || []) {
      const t = S.byId.get(h.toolId);
      if (!t || seen.has(t.id) || !tools.includes(t)) continue;
      seen.add(t.id);
      first.push(toolItem(t, `Dùng ${timeAgo(h.time)}`));
      if (first.length >= 8) break;
    }
    for (const t of tools) { if (first.length >= 8) break; if (!seen.has(t.id)) { seen.add(t.id); first.push(toolItem(t)); } }
    list = [...first, ...pageItems()];
  } else if (onlyActions) {
    list = [...actionItems(tools), ...commandItems()].filter((it) => !q || hit(it));
  } else {
    const score = (it) => (norm(it.title).startsWith(words[0] || '') ? 0 : norm(it.title).includes(q) ? 1 : 2);
    const toolsHit = tools.filter((t) => matches(t, q)).map((t) => toolItem(t, catLabel(t.category)));
    list = [
      ...toolsHit.sort((a, b) => score(a) - score(b)),
      ...actionItems(tools).filter(hit).sort((a, b) => score(a) - score(b)).slice(0, 8),
      ...pageItems().filter(hit),
      ...commandItems().filter(hit),
      ...outputItems().filter(hit).slice(0, 6),
    ];
  }
  items = list.slice(0, 40);
  if (active >= items.length) active = Math.max(0, items.length - 1);
}

function draw() {
  compute();
  let lastGroup = '';
  const rows = items.map((it, i) => {
    const head = it.group !== lastGroup ? html`<li class="pal-group" role="presentation">${it.group}</li>` : nothing;
    lastGroup = it.group;
    return html`${head}<li class="pal-item" role="option" id="pal-${i}" aria-selected=${i === active}
      @mousemove=${() => { if (active !== i) { active = i; draw(); } }} @click=${(e) => choose(i, e.ctrlKey)}>
      ${icon(it.icon)}
      <span class="pal-text"><span class="pal-title">${it.title}</span>${it.sub ? html`<span class="pal-sub">${it.sub}</span>` : nothing}</span>
      ${i === active && it.hint ? html`<span class="pal-hint">${it.hint}</span>` : nothing}
    </li>`;
  });
  render(html`
    <div class="pal-box">
      <div class="pal-input">${icon('search')}
        <input id="pal-q" type="text" role="combobox" aria-expanded="true" aria-controls="pal-list" aria-autocomplete="list"
          aria-activedescendant=${items.length ? `pal-${active}` : ''} placeholder="Tìm công cụ, việc cần làm, trang... (gõ > để chỉ hiện việc chạy được)"
          autocomplete="off" spellcheck="false" .value=${live(query)} @input=${(e) => { query = e.target.value; active = 0; draw(); }} @keydown=${onKey}>
      </div>
      <ul class="pal-list" id="pal-list" role="listbox" aria-label="Kết quả">
        ${rows.length ? rows : html`<li class="pal-empty">Không thấy gì khớp "${query.trim()}". Thử từ khoá khác, vd "wifi", "excel", "ổ cứng".</li>`}
      </ul>
      <div class="pal-foot"><span><kbd>↑</kbd><kbd>↓</kbd> chọn</span><span><kbd>Enter</kbd> mở</span><span><kbd>Ctrl</kbd>+<kbd>Enter</kbd> chạy ngay</span><span><kbd>Esc</kbd> đóng</span></div>
    </div>`, $('#palette'));
  document.getElementById(`pal-${active}`)?.scrollIntoView({ block: 'nearest' });
}

function onKey(e) {
  if (e.key === 'ArrowDown') { e.preventDefault(); active = Math.min(items.length - 1, active + 1); draw(); }
  else if (e.key === 'ArrowUp') { e.preventDefault(); active = Math.max(0, active - 1); draw(); }
  else if (e.key === 'Enter') { e.preventDefault(); choose(active, e.ctrlKey); }
}

function choose(i, alt = false) {
  const it = items[i];
  if (!it) return;
  closePalette();
  (alt && it.alt ? it.alt : it.run)();
}

export function openPalette(initial = '') {
  const dlg = $('#palette');
  query = initial;
  active = 0;
  // Lần đầu mở: nạp danh sách kết quả gần đây để tìm được cả file.
  if (!S.outputs) api('/api/outputs').then((r) => { S.outputs = r.items || []; if (dlg.open) draw(); }).catch(() => {});
  draw();
  if (!dlg.open) dlg.showModal();
  const input = $('#pal-q');
  input.focus();
  input.setSelectionRange(input.value.length, input.value.length);
}

export function closePalette() {
  const dlg = $('#palette');
  if (dlg.open) dlg.close();
}

export function initPalette() {
  const dlg = $('#palette');
  // Bấm ra ngoài khung thì đóng.
  dlg.addEventListener('click', (e) => { if (e.target === dlg) closePalette(); });
}
