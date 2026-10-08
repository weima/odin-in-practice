# Worker activity over local IPC

<a id="worker-activity"></a>

## 17a. Watch worker activity without confusing it for liveness

A Worker can report useful progress without sending its private conversation to the supervisor. In Coffee Shop, Pi emits JSON events; a Worker adapter translates only a small allowlist of those events into normalized activity messages. The supervisor validates each message, persists a bounded recent history, then derives a status snapshot alongside the authoritative process identity.

```text
Pi JSON events -> Worker adapter -> bounded activity messages
                                      | local Unix stream socket
                                      v
                         supervisor validation -> persistence -> status snapshot
```

The adapter is a privacy and compatibility boundary, not a JSON-event forwarder. Keep prompts, tool arguments, tool results, generated output, credentials, and arbitrary exception text out of activity messages. Send only fixed classifications and small identifiers needed to associate progress with a Worker.

### A local stream socket is still a byte stream

On Linux, a Unix-domain stream socket connects local processes without a TCP port or UDP datagrams. It is local IPC, not a network listener, and it does not provide message boundaries. One newline-delimited JSON object is one application event; a `send` or `recv` can cover part of a line or several lines. Buffer bytes until `\n`, parse each complete line, and retain any bytes after the last delimiter for the next pass.

Odin's [`core:net`](https://github.com/odin-lang/Odin/tree/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/net) is its TCP, UDP, and DNS API. For POSIX Unix-domain sockets, use `core:sys/posix`: `socket(.UNIX, .STREAM)`, `bind`, `listen`, `accept`, `connect`, `recv`, and `send` are declared in [`sys_socket.odin`](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/sys/posix/sys_socket.odin); the Linux `sockaddr_un` layout is in [`sys_un.odin`](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/sys/posix/sys_un.odin). These are OS-backed descriptors: close them on every path and manage the socket pathname's permissions, stale-file cleanup, and lifetime. This companion focuses on Linux and does not implement that socket lifecycle.

Do not substitute [`core:terminal`](https://github.com/odin-lang/Odin/tree/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/terminal): it handles terminal presentation and capability detection, not Herdr workspace or tab control. For ordinary workspace automation, prefer the [Herdr CLI](https://herdr.dev/docs/cli-reference/). Herdr's [documented socket API](https://herdr.dev/docs/socket-api/) is separate: it uses a Unix-domain socket on Unix and a named pipe on Windows. Neither is the activity transport described here.

### Bound and normalize every event

The companion accepts a strict JSON object with exactly four fields:

```json
{"version":1,"worker":"worker-7","sequence":12,"kind":"progress"}
```

A line is at most 512 bytes, excluding its newline. The parser uses Odin's pinned [`core:encoding/json` parser](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/encoding/json/parser.odin) in strict `.JSON` mode and explicitly rejects tokens after the object. Version must be `1`; `worker` must contain 1–48 ASCII letters, digits, `_`, `-`, or `.`; `sequence` must be a positive integer; and `kind` must be one of `started`, `progress`, `blocked`, `completed`, or `failed`. Unknown fields, values, kinds, malformed JSON, and oversized lines are rejected. These limits bound parser input and keep event content from becoming a covert channel for arbitrary logs. The example validates one already-framed line; its caller still has to enforce the limit while accumulating bytes, before an unbounded buffer can grow.

Give each event a monotonically increasing sequence within its Worker identity. The supervisor can reject duplicates or stale updates and detect gaps. Keep any queue and persisted history bounded too. A disconnected client, EOF halfway through a line, invalid event, or slow reader must not stall Worker execution: discard an incomplete final line, close or quarantine a bad client, and use a bounded best-effort queue that can drop activity when full. A missing activity event means only that no event was observed; it is not a failed operation. If delivery or persistence must be guaranteed, add an explicit acknowledgement/replay contract rather than pretending a successful local `send` proves supervisor receipt.

### A snapshot is not a liveness check

The latest accepted event is useful context, not proof that the Worker still exists or has completed. A process can crash after sending `progress`, or send `completed` before exiting; the event can also be delayed, dropped, or left in a buffer. Build a status snapshot from both sources: show the validated recent activity, but determine liveness and completion from the supervisor's process handle and verified process identity. A PID alone can be reused; pair it with the identity evidence described in [Chapter 15](cli-linux.md#dogfood-supervision). If the identity cannot be verified, report unknown rather than promoting stale activity to “alive.”

This boundary is the same whether you watch a Pi Worker, a test subprocess, or another local child. It keeps progress observable while leaving process control and lifecycle truth with the supervisor.

The small [companion package](../examples/17a-worker-activity/activity.odin) tests the bounded parser and allowlist with `core:testing`. It does **not** create a socket, implement stream buffering, persist snapshots, or prove delivery; those operational paths still need integration tests before production use.
