# Network programming

<a id="networking"></a>

Chapter 17 · Protocols, budgets, and trust boundaries

## 17. Network programming and a practical HTTP client

A program writes four bytes once, and its peer reads two bytes twice. Which side is broken? With TCP, neither necessarily is. A connection supplies a byte stream, not the record boundaries of the application that wrote it. That single distinction affects parser state, buffering, timeouts, and every claim that an echo demo is a complete protocol implementation.

This chapter uses the [pinned `core:net` source](https://github.com/odin-lang/Odin/tree/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/net), not guessed API names from another language. The companions perform TCP and UDP exchanges on `127.0.0.1`, using port zero to let the OS choose an available port. The HTTP client uses a maintained curl implementation rather than inventing HTTP parsing or TLS.

### 1. An address is not a socket, and a socket is not a message

`net.Endpoint` contains an address and port. A socket is an OS-backed handle with protocol state and a release obligation. A TCP listener accepts connections; each accepted socket is a separate resource. Closing an accepted connection is not the same operation as closing the listener. A UDP socket exchanges datagrams and need not accept each peer.

IPv4 and IPv6 are different address representations, not strings with interchangeable punctuation. Hostname lookup can return multiple candidates, fail, or take time. Parsing an IP literal is not DNS resolution, and resolving a hostname is not authenticating the server. Use endpoint/hostname procedures appropriate to the input contract.

In this revision, `dial_tcp_from_host` resolves a host and selects IPv4 when available, otherwise IPv6. Read that source before assuming a complete staggered multi-address connection strategy. A portable function name is not a guarantee of identical selection policy or cancellation behavior on every target.

While reading these wrappers, a lone `return` does not necessarily mean “no result.” `_listen_tcp` declares named `socket` and `err` results; its error branch returns their current values. See [Chapter 4's line-by-line explanation](odin-foundations.md#bare-returns), including why a returned numeric handle can already be closed on failure.

### 2. A real receive wrapper has a smaller promise than an application

The Linux implementation in [socket\_linux.odin](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/net/socket_linux.odin) delegates a receive to the kernel and translates its result. This short excerpt belongs inside that package:

```odin
bytes_read, errno := linux.recv(linux.Fd(tcp_sock), buf, {})
if errno != .NONE {
    return 0, _tcp_recv_error(errno)
}
return int(bytes_read), nil
```

It does not assemble your record. With a non-empty requested buffer, `0, nil` signals a gracefully closed TCP receive side. Requesting an empty buffer also returns zero in this wrapper, so do not use a zero-length read to test for EOF. A reset is an error, while a timeout and a nonblocking would-block condition have their own meanings.

The loopback companion’s `receive_exact` repeatedly reads into the unfilled suffix and deliberately limits each read to one byte. That proves the application does not depend on a send matching a receive. EOF before the expected count is a truncated record, not a successful shorter message.

```odin
// From the complete TCP companion: fixed-size record contract.
total := 0
for total < len(target) {
    n, err := net.recv_tcp(socket, target[total:][:1])
    if err != nil || n == 0 { return false }
    total += n
}
```

A real reusable API should preserve the received count and a suitable failure category instead of this teaching helper’s boolean. The buffer already contains partial bytes if a later read fails. Define whether those bytes may be inspected and whether the connection remains usable.

### 3. Sending all bytes is not an acknowledgement

Some socket APIs return after one partial write. In this pinned Odin library, `send_tcp` already loops over the remaining suffix and returns a sent count plus error. On failure it can report partial progress. Inspect the source and check both results; do not write a redundant loop based solely on another language’s send API.

A successful send means the local stack accepted the bytes under this API’s contract. It does not prove that the remote application parsed them or committed an operation. If an application needs acknowledgement, define a response and a correlation or sequence rule. Blindly retrying a request after an ambiguous disconnect can duplicate an external action.

The Linux send path uses `NOSIGNAL` to avoid a broken connection delivering SIGPIPE through that call. This is an implementation fact, not permission to ignore a returned connection error. A blocking send can still wait; buffer limits and deadlines belong to the larger protocol design.

### 4. Framing defines the parser’s obligations

Common framing choices include a fixed record size, a delimiter, a length prefix, or a higher-level protocol. A delimiter can span reads, and two messages can arrive in one read. A length prefix must be fully read, decoded in the protocol’s byte order, validated against a maximum, and checked for overflow before allocating payload storage.

For a two-byte big-endian length prefix, bytes `{0, 4}` advertise four payload bytes. Do not cast that buffer to a native integer pointer: host byte order, alignment, and layout are different concerns. Decode bytes deliberately, and reject a declared length above your budget before allocating.

Keep parser state when a read ends in the middle of a record. Keep unconsumed bytes when a read includes the next record. A parser that always discards its read buffer after finding one delimiter loses valid data. Exercise the parser with every possible split point, not only a single convenient network exchange.

### 5. UDP preserves datagrams, not delivery guarantees

One UDP send represents one datagram. Delivery, ordering, uniqueness, and congestion handling are not guaranteed. UDP is useful when the application genuinely chooses those trade-offs; it is not a simpler drop-in replacement for TCP reliability.

A zero-byte UDP datagram is valid data, not TCP-style EOF. If the receive buffer is too small, the rest of that datagram is not available as a continuation read. In the pinned Linux implementation, `recvfrom` uses the truncation flag and returns `Excess_Truncated` when the reported datagram is larger than the provided buffer. The companion deliberately tests that path. Other platform branches must be checked separately.

Do not echo large datagrams to arbitrary spoofable sources as a casual public demo. Bound request and response sizes, choose authentication/rate limits where appropriate, and keep these learning programs bound only to loopback.

### 6. A bounded buffer is not a deadline

The TCP and UDP companions set per-operation socket timeouts using `time.Duration`, as required by the Linux option adapter. Passing an integer that happens to mean “one second” is not the same typed contract. These timeouts do not automatically establish a whole-operation budget for DNS, connection attempts, repeated reads, and processing.

A peer can send one byte shortly before each read timeout and keep a naive record reader busy indefinitely. Use a monotonic overall deadline, plus limits on message bytes, message count, concurrent connections, and queued work. Nonblocking readiness is a hint that an operation may proceed, not a guarantee the next operation cannot return would-block.

For larger systems, study `core:nbio` and the selected platform event mechanism rather than assigning an unbounded thread to every accepted connection. Start with a bounded blocking design when it satisfies the actual workload. Measure before replacing it with a custom event framework.

### 7. A half-close is a protocol event

A TCP peer can finish sending while still receiving. The companion calls `shutdown(client, .Send)`, then confirms that the other side observes a graceful EOF after consuming the request. Closing the whole connection earlier would change the protocol.

Ownership must remain clear on every failure path: the listener, client, accepted socket, and buffers are distinct resources. Install cleanup after successful acquisition and return through their scope. No allocation wrapper makes an OS socket close itself simply because its handle is copied.

### 8. Use an HTTP implementation instead of rebuilding one accidentally

HTTP adds methods, status codes, headers, body framing, connection reuse, redirects, and version-specific rules. TLS adds peer authentication, certificate/hostname verification, cryptographic negotiation, and trust-store configuration. A hand-written `GET / HTTP/1.1` string followed by a receive loop is not a production HTTPS client.

The distribution includes [libcurl bindings](https://github.com/odin-lang/Odin/tree/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/vendor/curl). The binding’s C calling conventions, long option types, callbacks, and external library requirements need an ABI-aware integration. On the validation machine, the installed curl CLI is usable while the vendor binding’s development-library link requirements are not all present. The runnable companion therefore uses the existing CLI through an argument vector—no dependency installation or home-grown TLS.

This is an HTTP client adapter, not just a shell command concatenation. It has an input contract, request limits, transport result, HTTP status, owned capture buffers, and a caller-facing policy. A subprocess per request is suitable for some small batch tools; connection reuse, cancellation, and throughput requirements can justify an in-process maintained client later.

### 9. The runnable GET client separates transport from HTTP policy

[The complete companion](../examples/17-networking/http-client/main.odin) accepts a numeric loopback port and a small allowlist of fixture paths. It constructs the URL itself, so a prefix check cannot accidentally admit a URL whose user-info disguises another host. It does not follow redirects or accept arbitrary network targets.

```text
// Excerpt from the companion's argument vector; url is constructed locally.
"/usr/bin/curl", "--disable", "--silent", "--show-error",
"--connect-timeout", "1", "--max-time", "2",
"--max-filesize", "65536", "--proto", "=http",
"--noproxy", "*", "--write-out", "\n%{http_code}", "--", url
```

The first curl option disables user configuration files so they cannot silently add other transfers or change the request policy. The surrounding command uses GNU timeout as an outer subprocess bound. The curl timeout bounds its transfer; the maximum size limits the response body. Curl 8.4 and newer enforce that size while downloading too; verify the installed version when relying on the limit. A post-download size check alone would not bound peak capture memory. The narrow profile deliberately disables proxy routing for its loopback fixture; an enterprise client needs an explicit proxy policy rather than blindly copying that setting.

On successful transport, the three-digit status trailer is parsed separately from the body. A `404` is a real HTTP response, not a socket failure. This CLI prints a successful body only for 2xx results and returns a distinct status for HTTP rejection. A launch error, curl transport failure, invalid trailer, timeout, and oversized body are different failure cases.

The body slice borrows the captured stdout allocation. Consume it before releasing stdout, or clone it into an owner whose lifetime covers later use. The adapter releases both output buffers even when the child fails. Capture is acceptable here because the response is intentionally bounded; a streaming client must still consume backpressure without retaining an unlimited body.

### 10. Moving from the fixture to a production client

- **Target policy:** validate schemes, hostnames, ports, resolved addresses, proxy routes, and redirect targets. A safe initial URL does not make a redirected or newly resolved target safe; address validation must account for the actual connection.
- **TLS:** use HTTPS for real credentials/data, retain certificate and hostname verification, maintain a trust store, and test expiry and untrusted certificates. Do not solve an error with a blanket verification-disable flag.
- **Budgets:** include DNS/connect/transfer and an overall deadline; cap headers and decompressed body bytes, redirects, concurrent requests, and retries.
- **Retry policy:** distinguish transient transport failure from permanent rejection; bound retries with backoff/jitter and honor protocol guidance. Non-idempotent requests need an application-level duplicate-prevention contract.
- **Secrets:** keep credentials out of URLs, command-line history, process arguments, and diagnostics. An authenticated long-lived client often needs a different integration than this credential-free CLI fixture.
- **Reuse:** an in-process libcurl handle/pool can reuse connections, but handles, callbacks, owned response buffers, and thread access still require explicit lifetimes.
- **Evidence:** test redirects, malformed responses, status families, truncated bodies, TLS failures, deadlines, cancellation, and large/decompressed responses in an isolated environment.

These are deployment requirements, not capabilities silently supplied by this loopback example. The companion intentionally does not claim authenticated HTTPS integration, a connection pool, or arbitrary-URL safety.

### Companion exercises

**Exercise 17.1 · TCP is not a record API.** Run the loopback exchange, then change the read window to two bytes. Add a length-prefixed record with a 64-byte maximum. Test every split of the header and payload, two records in one input buffer, and EOF halfway through the payload. Expected result: identical parsed records for every valid split and an explicit truncation result for the incomplete case.

**Exercise 17.2 · HTTP has two success questions.** Use the local fixture commands in the companion README. Check `/ok`, `/missing`, an oversized body, and a delayed response. Assert stdout, stderr, and exit status separately. Expected result: transport success does not convert 404 into application success; a timeout or body-budget failure emits no partial success body.

**Exercise 17.3 · Audit the real wrappers.** Compare `recv_tcp`, `send_tcp`, and the selected Linux implementations. Explain why the sender wrapper already retries remaining bytes, why the receiver does not assemble a record, and why UDP truncation cannot be completed by another read. Then compare another platform branch without claiming it was executed.

**Checkpoint.** Name the protocol framing, valid peer, byte budget, operation deadline, ownership/release path, and acknowledgement rule before calling the connection a complete design.
