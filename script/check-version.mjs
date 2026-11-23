import { execFileSync, spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

export function parseVersion(value) {
  if (!/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(value) || value !== value.trim()) {
    throw new Error(`Invalid version ${JSON.stringify(value)}; use MAJOR.MINOR.PATCH without prefixes, suffixes, or leading zeroes.`);
  }
  return value.split('.').map(BigInt);
}

export function assertVersionIncrease(previous, current) {
  const before = parseVersion(previous);
  const after = parseVersion(current);
  for (let index = 0; index < 3; index++) {
    if (after[index] > before[index]) return;
    if (after[index] < before[index]) break;
  }
  throw new Error(`Update VERSION for this change: ${current} must be greater than ${previous}.`);
}

export function checkVersion(base, head) {
  for (const ref of [base, head]) {
    if (!/^[a-f0-9]{40}$/.test(ref ?? '')) throw new Error('Expected a full Git commit SHA for version comparison.');
  }
  const current = execFileSync('git', ['show', `${head}:VERSION`], { encoding: 'utf8' }).trim();
  parseVersion(current);
  if (/^0+$/.test(base)) return console.log(`Initial version: ${current}`);

  execFileSync('git', ['cat-file', '-e', `${base}^{commit}`]);
  const changed = execFileSync('git', ['diff', '--name-only', base, head], { encoding: 'utf8' }).trim();
  if (!changed) return console.log(`No file changes; retaining version ${current}.`);

  const previousFile = spawnSync('git', ['show', `${base}:VERSION`], { encoding: 'utf8' });
  if (previousFile.error) throw previousFile.error;
  const previous = previousFile.status === 0 ? previousFile.stdout.trim() : '0.0.0';
  assertVersionIncrease(previous, current);
  console.log(`Version check passed: ${previous} -> ${current}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    checkVersion(process.env.BASE_SHA, process.env.HEAD_SHA);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
