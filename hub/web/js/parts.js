// Trạm Tool - các khối giao diện dùng chung giữa các trang.
import { html, nothing } from '../vendor/lit-html/lit-html.js';
import { icon, enc, clock, dayKey, fmtDuration } from './core.js';
import { go, isPinned, togglePin, depsStatus, missingDeps, primaryAction, runState, catLabel } from './state.js';
import { runAction } from './run.js';
import { toast } from './ui.js';

export const stop = (fn) => (e) => { e.stopPropagation(); e.preventDefault(); fn(e); };

// Nút: kind = primary (một nút chính mỗi vùng) | secondary | ghost | danger.
export function btn(label, onClick, { kind = 'secondary', ic = '', sm = false, title = '', disabled = false, pressed = null } = {}) {
  return html`<button class="btn ${kind}${sm ? ' sm' : ''}" title=${title || nothing} ?disabled=${disabled}
    aria-pressed=${pressed == null ? nothing : String(pressed)} @click=${onClick}>${ic ? icon(ic) : nothing}${label}</button>`;
}

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
  return html`<div class="empty">${icon(ic)}<strong>${title}</strong>${text ? html`<span>${text}</span>` : nothing}${action}</div>`;
}

export const skeleton = (n = 3, h = 64) => html`<div class="stack">${Array.from({ length: n }, () => html`<div class="skeleton" style="height:${h}px"></div>`)}</div>`;

// Nhãn trạng thái. color theo cách gọi cũ (danger, warning, success, brand, informative, subtle).
const TAG = { danger: 'danger', warning: 'warn', success: 'ok', brand: 'accent', informative: 'accent' };
export function badge(color, text, ic = '') {
  return html`<span class="tag ${TAG[color] || ''}">${ic ? icon(ic) : nothing}${text}</span>`;
}

// Mỗi công cụ chỉ hiện một dấu hiệu, và chỉ khi có điều cần làm. Mức rủi ro thuộc về từng việc nên ghi ở trang
// công cụ, không ghi ở danh mục (một công cụ có cả việc chỉ xem lẫn việc đổi máy).
export function statusBadge(t) {
  if (t.manifestBroken) return badge('danger', 'tool.json bị lỗi');
  if (t.auto) return badge('subtle', 'Chưa có tool.json');
  if (t.status === 'broken') return badge('danger', 'Đang hỏng');
  if (depsStatus(t) === 'missing') return badge('danger', `Cần cài ${missingDeps(t).length} thứ`);
  if (t.status === 'warning') return badge('warning', 'Cần xem lại');
  return nothing;
}

// Kết quả một lần chạy: chữ kèm biểu tượng, không đóng khung.
export function runStateText(h, { withDur = true } = {}) {
  const st = runState(h);
  const dur = withDur && st.dur != null ? ` sau ${fmtDuration(st.dur)}` : '';
  return html`<span class="state ${st.color}">${h.state === 'running' ? html`<span class="live-mark" aria-hidden="true"></span>` : icon(st.icon)}${st.label}${dur}</span>`;
}

// Giờ ngắn cho cột thời gian: hôm nay "14:05", hôm qua, còn lại "07/10".
export function shortWhen(iso) {
  const k = dayKey(iso);
  const now = new Date();
  if (k === dayKey(now.toISOString())) return clock(iso);
  if (k === dayKey(new Date(now.getTime() - 86400000).toISOString())) return 'Hôm qua';
  const d = new Date(iso);
  return `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}`;
}

// Nút Chạy: action cần Admin có biểu tượng khiên (Windows sẽ hỏi UAC).
export function runButton(t, a, { kind = 'secondary', label = 'Chạy', sm = false } = {}) {
  if (!a) return nothing;
  return btn(label, stop(() => runAction(t.id, a.id)), {
    kind, sm, ic: a.admin ? 'shield' : 'play', disabled: !a.exists,
    title: a.admin ? `${a.label}. Cần quyền Admin, Windows sẽ hỏi.` : a.label,
  });
}

export function pinButton(t) {
  const on = isPinned(t.id);
  return html`<button class="icon-btn${on ? ' on' : ''}" aria-pressed=${on} aria-label=${on ? 'Bỏ ghim' : 'Ghim'}
    title=${on ? 'Bỏ ghim' : 'Ghim lên Tổng quan'} @click=${stop(() => togglePin(t.id).catch((e) => toast('error', e.message)))}>${icon(on ? 'star-filled' : 'star')}</button>`;
}

export const onRowKey = (hash) => (e) => {
  if ((e.key === 'Enter' || e.key === ' ') && e.target === e.currentTarget) { e.preventDefault(); go(hash); }
};

// Một dòng trong danh mục: cả dòng là một liên kết mở trang công cụ (ở đó mới chọn việc để chạy, vì phần lớn
// công cụ có nhiều việc). Ghim hiện khi rê chuột; mũi tên cho biết dòng bấm được.
export function toolRow(t, { cat = false } = {}) {
  const hash = `#/tool/${enc(t.id)}`;
  return html`<div class="trow" role="link" tabindex="0" aria-label=${t.name} @click=${() => go(hash)} @keydown=${onRowKey(hash)}>
    ${icon(t.icon || 'toolbox')}
    <div>
      <div class="trow-title"><span class="name">${t.name}</span>${statusBadge(t)}</div>
      <div class="trow-sub">${cat ? html`<span class="trow-cat">${catLabel(t.category)}</span>` : nothing}${t.summary}</div>
    </div>
    <div class="trow-side">${pinButton(t)}<span class="trow-go" aria-hidden="true">${icon('chevron-right')}</span></div>
  </div>`;
}

// Công cụ đã ghim: tên, việc chính (chính là việc nút Chạy sẽ làm), nút Chạy.
export function pinRow(t) {
  const hash = `#/tool/${enc(t.id)}`;
  const a = primaryAction(t);
  return html`<div class="pin" role="link" tabindex="0" aria-label=${t.name} @click=${() => go(hash)} @keydown=${onRowKey(hash)}>
    ${icon(t.icon || 'toolbox')}
    <div class="what"><span class="name">${t.name}</span><span class="sub">${a ? a.label : t.summary}</span></div>
    <div class="side">${runButton(t, a, { sm: true })}</div>
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
