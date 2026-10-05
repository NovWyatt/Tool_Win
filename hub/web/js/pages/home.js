// Trạm Tool - trang Tổng quan: cần chú ý, đã ghim, dùng gần đây, rồi toàn bộ công cụ theo nhóm.
import { html, nothing } from '../../vendor/lit-html/lit-html.js';
import { icon, enc, timeAgo, clock } from '../core.js';
import { S, go, visibleTools, pinnedTools, missingDeps, runState } from '../state.js';
import { section, pageHead, toolRow, toolTile, runStateBadge, stop, emptyState } from '../parts.js';
import { runAction } from '../run.js';
import { openPalette } from '../palette.js';
import { loadHistory, loadDepsAll, loadSystem, reloadCatalog } from '../data.js';

export function homeLoad() {
  loadHistory();
  loadSystem();
  if (!S.depsLoaded) loadDepsAll();
}

// Những điều nên xử lý: công cụ hỏng hoặc thiếu yêu cầu, ổ đầy, máy bật quá lâu, lần chạy báo lỗi hôm nay.
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
      if (d.freePct < 12) out.push({ ic: 'hard-drive', tone: 'warning', text: `Ổ ${d.drive} chỉ còn ${d.freePct}% trống (${d.free}). Ổ đầy làm máy chậm và Windows Update dễ lỗi.`, act: 'Xem máy', to: '#/system' });
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
    if ((h.state !== 'failed' && h.state !== 'error') || seen.has(h.toolId) || !vis.has(h.toolId)) continue;
    seen.add(h.toolId);
    out.push({ ic: 'dismiss-circle', tone: 'danger', text: `${h.toolName}: "${h.actionLabel}" lúc ${clock(h.time)} ${runState(h).label.toLowerCase()}.`, act: 'Lịch sử', to: '#/history' });
  }
  return out;
}

function attRow(a) {
  return html`<div class="attn-row ${a.tone}">
    ${icon(a.ic)}<span>${a.text}</span>
    ${a.act ? html`<fluent-button size="small" @click=${() => go(a.to)}>${a.act}</fluent-button>` : nothing}
  </div>`;
}

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
  return html`<div class="row clickable compact" role="link" tabindex="0" @click=${() => go(to)}
      @keydown=${(e) => { if (e.key === 'Enter' && e.target === e.currentTarget) go(to); }}>
    <div class="tile">${icon(t.icon || 'toolbox')}</div>
    <div class="row-main">
      <div class="row-title"><span class="name">${t.name}</span>${runStateBadge(h)}</div>
      <div class="row-sub">${h.actionLabel}, ${timeAgo(h.time)}</div>
    </div>
    <div class="row-side">
      ${a && a.exists && h.state !== 'running' ? html`<fluent-button appearance="outline" @click=${stop(() => runAction(t.id, a.id, { values: h.values || null }))}>
        ${icon('arrow-repeat', 'ic-16')}Chạy lại</fluent-button>` : nothing}
      ${icon('chevron-right', 'chev')}
    </div>
  </div>`;
}

export function homePage() {
  const tools = visibleTools();
  const cats = S.categories.filter((c) => tools.some((t) => t.category === c.id));
  const pins = pinnedTools();
  const att = attentionItems();
  const recent = recentRuns();
  return html`<div class="page">
    ${pageHead('Tổng quan', `${tools.length} công cụ trong ${cats.length} nhóm. Bấm vào một công cụ để xem chi tiết, hoặc bấm Chạy để mở ngay.`,
      html`<fluent-button appearance="subtle" title="Quét lại thư mục tools" @click=${() => reloadCatalog()}>${icon('refresh', 'ic-16')}Làm mới</fluent-button>`)}
    <button class="omnibox" @click=${() => openPalette()}>
      ${icon('search')}<span>Tìm hoặc chạy công cụ, vd "wifi", "excel", "ổ cứng"</span><span class="keys"><kbd>Ctrl</kbd><kbd>K</kbd></span>
    </button>
    ${att.length ? section('Cần chú ý', '', html`<div class="card attn">${att.map(attRow)}</div>`) : nothing}
    ${pins.length ? section('Đã ghim', '', html`<div class="tiles">${pins.map(toolTile)}</div>`) : nothing}
    ${recent.length ? section('Dùng gần đây', '', html`<div class="stack">${recent.map(recentRow)}</div>`,
      { tools: html`<fluent-button appearance="subtle" @click=${() => go('#/history')}>Xem lịch sử</fluent-button>` }) : nothing}
    ${tools.length ? cats.map((c) => section(c.label, c.description,
      html`<div class="stack">${tools.filter((t) => t.category === c.id).map(toolRow)}</div>`, { id: `cat-${c.id}` }))
    : emptyState('toolbox', 'Chưa có công cụ nào', 'Thả thư mục công cụ vào tools\\ rồi bấm Làm mới.',
      html`<fluent-button @click=${() => reloadCatalog()}>Làm mới</fluent-button>`)}
  </div>`;
}
