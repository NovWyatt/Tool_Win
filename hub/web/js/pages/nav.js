// Trạm Tool - thanh bên: tìm nhanh, Tổng quan, nhóm công cụ, các trang của trạm; Cài đặt ở chân (như Windows).
import { html, nothing } from '../../vendor/lit-html/lit-html.js';
import { icon, enc } from '../core.js';
import { S, go, visibleTools, PAGES } from '../state.js';
import { openPalette } from '../palette.js';

export function navTemplate() {
  const tools = visibleTools();
  const r = S.route;
  const cur = (cond) => (cond ? 'page' : nothing);
  const item = (hash, ic, label, active, count = null) => html`<button class="nav-item" aria-current=${cur(active)} @click=${() => go(hash)}>
    ${icon(ic)}<span>${label}</span>${count != null ? html`<span class="count">${count}</span>` : nothing}</button>`;
  const running = S.jobs.filter((j) => j.state === 'running').length;
  const pages = PAGES.filter((p) => !(p.tech && S.settings.simple));
  return html`
    <div class="brand">
      <span class="brand-mark">${icon('toolbox')}</span>
      <span class="brand-text"><strong>Trạm Tool</strong><small>Bộ công cụ Windows</small></span>
    </div>
    <button class="nav-search" @click=${() => openPalette()} aria-label="Tìm nhanh công cụ, việc, trang (Ctrl+K)">
      ${icon('search', 'ic-16')}<span>Tìm nhanh</span><span class="keys"><kbd>Ctrl</kbd><kbd>K</kbd></span>
    </button>
    <div class="nav-scroll">
      ${item('#/', 'home', 'Tổng quan', r.name === 'home')}
      ${running ? html`<div class="nav-running" title="Theo dõi ở thanh Đang chạy phía dưới"><span class="live-mark" aria-hidden="true"></span>Đang chạy ${running} việc</div>` : nothing}
      <div class="nav-group-title">Nhóm công cụ</div>
      ${S.categories.map((c) => {
        const n = tools.filter((t) => t.category === c.id).length;
        if (!n) return nothing;
        const active = (r.name === 'category' && r.id === c.id) || (r.name === 'tool' && S.byId.get(r.id)?.category === c.id);
        return item(`#/c/${enc(c.id)}`, c.icon, c.label, active, n);
      })}
      <div class="nav-group-title">Trạm</div>
      ${pages.filter((p) => !p.bottom).map((p) => item(`#/${p.id}`, p.icon, p.label, r.name === p.id))}
    </div>
    <div class="nav-foot">
      ${pages.filter((p) => p.bottom).map((p) => item(`#/${p.id}`, p.icon, p.label, r.name === p.id))}
      <div class="nav-host" title=${S.hub && S.hub.isAdmin ? 'Trạm đang chạy với quyền Admin' : 'Máy đang dùng trạm'}>
        ${S.hub ? `${S.hub.computer}${S.hub.isAdmin ? ' (Admin)' : ''}` : ''}${S.hub ? html`<span>${S.hub.version}</span>` : nothing}
      </div>
    </div>`;
}
