# Parallel programming lab

This is one complete Linux/native-thread package: `main.odin`, `parallel.odin`, and `parallel_test.odin`. The teaching baseline is Odin's official monthly `dev-2026-10` release (reported by the compiler as `dev-2026-10-nightly:84bc3fc`).

From the book root:

```sh
odin version
odin check docs/examples/19-parallel
odin run docs/examples/19-parallel
TZ=UTC odin test docs/examples/19-parallel
```

The program squares 10,000 signed values using four workers and checks the deterministic checksum `83333335000`. This is a correctness demonstration, not a speed benchmark or an async/await implementation.

The API admits at most 1,048,576 items and 1–16 requested workers. Input must remain immutable, output must occupy a separate non-overlapping range, and both buffers remain alive through joining. Valid inputs lie in ±1,000,000,000. Any non-success result invalidates the whole output; partial writes may remain.

An optional external stop flag is borrowed until the call returns. Initialize it before publication and use atomic operations for every concurrent read/write. Cancellation is cooperative between items, not forced termination or a guaranteed wall-clock deadline.

Tests cover the sequential oracle, uneven partitions, empty/small input, bounds, overlap, pre-cancellation, domain failure and partial thread-creation failure. The test allocator permits one handle allocation, rejects the next, and verifies cleanup. It delegates successful allocations to the test runner's allocator; it does not pretend to make the worker's context inherit that allocator.

## Verification

With the reference compiler on Linux, the package passed `odin check` and `odin build`; the program produced the expected checksum, and all seven tests passed with memory tracking enabled. The book's 31 chapter headings and local links were also checked. No speedup, other-platform execution, or exhaustive schedule coverage is claimed.

See [the chapter](../../chapters/parallel-programming.md) for thread-pool completion, allocation ownership, JavaScript Promise comparisons, production obligations and exercises. Tests do not prove all schedules race-free or establish performance on other machines.
