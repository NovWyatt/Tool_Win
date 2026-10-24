// Trạm Tool - trang chi tiết một công cụ: cần cài gì, việc chính, các việc khác xếp theo mức an toàn, trạng thái
// máy, yêu cầu, kết quả, hướng dẫn.
import { html, nothing } from '../../vendor/lit-html/lit-html.js';
import { unsafeHTML } from '../../vendor/lit-html/directives/unsafe-html.js';
import { marked } from '../../vendor/marked.min.js';
import DOMPurify from '../../vendor/purify.min.js';
import { api, icon, enc, timeAgo, fmtDuration, clock } from '../core.js';
import { S, go, update, isPinned, togglePin, primaryAction, lastRun, runState, catLabel, ACTION_GROUPS, actionGroup, missingFixes } from '../state.js';
import { section, emptyState, badge, runButton, skeleton, btn } from '../parts.js';
import { toast } from '../ui.js';
import { loadToolExtras, loadReqs, loadProbes, loadHistory, reloadCatalog, loadServer } from '../data.js';
import { fileRow } from './outputs.js';
import { refreshJobs, watchJob } from '../jobs.js';

const expanded = new Set(); // công cụ đang mở phần giới thiệu đầy đủ

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

// Cửa sổ cài mà trạm không theo dõi được (winget mở riêng): quay lại cửa sổ trạm thì tự kiểm tra lại, trong 30 phút.
let fixWatch = null;
window.addEventListener('focus', () => {
  if (!fixWatch || Date.now() > fixWatch.until) { fixWatch = null; return; }
  const t = S.byId.get(fixWatch.id);
  if (t) loadReqs(t, true).then(() => { if (!missingFixes(t, (S.toolData[t.id] || {}).reqs).length) fixWatch = null; });
});

async function fix(t, q) {
  const r = await api('/api/fix', { method: 'POST', body: { toolId: t.id, reqId: q.id } });
  if (r.cancelled) { toast('info', 'Đã huỷ: bạn chọn "Không" ở hộp thoại quyền Admin nên chưa cài.'); return; }
  if (r.jobId) {
    // Cài bằng action hoặc script của trạm: hiện ở thanh Đang chạy, xong thì trạm tự kiểm tra lại (jobs.js).
    watchJob(r.jobId);
    refreshJobs();
    toast('info', 'Đã mở cửa sổ cài đặt. Theo dõi ở thanh Đang chạy; cài xong trạm tự kiểm tra lại.', { ms: 9000 });
    return;
  }
  if (r.ok !== false) fixWatch = { id: t.id, until: Date.now() + 30 * 60000 };
  toast(r.ok === false ? 'error' : 'info', r.message || 'Đã mở cửa sổ cài đặt. Cài xong quay lại đây, trạm tự kiểm tra lại.', { ms: 9000 });
}

const fixLabel = (f) => f.label || (f.winget ? 'Cài' : 'Sửa');
const recheck = (t) => loadReqs(t, true).then(() => toast('success', 'Đã kiểm tra lại.', { ms: 2500 }));

// Dòng "sẵn sàng" dưới tên công cụ: đủ yêu cầu chưa, lần chạy gần nhất.
function readiness(t, d) {
  const items = [];
  if ((t.requires || []).length) {
    if (!d.reqs) items.push(html`<li>${icon('clock', 'ic-16')}Đang kiểm tra yêu cầu</li>`);
    else {
      const miss = d.reqs.filter((r) => !r.ok && !r.optional);
      items.push(miss.length
        ? html`<li class="bad">${icon('dismiss-circle', 'ic-16')}Cần cài thêm ${miss.length} thứ trước khi chạy</li>`
        : html`<li class="ok">${icon('check-circle', 'ic-16')}Đủ yêu cầu để chạy</li>`);
    }
  }
  const last = lastRun(t.id);
  if (last) {
    const st = runState(last);
    items.push(html`<li>${icon('history', 'ic-16')}Lần gần nhất ${timeAgo(last.time)}: ${last.actionLabel}, ${st.label.toLowerCase()}${st.dur != null ? ` sau ${fmtDuration(st.dur)}` : ''}</li>`);
  }
  return items.length ? html`<ul class="readiness">${items}</ul>` : nothing;
}

// Thiếu yêu cầu bắt buộc: nói ngay ở đầu trang, nút cài nằm cạnh từng thứ còn thiếu.
function needPanel(t, d) {
  if (!d.reqs) return nothing;
  const fixes = missingFixes(t, d.reqs);
  if (!fixes.length) return nothing;
  return html`<section class="need" id="need" aria-labelledby="need-title">
    <div class="need-head">
      ${icon('download')}
      <div><h2 id="need-title">Cần cài trước khi chạy</h2><p>Chạy khi còn thiếu thì công cụ sẽ báo lỗi. Cài xong trạm tự kiểm tra lại.</p></div>
      ${btn('Kiểm tra lại', () => recheck(t), { kind: 'ghost', sm: true, ic: 'refresh' })}
    </div>
    <ul class="need-list">${fixes.map((f) => html`<li>
      <span>${f.labels.join(', ')}${f.req.detail ? html`<small>${f.req.detail}</small>` : nothing}</span>
      ${f.fix ? btn(fixLabel(f.fix), () => act(() => fix(t, f.req)), { kind: 'primary', sm: true, ic: f.fix.admin ? 'shield' : 'download' })
        : html`<span class="muted small">Cài tay theo Hướng dẫn</span>`}
    </li>`)}</ul>
  </section>`;
}

async function serverOpen(t, a) {
  try {
    const r = await api('/api/server/open', { method: 'POST', body: { toolId: t.id, actionId: a.id } });
    toast('success', `Đã mở lại giao diện (cổng ${r.port}) trong trình duyệt.`, { ms: 5000 });
  } catch (e) { toast('error', e.message); loadServer(t); }
}

async function serverStop(t, a) {
  try {
    const r = await api('/api/server/stop', { method: 'POST', body: { toolId: t.id, actionId: a.id } });
    toast(r.ok ? 'success' : 'warning', r.message, { ms: r.ok ? 5000 : 12000 });
  } catch (e) { toast('error', e.message); }
  setTimeout(() => loadServer(t), 800);
}

// Giao diện web của action đang chạy: cổng, từ lúc nào; mở lại hoặc tắt.
function serverLine(t, a, d) {
  const s = a.webServer && d.server && d.server[a.id];
  if (!s || !s.running) return nothing;
  return html`<div class="row-note ok">${icon('globe', 'ic-16')}<span>Đang chạy ở cổng ${s.port}${s.startedAt ? ` từ ${clock(s.startedAt)}` : ''}${s.busy ? `, đang làm ${s.busy} việc` : ''}.</span>
    <button class="link" @click=${() => serverOpen(t, a)}>Mở lại</button>
    <button class="link" @click=${() => serverStop(t, a)}>Tắt</button></div>`;
}

// Nhãn mức an toàn của việc chính (các việc khác đã có tiêu đề nhóm nói điều này).
const MAIN_TAG = { xem: ['success', 'Không đổi gì trên máy'], sua: ['warning', 'Có thay đổi, hỏi trước'], 'tra-lai': ['warning', 'Hoàn tác'], 'cai-dat': ['warning', 'Cài đặt'] };

// Một việc: tên, mô tả, thời gian, quyền Admin, lần chạy gần nhất; nút Chạy ngay cạnh tên việc.
function actionRow(t, a, d, { main = false } = {}) {
  const last = lastRun(t.id, a.id);
  const tag = main && MAIN_TAG[actionGroup(a)];
  return html`<div class="arow${main ? ' main' : ''}">
    <div>
      <div class="arow-title"><span class="name" title=${S.settings.simple ? nothing : a.file || nothing}>${a.label}</span>
        ${tag ? badge(tag[0], tag[1]) : nothing}${!a.exists ? badge('danger', 'Thiếu file') : nothing}</div>
      ${a.description ? html`<div class="desc">${a.description}</div>` : nothing}
      <div class="arow-meta">
        ${a.duration ? html`<span>${icon('clock', 'ic-16')}${a.duration}</span>` : nothing}
        ${a.admin ? html`<span>${icon('shield', 'ic-16')}Cần quyền Admin</span>` : nothing}
        ${last ? html`<span>${icon('history', 'ic-16')}${timeAgo(last.time)}: ${runState(last).label.toLowerCase()}</span>` : nothing}
      </div>
      ${serverLine(t, a, d)}
      ${(a.changes || []).length ? html`<details class="changes"><summary>Những gì có thể thay đổi</summary>
        <ul>${a.changes.map((c) => html`<li>${c}</li>`)}</ul></details>` : nothing}
    </div>
    <div class="arow-act">${runButton(t, a, { kind: main ? 'primary' : 'secondary', label: 'Chạy' })}</div>
  </div>`;
}

// Các việc ngoài việc chính, theo nhóm an toàn; menu dòng lệnh gấp lại vì đã có đủ trong các nút trên.
function otherActions(t, others, d) {
  return ACTION_GROUPS.map((g) => {
    const list = others.filter((a) => actionGroup(a) === g.id);
    if (!list.length) return nothing;
    const body = html`<div class="actions-list">${list.map((a) => actionRow(t, a, d))}</div>`;
    if (g.id === 'khac') {
      return html`<details class="agroup fold">
        <summary><span class="agroup-title">${icon('chevron-right', 'ic-16')}${g.title}<span class="count">${list.length}</span></span><span class="agroup-desc">${g.desc}</span></summary>
        ${body}</details>`;
    }
    return html`<div class="agroup"><div class="agroup-head"><h3>${g.title}</h3><p>${g.desc}</p></div>${body}</div>`;
  });
}

function reqRow(t, q) {
  const state = q.ok ? 'ok' : q.optional ? 'opt' : 'bad';
  const ic = q.ok ? 'check-circle' : q.optional ? 'warning' : 'dismiss-circle';
  return html`<div class="kv req-${state}">
    <span class="k">${q.label}${q.optional ? html`<small>Không bắt buộc</small>` : nothing}</span>
    <span class="v"><span class="req-state">${icon(ic, 'ic-16')}${q.ok ? 'Đã có' : q.optional ? 'Chưa có' : 'Thiếu'}</span>${q.detail ? html`<small>${q.detail}</small>` : nothing}</span>
    <span>${!q.ok && q.fix ? btn(fixLabel(q.fix), () => act(() => fix(t, q)), { kind: q.optional ? 'secondary' : 'primary', sm: true, ic: 'download' }) : nothing}</span>
  </div>`;
}

const kvNote = (k, v) => html`<div class="kv"><span class="k">${k}</span><span class="v muted">${v}</span><span></span></div>`;

function probeRows(d) {
  if (d.probesErr) return kvNote('Lỗi', d.probesErr);
  if (!d.probes) return kvNote('', 'Đang đọc...');
  return d.probes.map((p) => html`<div class="kv">
    <span class="k">${p.label}</span>
    <span class="v">${p.value}${p.detail ? html`<small>${p.detail}</small>` : nothing}</span>
    <span>${p.state === 'changed' ? badge('warning', 'Đã đổi') : p.state === 'default' ? badge('subtle', 'Mặc định') : nothing}</span>
  </div>`);
}

function outputsBlock(t, d) {
  if (d.outs == null) return skeleton(2, 52);
  if (d.outsErr) return emptyState('warning', 'Không đọc được kết quả', d.outsErr);
  if (!d.outs.length) return emptyState('document', 'Chưa có kết quả', 'Chạy công cụ xong, file kết quả sẽ hiện ở đây.');
  return html`<div class="stack">${d.outs.slice(0, 8).map((f) => fileRow(f, { showTool: false }))}</div>
    ${d.outs.length > 8 ? html`<div class="more-link"><button class="link" @click=${() => go(`#/outputs/${enc(t.id)}`)}>Xem cả ${d.outs.length} kết quả</button></div>` : nothing}`;
}

// Mô tả dài: hiện hai dòng đầu, bấm Đọc thêm để mở hết.
function descBlock(t) {
  if (!t.description) return nothing;
  const long = t.description.length > 200;
  const open = !long || expanded.has(t.id);
  const toggle = () => { if (expanded.has(t.id)) expanded.delete(t.id); else expanded.add(t.id); update(); };
  return html`<p class="desc${open ? '' : ' clamp'}" id="tool-desc">${t.description}</p>
    ${long ? html`<button class="link more-btn" aria-expanded=${open ? 'true' : 'false'} aria-controls="tool-desc" @click=${toggle}>${open ? 'Thu gọn' : 'Đọc thêm'}</button>` : nothing}`;
}

const NOTE_ICON = { error: 'dismiss-circle', warning: 'warning', info: 'info' };

export function toolPage(id) {
  const t = S.byId.get(id);
  if (!t) {
    return html`<div class="page">${emptyState('warning', 'Không tìm thấy công cụ', 'Có thể thư mục công cụ đã bị đổi tên hoặc xoá.',
      btn('Về Tổng quan', () => go('#/')))}</div>`;
  }
  const d = S.toolData[id] || {};
  const pinned = isPinned(t.id);
  const a0 = primaryAction(t);
  const actions = t.actions || [];
  const others = actions.filter((a) => a !== a0);
  const notes = [];
  for (const p of t.problems || []) notes.push(['warning', p]);
  if (t.statusNote) notes.push([t.status === 'broken' ? 'error' : 'warning', t.statusNote]);
  if (t.auto && !t.manifestBroken) notes.push(['info', 'Công cụ này chưa có tool.json nên trạm đoán các nút chạy từ file .bat/.ps1. Bấm "Tạo tool.json" để đặt tên, nhóm, mức rủi ro và quyền Admin cho đúng.']);
  const deletable = (d.outs || []).filter((f) => f.deletable);
  const refresh = (label, fn) => btn(label, fn, { kind: 'ghost', sm: true, ic: 'refresh' });
  const known = (t.issues || []).length + (t.upgrades || []).length;

  return html`<div class="page">
    <nav class="crumbs" aria-label="Vị trí">
      <button @click=${() => go('#/')}>Tổng quan</button>${icon('chevron-right', 'ic-16')}
      <button @click=${() => go(`#/c/${enc(t.category)}`)}>${catLabel(t.category)}</button>
    </nav>
    <header class="tool-head">
      <div class="tool-ic${t.auto ? ' muted' : ''}">${icon(t.icon || 'toolbox')}</div>
      <div>
        <h1>${t.name}</h1>
        <p class="lede">${t.summary}</p>
        ${descBlock(t)}
        ${readiness(t, d)}
        <div class="bar">
          ${btn('Mở thư mục', () => act(() => api('/api/open', { method: 'POST', body: { toolId: t.id, target: 'folder' } })), { ic: 'folder', sm: true })}
          ${t.hasDocs ? btn('Hướng dẫn', () => scrollTo('docs'), { ic: 'book', sm: true }) : nothing}
          ${t.manifestBroken ? nothing : t.auto ? btn('Tạo tool.json', () => act(() => scaffold(t)), { ic: 'document', sm: true })
            : !S.settings.simple ? btn('Đóng gói gửi khách', () => pack(t), { ic: 'box', sm: true, title: 'Tạo file .zip trên Desktop để gửi qua Zalo, email, USB' }) : nothing}
          ${btn(pinned ? 'Bỏ ghim' : 'Ghim lên Tổng quan', () => togglePin(t.id).catch((e) => toast('error', e.message)),
            { kind: 'ghost', sm: true, ic: pinned ? 'star-filled' : 'star', pressed: pinned })}
        </div>
      </div>
    </header>
    ${notes.length ? html`<div class="tool-notes">${notes.map(([tone, text]) => html`<div class="notice ${tone}">${icon(NOTE_ICON[tone])}<span>${text}</span></div>`)}</div>` : nothing}
    ${needPanel(t, d)}
    ${a0 ? section(others.length ? 'Việc chính' : 'Việc công cụ làm', others.length ? 'Việc hay dùng nhất của công cụ này.' : '',
      html`<div class="actions-list">${actionRow(t, a0, d, { main: true })}</div>`, { id: 'main-action' })
      : section('Việc công cụ làm', '', emptyState('warning', 'Chưa có việc nào', 'Khai báo actions trong tool.json.'))}
    ${others.length ? section('Các việc khác', 'Xếp theo mức an toàn. Mỗi việc mở trong một cửa sổ riêng, theo dõi ở thanh Đang chạy phía dưới.',
      html`<div class="agroups">${otherActions(t, others, d)}</div>`) : nothing}
    ${(t.probes || []).length ? section('Trạng thái hiện tại trên máy này', 'Chỉ đọc, không thay đổi gì.', html`<div class="panel">${probeRows(d)}</div>`,
      { tools: refresh('Đọc lại', () => loadProbes(t)) }) : nothing}
    ${(t.requires || []).length ? section('Yêu cầu để chạy', 'Trạm tự kiểm tra; thiếu gì có nút cài.',
      html`<div class="panel">${d.reqsErr ? kvNote('Lỗi', d.reqsErr) : d.reqs ? d.reqs.map((q) => reqRow(t, q)) : kvNote('', 'Đang kiểm tra...')}</div>`,
      { id: 'reqs', tools: refresh('Kiểm tra lại', () => recheck(t)) }) : nothing}
    ${(t.outputs || []).length ? section('Kết quả gần đây', 'File do công cụ tạo ra trên máy này, mới nhất ở trên.', outputsBlock(t, d),
      { id: 'outs', tools: deletable.length > 1 ? btn('Chọn để xoá', () => go(`#/outputs/${enc(t.id)}`), { kind: 'ghost', sm: true, ic: 'delete' }) : nothing }) : nothing}
    ${t.hasDocs ? section('Hướng dẫn', html`<span class="mono">${t.docs}</span>`, html`<article class="doc">${!d.docs ? html`<div class="skeleton" style="height:120px"></div>`
      : d.docs.error ? html`<p class="muted">${d.docs.error}</p>`
      : /\.txt$/i.test(d.docs.name || '') ? html`<pre class="doc-txt">${d.docs.text}</pre>` : unsafeHTML(renderMarkdown(d.docs.text))}</article>`, { id: 'docs' }) : nothing}
    ${!S.settings.simple && known ? section('', '', html`<details class="fold known">
      <summary><span class="agroup-title">${icon('chevron-right', 'ic-16')}Lỗi đã biết và hướng nâng cấp<span class="count">${known}</span></span>
        <span class="agroup-desc">Tóm tắt từ bản phân tích; chi tiết ở trang Phân tích và nâng cấp.</span></summary>
      <div class="two-col">
        <div class="col-block"><h3>${icon('warning', 'ic-16')}Lỗi, rủi ro đã biết</h3><ul class="list-plain">${(t.issues || []).length ? t.issues.map((x) => html`<li>${x}</li>`) : html`<li class="muted">Chưa ghi nhận.</li>`}</ul></div>
        <div class="col-block"><h3>${icon('lightbulb', 'ic-16')}Hướng nâng cấp</h3><ul class="list-plain">${(t.upgrades || []).length ? t.upgrades.map((x) => html`<li>${x}</li>`) : html`<li class="muted">Chưa có.</li>`}</ul></div>
      </div></details>`) : nothing}
  </div>`;
}
