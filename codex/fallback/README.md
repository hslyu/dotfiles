# Codex CLI automatic model routing

Normal interactive `codex`, `codex-personal`, and `codex2` launches load this router, but automatic model/effort selection and capacity recovery apply only to threads with a confirmed **active Goal**. Ordinary conversations keep their selected model and effort, including when opening, resuming, or forking a thread. Existing CLI processes keep the version they loaded; reconnect with `codex resume` or `codex-personal resume` to activate updated rules.

## Priority and future releases

For active Goals, the initial priority is exactly:

1. `gpt-6.1-sol` / `max`
2. `gpt-6-astra` / `max`
3. `gpt-6.1-sol` / `xhigh`
4. `gpt-6-astra` / `xhigh`

The general rule is `[new recommended primary max, previous primary max, new recommended primary xhigh, previous primary xhigh]`. Recommendations come from the signed-in account's Codex `model/list`: an explicit `upgrade`/`upgradeInfo` target takes precedence; otherwise a new eligible `isDefault` model becomes primary. This uses Codex recommendations, not inferred benchmark rankings or version numbers. Merely appearing in the list does not promote a model.

The recommendation history is saved in `$CODEX_HOME/fallback-routing-v2-<identity-hash>.json`, separately for each account identity. For example, if a future `gpt-6.2-sol` becomes recommended, the pair becomes `gpt-6.2-sol` and `gpt-6.1-sol`. These future names are examples only; the router does not assume they exist. A later recommendation advances the pair again. Concurrent launchers and restarts retain the same history.

Only picker-visible general models and advertised `max`/`xhigh` combinations are used. Hidden, small, and specialized models are excluded from automatic promotion. Retired or unsupported combinations are skipped. If a previous primary is unavailable, the most recent available predecessor in the stored history is used. Initial accounts without Astra access can use only the advertised Sol stages.

For active Goals, the model and effort are set together in both the turn settings and `collaborationMode.settings`. Plan mode, instructions, workspace, tool permissions, and conversation history are preserved. Outside an active Goal, manual model/effort choices pass through unchanged. To pin settings within an active Goal, use the native launcher or disable routing.

## Capacity checks and recovery

A real structured `Selected model is at capacity` or `serverOverloaded` failure in an active Goal triggers routing directly from the failed turn notification. Native error wrappers such as `stream disconnected before completion:` and HTTP 503 status prefixes are recognized. Before moving down, the router checks earlier stages in priority order and returns to the earliest one that successfully completes a small isolated inference request. The just-failed stage's real request already establishes its current capacity failure.

Codex 0.162.1 marks an automatic Goal turn `blocked` **before** emitting its terminal error. For a confirmed capacity failure of that same turn, the router updates the existing thread's model/effort, then reactivates its Goal with automatic provenance. The native daemon schedules the continuation; the router does not also submit a duplicate turn. If the Goal remains active, a direct same-thread continuation is used instead. No new user prompt is required.

On reconnect, the router queries `thread/goal/get` and retains the thread's current settings as the continuation context. This also covers daemon-owned Goal turns that start and fail without any client `turn/start`, including joins that omit turn history. Stale reads cannot reactivate a Goal or cancel confirmed capacity recovery. Explicit stops, deliberate blocks, completed/limited Goals, and deleted Goals do not keep retrying. An already blocked Goal found on startup is not automatically revived without observing its active turn fail from capacity.

While a lower stage is working, earlier stages are checked every **60 seconds**. Healthy recovery updates the defaults for subsequent turns, including daemon-owned Goal continuations; a running command, edit, or successful turn is never interrupted or replayed just to change models. The running turn's actual stage is tracked separately from those future defaults.

Health checks use an empty temporary directory and ephemeral read-only conversations. They ask for only `OK`, disable hooks, shell tools, browsers, connectors, and agents, and do not include the work conversation. They consume a small amount of model usage. Model-list presence, local connection success, and timeouts are not treated as proof of capacity. Each probe has a **15-second** timeout and is interrupted and unsubscribed during cleanup.

A stage that passes a probe but immediately fails the real task again has a bounded retry burst to prevent oscillation. Its cooldown expires at the next 60-second check. If all stages are full, the CLI waits and rechecks in priority order every 60 seconds, resuming the original task automatically when a stage succeeds. Exiting the CLI, interrupting, or submitting a new request cancels the previous retry chain.

User cancellation, pausing/clearing a goal, authentication/quota errors in the work turn, quoted error text, and subagent failures do not trigger model routing. Capacity can change between a small probe and the actual task, so a positive probe is not a reservation; real capacity failures return through the same bounded retry policy.

Catalog discovery runs on active Goal task starts (with a five-minute cache) and is refreshed before capacity transitions. New recommendations apply automatically when the running Codex daemon advertises them.

## Launchers and controls

Install from dotfiles with `bash ~/dotfiles/codex/install-fallback.sh`.
The normal dotfiles installation/update scripts also run this installer after
installing the native Codex CLI. It copies the runtime into
`~/.local/share/codex-fallback`, installs launchers into `~/.local/bin`, and
adds a managed source block to Bash/Zsh startup files. Node.js 20+ and npm are required.
The native executable is discovered on each server and recorded in its local
`.native-codex` file; no machine-specific path, credentials, or recommendation
history is committed to dotfiles. Existing logins/configuration and disable
markers survive reinstalls. Use `--native EXECUTABLE` for a custom Codex installation.

The Bash `codex` function and the account launchers call `codex-fallback` directly, so npm replacing its own `codex` symlink does not disable routing in new shells. The wrapper also restores the symlink after `codex update`. The original npm package, authentication, and Codex configuration files are preserved.

The remote TUI sometimes prints a temporary proxy URL in its reconnect command. The launcher recognizes its own addresses and reconnects through a fresh proxy automatically. Plain `codex resume <thread-id>` also works.

Noninteractive `codex exec`, administration commands, non-TTY invocations, custom `--remote`, `--no-daemon`, `--oss`, and `--worktree` still use native Codex. The routing described here applies to normal interactive sessions, including `resume` and `fork`.

```bash
codex
codex-personal resume

# Disable for one launch:
CODEX_FALLBACK_DISABLE=1 codex

# Always use native Codex:
codex-native

# Disable globally (including account launchers and the Bash function):
touch ~/.local/share/codex-fallback/disabled

# Enable globally again:
rm -f ~/.local/share/codex-fallback/disabled

# Optional polling and probe timeouts in milliseconds (minimum 5000):
CODEX_FALLBACK_RECHECK_MS=60000 CODEX_FALLBACK_PROBE_TIMEOUT_MS=15000 codex

# Test without live inference calls:
node --test ~/.local/share/codex-fallback/codex-fallback.test.mjs

# Exercise the installed Codex app-server against a local Responses endpoint:
CODEX_FALLBACK_NATIVE_TESTS=1 node --test ~/.local/share/codex-fallback/native-integration.test.mjs

# Also exercise the actual terminal UI (requires util-linux script and stty):
CODEX_FALLBACK_NATIVE_TESTS=1 CODEX_FALLBACK_TUI_TESTS=1 node --test ~/.local/share/codex-fallback/native-integration.test.mjs
```

The old `CODEX_FALLBACK_MODELS` variable no longer selects a static list. Model names are managed by the recommendation history and their live capabilities.

Runtime: Node.js with locally pinned `ws`. See [validation scope and results](VALIDATION.md) for the actual CLI/daemon 0.162.1 checks and remaining limits. OpenAI's app-server protocol is experimental; a future incompatible protocol or recommendation schema change can require a code update. Changes in recommended model names using the documented fields require no manual rule edit.

Official protocol and model recommendations: https://learn.chatgpt.com/docs/app-server
Official note that only successful inference verifies model access for a request: https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server
