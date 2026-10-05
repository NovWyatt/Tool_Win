// Trạm Tool - bấm Chạy: hỏi tham số (nếu có), xác nhận việc thay đổi hệ thống, gọi máy chủ mở cửa sổ công cụ.
import { html, nothing, render } from '../vendor/lit-html/lit-html.js';
import { live } from '../vendor/lit-html/directives/live.js';
import { api, icon } from './core.js';
import { S, update } from './state.js';
import { openDialog, toast } from './ui.js';
import { refreshJobs, watchJob } from './jobs.js';

// Giá trị form đang nhập; file/thư mục chọn bằng hộp thoại gốc của Windows (máy chủ mở) nên giữ ở đây.
const form = { toolId: '', actionId: '', picks: {} };

// Giá trị lần chạy trước của chính action này (lưu trong lịch sử) để điền sẵn.
function lastValues(toolId, actionId) {
  const h = (S.history || []).find((x) => x.toolId === toolId && x.actionId === actionId && x.values);
  return h ? h.values : null;
}

function pickText(spec) {
  const v = form.picks[spec.id] || [];
  if (!v.length) return '';
  return v.length > 1 ? `${v.length} mục: ${v.join('; ')}` : v[0];
}

// Công tắc đang bật: theo giá trị đã có (lần trước, hoặc đọc lại khi vẽ lại form), không có thì theo mặc định.
const boolOn = (spec, prev) => (prev && prev[spec.id] != null ? prev[spec.id] === true || prev[spec.id] === 'true' : spec.default === true);

function field(spec, prev) {
  const id = `arg-${spec.id}`;
  const req = spec.required ? html`<span class="req" aria-hidden="true">*</span>` : nothing;
  const help = spec.help ? html`<div class="hint">${spec.help}</div>` : nothing;
  const err = html`<div class="field-error" id="err-${spec.id}" role="alert" hidden></div>`;
  const has = prev && prev[spec.id] != null;
  const def = has ? prev[spec.id] : spec.default;
  if (spec.type === 'file' || spec.type === 'folder') {
    const empty = spec.type === 'folder' ? 'Chưa chọn thư mục' : spec.multiple ? 'Chưa chọn file nào' : 'Chưa chọn file';
    const text = pickText(spec);
    return html`<div class="field"><span class="field-label" id="lbl-${spec.id}">${spec.label}${req}</span>
      <div class="pick">
        <div class="pick-value${text ? ' set' : ''}" id=${id} aria-labelledby="lbl-${spec.id}">${text || empty}</div>
        <fluent-button @click=${() => pickArg(spec)}>${icon('folder', 'ic-16')}Chọn</fluent-button>
        ${text ? html`<fluent-button appearance="subtle" icon-only aria-label="Bỏ chọn" title="Bỏ chọn"
          @click=${() => { form.picks[spec.id] = []; redrawForm(); }}>${icon('dismiss', 'ic-16')}</fluent-button>` : nothing}
      </div>${help}${err}</div>`;
  }
  if (spec.type === 'bool') {
    // Công tắc chạy thử: vẽ lại để ô điểm khôi phục theo kịp.
    return html`<div class="field"><label class="check"><input type="checkbox" id=${id} ?checked=${boolOn(spec, prev)}
      @change=${spec.dryRun ? () => redrawForm() : nothing}><span>${spec.label}</span></label>${help}${err}</div>`;
  }
  if (spec.type === 'choice') {
    const cur = def == null ? (spec.options[0] || {}).value : String(def);
    return html`<div class="field"><label class="field-label" for=${id}>${spec.label}${req}</label>
      <select class="inp" id=${id}>${spec.options.map((o) => html`<option value=${o.value} ?selected=${o.value === cur}>${o.label}</option>`)}</select>${help}${err}</div>`;
  }
  const num = spec.type === 'number';
  return html`<div class="field"><label class="field-label" for=${id}>${spec.label}${req}</label>
    <input class="inp" id=${id} type=${num ? 'number' : 'text'} min=${num && spec.min != null ? spec.min : nothing}
      max=${num && spec.max != null ? spec.max : nothing} .value=${live(def == null ? '' : String(def))}
      placeholder=${spec.placeholder || nothing} autocomplete="off" spellcheck="false">${help}${err}</div>`;
}

function collectValues(specs) {
  const values = {};
  for (const s of specs) {
    const el = document.getElementById(`arg-${s.id}`);
    let v;
    if (s.type === 'file' || s.type === 'folder') v = form.picks[s.id] || [];
    else if (s.type === 'bool') v = !!(el && el.checked);
    else v = el ? String(el.value).trim() : '';
    const empty = Array.isArray(v) ? !v.length : v === '' || v === false;
    const fail = (error) => ({ error, field: s.id });
    if (s.required && empty) return fail(`Chưa ${s.type === 'file' || s.type === 'folder' ? 'chọn' : 'nhập'} "${s.label}".`);
    if (s.type === 'number' && v !== '') {
      const n = Number(v);
      if (!Number.isInteger(n)) return fail(`"${s.label}" phải là số nguyên.`);
      if (s.min != null && n < s.min) return fail(`"${s.label}" nhỏ nhất là ${s.min}.`);
      if (s.max != null && n > s.max) return fail(`"${s.label}" lớn nhất là ${s.max}.`);
    }
    if (s.type === 'text' && /[%"!^]/.test(v)) return fail(`"${s.label}" không được chứa các ký tự % " ! ^.`);
    values[s.id] = v;
  }
  return { values };
}

// Mục trạng thái (dịch vụ, registry HKLM) công cụ khai báo: trạm ghi lại trước khi chạy action đổi máy.
const snapItems = (t) => (t.probes || []).filter((p) => p.snapshot !== false
  && (p.type === 'service' || (p.type === 'registry' && /^HKLM:\\/i.test(p.path || ''))));

// Lan can an toàn: điểm khôi phục hệ thống (action đổi máy có quyền Admin) và ghi trạng thái trước khi chạy.
// Chọn chạy thử thì máy chủ không làm cả hai, nên ô điểm khôi phục mờ đi.
function safetyBlock({ t, a, prev, rp }) {
  const snap = a.risk !== 'read-only' ? snapItems(t).length : 0;
  const dryOn = (a.args || []).some((s) => s.dryRun && boolOn(s, prev));
  if (!a.restorePoint && (!snap || dryOn)) return nothing;
  return html`<div class="safety">
    ${a.restorePoint ? html`<label class="check${dryOn ? ' off' : ''}"><input type="checkbox" id="opt-rp" ?checked=${rp && !dryOn} ?disabled=${dryOn}>
        <span>Tạo điểm khôi phục hệ thống trước khi chạy</span></label>
      <div class="hint">${dryOn ? 'Đang chọn chạy thử, máy không bị thay đổi nên không tạo điểm khôi phục.'
        : 'Máy lỗi sau khi chạy thì dùng Khôi phục hệ thống của Windows để quay lại điểm này. Thường mất từ nửa phút đến vài phút.'}</div>` : nothing}
    ${snap && !dryOn ? html`<p class="muted small note">${icon('history', 'ic-16')}<span>Trạm ghi lại ${snap} mục (dịch vụ, registry) trước khi chạy, để xem thay đổi và trả lại được ở trang Lịch sử.</span></p>` : nothing}
  </div>`;
}

let current = null; // { t, a, prev, rp, filled } của form đang mở, để vẽ lại khi chọn file hoặc bật chạy thử
function formBody(cur) {
  const { a, prev } = cur;
  const specs = a.args || [];
  const risky = a.risk === 'modifies-system' || !!a.confirm;
  const changes = a.changes || [];
  return html`
    ${a.description ? html`<p class=${specs.length ? 'muted' : ''}>${a.description}</p>` : nothing}
    ${cur.filled && specs.length ? html`<p class="muted small">${icon('history', 'ic-16')} Đã điền sẵn giá trị của lần chạy trước.</p>` : nothing}
    ${specs.length ? html`<div class="form">${specs.map((s) => field(s, prev))}</div>` : nothing}
    ${risky && a.confirm ? html`<div class="warnbox">${icon('warning', 'ic-16')}<span>${a.confirm}</span></div>` : nothing}
    ${risky && changes.length ? html`<p class="dlg-sub">Công cụ có thể thay đổi:</p><ul>${changes.map((c) => html`<li>${c}</li>`)}</ul>` : nothing}
    ${safetyBlock(cur)}
    ${a.admin ? html`<p class="muted note">${icon('shield', 'ic-16')} Windows sẽ hỏi quyền Admin (UAC). Bấm "Có" để tiếp tục.</p>` : nothing}`;
}

function redrawForm() {
  if (!current) return;
  // Giữ chữ đang gõ: đọc lại các ô trước khi vẽ lại.
  const specs = current.a.args || [];
  const snap = { ...(current.prev || {}) };
  for (const s of specs) {
    const el = document.getElementById(`arg-${s.id}`);
    if (!el || s.type === 'file' || s.type === 'folder') continue;
    snap[s.id] = s.type === 'bool' ? el.checked : el.value;
  }
  current.prev = snap;
  const rpEl = document.getElementById('opt-rp');
  if (rpEl && !rpEl.disabled) current.rp = rpEl.checked;
  const body = document.getElementById('dlg-body');
  if (body) render(html`${formBody(current)}<div class="form-error" id="dlg-error" role="alert" hidden></div>`, body);
}

async function pickArg(spec) {
  const t = S.byId.get(form.toolId);
  const a = t && (t.actions || []).find((x) => x.id === form.actionId);
  if (!a) return;
  const note = toast('info', 'Đang mở hộp thoại chọn của Windows. Nếu không thấy, nhìn thanh tác vụ.', { ms: 4000 });
  try {
    const r = await api('/api/pick', { method: 'POST', body: { toolId: t.id, actionId: a.id, argId: spec.id } });
    note.close();
    const paths = r.paths || [];
    if (!paths.length) return;
    form.picks[spec.id] = spec.multiple ? paths : [paths[0]];
    redrawForm();
  } catch (e) { note.update('error', e.message); }
}

export async function runAction(toolId, actionId, { values: given = null } = {}) {
  const t = S.byId.get(toolId);
  const a = t && (t.actions || []).find((x) => x.id === actionId);
  if (!a) return;
  const specs = a.args || [];
  const risky = a.risk === 'modifies-system' || !!a.confirm;
  let values = {};
  let rpChoice = null; // null: theo Cài đặt của trạm
  if (specs.length || risky || a.restorePoint) {
    const prev = given || lastValues(toolId, actionId);
    form.toolId = toolId;
    form.actionId = actionId;
    form.picks = {};
    for (const s of specs) {
      if ((s.type === 'file' || s.type === 'folder') && prev && Array.isArray(prev[s.id])) form.picks[s.id] = prev[s.id].slice();
    }
    current = { t, a, prev, rp: S.settings.restorePoint !== false, filled: !!prev };
    let collected = null;
    const ok = await openDialog({
      title: specs.length ? a.label : `Chạy "${a.label}"?`,
      body: formBody(current),
      wide: specs.length > 2,
      buttons: [
        { label: a.admin ? 'Chạy với quyền Admin' : 'Chạy', appearance: 'primary', value: true, icon: a.admin ? 'shield' : 'play' },
        { label: 'Huỷ', value: false },
      ],
      validate: () => {
        const r = collectValues(specs);
        if (r.error) return r;
        collected = r.values;
        const rpEl = document.getElementById('opt-rp');
        if (rpEl) rpChoice = rpEl.checked;
        return null;
      },
    });
    current = null;
    if (!ok) return;
    values = collected || {};
  }
  // Máy chủ trả lời sau khi cửa sổ công cụ hiện lên (hoặc sau khi bạn trả lời hộp thoại UAC): báo ngay là đang mở.
  const note = toast('info', a.admin ? `Đang mở ${t.name}. Windows sẽ hỏi quyền Admin, bấm "Có" để tiếp tục.` : `Đang mở ${t.name}...`, { ms: 0 });
  try {
    const body = { toolId, actionId, values };
    if (rpChoice !== null) body.restorePoint = rpChoice;
    const r = await api('/api/run', { method: 'POST', body });
    if (r.ok) {
      watchJob(r.jobId);
      note.update('success', r.jobId ? `Đã mở ${t.name}. Theo dõi ở thanh Đang chạy phía dưới.` : r.message, { ms: 5000 });
    } else if (r.cancelled) {
      note.update('info', 'Đã huỷ: bạn chọn "Không" ở hộp thoại quyền Admin nên công cụ chưa chạy.');
    } else {
      note.update('error', r.message || 'Không mở được công cụ.', { ms: 12000 });
    }
    refreshJobs();
    api('/api/history').then((h) => { S.history = h.items || []; update(); }).catch(() => {});
  } catch (e) { note.update('error', e.message, { ms: 12000 }); }
}
