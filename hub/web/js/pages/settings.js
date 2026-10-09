// Trạm Tool - trang Cài đặt (lưu ở hub\data\settings.json trên máy này).
import { html, nothing } from '../../vendor/lit-html/lit-html.js';
import { api, icon } from '../core.js';
import { S, saveSettings, update } from '../state.js';
import { toast, confirmDialog, applyTheme, showOverlay } from '../ui.js';
import { pageHead, btn } from '../parts.js';
import { reloadCatalog } from '../data.js';
import { refreshJobs, watchJob } from '../jobs.js';

// ------------------------------------------------------------------ cập nhật từ kho git
// S.update: undefined = chưa đọc; { loading } = đang đọc; còn lại là kết quả GET /api/update.
export async function loadUpdate(fetch = false) {
  S.update = { ...(S.update || {}), loading: true, fetching: fetch };
  update();
  try { S.update = await api(`/api/update${fetch ? '?fetch=1' : ''}`); } catch (e) { S.update = { error: e.message }; }
  update();
}

async function runUpdate() {
  const u = S.update || {};
  const ok = await confirmDialog({
    title: 'Cập nhật trạm và công cụ?',
    body: html`<p>Kéo ${u.behind} commit mới từ <span class="mono">${u.upstream}</span> về thư mục trạm (chỉ tiến lên, không gộp). Kết quả, dữ liệu khách trên máy giữ nguyên. Cửa sổ cập nhật hiện danh sách thay đổi và hỏi lại trước khi làm.</p>`,
    confirmLabel: 'Mở cửa sổ cập nhật',
    confirmIcon: 'download',
  });
  if (!ok) return;
  const note = toast('info', 'Đang mở cửa sổ cập nhật...', { ms: 0 });
  try {
    const r = await api('/api/update/run', { method: 'POST' });
    if (r.ok) { watchJob(r.jobId); note.update('success', 'Đã mở cửa sổ cập nhật. Trạm tự đọc lại danh sách công cụ khi cửa sổ đóng.', { ms: 6000 }); }
    else note.update('error', r.message || 'Không mở được cửa sổ cập nhật.', { ms: 12000 });
    refreshJobs();
  } catch (e) { note.update('error', e.message, { ms: 12000 }); }
}

// Cửa sổ cập nhật vừa đóng (jobs.js gọi): đọc lại danh sách công cụ và trạng thái kho.
export function onUpdateFinished() {
  reloadCatalog();
  loadUpdate(false);
}

const dateVi = (iso) => (iso ? new Date(iso).toLocaleDateString('vi-VN') : '');

function updateRow() {
  const u = S.update;
  if (u === undefined) queueMicrotask(() => loadUpdate(false));
  let desc;
  let tone = '';
  if (!u || (u.loading && !u.commit)) desc = u && u.fetching ? 'Đang hỏi kho git...' : 'Đang đọc...';
  else if (u.error) { desc = u.error; tone = 'warn'; }
  else if (!u.repo) desc = u.reason;
  else {
    const here = html`Đang ở <span class="mono">${u.commit}</span> ${u.subject} (${dateVi(u.commitDate)}), nhánh ${u.branch}.`;
    let state = nothing;
    if (u.loading && u.fetching) state = html` Đang hỏi kho git...`;
    else if (u.fetchError) { state = html` Không hỏi được kho: ${u.fetchError}`; tone = 'warn'; }
    else if (u.behind > 0) {
      state = html` <strong>Kho có ${u.behind} commit mới.</strong>${u.reason ? html` ${u.reason}` : nothing}
        <ul class="upd-list">${(u.incoming || []).slice(0, 5).map((c) => html`<li><span class="mono">${c.commit}</span> ${c.subject}</li>`)}${u.behind > 5 ? html`<li>... và ${u.behind - 5} commit nữa</li>` : nothing}</ul>`;
    } else if (u.fetched) state = html` Đã là bản mới nhất${u.ahead ? ` (máy có ${u.ahead} commit chưa đẩy lên kho)` : ''}.`;
    else if (u.reason) state = html` ${u.reason}`;
    else state = html` Bấm Kiểm tra để hỏi kho có bản mới không.`;
    desc = html`${here}${state}`;
  }
  const busy = !!(u && u.loading);
  const can = u && u.repo && u.upstream;
  return setting('download', 'Cập nhật trạm và công cụ', html`<span class=${tone}>${desc}</span>`, html`<div class="btn-row">
    ${can ? btn('Kiểm tra', () => loadUpdate(true), { ic: 'refresh', disabled: busy }) : nothing}
    ${u && u.canUpdate ? btn('Cập nhật', runUpdate, { kind: 'primary', ic: 'download', disabled: busy }) : nothing}</div>`);
}

async function save(patch, msg = 'Đã lưu cài đặt.') {
  try { await saveSettings(patch); applyTheme(); toast('success', msg, { ms: 2000 }); } catch (e) { toast('error', e.message); }
}

async function shutdown() {
  const ok = await confirmDialog({
    title: 'Tắt Trạm Tool?',
    body: html`<p>Máy chủ của trạm sẽ dừng. Công cụ đang chạy trong cửa sổ riêng không bị ảnh hưởng, nhưng trạm sẽ không ghi được kết quả của chúng. Mở lại bằng TramTool.bat.</p>`,
    confirmLabel: 'Tắt trạm',
    confirmIcon: 'power',
  });
  if (!ok) return;
  try {
    await api('/api/shutdown', { method: 'POST' });
    showOverlay('stopped', 'Đã tắt Trạm Tool', 'Có thể đóng cửa sổ này. Mở lại bằng TramTool.bat.');
  } catch (e) { toast('error', e.message); }
}

function setting(ic, title, desc, control) {
  return html`<div class="srow">${icon(ic)}<div><div class="t">${title}</div><div class="d">${desc}</div></div><div>${control}</div></div>`;
}

const group = (title, rows) => html`<section class="settings-group"><h2>${title}</h2><div class="panel">${rows}</div></section>`;

export function settingsPage() {
  const st = S.settings;
  const seg = (v, label) => html`<button aria-pressed=${st.theme === v} @click=${() => save({ theme: v })}>${label}</button>`;
  const browsers = [['auto', 'Tự động (Brave rồi Edge)'], ['brave', 'Brave'], ['edge', 'Microsoft Edge'], ['chrome', 'Google Chrome'], ['default', 'Trình duyệt mặc định']];
  const sw = (on, label, fn) => html`<input type="checkbox" role="switch" class="switch" aria-label=${label} .checked=${on}
    @change=${(e) => { if (!!e.target.checked !== on) fn(!!e.target.checked); }}>`;
  return html`<div class="page">
    ${pageHead('Cài đặt', 'Áp dụng cho trạm trên máy này.')}
    ${group('Giao diện', html`
      ${setting('moon', 'Sáng hoặc tối', 'Theo Windows, hoặc chọn cố định.',
        html`<div class="seg" role="group" aria-label="Giao diện">${seg('system', 'Theo Windows')}${seg('light', 'Sáng')}${seg('dark', 'Tối')}</div>`)}
      ${setting('people', 'Chế độ đơn giản', 'Ẩn công cụ kỹ thuật và phần phân tích, hợp cho nhân viên văn phòng dùng.',
        sw(st.simple, 'Chế độ đơn giản', (v) => save({ simple: v })))}`)}
    ${group('An toàn', setting('shield-check', 'Điểm khôi phục trước khi đổi máy', 'Tạo điểm khôi phục hệ thống (System Restore) trước khi chạy công cụ thay đổi máy bằng quyền Admin. Vẫn bỏ chọn được ở từng lần chạy.',
      sw(st.restorePoint !== false, 'Điểm khôi phục trước khi đổi máy', (v) => save({ restorePoint: v }))))}
    ${group('Máy chủ của trạm', html`
      ${setting('globe', 'Trình duyệt mở trạm', 'Áp dụng từ lần mở sau.',
        html`<select class="inp narrow" aria-label="Trình duyệt mở trạm" @change=${(e) => save({ browser: e.target.value })}>
          ${browsers.map(([v, l]) => html`<option value=${v} ?selected=${st.browser === v}>${l}</option>`)}</select>`)}
      ${setting('power', 'Tự tắt máy chủ trạm', 'Khi đã đóng hết cửa sổ trạm quá số phút này và không còn công cụ nào đang chạy. 0 = không tự tắt.',
        html`<input class="inp num" type="number" min="0" max="1440" aria-label="Số phút" .value=${String(st.autoExitMinutes)}
          @change=${(e) => save({ autoExitMinutes: Number(e.target.value) })}>`)}
      ${setting('tab-desktop', 'Lối tắt trên Desktop', 'Tạo biểu tượng "Trạm Tool" để mở nhanh.',
        btn('Tạo lối tắt', () => api('/api/shortcut', { method: 'POST' }).then((r) => toast('success', `Đã tạo lối tắt: ${r.path}`)).catch((e) => toast('error', e.message))))}`)}
    ${group('Công cụ', html`
      ${updateRow()}
      ${setting('folder', 'Thư mục trạm', html`<span class="mono">${S.hub ? S.hub.root : ''}</span>`,
        btn('Mở thư mục', () => api('/api/open-root', { method: 'POST' }).catch((e) => toast('error', e.message))))}
      ${setting('puzzle', 'Thêm công cụ mới', 'Thả thư mục công cụ (hoặc 1 file .bat/.ps1) vào tools\\ rồi bấm Làm mới. Xem docs\\THEM-CONG-CU.md để viết tool.json.',
        btn('Làm mới', () => reloadCatalog(), { ic: 'refresh' }))}
      ${setting('info', `Trạm Tool ${S.hub ? S.hub.version : ''}`, `${S.tools.length} công cụ trên máy ${S.hub ? S.hub.computer : ''}, mở bằng ${S.hub ? S.hub.browser || 'trình duyệt' : ''}.`,
        btn('Tắt trạm', shutdown, { ic: 'power' }))}`)}
  </div>`;
}
