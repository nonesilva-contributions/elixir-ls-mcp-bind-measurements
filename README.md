# elixir-ls-mcp-bind-measurements

Measurements for <https://github.com/elixir-lsp/elixir-ls/pull/1275>. They show
where the MCP TCP server of elixir-ls listens, who can reach it, and what a
failed listen does to the language server.

## Results

| What | `master` | Patch | Why it matters | Images |
|------|----------|-------|----------------|--------|
| Bind address | `0.0.0.0` | `127.0.0.1` | the server has no authentication | erlang 27, 28, 29 |
| Client on another address | connects | refused | the network reaches the server | erlang 27, 28, 29 |
| Listen fails | server stops | server runs | MCP must not stop the language server | elixir 1.18, 1.19, 1.20 |
| MCP tests of elixir-ls | - | 27 of 27 pass | the patch breaks no MCP test | elixir 1.18, 1.19, 1.20 |

The patch uses the default `mcpHost`, which is `localhost`. The elixir images
run OTP 27, 28 and 29. The whole `mix test` passed once with the patch, on
Elixir 1.18.4 with OTP 27. No script here runs it, because it takes long. The
outputs are in [`results/`](results/).

## Install

You need Docker. Nothing runs on the host.

```text
git clone https://github.com/nonesilva-contributions/elixir-ls-mcp-bind-measurements
git clone https://github.com/elixir-lsp/elixir-ls
```

The elixir-ls clone must have commit
`68df44b681ee0dbef91b8008b0354003a9a451fa`. The first run pulls the images
`erlang:27`, `erlang:28`, `erlang:29`, `elixir:1.18.4-otp-27`,
`elixir:1.19.6-otp-28` and `elixir:1.20.4-otp-29`.

## Usage

```text
src/run-all.sh ../elixir-ls
```

`src/run-all.sh` runs every measurement and writes one file per run to
`results/`. Each script also runs alone:

```text
src/run-bind.sh 27
src/run-listen-failure.sh ../elixir-ls 1.18.4-otp-27
```

## Tests

Every run checks its own result:

- Every case states its expected values. A value that differs prints
  `MISMATCH`, and the run exits with status 1.
- Each output ends with a `summary:` line with one verdict per case, and then
  `done`. Without `done`, the runner exits with status 1.

So `src/run-all.sh` exits with status 0 only when every check passes.

## Update

```text
git pull
src/run-all.sh ../elixir-ls
git diff results/
```

The outputs print ports as `<port>` and the bridge address as `<bridge-ip>`.
So two runs on the same images give the same files, and a new image changes
only its version lines.

## Uninstall

```text
docker image rm erlang:27 erlang:28 erlang:29 elixir:1.18.4-otp-27 elixir:1.19.6-otp-28 elixir:1.20.4-otp-29
```

Then delete the two clones.

## Details

### Bind and reach

`src/mcp_bind.erl` uses the listen options of the MCP TCP server, without
elixir-ls. `src/run-bind.sh` runs it in the official `erlang` images, on the
default bridge network of Docker. The container has its own network namespace.
The firewall rules of the host do not apply there, and the container has a
non-loopback address, `172.17.0.x`, to connect from. The module reads sockets
with `inet:sockname/1` and tests connections with `gen_tcp:connect/4`. It does
not use `ss`, `nc` or `ip`.

The patch adds the setting `mcpHost`, default `"localhost"`. The server
resolves the name as `resolve/1` in `src/mcp_bind.erl` does, IPv4 first, and
listens on the result. For an IPv6 address it adds the `inet6` option. The
results are the same on the three erlang images. A dash means that the case
does not try that connection.

| Case | Code | Host | Bound | From `<bridge-ip>` | To `127.0.0.1` | To `::1` | By name `localhost` |
|------|------|------|-------|--------------------|----------------|----------|---------------------|
| 1 | `master` | none | `0.0.0.0` | ok | - | refused | - |
| 2 | first version | `{127,0,0,1}` | `127.0.0.1` | refused | ok | - | - |
| 3 | bridge script | - | `127.0.0.1` | - | - | - | ok |
| 4 | patch | `localhost` | `127.0.0.1` | refused | ok | - | ok |
| 5 | patch | `0.0.0.0` | `0.0.0.0` | ok | - | - | - |
| 6 | patch | `::1` | `::1` | - | refused | ok | - |

- Case 1: on `master`, the network reaches the server. `0.0.0.0` is not a
  dual-stack bind, so `::1` was refused before the change too. There is no IPv6
  regression.
- Cases 3 and 4: the bridge script resolves `localhost` in the `inet` family,
  and the default of the patch binds `127.0.0.1`. So the client and the server
  meet on the same address.
- Case 5: `0.0.0.0` gives the same exposure as `master`. A user must set it.
- Case 6: `::1` does not resolve in the `inet` family, so the server falls back
  to `inet6` and binds `::1`.

### Listen failure

`src/listen_failure_test.exs` runs inside elixir-ls. It starts the language
server and sends it a configuration with `mcpEnabled`. Then it asks the server
for its state, which tells if the server is still alive. The container user is
not root, so a listen on port 80 fails with `:eacces`. `192.0.2.1` is a
documentation address, so no machine has it. The results are the same on the
three elixir images:

| Case | Code | Setting | Code uses it | OS answer to that listen | Language server | Exit reason |
|------|------|---------|--------------|--------------------------|-----------------|-------------|
| 1 | `master` | `mcpPort` 80 | yes | `:eacces` | down | `{:shutdown, {:failed_to_start_child, MCP.TCPServer, :eacces}}` |
| 2 | `master` | `mcpHost` `192.0.2.1` | no | `:eaddrnotavail` | alive | - |
| 3 | patch | `mcpPort` 80 | yes | `:eacces` | alive | - |
| 4 | patch | `mcpHost` `192.0.2.1` | yes | `:eaddrnotavail` | alive | - |
| 5 | patch | the MCP tests | - | - | 27 of 27 pass | - |

### The patch

The pull request is one commit. It is a patch in `patches/`, made with
`git format-patch` against `master`. To apply it on the elixir-ls clone, with
the message and the author:

```text
git checkout 68df44b681ee0dbef91b8008b0354003a9a451fa
git am ../elixir-ls-mcp-bind-measurements/patches/0001-Bind-the-MCP-server-to-loopback.patch
```

The first version of the pull request was commit
`c0138dc47d7bfdfdcb2fc233325a36db5363a44f`. It bound the server to the literal
`127.0.0.1`. The 4 new tests of the patch, in Docker, with Elixir 1.18.4 on
OTP 27:

| Code under test | Pass | Fail |
|-----------------|------|------|
| `master` | 0 | 4 |
| first version | 1 | 3 |
| patch | 4 | 0 |

### Not measured

- Windows and macOS. The runs use Linux containers only.
- A system with no IPv6 loopback. The containers here have `::1`.
- A second physical host. The non-loopback address is the bridge address of
  the container. A connect to it takes the same path as a connect from a
  remote host.
- The accept errors `:closed` and `:einval`, which the patch handles in the
  accept loop. They come when the listen socket closes, and no run here
  reproduces them.
- A `tools/call` request from the LAN address of a host. On `master` the server
  answered it. This was measured on a Linux host with OTP 27 and Elixir 1.20.0,
  not in Docker.

License: MIT.
