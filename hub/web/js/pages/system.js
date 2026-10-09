// Trạm Tool - trang Máy này: tóm tắt nhanh (chỉ đọc) theo nhóm, và yêu cầu của các công cụ.
import { html, nothing } from '../../vendor/lit-html/lit-html.js';
import { api, icon, enc, uptimeText, driveName } from '../core.js';
import { S, go, visibleTools } from '../state.js';
import { section, pageHead, emptyState, badge, skeleton, btn, onRowKey } from '../parts.js';
import { toast } from '../ui.js';
import { loadSystem, loadDepsAll } from '../data.js';
import { refreshJobs, watchJob } from '../jobs.js';

export function systemLoad() {
  loadSystem();
  loadDepsAll();
}

// Một ô thông tin: nhãn nhỏ, giá trị, ghi chú; meter = phần trăm đã dùng (vẽ thanh mảnh).
function spec(ic, label, value, { note = '', warn = false, act = nothing, meter = null } = {}) {
  return html`<div class="spec${warn ? ' warn' : ''}">
    <dt>${icon(ic)}${label}</dt>
    <dd>${value}</dd>
    ${meter != null ? html`<div class="meter" role="img" aria-label="Đã dùng ${Math.round(meter)}%"><span style="width:${Math.max(0, Math.min(100, meter))}%"></span></div>` : nothing}
    ${note ? html`<span class="note">${note}</span>` : nothing}
    ${act !== nothing ? html`<span class="act">${act}</span>` : nothing}
  </div>`;
}

// Mở cửa sổ sửa (script của trạm); cửa sổ Admin thì Windows hỏi UAC.
async function launchFix(path, opening, done) {
  const note = toast('info', opening, { ms: 0 });
  try {
    const r = await api(path, { method: 'POST' });
    if (r.ok) { watchJob(r.jobId); note.update('success', done, { ms: 6000 }); }
    else if (r.cancelled) note.update('info', 'Đã huỷ: bạn chọn "Không" ở hộp thoại quyền Admin.');
    else note.update('error', r.message || 'Không mở được cửa sổ sửa.', { ms: 12000 });
    refreshJobs();
  } catch (e) { note.update('error', e.message, { ms: 12000 }); }
}

export async function openRestoreUi() {
  try { await api('/api/restore-ui', { method: 'POST' }); toast('info', 'Đã mở Khôi phục hệ thống của Windows (cần quyền Admin).', { ms: 5000 }); } catch (e) { toast('error', e.message); }
}

function restoreSpec(r) {
  if (!r) return nothing;
  if (r.enabled) {
    return spec('shield-check', 'Bảo vệ hệ thống', 'Đang bật', {
      note: 'Trạm tạo điểm khôi phục trước khi chạy công cụ đổi máy.',
      act: btn('Mở Khôi phục hệ thống', openRestoreUi, { sm: true }),
    });
  }
  if (r.enabled === false) {
    const canFix = !r.policyOff && !r.vssDisabled && !r.configLocked;
    return spec('shield-error', 'Bảo vệ hệ thống', 'Đang tắt', {
      note: canFix ? 'Chưa có điểm khôi phục để quay lại nếu công cụ làm hỏng máy.' : r.detail,
      warn: true,
      act: canFix ? btn('Bật Bảo vệ hệ thống', () => launchFix('/api/restore/enable', 'Đang mở cửa sổ bật Bảo vệ hệ thống. Windows sẽ hỏi quyền Admin.', 'Đã mở cửa sổ bật Bảo vệ hệ thống. Xong bấm Đọc lại.'), { sm: true, ic: 'shield' }) : nothing,
    });
  }
  return spec('shield', 'Bảo vệ hệ thống', 'Không đọc được', { note: r.detail || '' });
}

function wingetSpec(w) {
  if (!w || typeof w !== 'object') return spec('download', 'winget', 'Không rõ', { note: 'Dùng để cài phần mềm còn thiếu.' });
  if (w.ok) return spec('download', 'winget', `Dùng được, ${w.version}`, { note: 'Dùng để cài phần mềm còn thiếu (nút Cài).' });
  return spec('download', 'winget', 'Chưa dùng được', {
    note: `${w.problem} Các nút Cài cần winget.`, warn: true,
    act: btn('Sửa winget', () => launchFix('/api/winget/fix', 'Đang mở cửa sổ sửa winget...', 'Đã mở cửa sổ sửa winget. Xong bấm Đọc lại.'), { sm: true }),
  });
}

function secureBootSpec(sb) {
  if (!sb || sb.enabled == null) return spec('shield', 'Secure Boot', 'Không đọc được', { note: 'Máy cũ chạy BIOS kiểu cũ (Legacy) hoặc thiếu quyền đọc.' });
  if (!sb.enabled) return spec('shield', 'Secure Boot', 'Đang tắt', { note: 'Windows 11 cần Secure Boot; bật trong BIOS nếu máy hỗ trợ.', warn: true });
  const map = { Updated: 'đã có chứng chỉ 2023', InProgress: 'đang cập nhật chứng chỉ 2023', NotStarted: 'chưa có chứng chỉ 2023' };
  const ok = sb.ca2023 === 'Updated';
  return spec(ok ? 'shield-check' : 'shield-error', 'Secure Boot', `Đang bật, ${map[sb.ca2023] || 'chưa rõ chứng chỉ'}`, {
    note: ok ? 'Sẵn sàng khi chứng chỉ 2011 hết hạn (19/10/2026).' : 'Chứng chỉ 2011 hết hạn 19/10/2026. Cập nhật Windows và BIOS để nhận chứng chỉ mới.',
    warn: !ok && !!sb.ca2023,
  });
}

const group = (title, body) => html`<section class="spec-group"><h2>${title}</h2><dl class="specs">${body}</dl></section>`;

function specs(s) {
  if (!s) return skeleton(4, 72);
  if (s.error) return emptyState('warning', 'Không đọc được thông tin máy', s.error);
  const days = s.lastBoot ? Math.floor((Date.now() - Date.parse(s.lastBoot)) / 86400000) : 0;
  return html`
    ${group('Máy', html`
      ${spec('laptop', 'Tên máy', s.computer, { note: s.model })}
      ${spec('window-wrench', 'Windows', `${s.displayVersion || ''} build ${s.build}`.trim(), { note: s.os })}
      ${spec('clock', 'Đã bật liên tục', uptimeText(s.uptimeText), { note: days >= 14 ? 'Nên khởi động lại: lâu không khởi động lại dễ chậm, lỗi cập nhật.' : '', warn: days >= 14 })}
      ${spec('cpu', 'CPU', s.cpu)}
      ${spec('data-bar', 'RAM', s.ramTotal, { note: `Đang dùng ${s.ramUsedPct}%, còn trống ${s.ramFree}`, warn: s.ramUsedPct >= 90, meter: s.ramUsedPct })}
      ${spec('flash', 'Card đồ hoạ', (s.gpus || []).join(', ') || 'Không rõ')}
      ${spec('person', 'Tài khoản', s.user, { note: s.isAdmin ? 'Trạm đang chạy với quyền Admin' : 'Công cụ cần Admin sẽ hỏi UAC khi chạy' })}`)}
    ${group('Ổ đĩa', html`
      ${(s.disks || []).map((d) => spec('hard-drive', `Ổ ${driveName(d.drive)} ${d.label || ''}`.trim(), `Còn ${d.free} trên ${d.size}`,
        { note: `${d.freePct}% trống`, warn: d.freePct < 12, meter: 100 - d.freePct }))}
      ${(s.physical || []).map((p) => spec('server', p.name || 'Ổ vật lý', p.health === 'Healthy' ? 'Khoẻ' : p.health || 'Không rõ',
        { note: `${p.media || ''} ${p.size || ''}`.trim(), warn: !!p.health && p.health !== 'Healthy' }))}`)}
    ${group('An toàn và cài đặt', html`
      ${secureBootSpec(s.secureBoot)}
      ${restoreSpec(s.restore)}
      ${wingetSpec(s.winget)}
      ${spec('code', 'Python', s.python || 'Chưa có', { note: s.pythonPath || 'Cần cho công cụ ghi âm, mdf2sql, DWG sang PDF', warn: !s.python })}`)}`;
}

function reqsList() {
  if (!S.depsLoaded) return skeleton(3, 56);
  const tools = visibleTools().filter((t) => S.deps[t.id] && S.deps[t.id].length);
  if (!tools.length) return emptyState('check-circle', 'Không công cụ nào khai báo yêu cầu', '');
  return html`<div class="cat-list">${tools.map((t) => {
    const items = S.deps[t.id];
    const bad = items.filter((q) => !q.ok && !q.optional);
    const to = `#/tool/${enc(t.id)}`;
    return html`<div class="trow" role="link" tabindex="0" aria-label=${t.name} @click=${() => go(to)} @keydown=${onRowKey(to)}>
      ${icon(t.icon || 'toolbox')}
      <div><div class="trow-title"><span class="name">${t.name}</span>${bad.length ? badge('danger', `Thiếu ${bad.length}`) : badge('success', 'Đủ')}</div>
        <div class="req-chips">${items.map((q) => html`<span class="req-chip ${q.ok ? 'ok' : q.optional ? 'opt' : 'bad'}"
          title=${q.ok ? 'Đã có' : q.optional ? 'Chưa có, không bắt buộc' : 'Còn thiếu'}>${icon(q.ok ? 'checkmark' : q.optional ? 'info' : 'dismiss')}${q.label}</span>`)}</div></div>
      <span></span></div>`;
  })}</div>`;
}

export function systemPage() {
  return html`<div class="page">
    ${pageHead('Máy này', 'Tóm tắt nhanh, chỉ đọc. Muốn chẩn đoán sâu hãy chạy CheckWinFix.',
      btn('Đọc lại', () => loadSystem(true), { kind: 'ghost', ic: 'refresh' }))}
    ${specs(S.system)}
    ${section('Yêu cầu của các công cụ', 'Python, SQL Server, mô hình, card đồ hoạ... mà từng công cụ cần.', reqsList(),
      { tools: btn('Kiểm tra lại', () => loadDepsAll(true).then(() => toast('success', 'Đã kiểm tra lại.', { ms: 2500 })), { kind: 'ghost', sm: true, ic: 'refresh' }) })}
  </div>`;
}
