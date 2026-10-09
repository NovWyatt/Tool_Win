// Trạm Tool - trang Phân tích và nâng cấp (docs\PHAN-TICH-NANG-CAP.md).
import { html } from '../../vendor/lit-html/lit-html.js';
import { unsafeHTML } from '../../vendor/lit-html/directives/unsafe-html.js';
import { S } from '../state.js';
import { pageHead } from '../parts.js';
import { loadRoadmap } from '../data.js';
import { renderMarkdown } from './tool.js';

export function roadmapLoad() { if (!S.roadmap) loadRoadmap(); }

export function roadmapPage() {
  const r = S.roadmap;
  return html`<div class="page">
    ${pageHead('Phân tích và nâng cấp', 'Đánh giá từng công cụ, lỗi đã biết và lộ trình nâng cấp. Nguồn: docs\\PHAN-TICH-NANG-CAP.md')}
    <article class="doc">${!r ? html`<div class="skeleton" style="height:160px"></div>`
      : r.error ? html`<p class="muted">${r.error}</p>` : unsafeHTML(renderMarkdown(r.text))}</article>
  </div>`;
}
