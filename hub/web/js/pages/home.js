// Trạm Tool - trang Tổng quan: máy này, ô tìm, cần chú ý, đã ghim, dùng gần đây, rồi danh mục công cụ theo nhóm.
import { html, nothing } from '../../vendor/lit-html/lit-html.js';
import { icon, enc, clock, uptimeText, driveName } from '../core.js';
import { S, go, visibleTools, pinnedTools, missingDeps, runState } from '../state.js';
import { section, toolRow, pinRow, runStateText, shortWhen, onRowKey, stop, emptyState, btn } from '../parts.js';
import { runAction } from '../run.js';
import { openPalette } from '../palette.js';
import { loadHistory, loadDepsAll, loadSystem, reloadCatalog } from '../data.js';
import { showResult } from '../result.js';

export function homeLoad() {
  loadHistory();
  loadSystem();
  if (!S.depsLoaded) loadDepsAll();
}

// Những điều nên xử lý: công cụ hỏng hoặc thiếu yêu cầu, ổ đầy, máy bật quá lâu, lần chạy hôm nay báo lỗi, làm
// một phần hoặc tìm thấy lỗi (file kết quả).
function attentionItems() {
  const out = [];
  for (const t of visibleTools()) {
    const to = `#/tool/${enc(t.id)}`;
    if (t.status === 'broken') out.push({ ic: 'dismiss-circle', tone: 'danger', text: `${t.name} đang hỏng.${t.statusNote ? ` ${t.statusNote}` : ''}`, act: 'Xem', to });
    const miss = missingDeps(t);
    if (miss.length) out.push({ ic: 'warning', tone: 'warning', text: `${t.name} còn thiếu: ${miss.map((m) => m.label).join(', ')}.`, act: 'Cài', to });
  }
  const s = S.system;
  if (s && !s.error) {
    for (const d of s.disks || []) {
      if (d.freePct < 12) out.push({ ic: 'hard-drive', tone: 'warning', text: `Ổ ${driveName(d.drive)} chỉ còn ${d.freePct}% trống (${d.free}). Ổ đầy làm máy chậm và Windows Update dễ lỗi.`, act: 'Xem máy', to: '#/system' });
    }
    const days = s.lastBoot ? Math.floor((Date.now() - Date.parse(s.lastBoot)) / 86400000) : 0;
    if (days >= 14) out.push({ ic: 'clock', tone: 'info', text: `Máy đã bật liên tục ${days} ngày. Khởi động lại giúp Windows cài xong bản cập nhật và chạy ổn định hơn.`, act: '', to: '' });
    const sb = s.secureBoot || {};
    if (sb.enabled && sb.ca2023 && sb.ca2023 !== 'Updated') {
      out.push({ ic: 'shield-error', tone: 'warning', text: 'Secure Boot chưa nhận chứng chỉ 2023 của Microsoft (chứng chỉ cũ hết hạn 19/10/2026). Máy vẫn khởi động bình thường; cập nhật Windows và BIOS để nhận bản vá khởi động sau này.', act: 'Xem máy', to: '#/system' });
    }
    if (s.restore && s.restore.enabled === false) {
      out.push({ ic: 'shield-error', tone: 'info', text: `Bảo vệ hệ thống đang tắt: trạm chưa tạo được điểm khôi phục trước khi chạy công cụ sửa máy. ${s.restore.policyOff || s.restore.vssDisabled || s.restore.configLocked ? s.restore.detail : 'Bật ở trang Máy này.'}`, act: 'Xem máy', to: '#/system' });
    }
    if (s.winget && typeof s.winget === 'object' && !s.winget.ok) {
      out.push({ ic: 'download', tone: 'warning', text: `winget chưa dùng được: ${s.winget.problem} Các nút Cài cần winget.`, act: 'Sửa', to: '#/system' });
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
      act: k ? 'Xem' : 'Lịch sử', to: '#/history', run: k ? () => showResult(h.toolId, k.path) : null,
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
    <div class="what"><span class="name">${t.name}</span><span class="sub">${h.actionLabel}</span></div>
    <div class="side">
      ${runStateText(h, { withDur: false })}
      ${a && a.exists && h.state !== 'running' ? html`<button class="icon-btn" title=${h.values ? 'Chạy lại với tham số của lần này' : 'Chạy lại'} aria-label="Chạy lại"
        @click=${stop(() => runAction(t.id, a.id, { values: h.values || null }))}>${icon('arrow-repeat')}</button>` : html`<span class="icon-gap"></span>`}
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

export function homePage() {
  const tools = visibleTools();
  const cats = S.categories.filter((c) => tools.some((t) => t.category === c.id));
  const pins = pinnedTools();
  const att = attentionItems();
  const recent = recentRuns();
  return html`<div class="page">
    <header class="page-head">
      <div><h1>Tổng quan</h1>${machineFacts()}</div>
      <div class="actions">${btn('Làm mới', () => reloadCatalog(), { kind: 'ghost', ic: 'refresh', title: 'Quét lại thư mục tools' })}</div>
    </header>
    <button class="omnibox" @click=${() => openPalette()}>
      ${icon('search')}<span>Tìm hoặc chạy công cụ, vd "wifi", "excel", "ổ cứng"</span><span class="keys"><kbd>Ctrl</kbd><kbd>K</kbd></span>
    </button>
    ${att.length ? section('Cần chú ý', '', html`<div class="notices">${att.map(noticeRow)}</div>`) : nothing}
    ${pins.length || recent.length ? html`<div class="quick">
      ${pins.length ? section('Đã ghim', '', html`<div class="stack">${pins.map(pinRow)}</div>`) : nothing}
      ${recent.length ? section('Dùng gần đây', '', html`<div class="stack">${recent.map(recentRow)}</div>`,
        { tools: btn('Lịch sử', () => go('#/history'), { kind: 'ghost', sm: true }) }) : nothing}
    </div>` : nothing}
    ${tools.length ? html`<section class="catalog">
      <div class="catalog-head"><h2>Tất cả công cụ</h2><span>${tools.length} công cụ, ${cats.length} nhóm</span></div>
      ${cats.map((c) => {
        const list = tools.filter((t) => t.category === c.id);
        return html`<div class="cat" id="cat-${c.id}">
          <div class="cat-head"><h3>${icon(c.icon || 'toolbox')}<span>${c.label}</span><span class="count">${list.length}</span></h3>${c.description ? html`<p>${c.description}</p>` : nothing}</div>
          <div class="cat-list">${list.map(toolRow)}</div>
        </div>`;
      })}
    </section>`
    : section('', '', emptyState('toolbox', 'Chưa có công cụ nào', 'Thả thư mục công cụ vào tools\\ rồi bấm Làm mới.',
      btn('Làm mới', () => reloadCatalog(), { ic: 'refresh' })))}
  </div>`;
}
