// Trạm Tool - file kết quả JSON của công cụ (chuẩn tramtool.ketqua/1): một dòng "tìm thấy gì" ở Lịch sử, thanh
// Đang chạy, Tổng quan; hộp thoại chi tiết với cách sửa và nút chạy công cụ được gợi ý.
import { html, nothing } from '../vendor/lit-html/lit-html.js';
import { api, icon, clock } from './core.js';
import { S } from './state.js';
import { openDialog, toast } from './ui.js';
import { runAction } from './run.js';

const STATE = {
  xong: { label: 'Xong', tone: 'ok', icon: 'check-circle' },
  loi: { label: 'Lỗi', tone: 'danger', icon: 'dismiss-circle' },
  'thieu-dieu-kien': { label: 'Chưa làm', tone: 'warn', icon: 'warning' },
  'mot-phan': { label: 'Làm được một phần', tone: 'warn', icon: 'warning' },
};

const LEVEL = {
  loi: { label: 'Lỗi', icon: 'dismiss-circle', order: 0 },
  'canh-bao': { label: 'Cần xem', icon: 'warning', order: 1 },
  'thong-tin': { label: 'Thông tin', icon: 'info', order: 2 },
  ok: { label: 'Đạt', icon: 'check-circle', order: 3 },
};

// "2 lỗi, 3 cần xem" (bỏ phần bằng 0); không có gì thì chuỗi rỗng.
export function countsText(k) {
  const t = (k && k.tomTat) || {};
  const parts = [];
  if (t.loi) parts.push(`${t.loi} lỗi`);
  if (t.canhBao) parts.push(`${t.canhBao} cần xem`);
  return parts.join(', ');
}

// Mức nặng nhất của kết quả để tô màu dòng tóm tắt.
export function resultTone(k) {
  if (!k) return '';
  const t = k.tomTat || {};
  if (k.trangThai === 'loi' || t.loi) return 'danger';
  if (k.trangThai === 'mot-phan' || k.trangThai === 'thieu-dieu-kien' || t.canhBao) return 'warn';
  return 'ok';
}

// Một câu cho thông báo nhanh: lời của công cụ, kèm số lỗi, cần xem.
export function resultSentence(k) {
  if (!k) return '';
  const counts = countsText(k);
  const msg = (k.thongDiep || '').replace(/[.\s]+$/, '');
  if (msg && counts) return `${msg}. Tìm thấy ${counts}.`;
  if (msg) return `${msg}.`;
  if (counts) return `Tìm thấy ${counts}.`;
  return k.trangThai === 'xong' ? 'Không có gì cần xử lý.' : '';
}

// Dòng tóm tắt dưới một lần chạy (Lịch sử).
export function resultLine(toolId, k) {
  if (!k) return nothing;
  const tone = resultTone(k);
  const ic = tone === 'danger' ? 'dismiss-circle' : tone === 'warn' ? 'warning' : 'check-circle';
  const text = resultSentence(k) || 'Công cụ đã ghi kết quả.';
  return html`<div class="row-note ${tone}">${icon(ic, 'ic-16')}<span>${k.chayThu ? 'Chạy thử. ' : ''}${text}</span>
    <button class="link" @click=${() => showResult(toolId, k.path)}>Xem chi tiết</button></div>`;
}

function nextButton(f, fromTool) {
  const n = f.chayTiep;
  if (!n) return nothing;
  const t = S.byId.get(n.congCu);
  const a = t && (t.actions || []).find((x) => x.id === n.action);
  if (!a || !a.exists) return nothing;
  const label = t.id === fromTool ? a.label : `${t.name}: ${a.label}`;
  // Việc cần hỏi (tham số, xác nhận) thì hộp thoại chạy thay chỗ hộp thoại này; không hỏi gì thì đóng hộp này trước.
  const asks = (a.args || []).length || a.risk === 'modifies-system' || !!a.confirm || a.restorePoint;
  const go = () => { if (!asks) document.getElementById('dlg')?.close(); runAction(t.id, a.id); };
  return html`<button class="btn secondary sm" title="Chạy việc này" @click=${go}>${icon(a.admin ? 'shield' : 'play')}${label}</button>`;
}

function findingRow(f, toolId) {
  const lv = LEVEL[f.mucDo] || LEVEL['thong-tin'];
  return html`<div class="finding ${f.mucDo}">
    ${icon(lv.icon, 'ic-16')}
    <div class="body">
      <div class="t">${f.tieuDe || f.ma || lv.label}</div>
      ${f.chiTiet ? html`<div class="d">${f.chiTiet}</div>` : nothing}
      ${f.cachSua ? html`<div class="fix"><b>Cách sửa:</b> ${f.cachSua}</div>` : nothing}
      ${f.chayTiep ? html`<div class="next">${nextButton(f, toolId)}</div>` : nothing}
    </div>
    ${f.ma ? html`<span class="code">${f.ma}</span>` : html`<span></span>`}
  </div>`;
}

async function reveal(toolId, path, index) {
  try { await api('/api/result/reveal', { method: 'POST', body: { toolId, path, index } }); } catch (e) { toast('error', e.message); }
}

function resultBody(toolId, r) {
  const st = STATE[r.trangThai] || { label: r.trangThai || 'Không rõ', tone: '', icon: 'info' };
  const t = r.tomTat || {};
  const items = [...(r.phatHien || [])].sort((a, b) => (LEVEL[a.mucDo] || LEVEL['thong-tin']).order - (LEVEL[b.mucDo] || LEVEL['thong-tin']).order);
  const main = items.filter((f) => f.mucDo === 'loi' || f.mucDo === 'canh-bao');
  const rest = items.filter((f) => f.mucDo !== 'loi' && f.mucDo !== 'canh-bao');
  const when = r.ketThuc || r.batDau || r.modified;
  return html`
    <div class="res-head">
      <span class="tag ${st.tone}">${icon(st.icon)}${st.label}${r.maThoat != null ? `, mã ${r.maThoat}` : ''}</span>
      ${r.chayThu ? html`<span class="tag">Chạy thử</span>` : nothing}
      <span class="muted small">${[r.cheDo, when ? `lúc ${clock(when)}` : '', r.may, r.phienBan ? `bản ${r.phienBan}` : ''].filter(Boolean).join(' · ')}</span>
    </div>
    ${r.thongDiep ? html`<p class="res-msg">${r.thongDiep}</p>` : nothing}
    ${items.length ? html`<dl class="facts-strip">
      <div><dt>Lỗi</dt><dd class=${t.loi ? 'warn' : ''}>${t.loi || 0}</dd></div>
      <div><dt>Cần xem</dt><dd>${t.canhBao || 0}</dd></div>
      <div><dt>Thông tin</dt><dd>${t.thongTin || 0}</dd></div>
    </dl>` : nothing}
    ${main.length ? html`<div class="findings">${main.map((f) => findingRow(f, toolId))}</div>`
      : items.length ? html`<p class="res-ok">${icon('check-circle', 'ic-16')}<span>Không có lỗi hay mục cần xem.</span></p>` : nothing}
    ${rest.length ? html`<details class="res-more" ?open=${!main.length}><summary>${rest.length} mục thông tin, đạt</summary>
      <div class="findings">${rest.map((f) => findingRow(f, toolId))}</div></details>` : nothing}
    ${r.boBot ? html`<p class="muted small">Còn ${r.boBot} mục nữa trong file, mở file để xem hết.</p>` : nothing}
    ${(r.tep || []).length ? html`<div class="res-files">${r.tep.map((f, i) => html`<div class="res-file">
      <span class="k">${f.nhan}</span><span class="mono" title=${f.duongDan}>${f.duongDan}</span>
      <button class="link" @click=${() => reveal(toolId, r.path, i)}>Mở thư mục</button></div>`)}</div>` : nothing}
    <p class="muted small res-src">${icon('document', 'ic-16')}<span class="mono">${r.file}</span></p>`;
}

export async function showResult(toolId, path) {
  let r;
  try { r = await api(`/api/result?id=${encodeURIComponent(toolId)}&path=${encodeURIComponent(path)}`); } catch (e) { toast('error', e.message); return; }
  const t = S.byId.get(toolId);
  const v = await openDialog({
    title: `Kết quả: ${t ? t.name : toolId}`,
    body: resultBody(toolId, r),
    wide: true,
    buttons: [{ label: 'Mở file JSON', value: 'open', icon: 'open' }, { label: 'Đóng', appearance: 'primary', value: false }],
  });
  if (v === 'open') {
    api('/api/open', { method: 'POST', body: { toolId, target: 'output', path } }).catch((e) => toast('error', e.message));
  }
}
