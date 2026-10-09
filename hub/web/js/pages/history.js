// Trạm Tool - trang Lịch sử chạy: mỗi lần chạy ra sao (xong, báo lỗi, đã đóng), chạy bao lâu; chạy lại với tham số cũ, xoá.
import { html, nothing } from '../../vendor/lit-html/lit-html.js';
import { api, icon, enc, clock, groupByDay } from '../core.js';
import { S, go, update } from '../state.js';
import { pageHead, emptyState, skeleton, runStateText, badge, btn } from '../parts.js';
import { runAction } from '../run.js';
import { toast, confirmDialog, openDialog } from '../ui.js';
import { loadHistory } from '../data.js';
import { refreshJobs, watchJob } from '../jobs.js';
import { openRestoreUi } from './system.js';

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

// Lý do không tạo được điểm khôi phục (hub\safety\TaoDiemKhoiPhuc.ps1 ghi vào restore-points.jsonl).
const RP_REASON = {
  disabled: 'Bảo vệ hệ thống đang tắt',
  policy: 'chính sách nhóm tắt Bảo vệ hệ thống',
  vss: 'dịch vụ Volume Shadow Copy bị vô hiệu hoá',
  cancelled: 'bạn chọn huỷ nên công cụ không chạy',
  'not-admin': 'cửa sổ không có quyền Admin',
  error: 'Windows báo lỗi',
};

function rpLine(h) {
  if (!h.restorePoint) return nothing;
  const rp = h.rp;
  if (!rp) {
    return h.state === 'running' ? html`<div class="row-note">${icon('shield', 'ic-16')}<span>Đang tạo điểm khôi phục trong cửa sổ công cụ...</span></div>`
      : html`<div class="row-note">${icon('shield', 'ic-16')}<span>Chưa thấy kết quả tạo điểm khôi phục (cửa sổ đóng trước khi tạo xong?).</span></div>`;
  }
  if (rp.created) {
    return html`<div class="row-note ok">${icon('shield-check', 'ic-16')}<span>Điểm khôi phục lúc ${clock(rp.pointAt || rp.at)}.</span>
      <button class="link" @click=${openRestoreUi}>Mở Khôi phục hệ thống</button></div>`;
  }
  const why = RP_REASON[rp.reason] || 'không rõ lý do';
  return html`<div class="row-note warn">${icon('shield-error', 'ic-16')}<span>Không tạo điểm khôi phục: ${why}${rp.message ? ` (${rp.message})` : ''}.</span></div>`;
}

function snapLine(h) {
  if (!h.snapshot) return nothing;
  const n = h.changed;
  const text = n == null ? 'Đã ghi trạng thái trước khi chạy.' : n ? `${n} mục đã khác so với trước khi chạy.` : 'Không mục nào đã ghi bị thay đổi.';
  return html`<div class="row-note">${icon('history', 'ic-16')}<span>${text}</span>
    <button class="link" @click=${() => showChanges(h)}>Xem thay đổi</button></div>`;
}

// Đường dẫn registry dài: cho xuống dòng sau dấu \ thay vì giữa chữ.
const breakPath = (s) => String(s || '').replace(/\\/g, '\\​');

// So trạng thái lúc trước khi chạy với hiện tại; mục đã khác thì trả lại được (cửa sổ Admin, hub\safety\TraLaiTrangThai.ps1).
async function showChanges(h) {
  let r;
  try { r = await api(`/api/snapshot?time=${encodeURIComponent(h.time)}`); } catch (e) { toast('error', e.message); return; }
  const items = r.items || [];
  const changed = items.filter((x) => x.changed);
  const restorable = changed.filter((x) => x.restorable);
  const body = html`<p>So trạng thái lúc ${clock(h.time)}, ngay trước khi chạy "${r.actionLabel}", với bây giờ.</p>
    <div class="panel diff">${items.map((x) => html`<div class="kv">
      <span class="k">${x.label}<small class="mono">${breakPath(x.target)}</small></span>
      <span class="v">${x.changed ? html`${x.before} → ${x.after}` : html`<span class="muted">${x.after}</span>`}${x.note ? html`<small>${x.note}</small>` : nothing}</span>
      <span>${x.changed ? badge('warning', 'Đã đổi') : badge('subtle', 'Như cũ')}</span></div>`)}</div>
    ${restorable.length ? html`<p class="muted note">${icon('shield', 'ic-16')}<span>Trả lại cần quyền Admin: Windows sẽ hỏi UAC, cửa sổ trả lại ghi rõ từng mục.</span></p>` : nothing}`;
  const v = await openDialog({
    title: changed.length ? `${changed.length} mục đã khác trước khi chạy` : 'Không mục nào thay đổi',
    body,
    wide: true,
    buttons: restorable.length
      ? [{ label: 'Đóng', value: false }, { label: `Trả lại ${restorable.length} mục như trước`, appearance: 'primary', icon: 'arrow-repeat', value: 'restore' }]
      : [{ label: 'Đóng', appearance: 'primary', value: false }],
  });
  if (v !== 'restore') return;
  const note = toast('info', 'Đang mở cửa sổ trả lại trạng thái. Windows sẽ hỏi quyền Admin, bấm "Có" để tiếp tục.', { ms: 0 });
  try {
    const res = await api('/api/snapshot/restore', { method: 'POST', body: { time: h.time } });
    if (res.ok) { watchJob(res.jobId); note.update('success', 'Đã mở cửa sổ trả lại trạng thái. Xem kết quả trong cửa sổ đó.', { ms: 6000 }); }
    else if (res.cancelled) note.update('info', 'Đã huỷ: bạn chọn "Không" ở hộp thoại quyền Admin.');
    else note.update('error', res.message || 'Không mở được cửa sổ trả lại trạng thái.', { ms: 12000 });
    refreshJobs();
    loadHistory();
  } catch (e) { note.update('error', e.message, { ms: 12000 }); }
}

function historyRow(h) {
  const t = S.byId.get(h.toolId);
  const a = t && (t.actions || []).find((x) => x.id === h.actionId);
  const vals = valuesText(a, h);
  const args = (h.args || []).filter((x) => !/^--?[A-Za-z]/.test(x));
  return html`<div class="hrow">
    <span class="when">${clock(h.time)}</span>
    <div>
      <div class="hrow-title"><span class="name">${t ? t.name : h.toolName}</span>${runStateText(h)}${h.elevated ? badge('brand', 'Admin', 'shield') : nothing}</div>
      <div class="sub">${h.actionLabel}</div>
      ${vals ? html`<div class="row-args" title=${vals}>${vals}</div>`
        : args.length ? html`<div class="row-args mono" title=${args.join('\n')}>${args.join('   ')}</div>` : nothing}
      ${h.state === 'error' && h.message ? html`<div class="row-args">${h.message}</div>` : nothing}
      ${rpLine(h)}${snapLine(h)}
    </div>
    <div class="side">
      ${a && a.exists && h.state !== 'running' ? btn('Chạy lại', () => runAction(t.id, a.id, { values: h.values || null }),
        { sm: true, ic: 'arrow-repeat', title: h.values ? 'Chạy lại với tham số của lần này' : 'Chạy lại' }) : nothing}
      ${t ? btn('Mở', () => go(`#/tool/${enc(t.id)}`), { kind: 'ghost', sm: true }) : nothing}
      ${h.state !== 'running' ? html`<button class="icon-btn del" title="Xoá dòng này khỏi lịch sử" aria-label="Xoá khỏi lịch sử"
        @click=${() => removeRuns([h.time])}>${icon('dismiss')}</button>` : html`<span class="icon-gap"></span>`}
    </div>
  </div>`;
}

export function historyPage() {
  const all = S.history;
  const actions = all && all.length ? btn('Xoá lịch sử', clearAll, { kind: 'ghost', ic: 'delete' }) : nothing;
  const head = pageHead('Lịch sử chạy', 'Mỗi lần mở công cụ từ trạm trên máy này, kết quả khi cửa sổ đóng và thời gian chạy.', actions);
  if (!all) return html`<div class="page">${head}${skeleton(4, 52)}</div>`;
  if (!all.length) {
    return html`<div class="page">${head}${emptyState('history', 'Chưa chạy công cụ nào', 'Mỗi lần bấm Chạy, trạm ghi lại ở đây để bạn xem kết quả và chạy lại nhanh.',
      btn('Về Tổng quan', () => go('#/')))}</div>`;
  }
  const problems = all.filter(isProblem).length;
  const list = filter === 'problems' ? all.filter(isProblem) : all;
  const setFilter = (f) => { filter = f; update(); };
  return html`<div class="page">
    ${head}
    <div class="tabs" role="group" aria-label="Lọc">
      <button class="tab" aria-pressed=${filter === 'all'} @click=${() => setFilter('all')}>Tất cả<span class="count">${all.length}</span></button>
      <button class="tab" aria-pressed=${filter === 'problems'} ?disabled=${!problems} @click=${() => setFilter('problems')}>Có lỗi<span class="count">${problems}</span></button>
    </div>
    ${list.length ? groupByDay(list, (h) => h.time).map((g) => html`<div class="day"><h2>${g.label}</h2><div class="stack">${g.items.map(historyRow)}</div></div>`)
      : emptyState('check-circle', 'Không có lần chạy nào báo lỗi', '')}
  </div>`;
}
