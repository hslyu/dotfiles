import assert from 'node:assert/strict';
import test from 'node:test';
import { createServer } from 'node:http';
import { connect } from 'node:net';
import { mkdtempSync, rmSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { WebSocket, WebSocketServer } from 'ws';
import { CapacityFallback, shouldWrap, startProxy, reconnectArgs } from './codex-fallback.mjs';
import { RoutingPolicy, stageKey, routeParams, isCapacityError } from './routing.mjs';
import { CapacityMonitor } from './monitor.mjs';

const capacity = { message: 'Selected model is at capacity. Please try a different model.', codexErrorInfo: 'serverOverloaded' };
const wait = (ms = 25) => new Promise(done => setTimeout(done, ms));
const stages = ['gpt-6.1-sol:max', 'gpt-6-astra:max', 'gpt-6.1-sol:xhigh', 'gpt-6-astra:xhigh'];
function model(name, extra = {}) {
  return { model: name, hidden: false, defaultReasoningEffort: 'medium',
    supportedReasoningEfforts: ['low', 'medium', 'high', 'xhigh', 'max'].map(reasoningEffort => ({ reasoningEffort })), ...extra };
}
function catalog(...names) { return new Map(names.map(name => [name, model(name)])); }
function fakeMonitor() {
  return { calls: [], outcomes: new Map(), records: [], probeThreads: new Set(),
    async refreshCatalog() {},
    async probe(stage) {
      this.calls.push(stageKey(stage));
      const result = this.outcomes.get(stageKey(stage)) ?? 'capacity';
      return typeof result === 'function' ? await result() : { status: result };
    },
    record(stage, status) { this.records.push([stageKey(stage), status]); }, close() {},
  };
}
async function fixture(t, { recheckMs = 60000, policy = new RoutingPolicy(catalog('gpt-6.1-sol', 'gpt-6-astra')),
  monitor = fakeMonitor(), goalStatus = 'active' } = {}) {
  const upstream = [], downstream = [];
  const fallback = new CapacityFallback(message => upstream.push(message), message => downstream.push(message),
    { policy, monitor, recheckMs, settleMs: 1 });
  t.after(() => fallback.close());
  const params = { threadId: 'original-thread', model: 'gpt-6-sol', effort: 'medium',
    cwd: '/original/workspace', approvalPolicy: 'on-request', sandboxPolicy: { type: 'workspaceWrite' },
    collaborationMode: { mode: 'default', settings: { model: 'gpt-6-sol', reasoning_effort: 'medium', developer_instructions: 'existing instructions' } },
    input: [{ type: 'text', text: 'Original request with previously completed actions' }], clientUserMessageId: 'original-message' };
  fallback.state(params.threadId);
  if (goalStatus) fallback.server({ method: 'thread/goal/updated', params: { threadId: params.threadId, goal: { status: goalStatus } } });
  await fallback.client({ id: 1, method: 'turn/start', params });
  return { fallback, upstream, downstream, params, policy, monitor };
}
function finish(fallback, id, error = capacity, threadId = 'original-thread', status = 'failed') {
  fallback.server({ method: 'turn/completed', params: { threadId, turn: { id, status, items: [], error } } });
}
const route = request => `${request.params.model}:${request.params.effort}`;

test('active goal tasks and failovers follow all four requested model/effort stages exactly', async t => {
  const { fallback, upstream, monitor } = await fixture(t);
  for (const id of ['one', 'two', 'three']) { finish(fallback, id); await wait(); }
  assert.deepEqual(upstream.map(route), stages);
  assert.deepEqual(monitor.calls, ['gpt-6.1-sol:max', 'gpt-6.1-sol:max', 'gpt-6-astra:max']);
  for (const request of upstream) {
    assert.equal(request.params.model, request.params.collaborationMode.settings.model);
    assert.equal(request.params.effort, request.params.collaborationMode.settings.reasoning_effort);
  }
});

test('ordinary conversations preserve manual settings and never retry capacity failures', async t => {
  const { fallback, upstream, params, monitor } = await fixture(t, { goalStatus: null, recheckMs: 10 });
  assert.deepEqual(upstream[0].params, params);
  finish(fallback, 'ordinary-capacity');
  await wait(35);
  assert.equal(upstream.length, 1);
  assert.deepEqual(monitor.calls, []);
  assert.deepEqual(monitor.records, []);
  await fallback.client({ id: 2, method: 'turn/start', params: { ...params, effort: 'high',
    collaborationMode: { ...params.collaborationMode, settings: { ...params.collaborationMode.settings, reasoning_effort: 'high' } } } });
  assert.equal(route(upstream.at(-1)), 'gpt-6-sol:high');
});

test('starting, resuming, and forking threads do not force max or replace configuration', async t => {
  const { fallback, upstream } = await fixture(t, { goalStatus: null });
  for (const method of ['thread/start', 'thread/resume', 'thread/fork']) {
    const params = { threadId: 'saved-thread', model: 'gpt-6-sol', config: { model_reasoning_effort: 'medium', other: true } };
    await fallback.client({ id: method, method, params });
    assert.deepEqual(upstream.at(-1).params, params);
  }
});

test('goal get/set responses activate routing only after the server confirms an active goal', async t => {
  const { fallback, upstream, params } = await fixture(t, { goalStatus: null });
  finish(fallback, 'ordinary', null, params.threadId, 'completed');
  await fallback.client({ id: 2, method: 'thread/goal/set', params: { threadId: params.threadId, objective: 'Do task' } });
  assert.equal(fallback.state(params.threadId).goalActive, false);
  fallback.server({ id: 2, result: { goal: { status: 'active' } } });
  await fallback.client({ id: 3, method: 'turn/start', params });
  assert.equal(route(upstream.at(-1)), stages[0]);
  finish(fallback, 'goal', null, params.threadId, 'completed');
  await fallback.client({ id: 4, method: 'thread/goal/get', params: { threadId: params.threadId } });
  fallback.server({ id: 4, result: { goal: null } });
  await fallback.client({ id: 5, method: 'turn/start', params });
  assert.deepEqual(upstream.at(-1).params, params);
});

test('goal completion, pauses, limits, and deletion stop retries without another prompt', async t => {
  for (const status of ['paused', 'complete', 'blocked', 'usageLimited', 'budgetLimited', null]) {
    const { fallback, upstream } = await fixture(t);
    finish(fallback, 'failed');
    fallback.server({ method: status ? 'thread/goal/updated' : 'thread/goal/cleared', params: {
      threadId: 'original-thread', ...(status ? { goal: { status } } : {}) } });
    await wait();
    assert.equal(upstream.length, 1, String(status));
    assert.equal(fallback.state('original-thread').goalActive, false);
    fallback.close();
  }
});

test('capacity continues the same thread and retains permissions, context, and instructions', async t => {
  const { fallback, upstream, params } = await fixture(t);
  finish(fallback, 'one'); await wait();
  const retry = upstream.at(-1);
  assert.equal(retry.params.threadId, params.threadId);
  assert.deepEqual(retry.params.sandboxPolicy, params.sandboxPolicy);
  assert.equal(retry.params.approvalPolicy, params.approvalPolicy);
  assert.equal(retry.params.cwd, params.cwd);
  assert.equal(retry.params.collaborationMode.settings.developer_instructions, 'existing instructions');
  assert.notDeepEqual(retry.params.input, params.input);
  assert.match(retry.params.input[0].text, /이미 끝낸 작업은 반복하지/);
  assert.equal(retry.params.clientUserMessageId, undefined);
  assert.equal(params.model, 'gpt-6-sol');
});

test('earliest recovered prior stage wins before descending to the next stage', async t => {
  const { fallback, upstream, monitor } = await fixture(t);
  finish(fallback, 'one'); await wait();
  monitor.outcomes.set(stages[0], 'available');
  finish(fallback, 'two'); await wait();
  assert.deepEqual(upstream.map(route), [stages[0], stages[1], stages[0]]);
});

test('recovered second stage wins when the first stage remains full', async t => {
  const { fallback, upstream, monitor } = await fixture(t);
  finish(fallback, 'one'); await wait(); finish(fallback, 'two'); await wait();
  monitor.outcomes.set(stages[1], 'available');
  finish(fallback, 'three'); await wait();
  assert.equal(route(upstream.at(-1)), stages[1]);
  assert.deepEqual(monitor.calls.slice(-2), [stages[0], stages[1]]);
});

test('periodic recovery leaves active work intact and the next turn returns to primary', async t => {
  const { fallback, upstream, monitor, params } = await fixture(t, { recheckMs: 20 });
  finish(fallback, 'one'); await wait(10);
  monitor.outcomes.set(stages[0], 'available'); await wait(35);
  assert.equal(upstream.filter(request => request.method === 'turn/start').length, 2);
  assert.equal(stageKey(fallback.state('original-thread').readyStage), stages[0]);
  const settings = upstream.find(request => request.method === 'thread/settings/update');
  assert.equal(route(settings), stages[0]);
  fallback.server({ id: settings.id, result: {} });
  fallback.server({ method: 'thread/settings/updated', params: { threadId: 'original-thread', threadSettings: settings.params } });
  assert.equal(stageKey(fallback.state('original-thread').stage), stages[1]);
  finish(fallback, 'success', null, 'original-thread', 'completed');
  await fallback.client({ id: 2, method: 'turn/start', params: { ...params, input: [{ type: 'text', text: 'Next task' }] } });
  assert.equal(route(upstream.at(-1)), stages[0]);
  assert.equal(upstream.at(-1).params.input[0].text, 'Next task');
});

test('when all stages are full it waits, probes in priority order, and resumes automatically', async t => {
  const { fallback, upstream, monitor, downstream } = await fixture(t, { recheckMs: 80 });
  for (const id of ['one', 'two', 'three', 'four']) { finish(fallback, id); await wait(10); }
  assert.equal(upstream.length, 4);
  assert.equal(fallback.state('original-thread').waiting, true);
  assert.ok(downstream.some(message => message.params?.summary === '모든 모델 단계가 용량 부족입니다.'));
  monitor.outcomes.set(stages[0], 'available'); await wait(90);
  assert.equal(route(upstream.at(-1)), stages[0]); assert.equal(upstream.length, 5);
});

test('probe successes followed by repeated real capacity failures cannot cause a hot retry loop', async t => {
  const { fallback, upstream, monitor } = await fixture(t);
  monitor.outcomes.set(stages[0], 'available');
  for (const id of ['one', 'two', 'three', 'four']) { finish(fallback, id); await wait(); }
  assert.deepEqual(upstream.map(route), [stages[0], stages[1], stages[0], stages[2], stages[3]]);
});

test('the cooldown expires during active fallback work so primary is checked again', async t => {
  const { fallback, upstream, monitor } = await fixture(t, { recheckMs: 40 });
  monitor.outcomes.set(stages[0], 'available');
  for (const id of ['one', 'two', 'three']) { finish(fallback, id); await wait(5); }
  assert.equal(route(upstream.at(-1)), stages[2]);
  await wait(55);
  assert.equal(stageKey(fallback.state('original-thread').readyStage), stages[0]);
  assert.equal(upstream.filter(request => request.method === 'turn/start').length, 4);
});

test('capacity recognition accepts native wrappers without matching arbitrary quoted error text', () => {
  for (const prefix of ['', 'stream disconnected before completion: ', 'unexpected status 503 Service Unavailable: ',
    'unexpected status 429 Too Many Requests: ']) {
    assert.equal(isCapacityError({ codexErrorInfo: 'other', message: `${prefix}${capacity.message}` }), true);
  }
  for (const message of [`Assistant quoted: ${capacity.message}`, 'Usage limit exceeded', 'Unauthorized',
    'exceeded retry limit, last status: 429 Too Many Requests']) {
    assert.equal(isCapacityError({ codexErrorInfo: 'other', message }), false);
  }
});

test('native blocked-before-error ordering updates settings and reactivates the Goal exactly once', async t => {
  const { fallback, upstream } = await fixture(t);
  fallback.server({ method: 'turn/started', params: { threadId: 'original-thread', turn: { id: 'native-failure', status: 'inProgress' } } });
  await fallback.client({ id: 'old-goal-read', method: 'thread/goal/get', params: { threadId: 'original-thread' } });
  fallback.server({ method: 'thread/goal/updated', params: { threadId: 'original-thread', turnId: 'native-failure', goal: { status: 'blocked' } } });
  fallback.server({ id: 'old-goal-read', result: { goal: { status: 'active' } } });
  assert.equal(fallback.state('original-thread').goalActive, false);
  finish(fallback, 'native-failure', { codexErrorInfo: 'other', message: `stream disconnected before completion: ${capacity.message}` });
  await wait();
  const settings = upstream.at(-1);
  assert.equal(settings.method, 'thread/settings/update'); assert.equal(route(settings), stages[1]);
  await fallback.client({ id: 'current-goal-read', method: 'thread/goal/get', params: { threadId: 'original-thread' } });
  fallback.server({ id: 'current-goal-read', result: { goal: { status: 'blocked' } } });
  assert.equal(fallback.state('original-thread').recoveringGoal, true);
  fallback.server({ id: settings.id, result: {} }); await wait();
  const activation = upstream.at(-1);
  assert.equal(activation.method, 'thread/goal/set');
  assert.deepEqual(activation.params, { threadId: 'original-thread', status: 'active', origin: 'automatic' });
  fallback.server({ method: 'thread/goal/updated', params: { threadId: 'original-thread', turnId: null, goal: { status: 'active' } } });
  fallback.server({ id: activation.id, result: { goal: { status: 'active' } } });
  assert.equal(upstream.filter(request => request.method === 'turn/start').length, 1);
  assert.equal(fallback.state('original-thread').goalActive, true);
});

test('a deliberate in-turn block followed by more work is not automatically reactivated', async t => {
  const { fallback, upstream } = await fixture(t);
  fallback.server({ method: 'turn/started', params: { threadId: 'original-thread', turn: { id: 'blocked', status: 'inProgress' } } });
  fallback.server({ method: 'thread/goal/updated', params: { threadId: 'original-thread', turnId: 'blocked', goal: { status: 'blocked' } } });
  fallback.server({ method: 'item/completed', params: { threadId: 'original-thread', turnId: 'blocked', item: { type: 'functionCall' } } });
  finish(fallback, 'blocked'); await wait();
  assert.equal(upstream.length, 1);
});

test('duplicate notifications cannot repeat a turn', async t => {
  const { fallback, upstream } = await fixture(t);
  finish(fallback, 'one'); finish(fallback, 'one'); await wait(); assert.equal(upstream.length, 2);
});

test('interrupts, quotas, authentication errors, subagents, and assistant quotes do not trigger routing', async t => {
  for (const error of [{ message: 'Usage limit exceeded' }, { message: 'Unauthorized' }, { message: 'Rate limit exceeded' }]) {
    const { fallback, upstream } = await fixture(t); finish(fallback, 'error', error); await wait();
    assert.equal(upstream.length, 1); fallback.close();
  }
  const { fallback, upstream } = await fixture(t);
  fallback.server({ method: 'item/agentMessage/delta', params: { delta: capacity.message } });
  finish(fallback, 'child', capacity, 'other-thread');
  finish(fallback, 'interrupted', capacity, 'original-thread', 'interrupted');
  finish(fallback, 'cancel-pending');
  await fallback.client({ id: 2, method: 'turn/interrupt', params: { threadId: 'original-thread', turnId: 'cancel-pending' } });
  await wait(); assert.equal(upstream.length, 2);
});

test('cancellation during a probe prevents automatic continuation', async t => {
  const { fallback, upstream, monitor } = await fixture(t);
  finish(fallback, 'one'); await wait();
  let release;
  monitor.outcomes.set(stages[0], () => new Promise(done => { release = done; }));
  finish(fallback, 'two'); await wait(5);
  await fallback.client({ id: 2, method: 'turn/interrupt', params: { threadId: 'original-thread', turnId: 'two' } });
  release({ status: 'available' }); await wait();
  assert.equal(upstream.filter(message => message.method === 'turn/start').length, 2);
});

test('new user input cancels a pending automatic continuation', async t => {
  const { fallback, upstream, params } = await fixture(t);
  finish(fallback, 'one');
  await fallback.client({ id: 2, method: 'turn/start', params: { ...params, input: [{ type: 'text', text: 'Updated task' }] } });
  await wait(); assert.equal(upstream.length, 2);
  assert.equal(upstream.at(-1).params.input[0].text, 'Updated task');
});

test('pausing or clearing a goal cancels its pending capacity retry', async t => {
  for (const message of [{ id: 2, method: 'thread/goal/set', params: { threadId: 'original-thread', status: 'paused' } },
    { id: 2, method: 'thread/goal/clear', params: { threadId: 'original-thread' } }]) {
    const { fallback, upstream } = await fixture(t);
    finish(fallback, 'one'); await fallback.client(message); await wait();
    assert.equal(upstream.filter(request => request.method === 'turn/start').length, 1);
    fallback.close();
  }
});

test('notify-only capacity errors and synchronous turn/start failures are handled', async t => {
  const { fallback, upstream } = await fixture(t);
  fallback.server({ method: 'error', params: { threadId: 'original-thread', turnId: 'one', error: capacity, willRetry: false } });
  finish(fallback, 'one', null); await wait(); assert.equal(route(upstream.at(-1)), stages[1]);
  fallback.server({ id: upstream.at(-1).id, error: capacity }); await wait();
  assert.equal(route(upstream.at(-1)), stages[2]);
});

test('stable serverOverloaded errors route even when the display wording changes', async t => {
  const { fallback, upstream } = await fixture(t);
  finish(fallback, 'one', { message: 'Temporary overload', codexErrorInfo: 'serverOverloaded' });
  await wait(); assert.equal(route(upstream.at(-1)), stages[1]);
});

test('a new recommendation discovered at a capacity transition is considered before lower stages', async t => {
  const { fallback, upstream, policy, monitor } = await fixture(t);
  monitor.refreshCatalog = async force => {
    if (force) {
      const metadata = catalog('gpt-6.1-sol', 'gpt-6-astra');
      metadata.set('gpt-next', model('gpt-next', { isDefault: true })); policy.update(metadata);
    }
  };
  monitor.outcomes.set('gpt-next:max', 'unknown');
  finish(fallback, 'one'); await wait();
  assert.equal(route(upstream.at(-1)), 'gpt-next:max');
});

test('new recommendations alternate with the prior primary and persist across concurrent launches', () => {
  const dir = mkdtempSync(join(tmpdir(), 'codex-policy-test-'));
  try {
    const path = join(dir, 'policy.json');
    const original = catalog('gpt-6.1-sol', 'gpt-6-astra');
    const policy = new RoutingPolicy(original, { path, identity: 'account-a' });
    const next = new Map(original); next.set('gpt-6.2-sol', model('gpt-6.2-sol', { isDefault: true }));
    policy.update(next);
    assert.deepEqual(policy.stages().map(stageKey), ['gpt-6.2-sol:max', stages[0], 'gpt-6.2-sol:xhigh', stages[2]]);
    const restarted = new RoutingPolicy(next, { path, identity: 'account-a' });
    assert.deepEqual(restarted.stages(), policy.stages());
    next.set('gpt-7-astra', model('gpt-7-astra', { isDefault: true })); next.get('gpt-6.2-sol').isDefault = false;
    restarted.update(next);
    assert.deepEqual(restarted.stages().map(stageKey), ['gpt-7-astra:max', 'gpt-6.2-sol:max', 'gpt-7-astra:xhigh', 'gpt-6.2-sol:xhigh']);
    assert.deepEqual(JSON.parse(readFileSync(path, 'utf8')).lineage.slice(0, 3), ['gpt-7-astra', 'gpt-6.2-sol', 'gpt-6.1-sol']);
    policy.update(original); assert.equal(JSON.parse(readFileSync(path, 'utf8')).lineage[0], 'gpt-7-astra');
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('upgrade metadata is used and unavailable models or effort combinations are skipped', () => {
  const metadata = catalog('gpt-6.1-sol', 'gpt-6-astra');
  metadata.get('gpt-6.1-sol').upgrade = 'gpt-next';
  metadata.set('gpt-next', model('gpt-next', { supportedReasoningEfforts: [{ reasoningEffort: 'max' }] }));
  const policy = new RoutingPolicy(metadata);
  assert.deepEqual(policy.stages().map(stageKey), ['gpt-next:max', stages[0], stages[2]]);
  metadata.set('gpt-8-luna', model('gpt-8-luna', { isDefault: true })); policy.update(metadata);
  assert.equal(policy.lineage[0], 'gpt-next');
  metadata.get('gpt-next').hidden = true; assert.deepEqual(policy.stages().map(stageKey), stages);
});

test('routing preserves the original collaboration mode and instructions', () => {
  const params = { model: 'old', effort: 'medium', collaborationMode: { mode: 'plan', settings: { model: 'old', reasoning_effort: 'medium', developer_instructions: 'keep me' } } };
  const routed = routeParams(params, { model: 'gpt-6-astra', effort: 'xhigh' });
  assert.equal(routed.collaborationMode.mode, 'plan');
  assert.equal(routed.collaborationMode.settings.developer_instructions, 'keep me');
  assert.equal(routed.collaborationMode.settings.reasoning_effort, 'xhigh'); assert.equal(params.model, 'old');
});

test('administrative, noninteractive, and custom remote commands remain native', () => {
  assert.equal(shouldWrap([], {}, true), true);
  assert.equal(shouldWrap(['-m', 'gpt-6-sol', 'resume', '--last'], {}, true), true);
  for (const args of [['exec', 'task'], ['app-server', 'proxy'], ['--version'], ['--remote', 'unix://'], ['--no-daemon'], ['--worktree']]) assert.equal(shouldWrap(args, {}, true), false);
  assert.equal(shouldWrap([], { CODEX_FALLBACK_DISABLE: '1' }, true), false); assert.equal(shouldWrap([], {}, false), false);
});

test('printed reconnect commands use a fresh proxy while custom remotes stay intact', () => {
  assert.deepEqual(reconnectArgs(['--remote', 'unix:///tmp/codex-fallback-Ab123/control.sock', 'resume', 'saved-thread']), ['resume', 'saved-thread']);
  const custom = ['--remote', 'unix:///custom/control.sock', 'resume', 'saved-thread']; assert.deepEqual(reconnectArgs(custom), custom);
});

async function mockBackend(t, handle) {
  const dir = mkdtempSync(join(tmpdir(), 'codex-backend-test-'));
  const socket = join(dir, 'backend.sock'); const http = createServer();
  const backend = new WebSocketServer({ server: http }); const requests = [];
  backend.on('connection', connection => connection.on('message', data => {
    const message = JSON.parse(data.toString()); requests.push(message);
    handle(message, response => connection.send(JSON.stringify(response)));
  }));
  await new Promise(done => http.listen(socket, done));
  t.after(async () => {
    for (const connection of backend.clients) connection.terminate();
    await new Promise(done => backend.close(done)); await new Promise(done => http.close(done));
    rmSync(dir, { recursive: true, force: true });
  });
  return { socket, dir, requests };
}

test('WebSocket transport relays RPC and automatically resumes the exact thread', async t => {
  const { socket, requests } = await mockBackend(t, (message, send) => {
    send({ id: message.id, result: message.method === 'thread/goal/get' ? { goal: { status: 'active' } } : { accepted: true } });
    if (message.method === 'turn/start' && message.params.model === 'gpt-6.1-sol') send({ method: 'turn/completed', params: {
      threadId: message.params.threadId, turn: { id: 'failed', status: 'failed', items: [], error: capacity } } });
  });
  const policy = new RoutingPolicy(catalog('gpt-6.1-sol', 'gpt-6-astra'));
  const proxy = await startProxy(socket, { policy, monitor: fakeMonitor(), settleMs: 1 }); t.after(() => proxy.close());
  const client = new WebSocket('ws://localhost/', { createConnection: () => connect(proxy.address.slice('unix://'.length)) });
  const replies = []; client.on('message', data => replies.push(JSON.parse(data.toString())));
  await new Promise((done, fail) => { client.once('open', done); client.once('error', fail); });
  client.send(JSON.stringify({ id: 0, method: 'thread/goal/get', params: { threadId: 'exact-thread' } }));
  await wait(10);
  client.send(JSON.stringify({ id: 1, method: 'turn/start', params: { threadId: 'exact-thread', model: 'gpt-6.1-sol', input: [{ type: 'text', text: 'Do task' }] } }));
  await wait(75);
  const turns = requests.filter(request => request.method === 'turn/start');
  assert.equal(turns.length, 2); assert.equal(turns[1].params.threadId, 'exact-thread');
  assert.equal(turns[1].params.model, 'gpt-6-astra'); assert.equal(turns[1].params.effort, 'max');
  assert.equal(replies[1].id, 1); assert.equal(replies.length, 3); client.terminate();
});

test('a reconnected daemon goal recovers from capacity without any new user turn', async t => {
  const mode = { mode: 'plan', settings: { model: 'gpt-6.1-sol', reasoning_effort: 'max', developer_instructions: 'keep plan instructions' } };
  const { socket, requests } = await mockBackend(t, (message, send) => {
    if (message.method === 'thread/resume') send({ id: message.id, result: {
      thread: { id: 'saved-goal' }, model: 'gpt-6.1-sol', reasoningEffort: 'max', collaborationMode: mode } });
    else if (message.method === 'thread/goal/get') {
      send({ id: message.id, result: { goal: { status: 'active' } } });
      send({ method: 'turn/started', params: { threadId: 'saved-goal', turn: { id: 'daemon-owned', status: 'inProgress', items: [] } } });
      send({ method: 'turn/completed', params: { threadId: 'saved-goal', turn: { id: 'daemon-owned', status: 'failed', items: [], error: capacity } } });
    } else if (message.method === 'turn/start') {
      send({ id: message.id, result: { turn: { id: 'recovered' } } });
      send({ method: 'turn/started', params: { threadId: 'saved-goal', turn: { id: 'recovered', status: 'inProgress', items: [] } } });
      send({ method: 'turn/completed', params: { threadId: 'saved-goal', turn: { id: 'recovered', status: 'completed', items: [], error: null } } });
    }
  });
  const policy = new RoutingPolicy(catalog('gpt-6.1-sol', 'gpt-6-astra'));
  const proxy = await startProxy(socket, { policy, monitor: fakeMonitor(), settleMs: 1 }); t.after(() => proxy.close());
  const client = new WebSocket('ws://localhost/', { createConnection: () => connect(proxy.address.slice('unix://'.length)) });
  const replies = []; client.on('message', data => replies.push(JSON.parse(data.toString())));
  await new Promise((done, fail) => { client.once('open', done); client.once('error', fail); });
  // This client reconnects only. It never submits a prompt or turn/start.
  client.send(JSON.stringify({ id: 1, method: 'thread/resume', params: { threadId: 'saved-goal' } }));
  await wait(75);
  const turns = requests.filter(request => request.method === 'turn/start');
  assert.equal(turns.length, 1);
  assert.match(turns[0].id, /^codex-fallback:/);
  assert.equal(turns[0].params.threadId, 'saved-goal');
  assert.equal(route(turns[0]), stages[1]);
  assert.equal(turns[0].params.collaborationMode.mode, 'plan');
  assert.equal(turns[0].params.collaborationMode.settings.developer_instructions, 'keep plan instructions');
  assert.ok(replies.some(message => message.method === 'turn/completed' && message.params.turn.id === 'recovered'
    && message.params.turn.status === 'completed'));
  assert.ok(!replies.some(message => typeof message.id === 'string' && message.id.startsWith('codex-fallback-control:')));
  client.terminate();
});

test('clearing a reconnected goal while its status query is pending prevents stale reactivation', async t => {
  const { socket, requests } = await mockBackend(t, (message, send) => {
    if (message.method === 'thread/resume') send({ id: message.id, result: {
      thread: { id: 'cleared-goal' }, model: 'gpt-6.1-sol', reasoningEffort: 'max' } });
    else if (message.method === 'thread/goal/get') {
      send({ method: 'thread/goal/cleared', params: { threadId: 'cleared-goal' } });
      send({ id: message.id, result: { goal: { status: 'active' } } });
      send({ method: 'turn/completed', params: { threadId: 'cleared-goal', turn: { id: 'old-turn', status: 'failed', items: [], error: capacity } } });
    }
  });
  const proxy = await startProxy(socket, { policy: new RoutingPolicy(catalog('gpt-6.1-sol', 'gpt-6-astra')),
    monitor: fakeMonitor(), settleMs: 1 }); t.after(() => proxy.close());
  const client = new WebSocket('ws://localhost/', { createConnection: () => connect(proxy.address.slice('unix://'.length)) });
  await new Promise((done, fail) => { client.once('open', done); client.once('error', fail); });
  client.send(JSON.stringify({ id: 1, method: 'thread/resume', params: { threadId: 'cleared-goal' } }));
  await wait(75);
  assert.equal(requests.filter(request => request.method === 'turn/start').length, 0);
  client.terminate();
});

test('health probes require successful inference, use isolated threads, and disable tools/hooks', async t => {
  let thread = 0;
  const { socket, dir, requests } = await mockBackend(t, (message, send) => {
    if (!message.method) return;
    if (message.method === 'thread/start') send({ id: message.id, result: { thread: { id: `probe-${++thread}` } } });
    else if (message.method === 'turn/start') {
      send({ method: 'turn/started', params: { threadId: message.params.threadId, turn: { id: 'probe-turn', status: 'inProgress', items: [] } } });
      send({ id: message.id, result: { turn: { id: 'probe-turn' } } });
      send({ method: 'turn/completed', params: { threadId: message.params.threadId, turn: { id: 'probe-turn', status: 'completed', items: [], error: null } } });
    } else if (message.id) send({ id: message.id, result: {} });
  });
  const monitor = new CapacityMonitor(socket, dir, new RoutingPolicy(), { probeTimeoutMs: 100 });
  t.after(() => monitor.close()); await monitor.ready;
  const result = await monitor.probe({ model: 'gpt-6.1-sol', effort: 'max' }); assert.equal(result.status, 'available');
  const started = requests.find(request => request.method === 'thread/start').params;
  assert.equal(started.ephemeral, true); assert.equal(started.sandbox, 'read-only'); assert.equal(started.approvalPolicy, 'never');
  assert.equal(started.config.features.hooks, false); assert.equal(started.config.features.shell_tool, false);
  assert.equal(started.config.agents.enabled, false); assert.notEqual(started.cwd, '/original/workspace');
  assert.equal(started.config.project_doc_max_bytes, 0); assert.ok(requests.some(request => request.method === 'thread/unsubscribe'));
});

test('health probe timeouts stay unknown and interrupt the probe instead of claiming recovery', async t => {
  const { socket, dir, requests } = await mockBackend(t, (message, send) => {
    if (message.method === 'thread/start') send({ id: message.id, result: { thread: { id: 'probe' } } });
    else if (message.method === 'turn/start') send({ id: message.id, result: { turn: { id: 'probe-turn' } } });
    else if (message.id) send({ id: message.id, result: {} });
  });
  const monitor = new CapacityMonitor(socket, dir, new RoutingPolicy(), { probeTimeoutMs: 20 });
  t.after(() => monitor.close()); await monitor.ready;
  const result = await monitor.probe({ model: 'gpt-6-astra', effort: 'xhigh' }); assert.equal(result.status, 'unknown');
  assert.ok(requests.some(request => request.method === 'turn/interrupt' && request.params.turnId === 'probe-turn'));
});
