// Trạm Tool - trang Cài đặt (lưu ở hub\data\settings.json trên máy này).
import { html } from '../../vendor/lit-html/lit-html.js';
import { api, icon } from '../core.js';
import { S, saveSettings } from '../state.js';
import { toast, confirmDialog, applyTheme, showOverlay } from '../ui.js';
import { reloadCatalog } from '../data.js';

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
  return html`<div class="card setting">${icon(ic)}<div><div class="t">${title}</div><div class="d">${desc}</div></div>${control}</div>`;
}

export function settingsPage() {
  const st = S.settings;
  const seg = (v, label) => html`<button aria-pressed=${st.theme === v} @click=${() => save({ theme: v })}>${label}</button>`;
  const browsers = [['auto', 'Tự động (Brave rồi Edge)'], ['brave', 'Brave'], ['edge', 'Microsoft Edge'], ['chrome', 'Google Chrome'], ['default', 'Trình duyệt mặc định']];
  return html`<div class="page">
    <header class="page-head"><div><h1>Cài đặt</h1><p>Áp dụng cho trạm trên máy này.</p></div></header>
    <div class="stack">
      <div class="group-title">Giao diện</div>
      ${setting('moon', 'Sáng hoặc tối', 'Theo Windows, hoặc chọn cố định.',
        html`<div class="seg" role="group" aria-label="Giao diện">${seg('system', 'Theo Windows')}${seg('light', 'Sáng')}${seg('dark', 'Tối')}</div>`)}
      ${setting('people', 'Chế độ đơn giản', 'Ẩn công cụ kỹ thuật và phần phân tích, hợp cho nhân viên văn phòng dùng.',
        html`<fluent-switch .checked=${st.simple} @change=${(e) => { if (!!e.target.checked !== st.simple) save({ simple: !!e.target.checked }); }}></fluent-switch>`)}
      <div class="group-title">Máy chủ của trạm</div>
      ${setting('globe', 'Trình duyệt mở trạm', 'Áp dụng từ lần mở sau.',
        html`<select class="inp narrow" aria-label="Trình duyệt mở trạm" @change=${(e) => save({ browser: e.target.value })}>
          ${browsers.map(([v, l]) => html`<option value=${v} ?selected=${st.browser === v}>${l}</option>`)}</select>`)}
      ${setting('power', 'Tự tắt máy chủ trạm', 'Khi đã đóng hết cửa sổ trạm quá số phút này và không còn công cụ nào đang chạy. 0 = không tự tắt.',
        html`<input class="inp num" type="number" min="0" max="1440" aria-label="Số phút" .value=${String(st.autoExitMinutes)}
          @change=${(e) => save({ autoExitMinutes: Number(e.target.value) })}>`)}
      ${setting('tab-desktop', 'Lối tắt trên Desktop', 'Tạo biểu tượng "Trạm Tool" để mở nhanh.',
        html`<fluent-button @click=${() => api('/api/shortcut', { method: 'POST' }).then((r) => toast('success', `Đã tạo lối tắt: ${r.path}`)).catch((e) => toast('error', e.message))}>Tạo lối tắt</fluent-button>`)}
      <div class="group-title">Công cụ</div>
      ${setting('folder', 'Thư mục trạm', html`<span class="mono">${S.hub ? S.hub.root : ''}</span>`,
        html`<fluent-button @click=${() => api('/api/open-root', { method: 'POST' }).catch((e) => toast('error', e.message))}>Mở thư mục</fluent-button>`)}
      ${setting('puzzle', 'Thêm công cụ mới', 'Thả thư mục công cụ (hoặc 1 file .bat/.ps1) vào tools\\ rồi bấm Làm mới. Xem docs\\THEM-CONG-CU.md để viết tool.json.',
        html`<fluent-button @click=${() => reloadCatalog()}>${icon('refresh', 'ic-16')}Làm mới</fluent-button>`)}
      ${setting('info', `Trạm Tool ${S.hub ? S.hub.version : ''}`, `${S.tools.length} công cụ trên máy ${S.hub ? S.hub.computer : ''}, mở bằng ${S.hub ? S.hub.browser || 'trình duyệt' : ''}.`,
        html`<fluent-button appearance="outline" @click=${shutdown}>${icon('power', 'ic-16')}Tắt trạm</fluent-button>`)}
    </div>
  </div>`;
}
