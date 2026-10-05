// Trạm Tool - trang Máy này: tóm tắt nhanh (chỉ đọc) và yêu cầu của các công cụ.
import { html, nothing } from '../../vendor/lit-html/lit-html.js';
import { api, icon, enc } from '../core.js';
import { S, go, visibleTools } from '../state.js';
import { section, pageHead, emptyState, badge, skeleton } from '../parts.js';
import { toast } from '../ui.js';
import { loadSystem, loadDepsAll } from '../data.js';
import { refreshJobs, watchJob } from '../jobs.js';

export function systemLoad() {
  loadSystem();
  loadDepsAll();
}

function stat(ic, label, value, note = '', warn = false, act = nothing) {
  return html`<div class="card stat${warn ? ' warn' : ''}"><span class="label">${icon(ic, 'ic-16')}${label}</span>
    <span class="value">${value}</span>${note ? html`<span class="note">${note}</span>` : nothing}${act !== nothing ? html`<span class="act">${act}</span>` : nothing}</div>`;
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

function restoreStat(r) {
  if (!r) return nothing;
  if (r.enabled) {
    return stat('shield-check', 'Bảo vệ hệ thống', 'Đang bật', 'Trạm tạo điểm khôi phục trước khi chạy công cụ đổi máy.', false,
      html`<fluent-button size="small" @click=${openRestoreUi}>Mở Khôi phục hệ thống</fluent-button>`);
  }
  if (r.enabled === false) {
    const canFix = !r.policyOff && !r.vssDisabled && !r.configLocked;
    return stat('shield-error', 'Bảo vệ hệ thống', 'Đang tắt', canFix ? 'Chưa có điểm khôi phục để quay lại nếu công cụ làm hỏng máy.' : r.detail, true,
      canFix ? html`<fluent-button size="small" @click=${() => launchFix('/api/restore/enable', 'Đang mở cửa sổ bật Bảo vệ hệ thống. Windows sẽ hỏi quyền Admin.', 'Đã mở cửa sổ bật Bảo vệ hệ thống. Xong bấm Đọc lại.')}>Bật Bảo vệ hệ thống</fluent-button>` : nothing);
  }
  return stat('shield', 'Bảo vệ hệ thống', 'Không đọc được', r.detail || '');
}

function wingetStat(w) {
  if (!w || typeof w !== 'object') return stat('download', 'winget', 'Không rõ', 'Dùng để cài phần mềm còn thiếu');
  if (w.ok) return stat('download', 'winget', `Dùng được, ${w.version}`, 'Dùng để cài phần mềm còn thiếu (nút Cài).');
  return stat('download', 'winget', 'Chưa dùng được', `${w.problem} Các nút Cài cần winget.`, true,
    html`<fluent-button size="small" @click=${() => launchFix('/api/winget/fix', 'Đang mở cửa sổ sửa winget...', 'Đã mở cửa sổ sửa winget. Xong bấm Đọc lại.')}>Sửa winget</fluent-button>`);
}

function secureBootStat(sb) {
  if (!sb || sb.enabled == null) return stat('shield', 'Secure Boot', 'Không đọc được', 'Máy cũ chạy BIOS kiểu cũ (Legacy) hoặc thiếu quyền đọc.');
  if (!sb.enabled) return stat('shield', 'Secure Boot', 'Đang tắt', 'Windows 11 cần Secure Boot; bật trong BIOS nếu máy hỗ trợ.', true);
  const map = { Updated: 'đã có chứng chỉ 2023', InProgress: 'đang cập nhật chứng chỉ 2023', NotStarted: 'chưa có chứng chỉ 2023' };
  const ok = sb.ca2023 === 'Updated';
  return stat(ok ? 'shield-check' : 'shield-error', 'Secure Boot', `Đang bật, ${map[sb.ca2023] || 'chưa rõ chứng chỉ'}`,
    ok ? 'Sẵn sàng khi chứng chỉ 2011 hết hạn (19/10/2026).' : 'Chứng chỉ 2011 hết hạn 19/10/2026. Cập nhật Windows và BIOS để nhận chứng chỉ mới.', !ok && !!sb.ca2023);
}

function stats(s) {
  if (!s) return skeleton(6, 96);
  if (s.error) return emptyState('warning', 'Không đọc được thông tin máy', s.error);
  const days = s.lastBoot ? Math.floor((Date.now() - Date.parse(s.lastBoot)) / 86400000) : 0;
  return html`
    ${stat('laptop', 'Máy', s.computer, s.model)}
    ${stat('window-wrench', 'Windows', `${s.displayVersion || ''} build ${s.build}`.trim(), s.os)}
    ${stat('clock', 'Đã bật liên tục', s.uptimeText, days >= 14 ? 'Nên khởi động lại: lâu không khởi động lại dễ chậm, lỗi cập nhật.' : '', days >= 14)}
    ${stat('cpu', 'CPU', s.cpu)}
    ${stat('data-bar', 'RAM', s.ramTotal, `Đang dùng ${s.ramUsedPct}%, còn trống ${s.ramFree}`, s.ramUsedPct >= 90)}
    ${stat('flash', 'Card đồ hoạ', (s.gpus || []).join(', ') || 'Không rõ')}
    ${secureBootStat(s.secureBoot)}
    ${stat('code', 'Python', s.python || 'Chưa có', s.pythonPath || 'Cần cho công cụ ghi âm, mdf2sql, DWG sang PDF', !s.python)}
    ${restoreStat(s.restore)}
    ${wingetStat(s.winget)}
    ${stat('person', 'Tài khoản', s.user, s.isAdmin ? 'Trạm đang chạy với quyền Admin' : 'Công cụ cần Admin sẽ hỏi UAC khi chạy')}
    ${(s.disks || []).map((d) => stat('hard-drive', `Ổ ${d.drive} ${d.label || ''}`.trim(), `Còn ${d.free} / ${d.size}`, `${d.freePct}% trống`, d.freePct < 12))}
    ${(s.physical || []).map((p) => stat('server', p.name || 'Ổ vật lý', p.health === 'Healthy' ? 'Khoẻ' : p.health || 'Không rõ', `${p.media || ''} ${p.size || ''}`.trim(), p.health && p.health !== 'Healthy'))}`;
}

function reqsList() {
  if (!S.depsLoaded) return skeleton(3, 64);
  const tools = visibleTools().filter((t) => S.deps[t.id] && S.deps[t.id].length);
  if (!tools.length) return emptyState('check-circle', 'Không công cụ nào khai báo yêu cầu', '');
  return tools.map((t) => {
    const items = S.deps[t.id];
    const bad = items.filter((q) => !q.ok && !q.optional);
    const to = `#/tool/${enc(t.id)}`;
    return html`<div class="row clickable" role="link" tabindex="0" @click=${() => go(to)} @keydown=${(e) => { if (e.key === 'Enter') go(to); }}>
      <div class="tile${bad.length ? '' : ' muted'}">${icon(t.icon || 'toolbox')}</div>
      <div class="row-main"><div class="row-title"><span class="name">${t.name}</span>${bad.length ? badge('danger', `Thiếu ${bad.length}`) : badge('success', 'Đủ')}</div>
        <div class="req-chips">${items.map((q) => html`<span class="req-chip ${q.ok ? 'ok' : q.optional ? 'opt' : 'bad'}"
          title=${q.ok ? 'Đã có' : q.optional ? 'Chưa có, không bắt buộc' : 'Còn thiếu'}>${icon(q.ok ? 'checkmark' : q.optional ? 'info' : 'dismiss', 'ic-16')}${q.label}</span>`)}</div></div>
      <div class="row-side">${icon('chevron-right', 'chev')}</div></div>`;
  });
}

export function systemPage() {
  return html`<div class="page">
    ${pageHead('Máy này', 'Tóm tắt nhanh, chỉ đọc. Muốn chẩn đoán sâu hãy chạy CheckWinFix.',
      html`<fluent-button appearance="subtle" @click=${() => loadSystem(true)}>${icon('refresh', 'ic-16')}Đọc lại</fluent-button>`)}
    <div class="stats">${stats(S.system)}</div>
    ${section('Yêu cầu của các công cụ', 'Python, SQL Server, mô hình, card đồ hoạ... mà từng công cụ cần.', html`<div class="stack">${reqsList()}</div>`,
      { tools: html`<fluent-button appearance="subtle" @click=${() => loadDepsAll(true).then(() => toast('success', 'Đã kiểm tra lại.', { ms: 2500 }))}>${icon('refresh', 'ic-16')}Kiểm tra lại</fluent-button>` })}
  </div>`;
}
