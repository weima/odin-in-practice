import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const source = await readFile(new URL('../docs/assets/font-size.js', import.meta.url), 'utf8');
const storage = new Map();
function page() {
  const content = { style: { setProperty: (_, value) => { content.size = value; } }, prepend: (controls) => { content.controls = controls; } };
  const context = {
    document: {
      querySelector: () => content,
      createElement: () => ({ attrs: {}, setAttribute(name, value) { this.attrs[name] = value; }, addEventListener(_, fn) { this.click = fn; }, append(...items) { this.items = items; } }),
    },
    localStorage: { getItem: (key) => storage.get(key) ?? null, setItem: (key, value) => storage.set(key, value) },
  };
  vm.runInNewContext(source, context);
  return content.controls.items;
}
let [down, up] = page();
assert.equal(down.disabled, true);
for (let i = 0; i < 10; i++) up.click();
assert.equal(storage.get('odin-book-font-size'), '24');
assert.equal(up.disabled, true);
[down, up] = page();
assert.equal(up.disabled, true, 'size persists across page loads');
for (let i = 0; i < 10; i++) down.click();
assert.equal(storage.get('odin-book-font-size'), '16');
assert.equal(down.disabled, true);
console.log('Font controls: 16–24px bounds and persistence across page loads pass');
