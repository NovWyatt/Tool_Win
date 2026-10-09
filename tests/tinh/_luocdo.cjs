// Kiểm mọi tools/<id>/tool.json theo hub/schema/tool.schema.json bằng Ajv. In mỗi dòng: "OK <id>" hoặc
// "FAIL <id> <lỗi>". Gọi: node _luocdo.cjs <thư mục repo> <thư mục chứa node_modules>
const fs = require('fs');
const path = require('path');
const root = process.argv[2];
const modules = process.argv[3];
const Ajv = require(path.join(modules, 'node_modules', 'ajv'));
const addFormats = require(path.join(modules, 'node_modules', 'ajv-formats'));
const strip = s => s.replace(/^﻿/, '');
const schema = JSON.parse(strip(fs.readFileSync(path.join(root, 'hub', 'schema', 'tool.schema.json'), 'utf8')));
const ajv = new Ajv({ allErrors: true, strict: false });
addFormats(ajv);
const validate = ajv.compile(schema);
const toolsDir = path.join(root, 'tools');
for (const d of fs.readdirSync(toolsDir).sort()) {
  const p = path.join(toolsDir, d, 'tool.json');
  if (!fs.existsSync(p)) continue;
  let data;
  try { data = JSON.parse(strip(fs.readFileSync(p, 'utf8'))); } catch (e) { console.log('FAIL ' + d + ' JSON: ' + e.message); continue; }
  if (validate(data)) { console.log('OK ' + d); continue; }
  const errs = validate.errors.slice(0, 5).map(e => (e.instancePath || '/') + ' ' + e.message + ' ' + JSON.stringify(e.params));
  console.log('FAIL ' + d + ' ' + errs.join(' | '));
}
