import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync, cpSync, unlinkSync, symlinkSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { resolveNativeCodex } from './native.mjs';

const source = dirname(fileURLToPath(import.meta.url));
function fixture(t) {
  const directory = mkdtempSync(join(tmpdir(), 'codex install '));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const native = join(directory, 'native-cli');
  const content = '#!/usr/bin/env node\nconsole.log(JSON.stringify({args:process.argv.slice(2),home:process.env.CODEX_HOME}));\n';
  writeFileSync(native, content, { mode: 0o755 });
  return { directory, native, content };
}

test('native resolution uses a machine-local pointer, falls back after a missing pointer, rejects recursion', t => {
  const { directory, native } = fixture(t);
  writeFileSync(join(directory, '.native-codex'), native);
  assert.equal(resolveNativeCodex({ runtimeDirectory: directory, home: directory, native: '' }), native);
  const fallback = join(directory, '.local/lib/node_modules/@openai/codex/bin');
  mkdirSync(fallback, { recursive: true });
  symlinkSync(native, join(fallback, 'codex.js'));
  writeFileSync(join(directory, '.native-codex'), '/nonexistent/native');
  assert.equal(resolveNativeCodex({ runtimeDirectory: directory, home: directory, native: '' }), native);
  const wrapper = join(directory, 'codex');
  writeFileSync(wrapper, '#!/bin/sh\nexec node /some/codex-fallback.mjs "$@"\n', { mode: 0o755 });
  assert.throws(() => resolveNativeCodex({ runtimeDirectory: directory, home: directory, native: wrapper }), /router itself/);
});

test('installation handles spaces, accounts, repeated installs and npm replacing its entry without touching native/config', t => {
  const { directory, native, content } = fixture(t);
  const prefix = join(directory, 'custom prefix');
  const runtime = join(prefix, 'share/codex-fallback');
  const bin = join(prefix, 'bin');
  mkdirSync(join(runtime, 'node_modules'), { recursive: true });
  cpSync(join(source, 'node_modules/ws'), join(runtime, 'node_modules/ws'), { recursive: true });
  writeFileSync(join(runtime, 'disabled'), 'keep');
  const personal = join(directory, 'personal account');
  mkdirSync(personal);
  writeFileSync(join(personal, 'config.toml'), 'keep configuration');
  writeFileSync(join(personal, 'auth.json'), 'keep authentication');
  const env = { ...process.env, CODEX_PERSONAL_HOME: personal, CODEX2_HOME: join(directory, 'second account') };
  const install = () => {
    const result = spawnSync('bash', [join(source, '../install-fallback.sh'), '--prefix', prefix, '--native', native, '--no-shell'], { encoding: 'utf8', env });
    assert.equal(result.status, 0, result.stderr + result.stdout);
  };
  const run = (name, args) => {
    const result = spawnSync(join(bin, name), args, { encoding: 'utf8', env });
    assert.equal(result.status, 0, result.stderr);
    return JSON.parse(result.stdout);
  };
  install();
  assert.deepEqual(run('codex', ['exec', 'two words']).args, ['exec', 'two words']);
  assert.equal(run('codex-personal', ['--version']).home, personal);
  assert.deepEqual(run('codex2', ['--version']).args, ['--dangerously-bypass-approvals-and-sandbox', '--version']);
  assert.deepEqual(run('codex-native', ['one argument']).args, ['one argument']);
  install();
  unlinkSync(join(bin, 'codex'));
  symlinkSync(native, join(bin, 'codex'));
  install();
  assert.equal(realpathSync(join(bin, 'codex')), join(bin, 'codex-fallback'));
  assert.equal(readFileSync(native, 'utf8'), content);
  assert.equal(readFileSync(join(runtime, 'disabled'), 'utf8'), 'keep');
  assert.equal(readFileSync(join(personal, 'config.toml'), 'utf8'), 'keep configuration');
  assert.equal(readFileSync(join(personal, 'auth.json'), 'utf8'), 'keep authentication');
  const shell = spawnSync('bash', ['-c', '. "$1"; codex --version', 'bash', join(runtime, 'shell.sh')], { encoding: 'utf8', env });
  assert.equal(shell.status, 0, shell.stderr);
  assert.deepEqual(JSON.parse(shell.stdout).args, ['--version']);
});
