// Trạm Tool - thông báo, hộp thoại, lớp phủ mất kết nối, giao diện sáng/tối.
import { html, render, nothing } from '../vendor/lit-html/lit-html.js';
import { setTheme } from '../vendor/fluent-web-components.min.js';
import { webLightTheme, webDarkTheme } from '../vendor/fluent-tokens.min.js';
import { $, icon } from './core.js';
import { S } from './state.js';

// ------------------------------------------------------------------ giao diện sáng/tối
const mq = matchMedia('(prefers-color-scheme: dark)');
export function applyTheme() {
  const dark = S.settings.theme === 'dark' || (S.settings.theme === 'system' && mq.matches);
  setTheme(dark ? webDarkTheme : webLightTheme);
  document.documentElement.dataset.theme = dark ? 'dark' : 'light';
  document.documentElement.style.colorScheme = dark ? 'dark' : 'light';
}
mq.addEventListener('change', () => { if (S.settings.theme === 'system') applyTheme(); });

// ------------------------------------------------------------------ thông báo nhanh
// Tin qua nhanh thì dùng toast; vấn đề cần xử lý thì hiện ngay trên trang (message bar), không dùng toast.
// Trả về { update(intent, text, opts), close() } để cập nhật cùng một thông báo thay vì hiện thêm cái mới.
const TOAST_ICON = { success: 'check-circle', error: 'dismiss-circle', warning: 'warning', info: 'info' };

export function toast(intent, text, { ms = 6000, action = null } = {}) {
  const host = document.createElement('div');
  $('#toasts').append(host);
  let timer = null;
  const close = () => { clearTimeout(timer); host.remove(); };
  const draw = (i, t, a) => render(html`<fluent-message-bar intent=${i} layout="multiline">
      <span slot="icon" class="toast-ic">${icon(TOAST_ICON[i] || 'info', 'ic-16')}</span>
      ${t}
      ${a ? html`<fluent-button slot="actions" size="small" @click=${() => { close(); a.run(); }}>${a.label}</fluent-button>` : nothing}
      <fluent-button slot="dismiss" appearance="transparent" icon-only aria-label="Đóng" @click=${close}>${icon('dismiss', 'ic-16')}</fluent-button>
    </fluent-message-bar>`, host);
  const arm = (m) => { clearTimeout(timer); if (m) timer = setTimeout(close, m); };
  draw(intent, text, action);
  arm(ms);
  return {
    update(i, t, opts = {}) { draw(i, t, opts.action || null); arm(opts.ms ?? 6000); },
    close,
  };
}

// ------------------------------------------------------------------ hộp thoại
// buttons: [{ label, value, appearance, icon, danger }]. Trả về value của nút được bấm, hoặc null khi đóng.
// validate(value): trả về null để đóng; trả về { error, field } để giữ hộp thoại và báo lỗi (field: id ô bị lỗi).
let dlgResolve = null;
export function openDialog({ title, body, buttons, validate = null, wide = false }) {
  const dlg = $('#dlg');
  if (dlgResolve) dlgResolve(null);
  const promise = new Promise((resolve) => {
    dlgResolve = (v) => { dlgResolve = null; resolve(v); };
  });
  const showError = (err) => {
    for (const el of document.querySelectorAll('#dlg-body .field-error')) { el.textContent = ''; el.hidden = true; }
    for (const el of document.querySelectorAll('#dlg-body .invalid')) el.classList.remove('invalid');
    const box = $('#dlg-error');
    box.textContent = err ? err.error : '';
    box.hidden = !err;
    if (!err) return;
    const fieldMsg = err.field && document.getElementById(`err-${err.field}`);
    if (fieldMsg) {
      fieldMsg.textContent = err.error;
      fieldMsg.hidden = false;
      fieldMsg.closest('.field')?.classList.add('invalid');
      box.hidden = true;
      fieldMsg.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
      document.getElementById(`arg-${err.field}`)?.focus?.();
    } else {
      box.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }
  };
  const choose = (b) => {
    if (validate && b.value) {
      const err = validate(b.value);
      if (err) { showError(err); return; }
    }
    if (dlgResolve) dlgResolve(b.value);
    dlg.hide();
  };
  $('#dlg-title').textContent = title;
  dlg.classList.toggle('wide', wide);
  render(html`${body}<div class="form-error" id="dlg-error" role="alert" hidden></div>`, $('#dlg-body'));
  render(html`${buttons.map((b) => html`<fluent-button appearance=${b.appearance || 'secondary'} class=${b.danger ? 'danger' : ''}
      data-primary=${b.appearance === 'primary' ? '1' : nothing} @click=${() => choose(b)}>${b.icon ? icon(b.icon, 'ic-16') : nothing}${b.label}</fluent-button>`)}`,
  $('#dlg-actions'));
  dlg.show();
  return promise;
}

export function initDialog() {
  const dlg = $('#dlg');
  dlg.addEventListener('toggle', () => {
    const open = dlg.dialog && dlg.dialog.open;
    if (!open && dlgResolve) dlgResolve(null);
  });
  // Enter trong ô nhập chữ = bấm nút chính.
  dlg.addEventListener('keydown', (e) => {
    if (e.key !== 'Enter' || e.isComposing) return;
    const t = e.composedPath()[0];
    if (!(t instanceof HTMLInputElement) || t.type === 'checkbox') return;
    const btn = $('#dlg-actions [data-primary]');
    if (btn) { e.preventDefault(); btn.click(); }
  });
}

// Hộp thoại xác nhận: tiêu đề là câu hỏi, nút chính là động từ ("Xoá 3 mục"), "Huỷ" là lựa chọn an toàn.
// ack: câu người dùng phải đánh dấu trước khi làm (dùng cho việc khó hoàn tác).
export function confirmDialog({ title, body, confirmLabel, confirmIcon = '', danger = false, ack = '' }) {
  return openDialog({
    title,
    body: html`${body}${ack ? html`<label class="ack"><input type="checkbox" id="dlg-ack"><span>${ack}</span></label>` : nothing}`,
    buttons: [{ label: confirmLabel, appearance: 'primary', danger, icon: confirmIcon, value: true }, { label: 'Huỷ', value: false }],
    validate: (v) => (v && ack && !$('#dlg-ack')?.checked ? { error: 'Đánh dấu ô xác nhận ở trên trước đã.' } : null),
  });
}

// ------------------------------------------------------------------ lớp phủ khi mất kết nối
let overlayKind = null;
export function showOverlay(kind, title = '', text = '') {
  overlayKind = kind;
  if (kind === 'token') {
    title = 'Hãy mở Trạm Tool bằng TramTool.bat';
    text = 'Trang này thiếu mã thông hành của phiên đang chạy. Bấm đúp file TramTool.bat trong thư mục Tool_Win, trạm sẽ tự mở đúng cửa sổ.';
  } else if (kind === 'offline') {
    title = 'Mất kết nối với Trạm Tool';
    text = 'Có thể cửa sổ máy chủ của trạm đã bị đóng hoặc tự tắt vì để lâu. Mở lại bằng TramTool.bat rồi bấm Thử lại.';
  }
  $('#overlay-title').textContent = title;
  $('#overlay-text').textContent = text;
  $('#overlay').hidden = false;
}
export const overlayShown = () => overlayKind;

window.addEventListener('tram:conn', (e) => {
  if (e.detail === 'offline' && overlayKind !== 'stopped') showOverlay('offline');
  else if (e.detail === 'token') showOverlay('token');
  else if (e.detail === 'ok' && overlayKind === 'offline') { $('#overlay').hidden = true; overlayKind = null; }
});
