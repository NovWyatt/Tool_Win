// Trạm Tool - trang Kết quả gần đây: file báo cáo, kết quả do công cụ tạo ra; mở, mở thư mục, chọn nhiều để xoá.
// Xoá = chuyển vào Thùng rác (máy chủ chỉ nhận đúng file đang được liệt kê là kết quả của công cụ).
import { html, nothing } from '../../vendor/lit-html/lit-html.js';
import { live } from '../../vendor/lit-html/directives/live.js';
import { api, icon, enc, timeAgo, fmtSize, groupByDay } from '../core.js';
import { S, go, update } from '../state.js';
import { pageHead, emptyState, skeleton, fileIcon, btn } from '../parts.js';
import { toast, confirmDialog } from '../ui.js';
import { loadOutputs, loadToolOutputs } from '../data.js';

const keyOf = (f) => `${f.toolId}|${f.path}`;
const baseName = (p) => String(p).split('\\').pop();

export function outputsLoad(toolId = '') {
  const t = toolId && S.byId.get(toolId);
  if (t) loadToolOutputs(t);
  if (!t || !S.outputs) loadOutputs();
}

function openOut(f, reveal) {
  api('/api/open', { method: 'POST', body: { toolId: f.toolId, target: reveal ? 'output-folder' : 'output', path: f.path } })
    .catch((e) => toast('error', e.message));
}

function toggleSel(f, on) {
  if (on) S.outSel.add(keyOf(f)); else S.outSel.delete(keyOf(f));
  update();
}

export function fileRow(f, { selectable = false, showTool = true } = {}) {
  const sel = S.outSel.has(keyOf(f));
  return html`<div class="frow${selectable ? ' selectable' : ''}${sel ? ' selected' : ''}">
    ${selectable ? html`<input type="checkbox" class="sel" .checked=${live(sel)} ?disabled=${!f.deletable}
      aria-label="Chọn ${f.name}" title=${f.deletable ? 'Chọn để xoá' : 'Kết quả này không xoá từ trạm được'}
      @change=${(e) => toggleSel(f, e.target.checked)}>` : nothing}
    ${icon(fileIcon(f))}
    <div>
      <div class="name">${f.name}</div>
      <div class="meta">${showTool ? `${f.label}, ${f.toolName}` : f.label}</div>
    </div>
    <div class="facts"><span>${f.isFolder ? 'Thư mục' : f.sizeText}</span><span>${timeAgo(f.modified)}</span></div>
    <div class="side">
      ${btn('Mở', () => openOut(f, false), { kind: 'ghost', sm: true, ic: 'open' })}
      ${btn('Thư mục', () => openOut(f, true), { kind: 'ghost', sm: true, ic: 'folder', title: 'Mở thư mục chứa và chọn sẵn file' })}
      ${f.deletable ? html`<button class="icon-btn del" title="Xoá (chuyển vào Thùng rác)" aria-label="Xoá ${f.name}"
        @click=${() => deleteOutputs([f])}>${icon('delete')}</button>` : html`<span class="icon-gap"></span>`}
    </div>
  </div>`;
}

export async function deleteOutputs(files) {
  const del = files.filter((f) => f.deletable);
  if (!del.length) return;
  const notes = [...new Set(del.map((f) => f.deleteNote).filter(Boolean))];
  const one = del.length === 1 ? del[0] : null;
  const size = del.reduce((s, f) => s + (f.isFolder ? 0 : f.size || 0), 0);
  const folders = del.filter((f) => f.isFolder).length;
  const ok = await confirmDialog({
    title: one ? `Xoá "${one.name}"?` : `Xoá ${del.length} kết quả?`,
    body: html`
      ${one ? html`<p>${one.label}, ${one.toolName}${one.isFolder ? html`<br><span class="muted">Cả thư mục và mọi thứ bên trong.</span>` : html`, ${one.sizeText}`}</p>`
        : html`<ul class="del-list">${del.slice(0, 8).map((f) => html`<li><span class="del-name">${icon(fileIcon(f), 'ic-16')}${f.name}</span><span class="muted">${f.toolName}</span></li>`)}
          ${del.length > 8 ? html`<li class="muted">và ${del.length - 8} mục khác</li>` : nothing}</ul>
          <p class="muted small">Tổng ${size ? fmtSize(size) : ''}${size && folders ? ' và ' : ''}${folders ? `${folders} thư mục` : ''}.</p>`}
      ${notes.map((n) => html`<div class="warnbox">${icon('warning', 'ic-16')}<span>${n}</span></div>`)}
      <p class="muted note">${icon('delete', 'ic-16')}<span>Chuyển vào Thùng rác, khôi phục lại được. Ổ USB hoặc ổ mạng không có Thùng rác: Windows sẽ hỏi trước khi xoá hẳn.</span></p>`,
    confirmLabel: one ? 'Chuyển vào Thùng rác' : `Xoá ${del.length} mục`,
    confirmIcon: 'delete',
    danger: true,
    ack: notes.length ? 'Tôi đã đọc cảnh báo ở trên và vẫn muốn xoá.' : '',
  });
  if (!ok) return;
  const note = toast('info', `Đang xoá ${del.length} mục...`, { ms: 0 });
  try {
    const r = await api('/api/outputs/delete', { method: 'POST', body: { items: del.map((f) => ({ toolId: f.toolId, path: f.path })) } });
    const failed = r.results.filter((x) => x.status === 'error');
    const cancelled = r.results.filter((x) => x.status === 'cancelled');
    for (const x of r.results) if (x.status === 'deleted') S.outSel.delete(`${x.toolId}|${x.path}`);
    if (!failed.length && !cancelled.length) {
      note.update('success', r.deleted === 1 ? 'Đã chuyển vào Thùng rác.' : `Đã chuyển ${r.deleted} mục vào Thùng rác.`, { ms: 5000 });
    } else {
      const why = failed.slice(0, 3).map((x) => `${baseName(x.path)}: ${x.message}`).join(' ');
      note.update(failed.length ? 'warning' : 'info',
        `Đã xoá ${r.deleted}/${del.length} mục.${cancelled.length ? ` Huỷ ${cancelled.length} mục.` : ''}${failed.length ? ` Không xoá được: ${why}` : ''}`, { ms: 15000 });
    }
  } catch (e) { note.update('error', e.message, { ms: 10000 }); }
  // Tải lại các danh sách có chứa mục vừa xoá.
  S.outputs = null;
  for (const id of new Set(del.map((f) => f.toolId))) {
    const t = S.byId.get(id);
    if (t && S.toolData[id]) loadToolOutputs(t);
  }
  if (S.route.name === 'outputs') loadOutputs(); // cả khi đang lọc một công cụ: số đếm trên các nút lọc lấy từ danh sách chung
}

export function outputsPage(toolId = '') {
  const t = toolId ? S.byId.get(toolId) : null;
  const list = t ? (S.toolData[t.id] || {}).outs : S.outputs;
  const head = pageHead(t ? `Kết quả của ${t.name}` : 'Kết quả gần đây',
    t ? 'Các file, thư mục công cụ này đã tạo trên máy, mới nhất ở trên.' : 'File báo cáo và kết quả do các công cụ tạo ra trên máy này, mới nhất ở trên.',
    btn('Làm mới', () => { if (t) (S.toolData[t.id] = S.toolData[t.id] || {}).outs = null; else S.outputs = null; update(); outputsLoad(toolId); }, { kind: 'ghost', ic: 'refresh' }));
  if (list == null) return html`<div class="page">${head}${skeleton(4, 52)}</div>`;

  // Lọc theo công cụ: danh sách chung lấy tối đa 15 file mỗi công cụ, bấm lọc thì tải đủ của công cụ đó.
  const all = S.outputs || [];
  const counts = new Map();
  for (const f of all) counts.set(f.toolId, (counts.get(f.toolId) || 0) + 1);
  const tabs = html`<div class="tabs" role="group" aria-label="Lọc theo công cụ">
    <button class="tab" aria-pressed=${!t} @click=${() => go('#/outputs')}>Tất cả${S.outputs ? html`<span class="count">${all.length}</span>` : nothing}</button>
    ${[...counts.keys()].map((id) => S.byId.get(id)).filter(Boolean).map((x) => html`<button class="tab" aria-pressed=${!!t && t.id === x.id}
      @click=${() => go(`#/outputs/${enc(x.id)}`)}>${x.name}<span class="count">${counts.get(x.id)}</span></button>`)}
    ${t && !counts.has(t.id) ? html`<button class="tab" aria-pressed="true">${t.name}</button>` : nothing}
  </div>`;

  if (!list.length) {
    return html`<div class="page">${head}${all.length || t ? tabs : nothing}
      ${emptyState('document-search', t ? 'Công cụ này chưa có kết quả' : 'Chưa có kết quả nào',
        'Chạy một công cụ chẩn đoán hoặc chuyển đổi, kết quả sẽ hiện ở đây.',
        t ? btn(`Mở ${t.name}`, () => go(`#/tool/${enc(t.id)}`)) : nothing)}</div>`;
  }

  const deletable = list.filter((f) => f.deletable);
  const chosen = list.filter((f) => S.outSel.has(keyOf(f)));
  const allOn = deletable.length > 0 && chosen.length === deletable.length;
  const someOn = chosen.length > 0 && !allOn;
  const size = chosen.reduce((s, f) => s + (f.isFolder ? 0 : f.size || 0), 0);
  const toggleAll = (on) => { for (const f of deletable) { if (on) S.outSel.add(keyOf(f)); else S.outSel.delete(keyOf(f)); } update(); };

  return html`<div class="page">
    ${head}
    ${tabs}
    <div class="selbar${chosen.length ? ' active' : ''}">
      <label class="check"><input type="checkbox" .checked=${live(allOn)} .indeterminate=${someOn} ?disabled=${!deletable.length}
        @change=${(e) => toggleAll(e.target.checked)}><span>Chọn tất cả</span></label>
      <span class="selbar-info">${chosen.length ? `Đã chọn ${chosen.length} mục${size ? `, ${fmtSize(size)}` : ''}` : `${list.length} mục`}</span>
      ${chosen.length ? btn('Bỏ chọn', () => { for (const f of chosen) S.outSel.delete(keyOf(f)); update(); }, { kind: 'ghost', sm: true }) : nothing}
      ${btn(chosen.length ? `Xoá ${chosen.length} mục` : 'Xoá mục đã chọn', () => deleteOutputs(chosen), { kind: 'danger', sm: true, ic: 'delete', disabled: !chosen.length })}
    </div>
    ${groupByDay(list, (f) => f.modified).map((g) => html`<div class="day"><h2>${g.label}</h2>
      <div class="stack">${g.items.map((f) => fileRow(f, { selectable: true, showTool: !t }))}</div></div>`)}
  </div>`;
}
