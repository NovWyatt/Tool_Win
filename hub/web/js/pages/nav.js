// Trạm Tool - thanh bên: tìm nhanh, Tổng quan, nhóm công cụ, các trang của trạm.
import { html, nothing } from '../../vendor/lit-html/lit-html.js';
import { icon, enc } from '../core.js';
import { S, go, visibleTools, PAGES, saveSettings } from '../state.js';
import { openPalette } from '../palette.js';
import { toast } from '../ui.js';

export function navTemplate() {
  const tools = visibleTools();
  const r = S.route;
  const cur = (cond) => (cond ? 'page' : nothing);
  const item = (hash, ic, label, active, count = null) => html`<button class="nav-item" aria-current=${cur(active)} @click=${() => go(hash)}>
    ${icon(ic)}<span>${label}</span>${count != null ? html`<span class="count">${count}</span>` : nothing}</button>`;
  const running = S.jobs.filter((j) => j.state === 'running').length;
  return html`
    <div class="brand">
      <span class="brand-mark">${icon('toolbox')}</span>
      <span class="brand-text"><strong>Trạm Tool</strong><small>Bộ công cụ Windows</small></span>
    </div>
    <button class="nav-search" @click=${() => openPalette()} aria-label="Tìm hoặc chạy (Ctrl+K)">
      ${icon('search', 'ic-16')}<span>Tìm hoặc chạy</span><span class="keys"><kbd>Ctrl</kbd><kbd>K</kbd></span>
    </button>
    <div class="nav-scroll">
      ${item('#/', 'home', 'Tổng quan', r.name === 'home', tools.length)}
      ${running ? html`<div class="nav-running" title="Số công cụ đang chạy"><span class="live-mark" aria-hidden="true"></span>Đang chạy ${running}</div>` : nothing}
      <div class="nav-group-title">Nhóm công cụ</div>
      ${S.categories.map((c) => {
        const n = tools.filter((t) => t.category === c.id).length;
        if (!n) return nothing;
        const active = (r.name === 'category' && r.id === c.id) || (r.name === 'tool' && S.byId.get(r.id)?.category === c.id);
        return item(`#/c/${enc(c.id)}`, c.icon, c.label, active, n);
      })}
      <div class="nav-group-title">Trạm</div>
      ${PAGES.filter((p) => !(p.tech && S.settings.simple)).map((p) => item(`#/${p.id}`, p.icon, p.label, r.name === p.id))}
    </div>
    <div class="nav-foot">
      <span title=${S.hub && S.hub.isAdmin ? 'Trạm đang chạy với quyền Admin' : 'Máy đang dùng trạm'}>${S.hub ? S.hub.computer : ''}${S.hub && S.hub.isAdmin ? ' (Admin)' : ''}</span>
      <label class="simple-toggle" title="Chế độ đơn giản: ẩn công cụ kỹ thuật">
        <span>Đơn giản</span>
        <input type="checkbox" role="switch" class="switch" .checked=${S.settings.simple} @change=${(e) => {
          const on = !!e.target.checked;
          if (on === S.settings.simple) return;
          saveSettings({ simple: on }).then(() => toast('info', on ? 'Đã bật chế độ đơn giản: ẩn công cụ kỹ thuật.' : 'Đã tắt chế độ đơn giản.', { ms: 2500 }))
            .catch((err) => toast('error', err.message));
        }}>
      </label>
    </div>`;
}
