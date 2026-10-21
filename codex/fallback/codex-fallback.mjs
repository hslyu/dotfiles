#!/usr/bin/env node
// Local, per-CLI-connection capacity fallback. The Codex runtime stays unchanged.
import { spawn, spawnSync } from 'node:child_process';
import { readFileSync, mkdtempSync, rmSync, chmodSync, existsSync, lstatSync, readlinkSync, symlinkSync, renameSync } from 'node:fs';
import { createServer } from 'node:http';
import { connect } from 'node:net';
import { tmpdir, homedir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { WebSocket, WebSocketServer } from 'ws';
import { RoutingPolicy, routeParams, stageKey, sameStage, isCapacityError } from './routing.mjs';
import { CapacityMonitor } from './monitor.mjs';
import { resolveNativeCodex } from './native.mjs';

const RUNTIME_DIRECTORY = dirname(fileURLToPath(import.meta.url));
const REAL_CODEX = resolveNativeCodex({ runtimeDirectory: RUNTIME_DIRECTORY, home: homedir() });
const DISABLED_FILE = join(RUNTIME_DIRECTORY, 'disabled');
const CONTINUE = '앞선 턴이 모델 용량 부족으로 중단되었습니다. 지금까지의 대화와 실제 작업 상태를 확인하고 원래 요청을 이어서 완료하세요. 이미 끝낸 작업은 반복하지 마세요.';
export { isCapacityError } from './routing.mjs';

// The remote TUI prints its temporary proxy URL in reconnect instructions.
// Reconnect through a fresh proxy, including when the user copies that command.
export function reconnectArgs(args) {
  const ownAddress = value => /^unix:\/\/\/tmp\/codex-fallback-[A-Za-z0-9]+\/control\.sock$/.test(value);
  const normalized = [];
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--remote' && ownAddress(args[i + 1] ?? '')) { i++; continue; }
    if (args[i].startsWith('--remote=') && ownAddress(args[i].slice('--remote='.length))) continue;
    normalized.push(args[i]);
  }
  return normalized;
}

export function shouldWrap(args, env = process.env, tty = Boolean(process.stdin.isTTY && process.stdout.isTTY)) {
  if (!tty || env.CODEX_FALLBACK_DISABLE === '1') return false;
  const bypass = ['-h', '--help', '-V', '--version', '--remote', '--no-daemon', '--oss', '--worktree'];
  if (args.some(arg => bypass.includes(arg) || arg.startsWith('--remote='))) return false;
  const valueOptions = new Set(['-c', '--config', '--enable', '--disable', '-i', '--image',
    '-m', '--model', '-p', '--profile', '-s', '--sandbox', '-C', '--cd', '--add-dir',
    '-a', '--ask-for-approval', '--remote-auth-token-env']);
  const commands = new Set(['agents', 'exec', 'e', 'review', 'login', 'logout', 'mcp', 'plugin',
    'app-server', 'remote-control', 'completion', 'update', 'doctor', 'sandbox', 'debug',
    'apply', 'a', 'queue', 'archive', 'delete', 'migrate-rollouts', 'unarchive', 'cloud',
    'exec-server', 'features', 'help']);
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--') return true;
    if (valueOptions.has(args[i])) { i++; continue; }
    if (args[i].startsWith('-')) continue;
    return !commands.has(args[i]);
  }
  return true;
}

// Remote new threads otherwise inherit the shared daemon's working directory.
export function defaultDirectoryArgs(args, cwd = process.cwd()) {
  const valueOptions = new Set(['-c', '--config', '--enable', '--disable', '-i', '--image',
    '-m', '--model', '-p', '--profile', '-s', '--sandbox', '--add-dir',
    '-a', '--ask-for-approval', '--remote-auth-token-env']);
  let commandSeen = false;
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--') break;
    if (arg === '-C' || arg === '--cd' || arg.startsWith('--cd=') || /^-C.+/.test(arg)) return args;
    if (valueOptions.has(arg)) { i++; continue; }
    if (!arg.startsWith('-') && !commandSeen) {
      if (arg === 'resume' || arg === 'fork') return args;
      commandSeen = true;
    }
  }
  return ['--cd', cwd, ...args];
}

// Managed workspace defaults outrank config.toml; new sessions need explicit
// overrides. Preserve saved sessions and any model/profile chosen by the user.
export function defaultModelArgs(args) {
  if (!shouldWrap(args, {}, true)) return args;
  const valueOptions = new Set(['-c', '--config', '--enable', '--disable', '-i', '--image',
    '-m', '--model', '-p', '--profile', '-s', '--sandbox', '-C', '--cd', '--add-dir',
    '-a', '--ask-for-approval', '--remote-auth-token-env']);
  let selectedModel = false;
  let selectedTier = false;
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--') break;
    if (/^(?:-m|-p|--model|--profile)(?:=|$)/.test(arg)
        || /^-[mp].+/.test(arg)) selectedModel = true;
    const config = arg === '-c' || arg === '--config' ? args[i + 1]
      : arg.startsWith('--config=') ? arg.slice(9)
      : arg.startsWith('-c') ? arg.slice(2) : null;
    if (/^\s*(?:model|model_reasoning_effort)\s*=/.test(config ?? '')) selectedModel = true;
    if (/^\s*service_tier\s*=/.test(config ?? '')) selectedTier = true;
    if (valueOptions.has(arg)) { i++; continue; }
    if (!arg.startsWith('-')) {
      if (arg === 'resume' || arg === 'fork') return args;
      break;
    }
  }
  return [
    ...(!selectedModel ? ['-c', 'model="gpt-6.1-sol"', '-c', 'model_reasoning_effort="medium"'] : []),
    ...(!selectedTier ? ['-c', 'service_tier="fast"'] : []),
    ...args,
  ];
}

export class CapacityFallback {
  constructor(sendServer, sendClient, { policy = new RoutingPolicy(), monitor = null,
    recheckMs = 60000, settleMs = 50 } = {}) {
    this.sendServer = sendServer;
    this.sendClient = sendClient;
    this.policy = policy;
    this.monitor = monitor ?? { refreshCatalog: async () => {}, probe: async () => ({ status: 'unknown' }),
      record: () => {}, probeThreads: new Set() };
    this.recheckMs = recheckMs;
    this.settleMs = settleMs;
    this.requests = new Map();
    this.internal = new Map();
    this.threads = new Map();
    this.handled = new Set();
    this.errors = new Map();
    this.sequence = 0;
    this.closed = false;
  }

  state(id) {
    if (!this.threads.has(id)) this.threads.set(id, { counts: new Map(), cancelled: false,
      generation: 0, active: false, degraded: false, waiting: false, stage: null,
      goalActive: false, goalRevision: 0, recoveringGoal: false, blockedTurnId: null,
      params: { threadId: id } });
    return this.threads.get(id);
  }

  updateGoal(state, goal, turnId = null) {
    ++state.goalRevision;
    const active = goal?.status === 'active';
    // Goal reads may replay the daemon's blocked snapshot while recovery is
    // pending. Only an explicit stop or a new mutation can cancel that work.
    if (goal?.status === 'blocked' && !turnId && (state.recoveringGoal || state.blockedTurnId)) return;
    // Native Goal failures emit blocked before error/turn/completed. Retain only
    // that running turn as a candidate; its terminal capacity error must confirm
    // recovery eligibility. Other blocks and explicit stops remain final.
    if (goal?.status === 'blocked' && turnId && (!state.turnId || turnId === state.turnId)
        && (state.goalActive || state.recoveringGoal) && !state.cancelled) {
      state.goalActive = false;
      state.turnId = turnId;
      state.blockedTurnId = turnId;
      return;
    }
    if ((state.goalActive || state.recoveringGoal || state.blockedTurnId) && !active) {
      ++state.generation; state.cancelled = true; state.waiting = false;
      state.degraded = false;
      this.cancelTimers(state);
    } else if (active && !state.goalActive) state.cancelled = false;
    state.goalActive = active;
    state.recoveringGoal = false;
    state.blockedTurnId = null;
  }

  control(method, params) {
    const id = `codex-fallback-control:${process.pid}:${++this.sequence}`;
    return new Promise((accept, reject) => {
      const timeout = setTimeout(() => {
        this.internal.delete(id); reject(new Error(`${method} timed out`));
      }, 5000);
      this.internal.set(id, { accept, reject, timeout });
      this.sendServer({ id, method, params });
    });
  }

  refreshGoal(state) {
    const revision = state.goalRevision;
    state.goalReady = this.control('thread/goal/get', { threadId: state.params.threadId })
      .then(result => {
        if (!this.closed && revision === state.goalRevision) this.updateGoal(state, result.goal);
      }).catch(() => { /* Without a confirmed active goal, leave manual settings alone. */ });
  }

  selectedStage(params, previous = null) {
    const model = params.collaborationMode?.settings?.model ?? params.model ?? previous?.model;
    const effort = params.collaborationMode?.settings?.reasoning_effort ?? params.effort
      ?? previous?.effort ?? this.policy.metadata.get(model)?.defaultReasoningEffort ?? null;
    return model ? { model, effort } : null;
  }

  async client(message) {
    let params = message.params ?? {};
    if (message.method === 'turn/start') {
      const state = this.state(params.threadId);
      this.cancelTimers(state);
      const generation = ++state.generation;
      state.cancelled = false; state.waiting = false;
      await state.goalReady;
      if (this.closed || state.cancelled || state.generation !== generation) {
        this.sendClient({ id: message.id, error: { code: -32000, message: 'Turn start was cancelled.' } });
        return;
      }
      if (!state.goalActive) {
        // Ordinary conversations pass through exactly as the user configured them.
        state.recoveringGoal = false; state.blockedTurnId = null;
        state.stage = this.selectedStage(params, state.stage);
        state.settingsStage = state.stage;
        state.active = true;
      } else if (state.active) {
        // Additional user input is steering; preserve the active turn's stage.
        params = state.stage ? routeParams(params, state.stage) : structuredClone(params);
      } else {
        state.counts.clear();
        try { await this.monitor.refreshCatalog(); } catch { /* Keep the last catalog on a network error. */ }
        let stage = this.policy.stages()[0];
        const currentIndex = this.policy.stages().findIndex(candidate => sameStage(candidate, state.stage));
        if (state.degraded && currentIndex > 0) {
          stage = await this.findRecovered(state, this.policy.stages().slice(0, currentIndex), generation)
            ?? this.policy.stages()[currentIndex];
        }
        if (this.closed || state.cancelled || state.generation !== generation) {
          this.sendClient({ id: message.id, error: { code: -32000, message: 'Turn start was cancelled.' } });
          return;
        }
        if (stage) {
          params = routeParams(params, stage); state.stage = stage;
          state.settingsStage = stage;
          state.counts.set(stageKey(stage), 1);
        }
        state.active = true;
      }
      state.params = structuredClone(params);
      message = { ...message, params };
    } else if (message.method === 'turn/interrupt' || message.method === 'thread/goal/clear'
        || (message.method === 'thread/goal/set' && params.status && params.status !== 'active')) {
      const state = this.state(params.threadId);
      if (message.method !== 'turn/interrupt') this.updateGoal(state, null);
      ++state.generation; state.cancelled = true; state.waiting = false;
      this.cancelTimers(state);
    }
    if (message.method && message.id !== undefined) this.requests.set(message.id,
      { method: message.method, params: structuredClone(params),
        ...(message.method === 'thread/goal/get' ? { goalRevision: this.state(params.threadId).goalRevision } : {}) });
    this.sendServer(message);
    if (message.method === 'turn/start') this.scheduleRecovery(this.state(params.threadId));
  }

  server(message) {
    const probeId = message.params?.threadId ?? message.params?.thread?.id;
    if (this.monitor.probeThreads?.has(probeId)) return;
    const internal = this.internal.get(message.id);
    if (internal) {
      this.internal.delete(message.id);
      if (internal.accept) {
        clearTimeout(internal.timeout);
        if (message.error) internal.reject(new Error(message.error.message));
        else internal.accept(message.result);
        return;
      }
      if (message.error) {
        internal.state.active = false;
        if (isCapacityError(message.error)) this.capacityFailure(internal.state, internal.stage, `rpc:${message.id}`);
        else this.notice('자동 모델 전환을 시작하지 못했습니다.', message.error.message);
      } else internal.state.turnId = message.result?.turn?.id ?? internal.state.turnId;
      return;
    }
    if (typeof message.id === 'string' && message.id.startsWith(`codex-fallback-control:${process.pid}:`)) return;

    const request = this.requests.get(message.id);
    if (request && (message.result || message.error)) {
      this.requests.delete(message.id);
      if (request.method === 'turn/start' && message.error) {
        const state = this.state(request.params.threadId);
        state.active = false;
        if (isCapacityError(message.error)) this.capacityFailure(state, state.stage, `rpc:${message.id}`);
      }
      if (request.method === 'model/list' && message.result?.data && !request.params.cursor && !message.result.nextCursor) {
        this.policy.update(new Map(message.result.data.filter(model => !model.hidden).map(model => [model.model, model])));
      }
      if (['thread/start', 'thread/resume', 'thread/fork'].includes(request.method)
          && message.result?.thread?.id) {
        const state = this.state(message.result.thread.id);
        state.stage = this.selectedStage({ ...message.result, effort: message.result.reasoningEffort });
        state.settingsStage = state.stage;
        const running = message.result.thread.turns?.find(turn => turn.status === 'inProgress');
        if (running) { state.active = true; state.turnId = running.id; }
        state.modelProvider = message.result.modelProvider;
        state.serviceTier = message.result.serviceTier ?? 'default';
        // Daemon-owned goal continuations need no new client turn/start. Seed a
        // continuation from the existing thread's sticky settings on reconnect.
        if (message.result.collaborationMode) state.params.collaborationMode = structuredClone(message.result.collaborationMode);
        this.refreshGoal(state);
      }
      if (['thread/goal/get', 'thread/goal/set'].includes(request.method) && message.result) {
        const state = this.state(request.params.threadId);
        if (request.method !== 'thread/goal/get' || request.goalRevision === state.goalRevision) this.updateGoal(state, message.result.goal);
      }
      if (request.method === 'thread/goal/clear' && message.result?.cleared) {
        this.updateGoal(this.state(request.params.threadId), null);
      }
    }

    const params = message.params ?? {};
    if (message.method === 'thread/goal/updated' && this.threads.has(params.threadId)) {
      this.updateGoal(this.state(params.threadId), params.goal, params.turnId);
    }
    if (message.method === 'thread/goal/cleared' && this.threads.has(params.threadId)) {
      this.updateGoal(this.state(params.threadId), null);
    }
    if (message.method === 'thread/settings/updated' && this.threads.has(params.threadId)) {
      const state = this.state(params.threadId);
      state.settingsStage = this.selectedStage(params.threadSettings);
      if (!state.active) state.stage = state.settingsStage;
      if (params.threadSettings.collaborationMode) state.params.collaborationMode = structuredClone(params.threadSettings.collaborationMode);
      state.modelProvider = params.threadSettings.modelProvider;
      state.serviceTier = params.threadSettings.serviceTier ?? 'default';
    }
    if (message.method === 'turn/started' && this.threads.has(params.threadId)) {
      const state = this.state(params.threadId);
      state.stage = state.settingsStage ?? state.stage;
      state.active = true; state.turnId = params.turn.id;
      if (state.stage) state.counts.set(stageKey(state.stage), Math.max(state.counts.get(stageKey(state.stage)) ?? 0, 1));
      this.scheduleRecovery(state);
    }
    if (message.method?.startsWith('item/') && this.threads.get(params.threadId)?.blockedTurnId) {
      // Work continuing after a block identifies a deliberate in-turn mutation,
      // rather than the native terminal-error transition observed above.
      this.updateGoal(this.state(params.threadId), null);
    }
    if (message.method === 'error' && !params.willRetry && isCapacityError(params.error)) {
      this.errors.set(`${params.threadId}:${params.turnId}`, params.error);
    }
    this.sendClient(message);

    if (message.method !== 'turn/completed') return;
    const state = this.threads.get(params.threadId);
    if (!state?.params) return;
    state.active = false;
    clearTimeout(state.recovery); state.recovery = null;
    const key = `${params.threadId}:${params.turn.id}`;
    const error = params.turn.error ?? this.errors.get(key);
    this.errors.delete(key);
    if (state.goalActive && state.stage && params.turn.status === 'completed') this.monitor.record(state.stage, 'available');
    if (params.turn.status === 'failed' && isCapacityError(error)) {
      const generation = state.generation, failed = state.stage;
      if (state.goalReady) void state.goalReady.then(() => {
        if (state.generation === generation && !state.active) this.capacityFailure(state, failed, key, params.turn.id);
      });
      else this.capacityFailure(state, state.stage, key, params.turn.id);
    } else if (state.blockedTurnId === params.turn.id) {
      this.updateGoal(state, null);
    }
  }

  capacityFailure(state, failed, key, turnId = null) {
    const blockedByFailure = turnId && state.blockedTurnId === turnId;
    if (this.closed || (!state.goalActive && !blockedByFailure) || state.cancelled || this.handled.has(key)) return;
    this.handled.add(key);
    state.recoveringGoal = Boolean(blockedByFailure);
    state.degraded = true;
    this.monitor.record(failed, 'capacity');
    if (failed) state.counts.set(stageKey(failed), Math.max(state.counts.get(stageKey(failed)) ?? 0, 1));
    const generation = ++state.generation;
    this.cancelTimers(state);
    state.pending = setTimeout(() => {
      state.pending = null;
      void this.retry(state, failed, generation).catch(error => this.notice('모델 경로 확인을 마치지 못했습니다.', error.message));
    }, this.settleMs);
  }

  valid(state, generation) { return !this.closed && (state.goalActive || state.recoveringGoal)
    && !state.cancelled && state.generation === generation; }

  async findRecovered(state, stages, generation) {
    for (const stage of stages) {
      if (!this.valid(state, generation)) return null;
      // A recovered probe followed by another real capacity failure gets a cooldown.
      if ((state.counts.get(stageKey(stage)) ?? 0) >= 2) continue;
      const result = await this.monitor.probe(stage, state, { force: true });
      if (this.valid(state, generation) && result.status === 'available') return stage;
      if (this.valid(state, generation) && result.status === 'capacity') {
        state.counts.set(stageKey(stage), Math.max(state.counts.get(stageKey(stage)) ?? 0, 1));
      }
    }
    return null;
  }

  async retry(state, failed, generation) {
    try { await this.monitor.refreshCatalog(true); } catch { /* Keep the last known supported stages. */ }
    if (!this.valid(state, generation)) return;
    const stages = this.policy.stages();
    const index = stages.findIndex(stage => sameStage(stage, failed));
    const prior = index >= 0 ? stages.slice(0, index) : stages;
    let next = await this.findRecovered(state, prior, generation);
    if (!next) next = stages.find(stage => (state.counts.get(stageKey(stage)) ?? 0) === 0);
    if (!this.valid(state, generation)) return;
    if (next) await this.resume(state, next, generation);
    else {
      state.waiting = true;
      this.notice('모든 모델 단계가 용량 부족입니다.', `${Math.round(this.recheckMs / 1000)}초 뒤 우선순위 순서로 다시 확인합니다. 종료하거나 새 요청을 입력하면 기존 재시도를 취소합니다.`);
      this.scheduleRecovery(state);
    }
  }

  async resume(state, stage, generation) {
    if (!this.valid(state, generation) || state.active) return;
    const retry = routeParams(state.params, stage);
    retry.input = [{ type: 'text', text: CONTINUE, text_elements: [] }];
    delete retry.clientUserMessageId; delete retry.toolOutput;
    state.counts.set(stageKey(stage), (state.counts.get(stageKey(stage)) ?? 0) + 1);
    state.stage = stage; state.settingsStage = stage; state.params = retry; state.waiting = false;
    if (state.recoveringGoal && !state.goalActive) {
      // Reactivation starts the next Goal turn inside the real daemon. Update
      // sticky settings first and let that scheduler own the continuation;
      // sending a second turn/start here would duplicate or steer its work.
      await this.control('thread/settings/update', this.stageSettings(state, stage));
      if (!this.valid(state, generation) || state.active) return;
      await this.control('thread/goal/set', { threadId: retry.threadId, status: 'active', origin: 'automatic' });
      this.scheduleRecovery(state);
      return;
    }
    state.active = true;
    const id = `codex-fallback:${process.pid}:${++this.sequence}`;
    this.internal.set(id, { state, stage });
    this.sendServer({ id, method: 'turn/start', params: retry });
    this.scheduleRecovery(state);
  }

  stageSettings(state, stage) {
    return routeParams({ threadId: state.params.threadId,
      ...(state.params.collaborationMode ? { collaborationMode: state.params.collaborationMode } : {}) }, stage);
  }

  scheduleRecovery(state) {
    clearTimeout(state.recovery); state.recovery = null;
    if (this.closed || (!state.goalActive && !state.recoveringGoal) || state.cancelled
        || (!state.waiting && (!state.active || !state.degraded))) return;
    if (!state.waiting && sameStage(state.stage, this.policy.stages()[0])) return;
    const generation = state.generation;
    state.recovery = setTimeout(() => {
      state.recovery = null;
      void this.checkRecovery(state, generation).catch(() => this.scheduleRecovery(state));
    }, this.recheckMs);
  }

  async checkRecovery(state, generation) {
    if (!this.valid(state, generation)) return;
    try { await this.monitor.refreshCatalog(); } catch { /* Cached catalog still works. */ }
    // The retry bound applies to one burst, not the entire task. Recheck every
    // higher stage after the cooldown even when a lower stage is still working.
    state.counts.clear();
    if (!state.waiting && state.stage) state.counts.set(stageKey(state.stage), 1);
    const stages = this.policy.stages();
    const index = stages.findIndex(stage => sameStage(stage, state.stage));
    const prior = state.waiting ? stages : stages.slice(0, Math.max(index, 0));
    const recovered = await this.findRecovered(state, prior, generation);
    if (!this.valid(state, generation)) return;
    if (recovered) {
      if (state.waiting && !state.active) await this.resume(state, recovered, generation);
      else {
        state.readyStage = recovered;
        // Native Goal continuations bypass client turn/start. Set only their
        // subsequent-turn defaults; keep the running work and its stage intact.
        await this.control('thread/settings/update', this.stageSettings(state, recovered));
      }
    } else this.scheduleRecovery(state);
  }

  notice(summary, details) {
    if (!this.closed) this.sendClient({ method: 'configWarning', params: { summary, details, path: null, range: null } });
  }

  cancelTimers(state) {
    clearTimeout(state.pending); clearTimeout(state.recovery);
    state.pending = null; state.recovery = null;
  }

  close() {
    this.closed = true;
    for (const state of this.threads.values()) { ++state.generation; this.cancelTimers(state); }
    for (const internal of this.internal.values()) if (internal.reject) {
      clearTimeout(internal.timeout); internal.reject(new Error('Local Codex connection closed'));
    }
    this.internal.clear();
  }
}

function cachedModels() {
  try {
    const home = process.env.CODEX_HOME ?? join(homedir(), '.codex');
    const catalog = JSON.parse(readFileSync(join(home, 'models_cache.json'), 'utf8'));
    return new Map(catalog.models.filter(model => model.visibility === 'list').map(model => [model.slug, {
      model: model.slug, hidden: false, modelSpecialty: model.model_specialty,
      upgrade: typeof model.upgrade === 'string' ? model.upgrade : model.upgrade?.model,
      upgradeInfo: model.upgrade_info, defaultReasoningEffort: model.default_reasoning_level,
      supportedReasoningEfforts: model.supported_reasoning_levels.map(option => ({ reasoningEffort: option.effort })),
    }]));
  } catch { return new Map(); }
}

function persistentPolicy() {
  const home = process.env.CODEX_HOME ?? join(homedir(), '.codex');
  let identity = null;
  try {
    const cached = JSON.parse(readFileSync(join(home, 'models_cache.json'), 'utf8'));
    identity = createHash('sha256').update(JSON.stringify(cached.identity ?? null)).digest('hex');
  } catch { /* Cache is not populated yet. */ }
  const path = join(home, `fallback-routing-v2${identity ? `-${identity.slice(0, 16)}` : ''}.json`);
  let lineage;
  // Retain history from the initial v2 file while keeping future logins separate.
  if (!existsSync(path)) {
    try {
      const saved = JSON.parse(readFileSync(join(home, 'fallback-routing-v2.json'), 'utf8'));
      if (saved.version === 2 && saved.identity === identity && Array.isArray(saved.lineage)
          && saved.lineage.length && saved.lineage.every(model => typeof model === 'string')) lineage = saved.lineage;
    } catch { /* First launch for this identity. */ }
  }
  return new RoutingPolicy(cachedModels(), { path, identity, ...(lineage ? { lineage } : {}) });
}

export async function startProxy(socketPath, { policy = persistentPolicy(), monitor = null,
  recheckMs = 60000, probeTimeoutMs = 15000, settleMs = 50 } = {}) {
  const directory = mkdtempSync(join(tmpdir(), 'codex-fallback-'));
  chmodSync(directory, 0o700);
  const localSocket = join(directory, 'control.sock');
  const http = createServer();
  const websocket = new WebSocketServer({ server: http, maxPayload: 128 * 1024 * 1024 });
  const connections = new Set();
  const capacityMonitor = monitor ?? new CapacityMonitor(socketPath, directory, policy, { probeTimeoutMs });
  websocket.on('connection', client => {
    const backend = new WebSocket('ws://localhost/', { createConnection: () => connect(socketPath),
      maxPayload: 128 * 1024 * 1024 });
    const queued = [];
    const sendClient = message => {
      if (client.readyState === WebSocket.OPEN) client.send(JSON.stringify(message));
    };
    const sendServer = message => {
      const encoded = JSON.stringify(message);
      if (backend.readyState === WebSocket.OPEN) backend.send(encoded);
      else queued.push(encoded);
    };
    const fallback = new CapacityFallback(sendServer, sendClient, { policy, monitor: capacityMonitor, recheckMs, settleMs });
    const pair = { client, backend, fallback };
    connections.add(pair);
    backend.on('open', () => { for (const message of queued.splice(0)) backend.send(message); });
    client.on('message', data => {
      try { void fallback.client(JSON.parse(data.toString())).catch(() => client.close(1011, 'Could not start Codex turn')); }
      catch { client.close(1003, 'Invalid JSON'); }
    });
    backend.on('message', data => {
      try { fallback.server(JSON.parse(data.toString())); }
      catch { client.close(1011, 'Invalid backend message'); }
    });
    client.on('ping', data => { if (backend.readyState === WebSocket.OPEN) backend.ping(data); });
    backend.on('ping', data => { if (client.readyState === WebSocket.OPEN) client.ping(data); });
    client.on('error', () => backend.terminate());
    backend.on('error', () => client.close(1011, 'Codex backend unavailable'));
    client.on('close', () => { fallback.close(); backend.terminate(); connections.delete(pair); });
    backend.on('close', () => { fallback.close(); client.close(); });
  });
  await new Promise((accept, reject) => {
    http.once('error', reject);
    http.listen(localSocket, accept);
  });
  return {
    address: `unix://${localSocket}`,
    async close() {
      for (const { client, backend, fallback } of connections) {
        fallback.close(); client.terminate(); backend.terminate();
      }
      await capacityMonitor.close?.();
      await new Promise(done => websocket.close(done));
      await new Promise(done => http.close(done));
      rmSync(directory, { recursive: true, force: true });
    },
  };
}

function run(args) {
  return new Promise(done => {
    const child = spawn(REAL_CODEX, args, { stdio: 'inherit' });
    const terminate = signal => child.kill(signal);
    const onInterrupt = () => terminate('SIGINT');
    const onTerminate = () => terminate('SIGTERM');
    process.on('SIGINT', onInterrupt);
    process.on('SIGTERM', onTerminate);
    child.on('error', error => { console.error(error.message); done(1); });
    child.on('exit', (code, signal) => {
      process.off('SIGINT', onInterrupt);
      process.off('SIGTERM', onTerminate);
      done(code ?? (signal === 'SIGINT' ? 130 : 1));
    });
  });
}

function restoreLauncher() {
  const launcher = join(homedir(), '.local/bin/codex');
  const wrapper = join(homedir(), '.local/bin/codex-fallback');
  try {
    if (lstatSync(launcher).isSymbolicLink()
        && resolve(dirname(launcher), readlinkSync(launcher)) === REAL_CODEX) {
      const temporary = `${launcher}.fallback-${process.pid}-${Date.now()}`;
      symlinkSync(wrapper, temporary); renameSync(temporary, launcher);
    }
  } catch { /* A custom launcher is owned by the user; leave it alone. */ }
}

async function main() {
  const args = defaultModelArgs(reconnectArgs(process.argv.slice(2)));
  restoreLauncher();
  if (existsSync(DISABLED_FILE) || !shouldWrap(args)) {
    try { process.exitCode = await run(args); } finally { restoreLauncher(); }
    return;
  }
  const positiveInteger = (value, fallback) => Number.isSafeInteger(Number(value)) && Number(value) >= 5000 ? Number(value) : fallback;
  const recheckMs = positiveInteger(process.env.CODEX_FALLBACK_RECHECK_MS, 60000);
  const probeTimeoutMs = positiveInteger(process.env.CODEX_FALLBACK_PROBE_TIMEOUT_MS, 15000);
  let proxy;
  try {
    const status = spawnSync(REAL_CODEX, ['app-server', 'daemon', 'start'], { encoding: 'utf8', timeout: 30000 });
    if (status.status !== 0) throw new Error(status.stderr?.trim() || 'Codex daemon could not start');
    const line = status.stdout.trim().split('\n').findLast(line => line.startsWith('{'));
    const daemon = JSON.parse(line);
    if (!daemon.socketPath) throw new Error('Codex daemon did not return a local socket');
    proxy = await startProxy(daemon.socketPath, { recheckMs, probeTimeoutMs });
  } catch (error) {
    console.error(`[codex-fallback] ${error.message}; 일반 Codex로 실행합니다.`);
    process.exitCode = await run(args);
    return;
  }
  try { process.exitCode = await run(['--remote', proxy.address, ...defaultDirectoryArgs(args)]); }
  finally { await proxy.close(); }
}

if (resolve(process.argv[1] ?? '') === fileURLToPath(import.meta.url)) await main();
