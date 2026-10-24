// Trạm Tool - bấm Chạy: hỏi tham số (nếu có), xác nhận việc thay đổi hệ thống, gọi máy chủ mở cửa sổ công cụ.
import { html, nothing, render } from '../vendor/lit-html/lit-html.js';
import { live } from '../vendor/lit-html/directives/live.js';
import { api, icon, enc } from './core.js';
import { S, update, go, missingFixes } from './state.js';
import { openDialog, toast } from './ui.js';
import { refreshJobs, watchJob } from './jobs.js';
import { loadServer } from './data.js';

// Giá trị form đang nhập; file/thư mục chọn bằng hộp thoại gốc của Windows (máy chủ mở) nên giữ ở đây.
// goiY: danh sách mục có sẵn trên máy cho ô chọn có goiY (tải khi mở form); seq: bỏ kết quả về muộn của form trước.
const form = { toolId: '', actionId: '', picks: {}, goiY: {}, seq: 0 };

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

// Mục có sẵn trên máy (vd bản sao lưu), bấm để chọn thay cho hộp thoại; mới nhất trước.
function suggestList(spec) {
  const g = form.goiY[spec.id];
  if (!g) return nothing;
  if (g.loading) return html`<div class="goiy-msg">Đang tìm trên máy...</div>`;
  if (g.error) return html`<div class="goiy-msg">Không liệt kê được: ${g.error}</div>`;
  const hidden = g.an ? html`<div class="hint">${g.anNhan ? g.anNhan.replace('{n}', g.an) : `Có ${g.an} mục khác không hiện.`}</div>` : nothing;
  if (!g.items.length) return html`<div class="goiy-msg">Không thấy mục nào trên máy này.</div>${hidden}`;
  const cur = (form.picks[spec.id] || [])[0] || '';
  const choose = (p) => { form.picks[spec.id] = [p]; redrawForm(); };
  return html`<div class="goiy" role="radiogroup" aria-labelledby="lbl-${spec.id}">
      ${g.items.map((it) => html`<label class="goiy-item${cur === it.path ? ' on' : ''}" title=${it.path}>
        <input type="radio" name="goiy-${spec.id}" .checked=${live(cur === it.path)} @change=${() => choose(it.path)}>
        <span class="goiy-text"><span class="goiy-title">${it.moTa || it.name}</span>
          <span class="goiy-sub">${it.nhan ? html`<span class="tag">${it.nhan}</span>` : nothing}${it.moTa ? it.name : nothing}</span></span>
      </label>`)}
    </div>
    ${g.tong > g.items.length ? html`<div class="hint">Hiện ${g.items.length} trên ${g.tong} mục, mới nhất trước.</div>` : nothing}${hidden}`;
}

async function loadSuggest(t, a, spec) {
  const seq = form.seq;
  form.goiY[spec.id] = { loading: true };
  let g;
  try {
    const r = await api(`/api/suggest?id=${encodeURIComponent(t.id)}&action=${encodeURIComponent(a.id)}&arg=${encodeURIComponent(spec.id)}`);
    g = { items: r.items || [], tong: r.tong || 0, an: r.an || 0, anNhan: r.anNhan || '' };
  } catch (e) { g = { error: e.message }; }
  if (seq !== form.seq) return;
  form.goiY[spec.id] = g;
  // Chưa có giá trị (lần trước để trống hoặc chạy lần đầu): chọn sẵn mục mới nhất, như công cụ hỏi trong cửa sổ.
  if (g.items && g.items.length && !(form.picks[spec.id] || []).length) form.picks[spec.id] = [g.items[0].path];
  redrawForm();
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
        <button class="btn secondary" @click=${() => pickArg(spec)}>${icon('folder')}Chọn</button>
        ${text ? html`<button class="icon-btn" aria-label="Bỏ chọn" title="Bỏ chọn"
          @click=${() => { form.picks[spec.id] = []; redrawForm(); }}>${icon('dismiss')}</button>` : nothing}
      </div>${spec.goiY ? suggestList(spec) : nothing}${help}${err}</div>`;
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
    ${cur.filled && specs.length ? html`<p class="muted small note">${icon('history', 'ic-16')}<span>Đã điền sẵn giá trị của lần chạy trước.</span></p>` : nothing}
    ${specs.length ? html`<div class="form">${specs.map((s) => field(s, prev))}</div>` : nothing}
    ${risky && a.confirm ? html`<div class="warnbox">${icon('warning', 'ic-16')}<span>${a.confirm}</span></div>` : nothing}
    ${risky && changes.length ? html`<p class="dlg-sub">Công cụ có thể thay đổi:</p><ul>${changes.map((c) => html`<li>${c}</li>`)}</ul>` : nothing}
    ${safetyBlock(cur)}
    ${a.admin ? html`<p class="muted note">${icon('shield', 'ic-16')}<span>Windows sẽ hỏi quyền Admin (UAC). Bấm "Có" để tiếp tục.</span></p>` : nothing}`;
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

// Công cụ còn thiếu yêu cầu bắt buộc: hỏi trước khi chạy vì công cụ gần như chắc chắn báo lỗi. Bỏ qua khi chính
// việc này là cách cài (vd action cai-dat). Trả về true nếu được chạy tiếp.
async function confirmMissing(t, a) {
  const fixes = missingFixes(t);
  if (!fixes.length || fixes.some((f) => f.fix && f.fix.action === a.id)) return true;
  const canFix = fixes.some((f) => f.fix);
  const v = await openDialog({
    title: `${t.name} còn thiếu yêu cầu`,
    body: html`<p>Chạy "${a.label}" lúc này nhiều khả năng sẽ báo lỗi vì máy còn thiếu:</p>
      <ul>${fixes.map((f) => html`<li>${f.labels.join(', ')}</li>`)}</ul>
      <p class="muted">${canFix ? 'Cài xong rồi chạy lại. ' : ''}Biết chắc việc này không cần các thứ trên thì vẫn chạy được.</p>`,
    buttons: [
      { label: 'Huỷ', value: false },
      { label: 'Vẫn chạy', value: 'run' },
      ...(canFix ? [{ label: 'Xem cách cài', appearance: 'primary', icon: 'download', value: 'fix' }] : []),
    ],
  });
  if (v === 'fix') go(`#/tool/${enc(t.id)}`);
  return v === 'run';
}

// Action mở giao diện web (webServer) mà giao diện đó đang chạy: mở lại trang, không hỏi, không mở thêm máy chủ.
async function reopenServer(t, a) {
  let s;
  try { s = ((await api(`/api/server?id=${encodeURIComponent(t.id)}`)).items || {})[a.id]; } catch { return false; }
  if (!s || !s.running) return false;
  try {
    await api('/api/server/open', { method: 'POST', body: { toolId: t.id, actionId: a.id } });
    toast('success', `${t.name}: giao diện đang chạy (cổng ${s.port}), đã mở lại trong trình duyệt.`, { ms: 6000 });
  } catch (e) { toast('error', e.message); }
  return true;
}

export async function runAction(toolId, actionId, { values: given = null } = {}) {
  const t = S.byId.get(toolId);
  const a = t && (t.actions || []).find((x) => x.id === actionId);
  if (!a) return;
  if (a.webServer && await reopenServer(t, a)) return;
  if (!await confirmMissing(t, a)) return;
  const specs = a.args || [];
  const risky = a.risk === 'modifies-system' || !!a.confirm;
  let values = {};
  let rpChoice = null; // null: theo Cài đặt của trạm
  if (specs.length || risky || a.restorePoint) {
    const prev = given || lastValues(toolId, actionId);
    form.toolId = toolId;
    form.actionId = actionId;
    form.picks = {};
    form.goiY = {};
    form.seq++;
    for (const s of specs) {
      if ((s.type === 'file' || s.type === 'folder') && prev && Array.isArray(prev[s.id])) form.picks[s.id] = prev[s.id].slice();
    }
    current = { t, a, prev, rp: S.settings.restorePoint !== false, filled: !!prev };
    for (const s of specs) if (s.goiY) loadSuggest(t, a, s);
    let collected = null;
    const ok = await openDialog({
      title: specs.length ? a.label : `Chạy "${a.label}"?`,
      body: formBody(current),
      wide: specs.length > 2,
      buttons: [
        { label: 'Huỷ', value: false },
        { label: a.admin ? 'Chạy với quyền Admin' : 'Chạy', appearance: 'primary', value: true, icon: a.admin ? 'shield' : 'play' },
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
      if (a.webServer) setTimeout(() => loadServer(t), 3000); // máy chủ ghi file trạng thái sau khi mở cổng
    } else if (r.cancelled) {
      note.update('info', 'Đã huỷ: bạn chọn "Không" ở hộp thoại quyền Admin nên công cụ chưa chạy.');
    } else {
      note.update('error', r.message || 'Không mở được công cụ.', { ms: 12000 });
    }
    refreshJobs();
    api('/api/history').then((h) => { S.history = h.items || []; update(); }).catch(() => {});
  } catch (e) { note.update('error', e.message, { ms: 12000 }); }
}
