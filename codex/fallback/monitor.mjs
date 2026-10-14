import { connect } from 'node:net';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { WebSocket } from 'ws';
import { stageKey, isCapacityError } from './routing.mjs';

export class LocalRpc {
  constructor(socketPath, { timeoutMs = 15000 } = {}) {
    this.timeoutMs = timeoutMs;
    this.sequence = 0;
    this.pending = new Map();
    this.listeners = new Set();
    this.socket = new WebSocket('ws://localhost/', {
      createConnection: () => connect(socketPath), maxPayload: 128 * 1024 * 1024,
    });
    this.ready = new Promise((accept, reject) => {
      const timeout = setTimeout(() => { reject(new Error('Local Codex connection timed out')); this.socket.terminate(); }, timeoutMs);
      this.socket.once('open', () => { clearTimeout(timeout); accept(); });
      this.socket.once('error', error => { clearTimeout(timeout); reject(error); });
    });
    this.socket.on('message', data => {
      let message;
      try { message = JSON.parse(data.toString()); } catch { return; }
      if (this.pending.has(message.id)) {
        const pending = this.pending.get(message.id);
        this.pending.delete(message.id);
        clearTimeout(pending.timeout);
        if (message.error) pending.reject(Object.assign(new Error(message.error.message), { rpcError: message.error }));
        else pending.accept(message.result);
      } else if (message.method && message.id !== undefined) {
        // Probe connections never approve or execute client-side tools.
        const result = message.method.includes('requestApproval') ? { decision: 'decline' }
          : message.method.includes('requestUserInput') ? { answers: {} }
          : message.method.includes('elicitation') ? { action: 'decline' }
          : null;
        this.send(result ? { id: message.id, result } : { id: message.id,
          error: { code: -32601, message: 'Client-side tools are disabled for capacity checks.' } });
      }
      for (const listener of this.listeners) listener(message);
    });
    this.socket.on('error', () => {});
    this.socket.on('close', () => {
      for (const pending of this.pending.values()) {
        clearTimeout(pending.timeout); pending.reject(new Error('Local Codex connection closed'));
      }
      this.pending.clear();
    });
  }

  send(message) {
    if (this.socket.readyState === WebSocket.OPEN) this.socket.send(JSON.stringify(message));
  }

  async call(method, params = {}, timeoutMs = this.timeoutMs) {
    await this.ready;
    if (this.socket.readyState !== WebSocket.OPEN) throw new Error('Local Codex connection is closed');
    const id = `codex-fallback-monitor:${process.pid}:${++this.sequence}`;
    return await new Promise((accept, reject) => {
      const timeout = setTimeout(() => { this.pending.delete(id); reject(new Error(`${method} timed out`)); }, timeoutMs);
      this.pending.set(id, { accept, reject, timeout });
      this.send({ id, method, params });
    });
  }

  async initialize() {
    await this.call('initialize', { clientInfo: { name: 'codex_capacity_monitor', version: '2.0.0' },
      capabilities: { experimentalApi: true } });
    this.send({ method: 'initialized' });
  }

  close() { this.socket.terminate(); }
}

export class CapacityMonitor {
  constructor(socketPath, directory, policy, { probeTimeoutMs = 15000, catalogRefreshMs = 300000, now = Date.now } = {}) {
    this.rpc = new LocalRpc(socketPath);
    this.ready = this.rpc.initialize();
    this.ready.catch(() => {});
    this.directory = join(directory, 'capacity-checks');
    mkdirSync(this.directory, { recursive: true, mode: 0o700 });
    this.policy = policy;
    this.probeTimeoutMs = probeTimeoutMs;
    this.catalogRefreshMs = catalogRefreshMs;
    this.now = now;
    this.catalogAt = 0;
    this.outcomes = new Map();
    this.inflight = new Map();
    this.probes = new Map();
    this.probeThreads = new Set();
    this.closed = false;
    this.rpc.listeners.add(message => {
      const probe = this.probes.get(message.params?.threadId);
      if (!probe) return;
      if (message.method === 'turn/started') probe.turnId = message.params.turn.id;
      if (message.method === 'item/started') {
        const type = message.params.item?.type;
        if (!['reasoning', 'agentMessage', 'userMessage'].includes(type)) probe.toolAttempted = true;
      }
      if (message.method === 'turn/completed') {
        probe.finished = true;
        const turn = message.params.turn;
        probe.accept({ status: !probe.toolAttempted && turn.status === 'completed' ? 'available'
          : isCapacityError(turn.error) ? 'capacity' : 'unknown', at: this.now() });
      }
    });
  }

  async refreshCatalog(force = false) {
    if (this.closed || (!force && this.catalogAt && this.now() - this.catalogAt < this.catalogRefreshMs)) return;
    if (this.refreshing) return this.refreshing;
    this.refreshing = (async () => {
      await this.ready;
      const catalog = new Map();
      let cursor = null;
      do {
        const result = await this.rpc.call('model/list', { includeHidden: false, limit: 100, cursor });
        for (const model of result.data) if (!model.hidden) catalog.set(model.model, model);
        cursor = result.nextCursor;
      } while (cursor);
      this.policy.update(catalog);
      this.catalogAt = this.now();
      if (this.mcpServers === undefined) {
        try {
          const result = await this.rpc.call('config/read', { includeLayers: false });
          this.mcpServers = Object.fromEntries(Object.keys(result.config?.mcp_servers ?? {}).map(name => [name, { enabled: false }]));
        } catch { this.mcpServers = {}; }
      }
    })();
    try { await this.refreshing; } finally { this.refreshing = null; }
  }

  record(stage, status) {
    if (stage) this.outcomes.set(stageKey(stage), { status, at: this.now() });
  }

  async probe(stage, context = {}, { force = false } = {}) {
    const key = `${stageKey(stage)}:${context.modelProvider ?? 'openai'}:${context.serviceTier ?? 'default'}`;
    const cached = this.outcomes.get(key);
    if (!force && cached && this.now() - cached.at < 3000) return cached;
    if (this.inflight.has(key)) return this.inflight.get(key);
    const promise = this.performProbe(stage, context);
    this.inflight.set(key, promise);
    try {
      const result = await promise;
      this.outcomes.set(key, result);
      return result;
    } finally { this.inflight.delete(key); }
  }

  async performProbe(stage, context) {
    let threadId, turnId, timeout;
    try {
      await this.ready;
      if (this.closed) return { status: 'unknown', at: this.now() };
      const config = {
        model_reasoning_effort: stage.effort, project_doc_max_bytes: 0, web_search: 'disabled',
        agents: { enabled: false }, memories: { use_memories: false }, mcp_servers: this.mcpServers ?? {},
        features: { hooks: false, apps: false, memories: false, shell_tool: false, unified_exec: false,
          code_mode: false, code_mode_host: false, browser_use: false, computer_use: false,
          image_generation: false, multi_agent: false, multi_agent_v2: false, plugins: false, skill_search: false },
      };
      const instructions = 'This is an isolated model capacity check. Reply with exactly OK. Do not call tools, read files, browse, use skills, or perform any other work.';
      const started = await this.rpc.call('thread/start', { model: stage.model, modelProvider: context.modelProvider,
        serviceTier: context.serviceTier ?? 'default', ephemeral: true, cwd: this.directory,
        approvalPolicy: 'never', sandbox: 'read-only', config, baseInstructions: instructions,
        developerInstructions: instructions, serviceName: 'codex_capacity_check' });
      threadId = started.thread.id;
      this.probeThreads.add(threadId);
      if (this.closed) return { status: 'unknown', at: this.now() };
      const completed = new Promise(accept => {
        const probe = { accept, toolAttempted: false, turnId: null };
        this.probes.set(threadId, probe);
        timeout = setTimeout(() => accept({ status: 'unknown', at: this.now() }), this.probeTimeoutMs);
      });
      const startedTurn = await this.rpc.call('turn/start', { threadId, model: stage.model, effort: stage.effort,
        input: [{ type: 'text', text: 'Reply exactly OK.', text_elements: [] }] });
      turnId = startedTurn.turn.id;
      const outcome = await completed;
      clearTimeout(timeout);
      return outcome;
    } catch (error) {
      clearTimeout(timeout);
      return { status: isCapacityError(error.rpcError) ? 'capacity' : 'unknown', at: this.now() };
    } finally {
      if (threadId) {
        const probe = this.probes.get(threadId);
        turnId ??= probe?.turnId;
        this.probes.delete(threadId);
        if (turnId && !this.closed && !probe?.finished) {
          // Timeouts or failed RPCs must leave no running probe.
          await this.rpc.call('turn/interrupt', { threadId, turnId }, 2000).catch(() => {});
        }
        if (!this.closed) await this.rpc.call('thread/unsubscribe', { threadId }, 2000).catch(() => {});
      }
    }
  }

  async close() {
    this.closed = true;
    const interruptions = [];
    for (const [threadId, probe] of this.probes) {
      if (probe.turnId && !probe.finished) interruptions.push(this.rpc.call('turn/interrupt', { threadId, turnId: probe.turnId }, 2000));
      probe.accept({ status: 'unknown', at: this.now() });
    }
    await Promise.allSettled(interruptions);
    this.rpc.close();
  }
}
