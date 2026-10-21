# Capacity recovery validation

The native integration tests launch the installed, unmodified Codex CLI/app-server 0.162.1 in an isolated Codex home and workspace. A loopback Responses endpoint supplies controlled errors and responses. No OpenAI credentials or live model inference are used. The actual Codex error parser, Goal lifecycle, conversation history, scheduler, settings updates, and terminal UI execute normally.

The previous implementation passed its mock tests but failed the native SSE regression: Codex emitted a same-turn `blocked` Goal update before a wrapped capacity error, and no continuation followed. The current implementation follows the observed native ordering and lets the native scheduler own Goal reactivation.

The final combined run reported **53 passed, 0 failed, 0 skipped**, including the opt-in native and terminal tests. The same native SSE test failed against the previously installed wrapper, confirming that it detects the original missing recovery.

The tested Codex 0.162.1 binary SHA-256 was `628e35487d888a28f0427fc37501da529dd3d81fcbad7a2c3421c1e8670d92e1`. The tested router SHA-256 was `2e755304928eb6d21d9051e8f182ccecc63f086f85d1b38e0243dfee899169b2`.

Covered native cases:

- SSE and HTTP 503 capacity failures, followed by same-thread recovery without another user prompt.
- WebSocket warmup failures that the runtime handles itself, and terminal failures after WebSocket/HTTP retries.
- Capacity failures after partial assistant output, preserving that output in subsequent context.
- A reconnect to a running Goal with turn history excluded.
- All four model/effort stages full, followed by successful real health probes and automatic recovery.
- Primary recovery during active fallback work, changing the next automatic turn without interrupting the current one.
- User pause, completion, deletion, and deletion during a pending health probe.
- Ordinary conversations preserving manual effort, and authentication/usage failures remaining stopped.
- The actual terminal UI showing the capacity error and the later recovered response without an additional prompt. The only terminal input during the test is terminal capability replies and exit keys.

The default unit/transport suite also covers cancellation, stale Goal reads, duplicate notifications, deliberate in-turn blocks, permission/context preservation, recommendation history, and installation.

## Reproduce

```bash
cd ~/dotfiles/codex/fallback
npm test
CODEX_FALLBACK_NATIVE_TESTS=1 CODEX_FALLBACK_TUI_TESTS=1 node --test native-integration.test.mjs
```

`CODEX_FALLBACK_TEST_NATIVE` can select a specific installed native executable. `CODEX_FALLBACK_TEST_ARTIFACTS` preserves isolated request/event traces and terminal output in a chosen directory. The native tests are opt-in and are skipped by an ordinary `npm test`.

## Limits

These are real client/runtime tests with a controlled upstream, not observations of OpenAI's production servers being saturated. They establish that the installed runtime can parse the tested failures and accept/schedule recovery. A different production error shape or later Codex version can require another change.

A generic HTTP 429 is deliberately not classified as model capacity. In a native test, Codex discarded that response's capacity text and exposed only `exceeded retry limit, last status: 429 Too Many Requests`, which cannot reliably distinguish capacity from rate limits or quota. Authentication and account usage limits do not trigger fallback.

The CLI must remain running and connected to its local proxy. Existing CLI processes retain their loaded wrapper; reconnect with `codex resume` or the corresponding account launcher after installing an update. A Goal already blocked before the proxy observes its active turn is not automatically reactivated.
