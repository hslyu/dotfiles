import { accessSync, constants, readFileSync, realpathSync } from 'node:fs';
import { basename, join } from 'node:path';

export function resolveNativeCodex({ runtimeDirectory, home, native = process.env.CODEX_FALLBACK_NATIVE } = {}) {
  let saved;
  try { saved = readFileSync(join(runtimeDirectory, '.native-codex'), 'utf8').trim(); } catch {}
  for (const candidate of [native, saved, join(home, '.local/lib/node_modules/@openai/codex/bin/codex.js')].filter(Boolean)) {
    try {
      const path = realpathSync(candidate);
      if (['codex-fallback', 'codex-fallback.mjs', 'codex-native'].includes(basename(path))) throw new Error('Native Codex points to a launcher itself');
      accessSync(path, constants.X_OK);
      const prefix = readFileSync(path).subarray(0, 2048).toString();
      if (prefix.startsWith('#!') && /codex-fallback\.mjs/.test(prefix)) throw new Error('Native Codex points to the router itself');
      return path;
    } catch (error) {
      if (candidate === native) throw error;
    }
  }
  throw new Error('Native Codex not found. Run dotfiles/codex/install-fallback.sh after installing the Codex CLI.');
}
