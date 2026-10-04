// Trạm Tool - trang Lịch sử chạy: mỗi lần chạy ra sao (xong, báo lỗi, đã đóng), chạy bao lâu; chạy lại với tham số cũ, xoá.
import { html, nothing } from '../../vendor/lit-html/lit-html.js';
import { api, icon, enc, clock, groupByDay } from '../core.js';
import { S, go, update } from '../state.js';
import { section, pageHead, emptyState, skeleton, runStateBadge, badge } from '../parts.js';
import { runAction } from '../run.js';
import { toast, confirmDialog } from '../ui.js';
import { loadHistory } from '../data.js';

let filter = 'all'; // all | problems

export function historyLoad() { loadHistory(); }

const isProblem = (h) => h.state === 'failed' || h.state === 'error';

async function removeRuns(times) {
  try {
    await api('/api/history/delete', { method: 'POST', body: { times } });
    S.history = (S.history || []).filter((h) => !times.includes(h.time));
    update();
  } catch (e) { toast('error', e.message); }
}

async function clearAll() {
  const n = (S.history || []).length;
  const ok = await confirmDialog({
    title: 'Xoá toàn bộ lịch sử chạy?',
    body: html`<p>Xoá ${n} lần chạy đã ghi trên máy này. Mục "Dùng gần đây" và giá trị điền sẵn của lần chạy trước cũng mất theo.</p>
      <p class="muted note">${icon('info', 'ic-16')} Chỉ xoá nhật ký của trạm; file kết quả của công cụ vẫn giữ nguyên.</p>`,
    confirmLabel: 'Xoá lịch sử',
    confirmIcon: 'delete',
    danger: true,
  });
  if (!ok) return;
  try {
    const r = await api('/api/history/delete', { method: 'POST', body: { all: true } });
    S.history = [];
    update();
    toast('success', `Đã xoá ${r.removed} lần chạy khỏi lịch sử.`, { ms: 4000 });
  } catch (e) { toast('error', e.message); }
}

// Tham số đã nhập, theo nhãn của form. Lần chạy cũ chưa ghi giá trị thì hiện tham số dòng lệnh.
function valuesText(a, h) {
  const specs = (a && a.args) || [];
  if (!h.values || !specs.length) return '';
  const filled = (v) => v != null && v !== '' && !(Array.isArray(v) && !v.length);
  return specs.filter((s) => filled(h.values[s.id])).map((s) => {
    const v = h.values[s.id];
    if (s.type === 'bool') return `${s.label}: ${v === true || v === 'true' ? 'có' : 'không'}`;
    if (s.type === 'choice') {
      const o = (s.options || []).find((x) => String(x.value) === String(v));
      return `${s.label}: ${o ? o.label : v}`;
    }
    if (Array.isArray(v)) return `${s.label}: ${v.length > 1 ? `${v.length} mục` : v[0]}`;
    return `${s.label}: ${v}`;
  }).join(', ');
}

function historyRow(h) {
  const t = S.byId.get(h.toolId);
  const a = t && (t.actions || []).find((x) => x.id === h.actionId);
  const vals = valuesText(a, h);
  const args = (h.args || []).filter((x) => !/^--?[A-Za-z]/.test(x));
  return html`<div class="row hist-row">
    <div class="tile muted">${icon(t ? t.icon || 'toolbox' : 'toolbox')}</div>
    <div class="row-main">
      <div class="row-title"><span class="name">${t ? t.name : h.toolName}</span>${runStateBadge(h)}${h.elevated ? badge('brand', 'Admin', 'shield') : nothing}</div>
      <div class="row-sub">${clock(h.time)} · ${h.actionLabel}</div>
      ${vals ? html`<div class="row-args" title=${vals}>${vals}</div>`
        : args.length ? html`<div class="row-args mono" title=${args.join('\n')}>${args.join('   ')}</div>` : nothing}
      ${h.state === 'error' && h.message ? html`<div class="row-args">${h.message}</div>` : nothing}
    </div>
    <div class="row-side">
      ${a && a.exists && h.state !== 'running' ? html`<fluent-button appearance="outline" title=${h.values ? 'Chạy lại với tham số của lần này' : 'Chạy lại'}
        @click=${() => runAction(t.id, a.id, { values: h.values || null })}>${icon('arrow-repeat', 'ic-16')}Chạy lại</fluent-button>` : nothing}
      ${t ? html`<fluent-button appearance="subtle" @click=${() => go(`#/tool/${enc(t.id)}`)}>Mở</fluent-button>` : nothing}
      ${h.state !== 'running' ? html`<button class="icon-btn del" title="Xoá dòng này khỏi lịch sử" aria-label="Xoá khỏi lịch sử"
        @click=${() => removeRuns([h.time])}>${icon('dismiss')}</button>` : html`<span class="icon-gap"></span>`}
    </div>
  </div>`;
}

export function historyPage() {
  const all = S.history;
  const actions = all && all.length ? html`<fluent-button appearance="subtle" @click=${clearAll}>${icon('delete', 'ic-16')}Xoá lịch sử</fluent-button>` : nothing;
  const head = pageHead('Lịch sử chạy', 'Mỗi lần mở công cụ từ trạm trên máy này, kết quả khi cửa sổ đóng và thời gian chạy.', actions);
  if (!all) return html`<div class="page">${head}<div class="stack">${skeleton(4, 64)}</div></div>`;
  if (!all.length) {
    return html`<div class="page">${head}${emptyState('history', 'Chưa chạy công cụ nào', 'Mỗi lần bấm Chạy, trạm ghi lại ở đây để bạn xem kết quả và chạy lại nhanh.',
      html`<fluent-button @click=${() => go('#/')}>Về Tổng quan</fluent-button>`)}</div>`;
  }
  const problems = all.filter(isProblem).length;
  const list = filter === 'problems' ? all.filter(isProblem) : all;
  const setFilter = (f) => { filter = f; update(); };
  return html`<div class="page">
    ${head}
    <div class="filters" role="group" aria-label="Lọc">
      <button class="filter" aria-pressed=${filter === 'all'} @click=${() => setFilter('all')}>Tất cả<span class="count">${all.length}</span></button>
      <button class="filter" aria-pressed=${filter === 'problems'} ?disabled=${!problems} @click=${() => setFilter('problems')}>Có lỗi<span class="count">${problems}</span></button>
    </div>
    ${list.length ? groupByDay(list, (h) => h.time).map((g) => section(g.label, '', html`<div class="stack">${g.items.map(historyRow)}</div>`))
      : emptyState('check-circle', 'Không có lần chạy nào báo lỗi', '')}
  </div>`;
}
