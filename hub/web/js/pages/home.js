// Trạm Tool - trang Tổng quan: máy này, ô tìm (lọc danh mục ngay tại chỗ), cần chú ý, đã ghim, dùng gần đây,
// rồi danh mục công cụ theo nhóm.
import { html, nothing } from '../../vendor/lit-html/lit-html.js';
import { live } from '../../vendor/lit-html/directives/live.js';
import { icon, enc, clock, uptimeText, driveName, norm } from '../core.js';
import { S, go, update, visibleTools, pinnedTools, missingDeps, runState, matches, saveSettings } from '../state.js';
import { section, toolRow, pinRow, runStateText, shortWhen, onRowKey, stop, emptyState, btn } from '../parts.js';
import { runAction } from '../run.js';
import { openPalette } from '../palette.js';
import { toast } from '../ui.js';
import { loadHistory, loadDepsAll, loadSystem, reloadCatalog } from '../data.js';
import { showResult } from '../result.js';

let query = '';

export function homeLoad() {
  query = '';
  loadHistory();
  loadSystem();
  if (!S.depsLoaded) loadDepsAll();
}

// Phím "/" ở Tổng quan: vào ô tìm của trang thay vì mở hộp Tìm nhanh.
export function focusHomeFind() {
  const el = document.getElementById('home-q');
  if (!el) return false;
  el.focus();
  el.select();
  return true;
}

// Những điều nên xử lý: công cụ hỏng hoặc thiếu yêu cầu, ổ đầy, máy bật quá lâu, lần chạy hôm nay báo lỗi, làm
// một phần hoặc tìm thấy lỗi (file kết quả). Chữ trên nút nói đúng việc nút làm.
function attentionItems() {
  const out = [];
  for (const t of visibleTools()) {
    const to = `#/tool/${enc(t.id)}`;
    if (t.status === 'broken') out.push({ ic: 'dismiss-circle', tone: 'danger', text: `${t.name} đang hỏng.${t.statusNote ? ` ${t.statusNote}` : ''}`, act: 'Xem công cụ', to });
    const miss = missingDeps(t);
    if (miss.length) out.push({ ic: 'download', tone: 'warning', text: `${t.name} cần cài thêm: ${miss.map((m) => m.label).join(', ')}.`, act: 'Xem cách cài', to });
  }
  const s = S.system;
  if (s && !s.error) {
    for (const d of s.disks || []) {
      if (d.freePct < 12) out.push({ ic: 'hard-drive', tone: 'warning', text: `Ổ ${driveName(d.drive)} chỉ còn ${d.freePct}% trống (${d.free}). Ổ đầy làm máy chậm và Windows Update dễ lỗi.`, act: 'Xem ổ đĩa', to: '#/system' });
    }
    const days = s.lastBoot ? Math.floor((Date.now() - Date.parse(s.lastBoot)) / 86400000) : 0;
    if (days >= 14) out.push({ ic: 'clock', tone: 'info', text: `Máy đã bật liên tục ${days} ngày. Khởi động lại giúp Windows cài xong bản cập nhật và chạy ổn định hơn.`, act: '', to: '' });
    const sb = s.secureBoot || {};
    if (sb.enabled && sb.ca2023 && sb.ca2023 !== 'Updated') {
      out.push({ ic: 'shield-error', tone: 'warning', text: 'Secure Boot chưa nhận chứng chỉ 2023 của Microsoft (chứng chỉ cũ hết hạn 19/10/2026). Máy vẫn khởi động bình thường; cập nhật Windows và BIOS để nhận bản vá khởi động sau này.', act: 'Xem máy', to: '#/system' });
    }
    if (s.restore && s.restore.enabled === false) {
      out.push({ ic: 'shield-error', tone: 'info', text: `Bảo vệ hệ thống đang tắt nên trạm chưa tạo được điểm khôi phục trước khi chạy công cụ sửa máy. ${s.restore.policyOff || s.restore.vssDisabled || s.restore.configLocked ? s.restore.detail : ''}`.trim(), act: 'Bật ở trang Máy này', to: '#/system' });
    }
    if (s.winget && typeof s.winget === 'object' && !s.winget.ok) {
      out.push({ ic: 'download', tone: 'warning', text: `winget chưa dùng được: ${s.winget.problem} Các nút Cài cần winget.`, act: 'Sửa winget', to: '#/system' });
    }
  }
  const seen = new Set();
  const vis = new Set(visibleTools().map((t) => t.id));
  for (const h of S.history || []) {
    if (Date.now() - Date.parse(h.time) > 86400000) break;
    // Chỉ xét lần chạy mới nhất của mỗi công cụ: chạy lại ổn rồi thì thôi nhắc lần trước.
    if (seen.has(h.toolId) || !vis.has(h.toolId) || h.state === 'running') continue;
    seen.add(h.toolId);
    const k = h.ketQua;
    const errs = (k && k.tomTat && k.tomTat.loi) || 0;
    const bad = h.state === 'failed' || h.state === 'error';
    if (!bad && h.state !== 'partial' && !errs) continue;
    const what = errs && !bad ? `tìm thấy ${errs} lỗi` : runState(h).label.toLowerCase();
    out.push({
      ic: bad ? 'dismiss-circle' : 'warning', tone: bad ? 'danger' : 'warning',
      text: `${h.toolName}: "${h.actionLabel}" lúc ${clock(h.time)} ${what}.`,
      act: k ? 'Xem kết quả' : 'Xem lịch sử', to: '#/history', run: k ? () => showResult(h.toolId, k.path) : null,
    });
  }
  return out;
}

const noticeRow = (a) => html`<div class="notice-row ${a.tone}">
  ${icon(a.ic)}<span>${a.text}</span>
  ${a.act ? btn(a.act, () => (a.run ? a.run() : go(a.to)), { sm: true }) : nothing}
</div>`;

// Mỗi việc (công cụ + action) chỉ hiện lần chạy gần nhất.
function recentRuns() {
  const seen = new Set();
  const list = [];
  const vis = new Set(visibleTools().map((t) => t.id));
  for (const h of S.history || []) {
    const key = `${h.toolId}|${h.actionId}`;
    if (seen.has(key) || !vis.has(h.toolId)) continue;
    seen.add(key);
    list.push(h);
    if (list.length >= 5) break;
  }
  return list;
}

function recentRow(h) {
  const t = S.byId.get(h.toolId);
  const a = (t.actions || []).find((x) => x.id === h.actionId);
  const to = `#/tool/${enc(t.id)}`;
  return html`<div class="rrow" role="link" tabindex="0" aria-label=${t.name} @click=${() => go(to)} @keydown=${onRowKey(to)}>
    <span class="when">${shortWhen(h.time)}</span>
    <div class="what"><span class="name">${t.name}</span><span class="sub"><span class="sub-text">${h.actionLabel}</span>${runStateText(h, { withDur: false })}</span></div>
    <div class="side">
      ${a && a.exists && h.state !== 'running' ? btn('Chạy lại', stop(() => runAction(t.id, a.id, { values: h.values || null })),
        { kind: 'ghost', sm: true, ic: 'arrow-repeat', title: h.values ? `Chạy lại "${a.label}" với tham số của lần này` : `Chạy lại "${a.label}"` }) : nothing}
    </div>
  </div>`;
}

// Vài dòng về máy đang dùng, lấy từ trang Máy này.
function machineFacts() {
  const s = S.system;
  if (!s) return html`<p class="facts-wait">Đang đọc thông tin máy...</p>`;
  if (s.error) return nothing;
  const c = (s.disks || []).find((d) => /^C:/i.test(d.drive));
  const fact = (k, v, warn = false) => html`<div><dt>${k}</dt><dd class=${warn ? 'warn' : ''} title=${v}>${v}</dd></div>`;
  return html`<dl class="facts-strip">
    ${fact('Máy', s.computer)}
    ${fact('Windows', `${s.displayVersion || ''} build ${s.build}`.trim())}
    ${c ? fact('Ổ C còn trống', `${c.free}, ${Math.round(c.freePct)}%`, c.freePct < 12) : nothing}
    ${s.uptimeText ? fact('Đã bật liên tục', uptimeText(s.uptimeText)) : nothing}
  </dl>`;
}

// Chế độ đơn giản ẩn công cụ kỹ thuật: nói rõ để không ai tưởng công cụ bị mất.
function hiddenNote(n, tail = '') {
  if (!n) return nothing;
  const show = () => saveSettings({ simple: false }).then(() => toast('info', 'Đã tắt chế độ đơn giản, hiện mọi công cụ.', { ms: 2500 }))
    .catch((e) => toast('error', e.message));
  return html`<p class="hidden-note">${icon('eye', 'ic-16')}<span>Chế độ đơn giản đang ẩn ${n} công cụ kỹ thuật${tail}.</span>
    <button class="link" @click=${show}>Hiện tất cả</button></p>`;
}

function findResults(q) {
  const tools = visibleTools();
  const first = norm(q).split(/\s+/)[0] || '';
  const score = (t) => (norm(t.name).startsWith(first) ? 0 : norm(t.name).includes(first) ? 1 : 2);
  const hits = tools.filter((t) => matches(t, q)).sort((a, b) => score(a) - score(b));
  const hidden = S.tools.filter((t) => !tools.includes(t) && matches(t, q)).length;
  return html`<section class="section find-results" aria-live="polite">
    <div class="section-head"><div><h2>${hits.length ? `${hits.length} công cụ khớp "${q}"` : `Không thấy công cụ nào khớp "${q}"`}</h2>
      ${hits.length ? html`<p>Enter để mở công cụ đầu tiên, mũi tên xuống để chọn.</p>` : nothing}</div></div>
    ${hits.length ? html`<div class="cat-list">${hits.map((t) => toolRow(t, { cat: true }))}</div>`
      : emptyState('search', 'Thử từ khác', 'Gõ việc cần làm hoặc tên phần mềm, vd "in", "mạng", "word", "bitlocker".')}
    ${hiddenNote(hidden, ' khớp từ này')}
    <p class="find-more">Tìm cả việc chạy được, trang và file kết quả: <button class="link" @click=${() => { const v = query; query = ''; openPalette(v); }}>mở Tìm nhanh</button></p>
  </section>`;
}

function onFindKey(e) {
  if (e.key === 'Escape' && query) { e.preventDefault(); e.stopPropagation(); query = ''; update(); return; }
  if (e.key === 'ArrowDown') {
    const row = document.querySelector('.find-results .trow');
    if (row) { e.preventDefault(); row.focus(); }
    return;
  }
  if (e.key === 'Enter') {
    const row = document.querySelector('.find-results .trow');
    if (row) { e.preventDefault(); row.click(); }
  }
}

// Mũi tên lên, xuống giữa các dòng kết quả; lên khỏi dòng đầu thì về ô tìm.
function onResultsKey(e) {
  if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return;
  const rows = [...document.querySelectorAll('.find-results .trow')];
  const i = rows.indexOf(document.activeElement);
  if (i < 0) return;
  e.preventDefault();
  if (e.key === 'ArrowDown') rows[Math.min(rows.length - 1, i + 1)].focus();
  else if (i === 0) document.getElementById('home-q')?.focus();
  else rows[i - 1].focus();
}

function findBox() {
  return html`<div class="find">
    ${icon('search')}
    <input id="home-q" class="find-input" type="text" role="searchbox" aria-label="Tìm công cụ" autocomplete="off" spellcheck="false"
      placeholder="Tìm công cụ: wifi, máy in, excel, ổ cứng..." .value=${live(query)}
      @input=${(e) => { query = e.target.value; update(); }} @keydown=${onFindKey}>
    ${query ? html`<button class="icon-btn" aria-label="Xoá chữ đã gõ" title="Xoá (Esc)" @click=${() => { query = ''; update(); document.getElementById('home-q')?.focus(); }}>${icon('dismiss')}</button>`
      : html`<button class="find-hint" title="Tìm cả việc chạy được, trang và file kết quả" @click=${() => openPalette()}>Tìm nhanh mọi thứ<span class="keys"><kbd>Ctrl</kbd><kbd>K</kbd></span></button>`}
  </div>`;
}

// Một khung trang cho cả lúc tìm lẫn lúc không: đổi khung thì lit-html dựng lại cả trang, ô tìm mất con trỏ sau chữ đầu.
export function homePage() {
  const q = query.trim();
  return html`<div class="page" @keydown=${onResultsKey}>
    <header class="page-head">
      <div><h1>Tổng quan</h1>${machineFacts()}</div>
      <div class="actions">${btn('Làm mới', () => reloadCatalog(), { kind: 'ghost', ic: 'refresh', title: 'Quét lại thư mục tools' })}</div>
    </header>
    ${findBox()}
    ${q ? findResults(q) : homeBody()}
  </div>`;
}

function homeBody() {
  const tools = visibleTools();
  const cats = S.categories.filter((c) => tools.some((t) => t.category === c.id));
  const pins = pinnedTools();
  const att = attentionItems();
  const recent = recentRuns();
  const hidden = S.tools.length - tools.length;
  return html`
    ${att.length ? section('Cần chú ý', '', html`<div class="notices">${att.map(noticeRow)}</div>`) : nothing}
    ${pins.length || recent.length ? html`<div class="quick">
      ${pins.length ? section('Đã ghim', 'Nút Chạy làm việc chính ghi dưới tên công cụ.', html`<div class="stack">${pins.map(pinRow)}</div>`) : nothing}
      ${recent.length ? section('Dùng gần đây', '', html`<div class="stack">${recent.map(recentRow)}</div>`,
        { tools: btn('Xem lịch sử', () => go('#/history'), { kind: 'ghost', sm: true }) }) : nothing}
    </div>` : nothing}
    ${tools.length ? html`<section class="catalog">
      <div class="catalog-head"><h2>Tất cả công cụ</h2><span>${tools.length} công cụ trong ${cats.length} nhóm. Bấm một dòng để xem các việc và chạy.</span></div>
      ${hiddenNote(hidden)}
      ${cats.map((c) => {
        const list = tools.filter((t) => t.category === c.id);
        return html`<div class="cat" id="cat-${c.id}">
          <div class="cat-head"><h3>${icon(c.icon || 'toolbox')}<span>${c.label}</span><span class="count">${list.length}</span></h3>${c.description ? html`<p>${c.description}</p>` : nothing}</div>
          <div class="cat-list">${list.map((t) => toolRow(t))}</div>
        </div>`;
      })}
    </section>`
    : section('', '', html`${emptyState('toolbox', 'Chưa có công cụ nào', hidden ? '' : 'Thả thư mục công cụ vào tools\\ rồi bấm Làm mới.',
      btn('Làm mới', () => reloadCatalog(), { ic: 'refresh' }))}${hiddenNote(hidden)}`)}`;
}
