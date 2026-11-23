import assert from 'node:assert/strict';
import test from 'node:test';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { assertVersionIncrease, parseVersion } from '../script/check-version.mjs';

test('versions must use exactly three numeric components without leading zeroes', () => {
  for (const version of ['0.0.0', '1.0.0', '12.34.56']) assert.doesNotThrow(() => parseVersion(version));
  for (const version of ['', '1.2', 'v1.2.3', '01.2.3', '1.02.3', '1.2.03', '1.2.3-beta', '1.2.3+build', '1.2.3\n']) {
    assert.throws(() => parseVersion(version), /Invalid version/);
  }
});

test('numeric version ordering accepts patch, minor, and major increments', () => {
  for (const [before, after] of [['1.0.9', '1.0.10'], ['1.9.9', '1.10.0'], ['1.99.99', '2.0.0']]) {
    assert.doesNotThrow(() => assertVersionIncrease(before, after));
  }
});

test('unchanged and downgraded versions reject a changed release', () => {
  for (const after of ['1.2.3', '1.2.2', '1.1.99', '0.99.99']) {
    assert.throws(() => assertVersionIncrease('1.2.3', after), /Update VERSION/);
  }
});

test('the CI command checks committed changes and permits unchanged promotions', () => {
  const workspace = mkdtempSync(join(tmpdir(), 'pt-version-test-'));
  const checker = fileURLToPath(new URL('../script/check-version.mjs', import.meta.url));
  const git = (...args) => execFileSync('git', args, { cwd: workspace, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  const commit = () => {
    git('add', '.');
    git('-c', 'user.name=Version Test', '-c', 'user.email=version@example.test', '-c', 'commit.gpgsign=false', 'commit', '-m', 'Fixture');
    return git('rev-parse', 'HEAD');
  };
  const check = (base, head) => spawnSync(process.execPath, [checker], {
    cwd: workspace, encoding: 'utf8', env: { ...process.env, BASE_SHA: base, HEAD_SHA: head }
  });
  try {
    git('init', '--quiet');
    writeFileSync(join(workspace, 'app.txt'), 'original');
    const baseline = commit();
    writeFileSync(join(workspace, 'VERSION'), '1.0.0\n');
    const initial = commit();
    assert.equal(check(baseline, initial).status, 0, 'introducing versioning should pass');
    assert.equal(check(initial, initial).status, 0, 'an unchanged promotion should pass');

    writeFileSync(join(workspace, 'app.txt'), 'changed');
    const unchangedVersion = commit();
    assert.match(check(initial, unchangedVersion).stderr, /Update VERSION/);
    assert.equal(check(initial, unchangedVersion).status, 1);

    writeFileSync(join(workspace, 'VERSION'), '1.0.1\n');
    const patch = commit();
    assert.equal(check(initial, patch).status, 0, 'a changed release with a version bump should pass');

    writeFileSync(join(workspace, 'VERSION'), '1.0\n');
    const invalid = commit();
    assert.equal(check(patch, invalid).status, 1, 'invalid committed versions must fail');
  } finally {
    assert.equal(dirname(workspace), tmpdir());
    rmSync(workspace, { recursive: true, force: true });
  }
});
