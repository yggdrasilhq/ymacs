#!/usr/bin/env node
import { chmodSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';

for (const p of [resolve(join('bin', 'ymacs')), resolve(join('ymacs-bin'))]) {
  if (existsSync(p)) chmodSync(p, 0o755);
}
console.log("ymacs finalize: permissions set");
