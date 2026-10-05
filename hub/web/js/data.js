// Trạm Tool - tải dữ liệu từ máy chủ vào S rồi vẽ lại. Trang nào cần gì thì gọi hàm tương ứng.
import { api } from './core.js';
import { S, update, setCatalog } from './state.js';
import { toast } from './ui.js';

// Trang khác gọi cùng một thứ khi nó đang tải thì dùng chung lần gọi đó (máy chủ xử lý từng yêu cầu một).
const inflight = new Map();
function shared(key, fn) {
  if (!inflight.has(key)) inflight.set(key, fn().finally(() => inflight.delete(key)));
  return inflight.get(key);
}

export const loadHistory = () => shared('history', async () => {
  try { S.history = (await api('/api/history')).items || []; } catch { S.history = S.history || []; }
  update();
});

export const loadDepsAll = (fresh = false) => shared(`deps-all${fresh ? '-fresh' : ''}`, async () => {
  try {
    const all = await api(`/api/deps-all${fresh ? '?fresh=1' : ''}`);
    S.deps = { ...S.deps, ...all };
    S.depsLoaded = true;
    update();
  } catch { /* hiện lỗi ở trang chi tiết */ }
});

// Thông tin máy đọc bằng CIM mất 1-2 giây: giữ 5 phút, bấm Đọc lại thì đọc mới.
export async function loadSystem(fresh = false) {
  if (!fresh && S.system && !S.system.error && Date.now() - S.systemAt < 300000) return;
  await shared(`system${fresh ? '-fresh' : ''}`, async () => {
    try {
      S.system = await api(`/api/system${fresh ? '?fresh=1' : ''}`);
      S.systemAt = Date.now();
    } catch (e) { S.system = { error: e.message }; }
    update();
  });
}

export const loadOutputs = () => shared('outputs', async () => {
  try { S.outputs = (await api('/api/outputs')).items || []; } catch (e) { S.outputs = []; toast('error', e.message); }
  update();
});

const td = (id) => (S.toolData[id] = S.toolData[id] || {});

export async function loadToolOutputs(t) {
  try { td(t.id).outs = (await api(`/api/outputs?id=${encodeURIComponent(t.id)}`)).items || []; } catch (e) { td(t.id).outs = []; td(t.id).outsErr = e.message; }
  update();
}

export async function loadReqs(t, fresh = false) {
  try {
    const r = await api(`/api/deps?id=${encodeURIComponent(t.id)}${fresh ? '&fresh=1' : ''}`);
    td(t.id).reqs = r.items;
    td(t.id).reqsErr = '';
    S.deps[t.id] = r.items;
  } catch (e) { td(t.id).reqsErr = e.message; }
  update();
}

export async function loadProbes(t) {
  td(t.id).probes = null;
  update();
  try { td(t.id).probes = (await api(`/api/probes?id=${encodeURIComponent(t.id)}`)).items; td(t.id).probesErr = ''; } catch (e) { td(t.id).probesErr = e.message; td(t.id).probes = []; }
  update();
}

export async function loadDocs(t) {
  try {
    const r = await api(`/api/docs?id=${encodeURIComponent(t.id)}`);
    td(t.id).docs = { name: r.name, text: r.markdown };
  } catch (e) { td(t.id).docs = { error: e.message }; }
  update();
}

export async function loadToolExtras(t) {
  const jobs = [];
  if ((t.requires || []).length) jobs.push(loadReqs(t));
  if ((t.probes || []).length) jobs.push(loadProbes(t));
  if ((t.outputs || []).length) jobs.push(loadToolOutputs(t));
  if (t.hasDocs && !td(t.id).docs) jobs.push(loadDocs(t));
  await Promise.allSettled(jobs);
}

export async function loadRoadmap() {
  try { S.roadmap = { text: (await api('/api/doc?name=PHAN-TICH-NANG-CAP')).markdown }; } catch (e) { S.roadmap = { error: e.message }; }
  update();
}

export async function reloadCatalog(silent = false) {
  try {
    await api('/api/reload', { method: 'POST' });
    setCatalog(await api('/api/state'));
    S.deps = {};
    S.toolData = {};
    S.outputs = null;
    update();
    loadDepsAll();
    if (!silent) toast('success', `Đã quét lại: ${S.tools.length} công cụ.`, { ms: 3000 });
  } catch (e) { toast('error', e.message); }
}
