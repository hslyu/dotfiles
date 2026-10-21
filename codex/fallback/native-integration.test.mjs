import assert from 'node:assert/strict';
import test from 'node:test';
import { createServer } from 'node:http';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir, homedir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { connect } from 'node:net';
import { WebSocket, WebSocketServer } from 'ws';
import { LocalRpc } from './monitor.mjs';
import { RoutingPolicy, stageKey } from './routing.mjs';
import { resolveNativeCodex } from './native.mjs';

// Opt in: this starts the installed, unmodified Codex app-server. Only its
// Responses endpoint is replaced; no OpenAI credentials or live inference.
const enabled = process.env.CODEX_FALLBACK_NATIVE_TESTS === '1';
const options = { skip: !enabled, timeout: 15000 };
const runtime = process.env.CODEX_FALLBACK_TEST_RUNTIME;
const { startProxy } = await import(runtime ? pathToFileURL(resolve(runtime)).href : './codex-fallback.mjs');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const capacityMessage = 'Selected model is at capacity. Please try a different model.';

function responseEvents(request, outcome) {
  const id = `response-${request.index}`;
  const failure = { type: 'response.failed', response: { id, status: 'failed', error: { code: 'server_overloaded', message: capacityMessage } } };
  if (outcome === 'capacity') return [failure];
  const text = outcome === 'capacity-after-text' ? 'PREVIOUS_STEP' : request.probe ? 'OK' : outcome === 'initialized' ? 'INITIALIZED' : 'RECOVERED';
  const item = { id: `message-${request.index}`, type: 'message', role: 'assistant', status: 'completed',
    content: [{ type: 'output_text', text, annotations: [] }] };
  return [
    { type: 'response.created', response: { id, status: 'in_progress', output: [] } },
    { type: 'response.output_item.added', output_index: 0, item: { ...item, status: 'in_progress', content: [] } },
    { type: 'response.output_text.delta', output_index: 0, content_index: 0, item_id: item.id, delta: text },
    { type: 'response.output_item.done', output_index: 0, item },
    outcome === 'capacity-after-text' ? failure : { type: 'response.completed', response: { id, status: 'completed', output: [item],
      usage: { input_tokens: 10, output_tokens: 1, total_tokens: 11 } } },
  ];
}

async function fixture(t, { behavior = request => request.index === 0 ? 'capacity' : 'success',
  recheckMs = 80, settleMs = 10, stopOnSuccess = true, websockets = false } = {}) {
  const artifactRoot = process.env.CODEX_FALLBACK_TEST_ARTIFACTS;
  if (artifactRoot) mkdirSync(artifactRoot, { recursive: true });
  const directory = mkdtempSync(join(artifactRoot ?? tmpdir(), 'codex-native-capacity-'));
  const testHome = join(directory, 'home'), workspace = join(directory, 'workspace');
  mkdirSync(testHome); mkdirSync(workspace);
  const requests = [], events = [], calls = [];
  const extraProcesses = [];
  let child, rpc, proxy, upstream, apiWebsocket, stderr = '', goalStarted = false, stopping = null;
  const native = process.env.CODEX_FALLBACK_TEST_NATIVE ?? resolveNativeCodex({
    runtimeDirectory: dirname(fileURLToPath(import.meta.url)), home: homedir() });
  const version = spawnSync(native, ['--version'], { encoding: 'utf8' }).stdout?.trim();
  const result = { requests, events, calls, directory, version, native, testHome, workspace,
    port: null, threadId: null, onEvent: null, onRequest: null, extraProcesses, tuiOutput: '', tuiRPC: [], tuiReplies: [] };
  result.call = (method, params) => { calls.push({ method, params }); return rpc.call(method, params); };
  result.waitFor = async (predicate, timeout = 5000) => {
    const deadline = Date.now() + timeout;
    while (!predicate()) {
      if (Date.now() > deadline) throw new Error(`Timed out: ${JSON.stringify(events.filter(event =>
        ['error', 'turn/completed', 'thread/goal/updated', 'configWarning'].includes(event.method)))}`);
      await pause(10);
    }
  };
  result.goal = async () => {
    goalStarted = true;
    return result.call('thread/goal/set', { threadId: result.threadId, status: 'active', origin: 'user',
      objective: 'Native capacity regression: reply RECOVERED without tools.' });
  };
  result.reconnect = async (params = {}) => {
    rpc.close(); await proxy.close();
    await connectProxy();
    await result.call('thread/resume', { threadId: result.threadId, ...params });
  };
  result.directObserver = async () => {
    rpc.close();
    rpc = new LocalRpc(socket, { timeoutMs: 5000 });
    attachListener(); await rpc.initialize();
    await result.call('thread/resume', { threadId: result.threadId });
    result.proxyAddress = proxy.address;
  };
  t.after(async () => {
    for (const process of extraProcesses) if (process.exitCode === null) {
      try { globalThis.process.kill(-process.pid, 'SIGTERM'); } catch {}
    }
    if (stopping) await stopping.catch(() => {});
    rpc?.close(); await proxy?.close();
    if (child?.exitCode === null) {
      process.kill(-child.pid, 'SIGTERM');
      await Promise.race([new Promise(resolve => child.once('exit', resolve)), pause(1000)]);
      if (child.exitCode === null) process.kill(-child.pid, 'SIGKILL');
    }
    upstream?.closeAllConnections();
    if (apiWebsocket) {
      for (const connection of apiWebsocket.clients) connection.terminate();
      await new Promise(resolve => apiWebsocket.close(resolve));
    }
    if (upstream) await new Promise(resolve => upstream.close(resolve));
    const summary = { test: t.name, version, calls, requests, events, stderr, tuiRPC: result.tuiRPC, tuiReplies: result.tuiReplies };
    if (artifactRoot) {
      writeFileSync(join(directory, 'observed.json'), JSON.stringify(summary, null, 2));
      if (result.tuiOutput) writeFileSync(join(directory, 'tui.txt'), result.tuiOutput);
    }
    else rmSync(directory, { recursive: true, force: true });
  });

  upstream = createServer(async (req, res) => {
    try {
      const chunks = []; for await (const chunk of req) chunks.push(chunk);
      const body = JSON.parse(Buffer.concat(chunks).toString() || '{}');
      if (!req.url?.endsWith('/responses')) { res.writeHead(404); res.end('{}'); return; }
      const request = { index: requests.length, transport: 'http', model: body.model, effort: body.reasoning?.effort,
        probe: JSON.stringify(body.input).includes('Reply exactly OK.'), body };
      requests.push(request); result.onRequest?.(request);
      const outcome = await behavior(request);
      if (res.destroyed) return;
      if (typeof outcome === 'object' && outcome.status) {
        res.writeHead(outcome.status, { 'Content-Type': 'application/json', 'x-should-retry': 'false' });
        res.end(JSON.stringify({ error: { type: outcome.code ?? 'server_overloaded', code: outcome.code ?? 'server_overloaded',
          message: outcome.message ?? capacityMessage } }));
        return;
      }
      res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache' });
      const send = data => res.write(`data: ${JSON.stringify(data)}\n\n`);
      for (const event of responseEvents(request, outcome)) send(event);
      res.end();
    } catch (error) { if (!res.destroyed) { res.writeHead(500); res.end(JSON.stringify({ error: error.message })); } }
  });
  if (websockets) {
    apiWebsocket = new WebSocketServer({ server: upstream });
    apiWebsocket.on('connection', connection => connection.on('message', async data => {
      const body = JSON.parse(data.toString());
      const request = { index: requests.length, transport: 'websocket', model: body.model, effort: body.reasoning?.effort,
        probe: JSON.stringify(body.input).includes('Reply exactly OK.'), body };
      requests.push(request); result.onRequest?.(request);
      const outcome = await behavior(request);
      if (connection.readyState === WebSocket.OPEN) for (const event of responseEvents(request, outcome)) connection.send(JSON.stringify(event));
    }));
  }
  await new Promise(resolve => upstream.listen(0, '127.0.0.1', resolve));
  result.port = upstream.address().port;
  writeFileSync(join(testHome, 'config.toml'), `model = "gpt-6.1-sol"
model_provider = "capacity_test"
model_reasoning_effort = "max"
approval_policy = "never"
sandbox_mode = "read-only"
web_search = "disabled"
[model_providers.capacity_test]
name = "Isolated native regression"
base_url = "http://127.0.0.1:${result.port}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = ${websockets}
request_max_retries = 0
stream_max_retries = 0
[features]
hooks = false
apps = false
shell_tool = false
unified_exec = false
code_mode = false
code_mode_host = false
multi_agent = false
plugins = false
responses_websockets = ${websockets}
responses_websockets_v2 = ${websockets}
[projects.${JSON.stringify(workspace)}]
trust_level = "trusted"
`);
  const socket = join(directory, 'server.sock');
  child = spawn(native, ['app-server', '--listen', `unix://${socket}`], { detached: true, cwd: workspace,
    env: { ...process.env, CODEX_HOME: testHome, OPENAI_API_KEY: '', CODEX_API_KEY: '' }, stdio: ['ignore', 'ignore', 'pipe'] });
  child.stderr.on('data', data => { stderr += data.toString(); });
  await result.waitFor(() => existsSync(socket) || child.exitCode !== null);
  assert.ok(existsSync(socket), stderr);
  async function connectProxy() {
    const metadata = new Map(['gpt-6.1-sol', 'gpt-6-astra'].map(model => [model, { model, hidden: false,
      defaultReasoningEffort: 'medium', supportedReasoningEfforts: ['max', 'xhigh'].map(reasoningEffort => ({ reasoningEffort })) }]));
    proxy = await startProxy(socket, { policy: new RoutingPolicy(metadata), recheckMs, settleMs, probeTimeoutMs: 1000 });
    rpc = new LocalRpc(proxy.address.slice('unix://'.length), { timeoutMs: 5000 });
    attachListener();
    await rpc.initialize();
  }
  function attachListener() {
    rpc.listeners.add(message => {
      if (!message.method) return;
      events.push(message);
      result.onEvent?.(message);
      if (goalStarted && stopOnSuccess && message.method === 'turn/completed' && message.params?.threadId === result.threadId
          && message.params.turn.status === 'completed' && !stopping) {
        stopping = result.call('thread/goal/set', { threadId: result.threadId, status: 'paused', origin: 'user' });
        stopping.catch(() => {});
      }
    });
  }
  await connectProxy();
  const thread = await result.call('thread/start', { model: 'gpt-6.1-sol', modelProvider: 'capacity_test', cwd: workspace,
    sandbox: 'read-only', approvalPolicy: 'never', baseInstructions: 'Local regression test. Reply RECOVERED without tools.',
    developerInstructions: 'Never call tools or access files. Reply RECOVERED.' });
  result.threadId = thread.thread.id;
  return result;
}

const completed = fixture => fixture.events.some(event => event.method === 'turn/completed'
  && event.params.threadId === fixture.threadId && event.params.turn.status === 'completed');
const failed = fixture => fixture.events.find(event => event.method === 'turn/completed'
  && event.params.threadId === fixture.threadId && event.params.turn.status === 'failed');

test('native SSE capacity failure blocks the Goal, then recovers without a client turn/start', options, async t => {
  const f = await fixture(t);
  await f.goal(); await f.waitFor(() => completed(f));
  assert.deepEqual(f.requests.filter(request => !request.probe).map(stageKey), ['gpt-6.1-sol:max', 'gpt-6-astra:max']);
  assert.equal(f.calls.filter(call => call.method === 'turn/start').length, 0);
  const blockIndex = f.events.findIndex(event => event.method === 'thread/goal/updated' && event.params.goal.status === 'blocked');
  const errorIndex = f.events.findIndex(event => event.method === 'error');
  assert.ok(blockIndex >= 0 && blockIndex < errorIndex);
  assert.equal(failed(f).params.turn.error.codexErrorInfo, 'other');
  assert.match(failed(f).params.turn.error.message, /^stream disconnected before completion: Selected model is at capacity\./);
  const resumed = f.events.slice(errorIndex).find(event => event.method === 'thread/goal/updated' && event.params.goal.status === 'active');
  assert.equal(resumed.params.threadId, f.threadId);
  assert.ok(JSON.stringify(f.requests[1].body.input).includes('Native capacity regression'));
});

test('native HTTP 503 capacity errors also recover through real Goal reactivation', options, async t => {
  const f = await fixture(t, { behavior: request => request.index === 0 ? { status: 503 } : 'success' });
  await f.goal(); await f.waitFor(() => completed(f));
  assert.match(failed(f).params.turn.error.message, /^unexpected status 503 Service Unavailable: Selected model is at capacity\./);
  assert.equal(f.requests[1].model, 'gpt-6-astra');
  assert.equal(f.calls.filter(call => call.method === 'turn/start').length, 0);
});

test('native WebSocket warmup failure does not force a model switch when the work succeeds', options, async t => {
  const f = await fixture(t, { websockets: true });
  await f.goal(); await f.waitFor(() => completed(f));
  assert.ok(f.requests.some(request => request.transport === 'websocket'));
  assert.equal(f.requests[0].body.generate, false);
  assert.equal(failed(f), undefined);
  assert.ok(f.requests.every(request => request.model === 'gpt-6.1-sol'));
  assert.equal(f.calls.filter(call => call.method === 'turn/start').length, 0);
});

test('native terminal capacity after WebSocket and HTTP retries switches the model', options, async t => {
  const f = await fixture(t, { websockets: true, behavior: request => request.model === 'gpt-6.1-sol' ? 'capacity' : 'success' });
  await f.goal(); await f.waitFor(() => completed(f));
  assert.ok(f.requests.some(request => request.transport === 'websocket'));
  assert.ok(failed(f));
  assert.equal(f.requests.filter(request => !request.probe).at(-1).model, 'gpt-6-astra');
  assert.equal(f.calls.filter(call => call.method === 'turn/start').length, 0);
});

test('native recovery retains output recorded before a mid-stream capacity failure', options, async t => {
  const f = await fixture(t, { behavior: request => request.index === 0 ? 'capacity-after-text' : 'success' });
  await f.goal(); await f.waitFor(() => completed(f));
  assert.ok(JSON.stringify(f.requests[1].body.input).includes('PREVIOUS_STEP'));
  assert.equal(f.events.filter(event => event.method === 'item/agentMessage/delta' && event.params.delta === 'PREVIOUS_STEP').length, 1);
  assert.equal(f.calls.filter(call => call.method === 'turn/start').length, 0);
});

test('native ordinary conversations keep manual effort and do not retry capacity errors', options, async t => {
  const f = await fixture(t, { behavior: () => 'capacity' });
  await f.call('turn/start', { threadId: f.threadId, model: 'gpt-6.1-sol', effort: 'medium',
    input: [{ type: 'text', text: 'Ordinary conversation, no Goal.' }] });
  await f.waitFor(() => failed(f)); await pause(150);
  assert.equal(f.requests.length, 1); assert.equal(f.requests[0].effort, 'medium');
  assert.equal((await f.call('thread/goal/get', { threadId: f.threadId })).goal, null);
});

test('native quota/authentication failures stay blocked and never route', options, async t => {
  for (const [status, message] of [[401, 'Unauthorized test credential'], [429, 'Usage limit exceeded']]) {
    await t.test(String(status), async childTest => {
      const f = await fixture(childTest, { behavior: () => ({ status, message, code: status === 401 ? 'unauthorized' : 'usage_limit_reached' }) });
      await f.goal(); await f.waitFor(() => failed(f)); await pause(150);
      assert.equal(f.requests.length, 1);
      assert.notEqual((await f.call('thread/goal/get', { threadId: f.threadId })).goal?.status, 'active');
    });
  }
});

test('native all-full stages wait and resume automatically after real health probes succeed', options, async t => {
  let available = false;
  const f = await fixture(t, { behavior: () => available ? 'success' : 'capacity', recheckMs: 200 });
  await f.goal();
  await f.waitFor(() => f.events.some(event => event.method === 'configWarning' && event.params.summary === '모든 모델 단계가 용량 부족입니다.'));
  assert.deepEqual(f.requests.filter(request => !request.probe).map(stageKey),
    ['gpt-6.1-sol:max', 'gpt-6-astra:max', 'gpt-6.1-sol:xhigh', 'gpt-6-astra:xhigh']);
  available = true;
  await f.waitFor(() => completed(f));
  assert.ok(f.requests.some(request => request.probe));
  assert.equal(stageKey(f.requests.filter(request => !request.probe).at(-1)), 'gpt-6.1-sol:max');
  assert.equal(f.calls.filter(call => call.method === 'turn/start').length, 0);
});

test('native user pause during capacity recovery prevents automatic Goal reactivation', options, async t => {
  for (const status of ['paused', 'complete', null]) {
    await t.test(String(status), async childTest => {
      const f = await fixture(childTest, { behavior: () => 'capacity', settleMs: 250 });
      await f.goal(); await f.waitFor(() => failed(f));
      if (status) await f.call('thread/goal/set', { threadId: f.threadId, status, origin: 'user' });
      else await f.call('thread/goal/clear', { threadId: f.threadId });
      await pause(350);
      assert.equal(f.requests.length, 1);
      const goal = (await f.call('thread/goal/get', { threadId: f.threadId })).goal;
      assert.equal(goal?.status ?? null, status);
    });
  }
});

test('native reconnect to an already running Goal recovers without a new prompt', options, async t => {
  let release;
  const f = await fixture(t, { behavior: request => request.index === 0 ? new Promise(resolve => { release = resolve; }) : 'success' });
  await f.goal(); await f.waitFor(() => release);
  await f.reconnect({ excludeTurns: true });
  release('capacity');
  await f.waitFor(() => completed(f));
  assert.equal(f.requests[1].model, 'gpt-6-astra');
  assert.equal(f.calls.filter(call => call.method === 'turn/start').length, 0);
});

test('native clearing a Goal while a health probe is pending prevents later reactivation', options, async t => {
  let release;
  const f = await fixture(t, { behavior: request => request.probe ? new Promise(resolve => { release = resolve; }) : 'capacity' });
  await f.goal(); await f.waitFor(() => release);
  await f.call('thread/goal/clear', { threadId: f.threadId });
  release('success'); await pause(150);
  assert.equal((await f.call('thread/goal/get', { threadId: f.threadId })).goal, null);
  assert.deepEqual(f.requests.filter(request => !request.probe).map(stageKey), ['gpt-6.1-sol:max', 'gpt-6-astra:max']);
});

test('native recovery updates the next daemon Goal turn without interrupting active fallback work', options, async t => {
  let release;
  const f = await fixture(t, { stopOnSuccess: false, recheckMs: 80, behavior: request => {
    if (request.probe) return 'success';
    if (request.index === 0) return 'capacity';
    if (request.model === 'gpt-6-astra') return new Promise(resolve => { release = resolve; });
    return 'success';
  } });
  f.onEvent = event => {
    if (event.method === 'turn/completed' && event.params.threadId === f.threadId
        && f.events.filter(message => message.method === 'turn/completed' && message.params.threadId === f.threadId
          && message.params.turn.status === 'completed').length === 2) {
      void f.call('thread/goal/set', { threadId: f.threadId, status: 'paused', origin: 'user' }).catch(() => {});
    }
  };
  await f.goal();
  await f.waitFor(() => release && f.requests.some(request => request.probe));
  await pause(80);
  assert.equal(f.events.filter(event => event.method === 'turn/completed' && event.params.turn.status === 'completed').length, 0);
  release('success');
  await f.waitFor(() => f.events.filter(event => event.method === 'turn/completed' && event.params.threadId === f.threadId
    && event.params.turn.status === 'completed').length >= 2);
  assert.deepEqual(f.requests.filter(request => !request.probe).slice(0, 3).map(stageKey),
    ['gpt-6.1-sol:max', 'gpt-6-astra:max', 'gpt-6.1-sol:max']);
  assert.equal(f.calls.filter(call => call.method === 'turn/start').length, 0);
});

test('native terminal UI displays automatic recovery without any user prompt',
  { ...options, skip: !enabled || process.env.CODEX_FALLBACK_TUI_TESTS !== '1' }, async t => {
    const f = await fixture(t, { behavior: request => request.index === 0 ? 'initialized' : request.index === 1 ? 'capacity' : 'success' });
    await f.call('turn/start', { threadId: f.threadId, input: [{ type: 'text', text: 'Initialize this isolated test conversation.' }] });
    await f.waitFor(() => completed(f));
    const previousCompletions = f.events.filter(event => event.method === 'turn/completed' && event.params.turn.status === 'completed').length;
    const previousInputs = f.calls.filter(call => call.method === 'turn/start').length;
    await f.directObserver();
    const relayPath = join(f.directory, 'tui.sock');
    const http = createServer(), relay = new WebSocketServer({ server: http });
    const connections = new Set();
    relay.on('connection', client => {
      const backend = new WebSocket('ws://localhost/', { createConnection: () => connect(f.proxyAddress.slice('unix://'.length)) });
      connections.add(backend); const queued = [];
      backend.on('open', () => { for (const text of queued) backend.send(text); });
      client.on('message', data => {
        const text = data.toString();
        try { f.tuiRPC.push(JSON.parse(text)); } catch {}
        if (backend.readyState === WebSocket.OPEN) backend.send(text); else queued.push(text);
      });
      backend.on('message', data => {
        try { f.tuiReplies.push(JSON.parse(data.toString())); } catch {}
        if (client.readyState === WebSocket.OPEN) client.send(data.toString());
      });
      backend.on('error', () => client.terminate()); client.on('error', () => backend.terminate());
      client.on('close', () => { backend.terminate(); connections.delete(backend); });
    });
    await new Promise(resolve => http.listen(relayPath, resolve));
    t.after(async () => {
      for (const client of relay.clients) client.terminate();
      for (const backend of connections) backend.terminate();
      await new Promise(resolve => relay.close(resolve)); await new Promise(resolve => http.close(resolve));
    });
    const quote = text => `'${text.replaceAll("'", "'\\''")}'`;
    const args = [f.native, '--remote', `unix://${relayPath}`, '--no-alt-screen', 'resume', f.threadId];
    const tui = spawn('script', ['-qefc', `stty cols 120 rows 40\nexec ${args.map(quote).join(' ')}`, '/dev/null'], { detached: true,
      cwd: f.workspace, env: { ...process.env, CODEX_HOME: f.testHome, TERM: 'xterm-256color',
        OPENAI_API_KEY: '', CODEX_API_KEY: '' }, stdio: ['pipe', 'pipe', 'pipe'] });
    f.extraProcesses.push(tui);
    tui.stdout.on('data', data => {
      const text = data.toString(); f.tuiOutput += text;
      if (text.includes('\x1b[6n')) tui.stdin.write('\x1b[1;1R');
      if (text.includes('\x1b]10;?')) tui.stdin.write('\x1b]10;rgb:ffff/ffff/ffff\x07');
      if (text.includes('\x1b]11;?')) tui.stdin.write('\x1b]11;rgb:0000/0000/0000\x07');
    });
    tui.stderr.on('data', data => { f.tuiOutput += data.toString(); });
    await f.waitFor(() => /[›❯]/u.test(f.tuiOutput) || tui.exitCode !== null, 8000);
    assert.equal(tui.exitCode, null, f.tuiOutput);
    await f.waitFor(() => f.tuiRPC.some(request => request.method === 'thread/goal/get'
      && f.tuiReplies.some(reply => reply.id === request.id && reply.result?.goal === null)));
    assert.ok(!f.tuiOutput.includes('RECOVERED'));
    await f.goal();
    await f.waitFor(() => f.events.filter(event => event.method === 'turn/completed' && event.params.turn.status === 'completed').length > previousCompletions);
    await f.waitFor(() => f.tuiOutput.includes('RECOVERED'));
    assert.ok(f.tuiOutput.includes('Selected model is at capacity'));
    assert.equal(f.calls.filter(call => call.method === 'turn/start').length, previousInputs);
    assert.equal(f.requests[2].model, 'gpt-6-astra');
    tui.stdin.write('\x03\x03');
  });
