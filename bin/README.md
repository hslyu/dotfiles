# bin

## ropen

`ropen` copies a remote file into the connected local computer's `~/Downloads`
and opens it with macOS `open` or Linux `xdg-open`. Use `-n` to copy only.

### Connect normally, transfer without managing ports

Install `bin/ropen` and `bin/rscp` together on the server, and optionally
`bin/ropen` on the client (Python 3 required).
On the client, add the following to `~/.ssh/config`, retaining each host's
existing HostName, User, Port and other forwards:

```sshconfig
Host my-server
  ControlMaster auto
  ControlPath /tmp/ropen-master-%r-%C.sock
  ControlPersist 60
  RemoteForward /tmp/ropen-control-%r-%C.sock /tmp/ropen-master-%r-%C.sock
  ServerAliveInterval 30
  ServerAliveCountMax 3
```

On each Linux SSH server, add the following at the **end** of sshd_config,
validate with `sudo sshd -t`, then reload the SSH service. Replace `hslyu` with
the remote account. This lets a new connection replace the Unix socket left
after the previous transport exits, without changing settings for other users:

```sshconfig
Match User hslyu
  StreamLocalBindUnlink yes
Match all
```

Remove the old `RemoteForward 2222 localhost:22`. Reconnect once after changing
the client configuration; existing SSH transports do not acquire new forwards.
Then use plain SSH as usual:

```bash
ssh my-server
# On the server:
ropen -n paper.pdf
ropen figure.png
```

Alternatively, with `ropen` installed on the client:

```bash
ropen ssh my-server
ropen ssh -p 17771 user@server.example
```

The private Unix socket forwards only the SSH master's control interface.
For each transfer, `ropen` requests `-R 127.0.0.1:0:localhost:22` through that
control interface. OpenSSH chooses a free TCP port, reports it to `ropen`, and
the file is sent through that port. `ropen` cancels the port when finished,
including on transfer failure. Concurrent transfers on one transport serialize
their allocation and cleanup. No fixed port or `clear` step is required.

The server currently requires Linux, Python 3 and permission to run `sudo -n ss`
to identify SSH-owned sockets. The SSH/tmux session's connected client is chosen
first. Detached Codex/VS Code processes can use a sole connected client. When
several clients are available and the current one cannot be identified, choose
the intended socket explicitly with `ROPEN_CONTROL=/tmp/ropen-control-...sock`.
No arbitrary connection is selected.

### First-time setup

On macOS enable System Settings → General → Sharing → Remote Login. On Linux
enable the local SSH service. From the server run:

```bash
ropen login
```

This installs the server's public key in the connected client's authorized_keys.
If client and server usernames differ, set `ROPEN_USER=local_username`.
`--no-mkdir` requires the client's Downloads directory to exist. Explicit
`ROPEN_PORT` and optional `ROPEN_HOST` remain available for manual tunnels, but
there is no default TCP port. Local host keys are remembered in
`~/.ssh/ropen_known_hosts` under an identity independent of the temporary port.

### Reset all of this account's SSH forwards

```bash
ropen reset --dry-run  # list affected transports
ropen reset
```

`reset` terminates this account's SSH transport processes holding forwarding
listeners, including old 2222 tunnels, ropen control channels, local/dynamic
forward listeners, and outgoing SSH commands with explicit forwarding options.
All forwards carried by those transports close. Their login sessions, including
the current one if it carries forwarding, may disconnect; reconnect normally to
use ropen again. Application servers and other users' processes are excluded.
Detached tmux sessions continue running. Outgoing reverse forwards configured
only via SSH config without a local listener/control socket cannot be discovered
from this server; reset those on their receiving server.

`ropen clear` has been removed.

## rscp

`rscp` copies files from the connected local computer to this server. It shares
`ropen`'s connection discovery, automatic port allocation, transfer lock, SSH key
and host-key settings, and cancels the temporary tunnel even if copying fails.
Use the connection and login setup above; no fixed port is required.

```bash
rscp '~/Downloads/file.pdf' .
rscp -r '~/Downloads/my folder' ./
```

Quote `~/` paths to prevent the server shell from expanding them. `-r` copies
directories. `ROPEN_USER` and `ROPEN_CONTROL` select the local user and connection;
`ROPEN_PORT` and optional `ROPEN_HOST` still support manually configured tunnels.
