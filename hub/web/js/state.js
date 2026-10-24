// Trạm Tool - trạng thái giao diện và các hàm đọc trạng thái dùng ở nhiều trang.
import { api, norm, local } from './core.js';

export const S = {
  hub: null,
  categories: [],
  tools: [],
  byId: new Map(),
  // Lưu ở máy chủ (hub\data\settings.json)
  settings: { browser: 'auto', autoExitMinutes: 10, pins: [], theme: local.get('themeCache', 'system'), simple: false, restorePoint: true },
  deps: {},
  depsLoaded: false,
  history: null, // null = chưa tải
  jobs: [],
  outputs: null,
  outSel: new Set(), // khoá "toolId|path" của các kết quả đang chọn
  system: null,
  systemAt: 0,
  toolData: {}, // id công cụ -> { reqs, probes, outs, docs, err }
  roadmap: null,
  route: { name: 'home' },
};

// ------------------------------------------------------------------ vẽ lại
// Mọi thay đổi gọi update(); nhiều thay đổi trong cùng một lượt xử lý chỉ vẽ một lần.
// Không dùng requestAnimationFrame: tab ở nền thì rAF dừng, quay lại sẽ thấy trạng thái cũ.
let renderer = () => {};
let queued = false;
export function setRenderer(fn) { renderer = fn; }
export function update() {
  if (queued) return;
  queued = true;
  queueMicrotask(() => { queued = false; renderer(); });
}

export function go(hash) {
  if (location.hash === hash) window.dispatchEvent(new HashChangeEvent('hashchange'));
  else location.hash = hash;
}

// Các trang của trạm (ngoài trang công cụ), dùng cho thanh bên và ô tìm nhanh.
export const PAGES = [
  { id: 'outputs', label: 'Kết quả gần đây', icon: 'document-search' },
  { id: 'history', label: 'Lịch sử chạy', icon: 'history' },
  { id: 'system', label: 'Máy này', icon: 'desktop-pulse' },
  { id: 'roadmap', label: 'Phân tích và nâng cấp', icon: 'map', tech: true },
  { id: 'settings', label: 'Cài đặt', icon: 'settings', bottom: true },
];

// ------------------------------------------------------------------ danh mục
export const RISK = {
  'read-only': { label: 'Chỉ đọc', color: 'success' },
  'asks-before-change': { label: 'Hỏi trước khi sửa', color: 'informative' },
  'modifies-system': { label: 'Thay đổi hệ thống', color: 'warning' },
};

export function catLabel(id, cats = S.categories) {
  return (cats.find((c) => c.id === id) || {}).label || 'Khác';
}

export function setCatalog(state) {
  S.hub = state.hub;
  S.categories = state.categories || [];
  S.tools = (state.tools || []).map((t) => ({
    ...t,
    _hay: norm([t.name, t.summary, t.description, (t.tags || []).join(' '),
      (t.actions || []).map((a) => `${a.label} ${a.file}`).join(' '), catLabel(t.category, state.categories)].join(' ')),
  }));
  S.byId = new Map(S.tools.map((t) => [t.id, t]));
  if (state.hub && state.hub.settings) applySettings(state.hub.settings);
}

export function applySettings(s) {
  S.settings = { ...S.settings, ...s, pins: Array.isArray(s.pins) ? s.pins : [] };
  local.set('themeCache', S.settings.theme); // chỉ để tô đúng màu ngay lúc mở, giá trị thật ở máy chủ
}

export async function saveSettings(patch) {
  applySettings({ ...S.settings, ...patch });
  update();
  const r = await api('/api/settings', { method: 'POST', body: patch });
  applySettings(r);
  update();
  return r;
}

export const visibleTools = () => S.tools.filter((t) => !S.settings.simple || t.audience !== 'tech');
export const isPinned = (id) => S.settings.pins.includes(id);
export const pinnedTools = () => S.settings.pins.map((id) => S.byId.get(id)).filter((t) => t && visibleTools().includes(t));

export async function togglePin(id) {
  const pins = isPinned(id) ? S.settings.pins.filter((x) => x !== id) : [...S.settings.pins, id];
  await saveSettings({ pins });
}

// Từ tìm ngắn (1-2 chữ, vd "in" trong "máy in") phải khớp đầu một từ, không thì "in" khớp cả "windows", "admin".
export function hayHas(hay, w) {
  if (w.length > 2) return hay.includes(w);
  return ` ${hay.replace(/[^a-z0-9]+/g, ' ')}`.includes(` ${w}`);
}

export function matches(tool, query) {
  const words = norm(query).split(/\s+/).filter(Boolean);
  return words.every((w) => hayHas(tool._hay, w));
}

export function depsStatus(tool) {
  const items = S.deps[tool.id];
  if (!items) return 'unknown';
  return items.some((r) => !r.ok && !r.optional) ? 'missing' : 'ok';
}
export const missingDeps = (tool) => (S.deps[tool.id] || []).filter((r) => !r.ok && !r.optional);

export function primaryAction(tool) {
  return (tool.actions || []).find((a) => a.primary) || (tool.actions || [])[0];
}

// Các việc còn lại trên trang công cụ, xếp theo mức an toàn để việc chỉ xem không nằm lẫn với việc đổi máy.
// tool.json có thể ghi "group" cho từng action; không ghi thì trạm đoán theo id và mức rủi ro.
export const ACTION_GROUPS = [
  { id: 'xem', title: 'Chỉ xem, không đổi gì', desc: 'Đọc thông tin hoặc tạo file kết quả mới. Chạy lúc nào cũng được.' },
  { id: 'sua', title: 'Có thay đổi', desc: 'Đổi cài đặt, dịch vụ hoặc file. Trạm hoặc cửa sổ công cụ hỏi lại trước khi đổi.' },
  { id: 'tra-lai', title: 'Trả lại như cũ', desc: 'Hoàn tác thay đổi của lần sửa trước.' },
  { id: 'cai-dat', title: 'Cài đặt môi trường chạy', desc: 'Chỉ cần khi trạm báo thiếu yêu cầu.' },
  { id: 'khac', title: 'Cách chạy khác', desc: 'Menu trong cửa sổ dòng lệnh, giống bấm đúp file .bat trong thư mục công cụ.' },
];

export function actionGroup(a) {
  if (ACTION_GROUPS.some((g) => g.id === a.group)) return a.group;
  if (/^menu/.test(a.id)) return 'khac';
  if (a.id === 'cai-dat') return 'cai-dat';
  if (/hoan-tac|tra-lai|khoi-phuc|mac-dinh|bat-lai/.test(a.id)) return 'tra-lai';
  return !a.risk || a.risk === 'read-only' ? 'xem' : 'sua';
}

// Yêu cầu còn thiếu của công cụ, gộp theo cách cài (nhiều yêu cầu cùng một action Cài đặt thì một nút).
export function missingFixes(tool, reqs = S.deps[tool.id]) {
  const out = [];
  for (const q of (reqs || []).filter((r) => !r.ok && !r.optional)) {
    const key = q.fix ? JSON.stringify(q.fix) : `none:${q.id || q.label}`;
    const same = out.find((x) => x.key === key);
    if (same) same.labels.push(q.label);
    else out.push({ key, req: q, fix: q.fix || null, labels: [q.label] });
  }
  return out;
}

// Lần chạy gần nhất của công cụ (và action nếu có) theo lịch sử.
export function lastRun(toolId, actionId = '') {
  return (S.history || []).find((h) => h.toolId === toolId && (!actionId || h.actionId === actionId)) || null;
}

// Trạng thái một lần chạy -> chữ + màu, dùng chung cho lịch sử, thanh Đang chạy, trang công cụ.
export function runState(h) {
  const dur = h.durationSec != null && h.state !== 'running' ? h.durationSec : null;
  switch (h.state) {
    case 'running': return { label: 'Đang chạy', color: 'brand', icon: 'window-console', dur };
    case 'done': return { label: 'Xong', color: 'success', icon: 'check-circle', dur };
    // Mã 2: thiếu điều kiện hoặc người dùng từ chối, công cụ chưa làm gì. Mã 3: làm được một phần.
    case 'blocked': return { label: 'Chưa làm', color: 'warning', icon: 'warning', dur };
    case 'partial': return { label: 'Làm được một phần', color: 'warning', icon: 'warning', dur };
    case 'failed': return { label: h.exitCode != null ? `Báo lỗi, mã ${h.exitCode}` : 'Báo lỗi', color: 'danger', icon: 'dismiss-circle', dur };
    case 'closed': return { label: 'Đã đóng cửa sổ', color: 'subtle', icon: 'dismiss', dur };
    case 'ended': return { label: 'Đã kết thúc', color: 'subtle', icon: 'checkmark', dur };
    case 'cancelled': return { label: 'Đã huỷ', color: 'subtle', icon: 'dismiss', dur: null };
    case 'error': return { label: 'Không mở được', color: 'danger', icon: 'warning', dur: null };
    default: return { label: 'Không rõ kết quả', color: 'subtle', icon: 'open', dur: null }; // lần chạy cũ, trạm chưa ghi kết quả
  }
}
