// Trạm Tool - trang chi tiết một công cụ: sẵn sàng chưa, các việc chạy được, trạng thái máy, yêu cầu, kết quả, hướng dẫn.
import { html, nothing } from '../../vendor/lit-html/lit-html.js';
import { unsafeHTML } from '../../vendor/lit-html/directives/unsafe-html.js';
import { marked } from '../../vendor/marked.min.js';
import DOMPurify from '../../vendor/purify.min.js';
import { api, icon, enc, timeAgo, fmtDuration } from '../core.js';
import { S, go, isPinned, togglePin, primaryAction, lastRun, runState, catLabel, RISK } from '../state.js';
import { section, emptyState, badge, runButton, skeleton } from '../parts.js';
import { toast } from '../ui.js';
import { loadToolExtras, loadReqs, loadProbes, loadHistory, reloadCatalog } from '../data.js';
import { fileRow } from './outputs.js';

export function toolLoad(id) {
  const t = S.byId.get(id);
  if (t) loadToolExtras(t);
  if (!S.history) loadHistory();
}

export function renderMarkdown(md) {
  const htmlText = marked.parse(String(md || ''), { gfm: true, breaks: false });
  const clean = DOMPurify.sanitize(htmlText, { USE_PROFILES: { html: true } });
  // Liên kết ra ngoài mở bằng trình duyệt; liên kết nội bộ (file .md) không bấm được trong trạm.
  return clean.replace(/<a href="(?!https?:)[^"]*"/g, '<a');
}

const scrollTo = (id) => document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' });

async function act(fn) {
  try { await fn(); } catch (e) { toast('error', e.message); }
}

async function pack(t) {
  const note = toast('info', 'Đang đóng gói...', { ms: 0 });
  try {
    const r = await api('/api/pack', { method: 'POST', body: { toolId: t.id } });
    note.update('success', `Đã tạo ${r.path} (${r.files} file, ${r.size}). Gửi file .zip này cho khách.`, { ms: 9000 });
  } catch (e) { note.update('error', e.message, { ms: 9000 }); }
}

async function scaffold(t) {
  const r = await api('/api/scaffold', { method: 'POST', body: { toolId: t.id } });
  toast('success', `Đã tạo ${r.path}. Sửa tên, nhóm, mức rủi ro rồi bấm Làm mới.`, { ms: 9000 });
  await reloadCatalog(true);
}

async function fix(t, q) {
  const r = await api('/api/fix', { method: 'POST', body: { toolId: t.id, reqId: q.id } });
  toast(r.ok === false ? 'error' : 'info', r.message || 'Đã mở cửa sổ cài đặt. Cài xong bấm "Kiểm tra lại".', { ms: 9000 });
}

// Dòng "sẵn sàng" dưới tên công cụ: yêu cầu, quyền Admin, thời gian chạy, lần chạy gần nhất.
function readiness(t, d) {
  const a = primaryAction(t);
  const chips = [];
  if ((t.requires || []).length) {
    if (!d.reqs) chips.push(html`<span class="chip-info">${icon('clock', 'ic-16')}Đang kiểm tra yêu cầu</span>`);
    else {
      const miss = d.reqs.filter((r) => !r.ok && !r.optional);
      chips.push(miss.length
        ? html`<button class="chip-info bad" @click=${() => scrollTo('reqs')}>${icon('dismiss-circle', 'ic-16')}Thiếu ${miss.length} yêu cầu</button>`
        : html`<span class="chip-info ok">${icon('check-circle', 'ic-16')}Đủ yêu cầu để chạy</span>`);
    }
  }
  if (a && a.admin) chips.push(html`<span class="chip-info">${icon('shield', 'ic-16')}Cần quyền Admin</span>`);
  if (a && a.duration) chips.push(html`<span class="chip-info">${icon('clock', 'ic-16')}${a.duration}</span>`);
  const last = lastRun(t.id);
  if (last) {
    const st = runState(last);
    chips.push(html`<span class="chip-info">${icon('history', 'ic-16')}Lần gần nhất ${timeAgo(last.time)}: ${st.label.toLowerCase()}${st.dur != null ? ` sau ${fmtDuration(st.dur)}` : ''}</span>`);
  }
  return chips.length ? html`<div class="readiness">${chips}</div>` : nothing;
}

function actionRow(t, a) {
  const last = lastRun(t.id, a.id);
  const risk = RISK[a.risk];
  return html`<div class="row action-row">
    <div class="row-main">
      <div class="row-title"><span class="name">${a.label}</span>
        ${a.risk !== 'read-only' ? badge(risk.color, risk.label) : nothing}${!a.exists ? badge('danger', 'Thiếu file') : nothing}</div>
      ${a.description ? html`<div class="desc">${a.description}</div>` : nothing}
      <div class="row-meta">
        ${a.duration ? html`<span>${icon('clock', 'ic-16')}${a.duration}</span>` : nothing}
        ${a.admin ? html`<span>${icon('shield', 'ic-16')}Cần quyền Admin</span>` : nothing}
        ${last ? html`<span>${icon('history', 'ic-16')}${timeAgo(last.time)}: ${runState(last).label.toLowerCase()}</span>` : nothing}
        ${a.file ? html`<span class="mono">${a.file}</span>` : nothing}
      </div>
      ${(a.changes || []).length ? html`<details class="changes"><summary>Công cụ có thể thay đổi</summary>
        <ul>${a.changes.map((c) => html`<li>${c}</li>`)}</ul></details>` : nothing}
    </div>
    <div class="row-side">${runButton(t, a, { appearance: a.primary ? 'primary' : 'outline' })}</div>
  </div>`;
}

function reqRow(t, q) {
  const state = q.ok ? 'ok' : q.optional ? 'opt' : 'bad';
  const ic = q.ok ? 'check-circle' : q.optional ? 'warning' : 'dismiss-circle';
  const fixLabel = q.fix && (q.fix.label || (q.fix.winget ? 'Cài' : 'Sửa'));
  return html`<div class="kv">
    <span class="k">${q.label}${q.optional ? html` <span class="small">(không bắt buộc)</span>` : nothing}</span>
    <span class="v req-${state}">${icon(ic, 'ic-16')} ${q.ok ? 'Đã có' : q.optional ? 'Chưa có' : 'Thiếu'}<small>${q.detail}</small></span>
    <span>${!q.ok && q.fix ? html`<fluent-button appearance="primary" size="small" @click=${() => act(() => fix(t, q))}>${fixLabel}</fluent-button>` : nothing}</span>
  </div>`;
}

function probeRows(d) {
  if (d.probesErr) return html`<div class="kv"><span class="k">Lỗi</span><span class="v">${d.probesErr}</span><span></span></div>`;
  if (!d.probes) return html`<div class="kv"><span class="k">&nbsp;</span><span class="v muted">Đang đọc...</span><span></span></div>`;
  return d.probes.map((p) => html`<div class="kv">
    <span class="k">${p.label}</span>
    <span class="v">${p.value}${p.detail ? html`<small>${p.detail}</small>` : nothing}</span>
    <span>${p.state === 'changed' ? badge('warning', 'Đã đổi') : p.state === 'default' ? badge('subtle', 'Mặc định') : nothing}</span>
  </div>`);
}

function outputsBlock(t, d) {
  if (d.outs == null) return skeleton(2, 60);
  if (d.outsErr) return emptyState('warning', 'Không đọc được kết quả', d.outsErr);
  if (!d.outs.length) return emptyState('document', 'Chưa có kết quả', 'Chạy công cụ xong, file kết quả sẽ hiện ở đây.');
  return html`${d.outs.slice(0, 8).map((f) => fileRow(f, { showTool: false }))}
    ${d.outs.length > 8 ? html`<button class="more-link" @click=${() => go(`#/outputs/${enc(t.id)}`)}>Xem cả ${d.outs.length} kết quả</button>` : nothing}`;
}

export function toolPage(id) {
  const t = S.byId.get(id);
  if (!t) {
    return html`<div class="page">${emptyState('warning', 'Không tìm thấy công cụ', 'Có thể thư mục công cụ đã bị đổi tên hoặc xoá.',
      html`<fluent-button @click=${() => go('#/')}>Về Tổng quan</fluent-button>`)}</div>`;
  }
  const d = S.toolData[id] || {};
  const pinned = isPinned(t.id);
  const a0 = primaryAction(t);
  const notes = [];
  for (const p of t.problems || []) notes.push(['warning', p]);
  if (t.statusNote) notes.push([t.status === 'broken' ? 'error' : 'warning', t.statusNote]);
  if (t.auto) notes.push(['info', 'Công cụ này chưa có tool.json nên trạm đoán các nút chạy từ file .bat/.ps1. Bấm "Tạo tool.json" để đặt tên, nhóm, mức rủi ro và quyền Admin cho đúng.']);
  const missing = d.reqs ? d.reqs.filter((r) => !r.ok && !r.optional) : [];
  if (missing.length) notes.unshift(['error', `Còn thiếu ${missing.map((m) => m.label).join(', ')}. Bấm nút Cài ở mục "Yêu cầu để chạy" bên dưới.`]);
  const deletable = (d.outs || []).filter((f) => f.deletable);

  return html`<div class="page">
    <nav class="crumbs" aria-label="Vị trí">
      <button @click=${() => go('#/')}>Tổng quan</button>${icon('chevron-right', 'ic-16')}
      <button @click=${() => go(`#/c/${enc(t.category)}`)}>${catLabel(t.category)}</button>
    </nav>
    <div class="card hero">
      <div class="tile lg${t.auto ? ' muted' : ''}">${icon(t.icon || 'toolbox')}</div>
      <div class="hero-main">
        <h1>${t.name}</h1>
        <p>${t.summary}</p>
        ${t.description ? html`<p class="small muted">${t.description}</p>` : nothing}
        ${readiness(t, d)}
        <div class="bar">
          ${runButton(t, a0, { appearance: 'primary', label: a0 && (t.actions || []).length > 1 ? `Chạy: ${a0.label}` : 'Chạy' })}
          <fluent-button @click=${() => act(() => api('/api/open', { method: 'POST', body: { toolId: t.id, target: 'folder' } }))}>${icon('folder', 'ic-16')}Mở thư mục</fluent-button>
          ${t.hasDocs ? html`<fluent-button @click=${() => scrollTo('docs')}>${icon('book', 'ic-16')}Hướng dẫn</fluent-button>` : nothing}
          ${!t.auto
            ? html`<fluent-button title="Tạo file .zip trên Desktop để gửi qua Zalo, email, USB" @click=${() => pack(t)}>${icon('box', 'ic-16')}Đóng gói gửi khách</fluent-button>`
            : html`<fluent-button appearance="primary" @click=${() => act(() => scaffold(t))}>${icon('document', 'ic-16')}Tạo tool.json</fluent-button>`}
          <fluent-button appearance="subtle" aria-pressed=${pinned} @click=${() => togglePin(t.id).catch((e) => toast('error', e.message))}>
            ${icon(pinned ? 'star-filled' : 'star', 'ic-16')}${pinned ? 'Bỏ ghim' : 'Ghim'}</fluent-button>
        </div>
      </div>
    </div>
    ${notes.map(([intent, text]) => html`<fluent-message-bar intent=${intent} layout="multiline" class="note-bar">${text}</fluent-message-bar>`)}
    ${section('Các việc chạy được', (t.actions || []).length > 1 ? 'Mỗi việc mở trong một cửa sổ riêng. Cửa sổ đang mở hiện ở thanh Đang chạy phía dưới.' : '',
      html`<div class="stack">${(t.actions || []).length ? t.actions.map((a) => actionRow(t, a)) : emptyState('warning', 'Chưa có việc nào', 'Khai báo actions trong tool.json.')}</div>`)}
    ${(t.probes || []).length ? section('Trạng thái hiện tại trên máy này', 'Chỉ đọc, không thay đổi gì.', html`<div class="card">${probeRows(d)}</div>`,
      { tools: html`<fluent-button appearance="subtle" @click=${() => loadProbes(t)}>${icon('refresh', 'ic-16')}Đọc lại</fluent-button>` }) : nothing}
    ${(t.requires || []).length ? section('Yêu cầu để chạy', 'Trạm tự kiểm tra; thiếu gì có nút cài.',
      html`<div class="card">${d.reqsErr ? html`<div class="kv"><span class="k">Lỗi</span><span class="v">${d.reqsErr}</span><span></span></div>`
        : d.reqs ? d.reqs.map((q) => reqRow(t, q)) : html`<div class="kv"><span class="k">&nbsp;</span><span class="v muted">Đang kiểm tra...</span><span></span></div>`}</div>`,
      { id: 'reqs', tools: html`<fluent-button appearance="subtle" @click=${() => loadReqs(t, true).then(() => toast('success', 'Đã kiểm tra lại.', { ms: 2500 }))}>${icon('refresh', 'ic-16')}Kiểm tra lại</fluent-button>` }) : nothing}
    ${(t.outputs || []).length ? section('Kết quả gần đây', 'File do công cụ tạo ra trên máy này, mới nhất ở trên.', html`<div class="stack">${outputsBlock(t, d)}</div>`,
      { id: 'outs', tools: deletable.length > 1 ? html`<fluent-button appearance="subtle" @click=${() => go(`#/outputs/${enc(t.id)}`)}>${icon('delete', 'ic-16')}Chọn để xoá</fluent-button>` : nothing }) : nothing}
    ${!S.settings.simple && ((t.issues || []).length || (t.upgrades || []).length) ? section('Lỗi đã biết và hướng nâng cấp', 'Tóm tắt từ bản phân tích; chi tiết ở trang Phân tích và nâng cấp.', html`<div class="two-col">
      <div class="card"><div class="card-title">${icon('warning', 'ic-16')}Lỗi, rủi ro đã biết</div><ul class="list-plain">${(t.issues || []).length ? t.issues.map((x) => html`<li>${x}</li>`) : html`<li class="muted">Chưa ghi nhận.</li>`}</ul></div>
      <div class="card"><div class="card-title">${icon('lightbulb', 'ic-16')}Hướng nâng cấp</div><ul class="list-plain">${(t.upgrades || []).length ? t.upgrades.map((x) => html`<li>${x}</li>`) : html`<li class="muted">Chưa có.</li>`}</ul></div>
    </div>`) : nothing}
    ${t.hasDocs ? section('Hướng dẫn', t.docs, html`<div class="card doc">${!d.docs ? html`<div class="skeleton" style="height:120px;border:0"></div>`
      : d.docs.error ? html`<p class="muted">${d.docs.error}</p>`
      : /\.txt$/i.test(d.docs.name || '') ? html`<pre class="doc-txt">${d.docs.text}</pre>` : unsafeHTML(renderMarkdown(d.docs.text))}</div>`, { id: 'docs' }) : nothing}
  </div>`;
}

