# bin

## ropen

`ropen` opens a file on the local Mac from a remote SSH session. It copies the
remote file through a reverse SSH tunnel and runs macOS `open` locally.

### Local Mac SSH Config

Add this to the **local Mac** `~/.ssh/config`:

```sshconfig
Host <hostname> snu10
  RemoteForward 2222 localhost:22
  ExitOnForwardFailure yes
  ServerAliveInterval 30
  ServerAliveCountMax 3
```

Then connect from the Mac using the host alias:

```bash
ssh snu10
```

If a host needs a custom SSH port or hostname, keep those settings in the same
host block:

```sshconfig
Host snu10
  HostName snu10
  User hslyu
  Port 17771
  RemoteForward 2222 localhost:22
  ExitOnForwardFailure yes
  ServerAliveInterval 30
  ServerAliveCountMax 3
```

`ropen` expects the tunnel to exist at `localhost:2222` on the remote server by
default. Override it only when needed:

```bash
ROPEN_PORT=2223 ropen paper.pdf
ROPEN_USER=mac_user ropen paper.pdf
```

### First-Time Setup

On the Mac, enable Remote Login:

```text
System Settings -> General -> Sharing -> Remote Login -> ON
```

From the remote SSH session, install the remote public key into the Mac through
the tunnel:

```bash
ropen login
```

After that, open files from the remote server:

```bash
ropen paper.pdf
ropen figure.png
```

macOS decides which local app opens the file based on the copied file's
extension.
