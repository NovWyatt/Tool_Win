// Trạm Tool - các khối giao diện dùng chung giữa các trang.
import { html, nothing } from '../vendor/lit-html/lit-html.js';
import { icon, enc, timeAgo, fmtDuration } from './core.js';
import { S, go, isPinned, togglePin, depsStatus, missingDeps, primaryAction, runState, RISK } from './state.js';
import { runAction } from './run.js';
import { toast } from './ui.js';

export const stop = (fn) => (e) => { e.stopPropagation(); e.preventDefault(); fn(e); };

export function section(title, desc, body, { tools = nothing, id = nothing } = {}) {
  return html`<section class="section" id=${id}>
    ${title || desc || tools !== nothing ? html`<div class="section-head">
      <div>${title ? html`<h2>${title}</h2>` : nothing}${desc ? html`<p>${desc}</p>` : nothing}</div>
      ${tools !== nothing ? html`<div class="tools">${tools}</div>` : nothing}
    </div>` : nothing}
    ${body}
  </section>`;
}

export function pageHead(title, desc, actions = nothing) {
  return html`<header class="page-head">
    <div><h1>${title}</h1>${desc ? html`<p>${desc}</p>` : nothing}</div>
    ${actions !== nothing ? html`<div class="actions">${actions}</div>` : nothing}
  </header>`;
}

export function emptyState(ic, title, text, action = nothing) {
  return html`<div class="card empty">${icon(ic)}<strong>${title}</strong>${text ? html`<span>${text}</span>` : nothing}${action}</div>`;
}

export const skeleton = (n = 3, h = 72) => html`${Array.from({ length: n }, () => html`<div class="skeleton" style="height:${h}px"></div>`)}`;

export function badge(color, text, ic = '') {
  return html`<fluent-badge appearance="tint" color=${color} size="medium">${ic ? icon(ic) : nothing}${text}</fluent-badge>`;
}

// Mỗi công cụ chỉ hiện một dấu hiệu, và chỉ khi có điều bất thường; "Chỉ đọc" là mặc định nên không ghi.
export function statusBadge(t) {
  if (t.auto) return badge('subtle', 'Chưa có tool.json');
  if (t.status === 'broken') return badge('danger', 'Đang hỏng');
  if (depsStatus(t) === 'missing') return badge('danger', `Thiếu ${missingDeps(t).length} yêu cầu`);
  if (t.status === 'warning') return badge('warning', 'Cần xem lại');
  const a = primaryAction(t);
  if (a && a.risk === 'modifies-system') return badge('warning', RISK['modifies-system'].label);
  return nothing;
}

export function runStateBadge(h) {
  const st = runState(h);
  const dur = st.dur != null ? ` sau ${fmtDuration(st.dur)}` : '';
  return badge(st.color, `${st.label}${dur}`);
}

// Nút Chạy: action cần Admin có biểu tượng khiên (Windows sẽ hỏi UAC).
export function runButton(t, a, { appearance = '', label = 'Chạy', size = '' } = {}) {
  if (!a) return nothing;
  const app = appearance || (a.risk === 'modifies-system' ? 'outline' : 'primary');
  return html`<fluent-button appearance=${app} size=${size || nothing} ?disabled=${!a.exists}
    title=${a.admin ? `${a.label}. Cần quyền Admin, Windows sẽ hỏi.` : a.label}
    @click=${stop(() => runAction(t.id, a.id))}>${icon(a.admin ? 'shield' : 'play', 'ic-16')}${label}</fluent-button>`;
}

export function pinButton(t) {
  const on = isPinned(t.id);
  return html`<button class="icon-btn${on ? ' on' : ''}" aria-pressed=${on} aria-label=${on ? 'Bỏ ghim' : 'Ghim'}
    title=${on ? 'Bỏ ghim' : 'Ghim lên Tổng quan'} @click=${stop(() => togglePin(t.id).catch((e) => toast('error', e.message)))}>${icon(on ? 'star-filled' : 'star')}</button>`;
}

const onRowKey = (hash) => (e) => {
  if ((e.key === 'Enter' || e.key === ' ') && e.target === e.currentTarget) { e.preventDefault(); go(hash); }
};

export function toolRow(t) {
  const hash = `#/tool/${enc(t.id)}`;
  return html`<div class="row clickable" role="link" tabindex="0" @click=${() => go(hash)} @keydown=${onRowKey(hash)}>
    <div class="tile${t.auto ? ' muted' : ''}">${icon(t.icon || 'toolbox')}</div>
    <div class="row-main">
      <div class="row-title"><span class="name">${t.name}</span>${statusBadge(t)}</div>
      <div class="row-sub">${t.summary}</div>
    </div>
    <div class="row-side">${runButton(t, primaryAction(t))}${pinButton(t)}${icon('chevron-right', 'chev')}</div>
  </div>`;
}

// Thẻ nhỏ cho công cụ đã ghim.
export function toolTile(t) {
  const a = primaryAction(t);
  const hash = `#/tool/${enc(t.id)}`;
  const last = (S.history || []).find((h) => h.toolId === t.id);
  return html`<div class="card tile-card clickable" role="link" tabindex="0" @click=${() => go(hash)} @keydown=${onRowKey(hash)}>
    <div class="tile-card-top"><div class="tile">${icon(t.icon || 'toolbox')}</div>${pinButton(t)}</div>
    <div class="tile-card-name">${t.name}</div>
    <div class="tile-card-sub">${last ? `Chạy ${timeAgo(last.time)}` : t.summary}</div>
    <div class="tile-card-bar">${runButton(t, a, { size: 'small' })}${statusBadge(t)}</div>
  </div>`;
}

export function fileIcon(f) {
  if (f.isFolder) return 'folder';
  if (/\.(docx?|txt|md|log)$/i.test(f.name)) return 'document-text';
  if (/\.pdf$/i.test(f.name)) return 'pdf';
  if (/\.(sql|gz)$/i.test(f.name)) return 'database';
  if (/\.(json|csv|xlsx?)$/i.test(f.name)) return 'table';
  if (/\.html?$/i.test(f.name)) return 'globe';
  return 'document';
}
