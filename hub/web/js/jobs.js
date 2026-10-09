// Trạm Tool - thanh "Đang chạy": các cửa sổ công cụ mở từ trạm, thời gian chạy, kết quả khi cửa sổ đóng.
// Máy chủ chỉ xử lý một yêu cầu một lúc nên hỏi định kỳ (2 giây/lần) và chỉ hỏi khi còn công cụ đang chạy.
import { html, nothing } from '../vendor/lit-html/lit-html.js';
import { repeat } from '../vendor/lit-html/directives/repeat.js';
import { api, icon, enc, fmtElapsed, fmtDuration } from './core.js';
import { S, update, go, runState } from './state.js';
import { toast } from './ui.js';
import { resultSentence, resultTone, showResult } from './result.js';
import { loadToolOutputs, loadServer, hasWebServer } from './data.js';

let pollTimer = null;
let tickTimer = null;
const seenDone = new Set();
// Việc vừa mở từ trang này: vẫn báo kết quả khi nó xong trước cả lần hỏi đầu tiên (công cụ chạy vài giây).
const watching = new Set();
export function watchJob(id) { if (id) watching.add(id); }

const elapsed = (j) => (Date.now() - Date.parse(j.time)) / 1000;
const running = () => S.jobs.filter((j) => j.state === 'running');

export async function refreshJobs() {
  let items;
  try { items = (await api('/api/jobs')).items || []; } catch { return; }
  const before = new Map(S.jobs.map((j) => [j.id, j.state]));
  S.jobs = items;
  for (const j of items) {
    if (j.state === 'running') continue;
    // Công cụ vừa đóng: báo nếu chạy lâu (người dùng có thể đã quay sang việc khác) hoặc báo lỗi.
    const was = before.get(j.id) === 'running' || watching.has(j.id);
    watching.delete(j.id);
    if (was && !seenDone.has(j.id)) {
      seenDone.add(j.id);
      onFinished(j);
    }
  }
  schedule();
  update();
}

function onFinished(j) {
  const t = S.byId.get(j.toolId);
  // Kết quả mới có thể đã được tạo: trang công cụ đang mở thì tải lại ngay, trang khác tải lại khi mở.
  S.outputs = null;
  if (t && S.route.name === 'tool' && S.route.id === t.id) {
    if ((t.outputs || []).length) loadToolOutputs(t);
    if (hasWebServer(t)) loadServer(t);
  } else if (S.toolData[j.toolId]) S.toolData[j.toolId].outs = null;
  api('/api/history').then((h) => { S.history = h.items || []; update(); }).catch(() => {});
  const k = j.ketQua;
  if (k) {
    // Công cụ ghi file kết quả: báo luôn tìm thấy gì, kể cả khi chạy nhanh.
    const tone = resultTone(k);
    const st = runState(j);
    toast(tone === 'danger' ? 'error' : tone === 'warn' ? 'warning' : 'success',
      `${j.toolName}: ${j.actionLabel} ${st.label.toLowerCase()}. ${resultSentence(k)}`, {
        ms: tone === 'ok' ? 8000 : 15000, action: { label: 'Xem chi tiết', run: () => showResult(j.toolId, k.path) },
      });
  } else if (j.state === 'failed') {
    toast('error', `${j.toolName}: ${j.actionLabel} báo lỗi (mã ${j.exitCode}) sau ${fmtDuration(j.durationSec)}.`, {
      ms: 12000, action: { label: 'Mở công cụ', run: () => go(`#/tool/${enc(j.toolId)}`) },
    });
  } else if (j.state === 'blocked' || j.state === 'partial') {
    toast('warning', `${j.toolName}: ${j.actionLabel} ${runState(j).label.toLowerCase()} (mã ${j.exitCode}). Xem lời báo trong cửa sổ công cụ.`, {
      ms: 12000, action: { label: 'Mở công cụ', run: () => go(`#/tool/${enc(j.toolId)}`) },
    });
  } else if (j.durationSec >= 30 && j.state === 'done') {
    const hasOut = t && (t.outputs || []).length;
    toast('success', `${j.toolName}: ${j.actionLabel} đã xong sau ${fmtDuration(j.durationSec)}.`, {
      ms: 12000, action: hasOut ? { label: 'Xem kết quả', run: () => go(`#/tool/${enc(j.toolId)}`) } : null,
    });
  }
}

function schedule() {
  const busy = running().length > 0;
  if (busy && !pollTimer) pollTimer = setInterval(refreshJobs, 2000);
  if (!busy && pollTimer) { clearInterval(pollTimer); pollTimer = null; }
  // Đồng hồ trên thanh chạy từng giây, không cần hỏi máy chủ.
  if (busy && !tickTimer) tickTimer = setInterval(update, 1000);
  if (!busy && tickTimer) { clearInterval(tickTimer); tickTimer = null; }
}

async function dismiss(ids, all = false) {
  try {
    await api('/api/jobs/dismiss', { method: 'POST', body: all ? { all: true } : { ids } });
    S.jobs = S.jobs.filter((j) => j.state === 'running' || (!all && !ids.includes(j.id)));
    update();
  } catch (e) { toast('error', e.message); }
}

async function focusJob(j) {
  try { await api('/api/jobs/focus', { method: 'POST', body: { id: j.id } }); } catch (e) { toast('warning', e.message); }
}

function jobItem(j) {
  const t = S.byId.get(j.toolId);
  const st = runState(j);
  const live = j.state === 'running';
  return html`<div class="job ${live ? 'live' : `end ${st.color}`}">
    <button class="job-main" title="Mở trang công cụ" @click=${() => go(`#/tool/${enc(j.toolId)}`)}>
      ${live ? html`<span class="live-mark" role="img" aria-label="Đang chạy"></span>` : html`<span class="job-ic">${icon(st.icon, 'ic-16')}</span>`}
      <span class="job-text">
        <span class="job-name">${t ? t.name : j.toolName}</span>
        <span class="job-sub">${j.actionLabel}</span>
      </span>
      <span class="job-time">${live ? fmtElapsed(elapsed(j)) : `${st.label}${st.dur != null ? ` sau ${fmtDuration(st.dur)}` : ''}`}</span>
    </button>
    ${live && !j.elevated && !j.selfElevates ? html`<button class="icon-btn sm" title="Hiện cửa sổ công cụ" aria-label="Hiện cửa sổ" @click=${() => focusJob(j)}>${icon('open', 'ic-16')}</button>` : nothing}
    ${live && (j.elevated || j.selfElevates) ? html`<span class="job-shield" title=${j.selfElevates ? 'Công cụ tự xin quyền Admin' : 'Chạy với quyền Admin'}>${icon('shield', 'ic-16')}</span>` : nothing}
    ${!live ? html`<button class="icon-btn sm" title="Ẩn khỏi thanh này" aria-label="Ẩn" @click=${() => dismiss([j.id])}>${icon('dismiss', 'ic-16')}</button>` : nothing}
  </div>`;
}

export function dockTemplate() {
  if (!S.jobs.length) return nothing;
  const live = running().length;
  const done = S.jobs.length - live;
  // Một hàng (cuộn ngang khi chật): việc đang chạy đứng đầu, rồi việc vừa xong, mới nhất trước.
  const ordered = [...running(), ...S.jobs.filter((j) => j.state !== 'running')];
  return html`<div class="dock" role="region" aria-label="Công cụ đang chạy">
    <div class="dock-head">
      ${icon('window-console', 'ic-16')}
      <span>${live ? `Đang chạy ${live}` : 'Đã chạy xong'}</span>
      ${done > 1 ? html`<button class="link-btn" @click=${() => dismiss([], true)}>Ẩn ${done} việc đã xong</button>` : nothing}
    </div>
    <div class="dock-list">${repeat(ordered.slice(0, 8), (j) => j.id, jobItem)}</div>
  </div>`;
}
