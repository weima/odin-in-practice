import { readdirSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const source = resolve('docs/diagrams');
const target = resolve('docs/assets/diagrams');
mkdirSync(target, { recursive: true });
for (const name of readdirSync(source).filter(name => name.endsWith('.mmd')).sort()) {
  const result = spawnSync(resolve('node_modules/.bin/mmdc'), [
    '--input', resolve(source, name),
    '--output', resolve(target, name.replace(/\.mmd$/, '.svg')),
    '--configFile', resolve('tools/mermaid.json'),
    '--backgroundColor', 'white',
  ], { stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}
