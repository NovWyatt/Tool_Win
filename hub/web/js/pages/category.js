// Trạm Tool - trang một nhóm công cụ.
import { html } from '../../vendor/lit-html/lit-html.js';
import { S, visibleTools } from '../state.js';
import { pageHead, toolRow, emptyState } from '../parts.js';
import { homePage } from './home.js';

export function categoryPage(id) {
  const c = S.categories.find((x) => x.id === id);
  if (!c) return homePage();
  const tools = visibleTools().filter((t) => t.category === id);
  return html`<div class="page">
    ${pageHead(c.label, c.description)}
    <div class="cat-list">${tools.length ? tools.map((t) => toolRow(t)) : emptyState('toolbox', 'Nhóm này chưa có công cụ', 'Có thể công cụ đang bị ẩn do chế độ đơn giản.')}</div>
  </div>`;
}
