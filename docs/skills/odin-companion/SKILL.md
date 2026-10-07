---
name: odin-companion
description: "Trigger: Odin code, pointers, allocators, parallelism, CLI or libav. Ground changes in the installed compiler and Odin in Practice."
license: "Not specified; consult the book repository's licensing."
metadata:
  author: "weima"
  version: "1.0"
---

## Activation Contract

Load for writing, debugging, reviewing or explaining Odin code alongside the book.

## Hard Rules

- Treat the installed compiler and library source as authority; distinguish the book's pinned edition from the reader's compiler.
- State ownership, borrowed lifetimes, release obligations and partial-failure behavior at each boundary.
- Use native threads and documented synchronization for parallel work; never invent built-in JavaScript Promise or async/await support.
- Keep demos separate from production claims. Request permission before installing tools, accessing credentials, contacting production or starting containers.

## Decision Gates

| Task | Inspect first |
| --- | --- |
| Language or library API | Installed declarations and target implementation |
| Memory or threads | Allocator state, publication, cancellation and joining |
| CLI or networking | Framing, budgets, exit/error contract and cleanup |
| C or libav | Installed headers, ABI/version, ownership and state machine |

## Execution Steps

1. Read [the source and verification checklist](references/checklist.md) for the relevant branch.
2. Record `odin version` and locate libraries with `odin root`; inspect exact signatures before editing.
3. Make the smallest change that satisfies the request. Reuse the project's conventions and dependencies.
4. Check a complete package, run focused tests and exercise success plus the relevant failure boundary.
5. Report compiler/platform, commands, results and untested obligations; attach measurements before claiming a speedup.

## Output Contract

Return changed paths, verified behavior and remaining limits. Label fragments, intentional compile failures and complete runnable programs distinctly.

## Runnable starting points

The [CLI example](examples/cli/main.odin) uses `core:flags` to parse a required positional name and a boolean option. The [network example](examples/network/main.odin) performs a bounded TCP round trip on loopback, checks the exact byte count, and defers socket cleanup. Both are complete programs, not production templates.

```sh
odin run examples/cli -- Ada --loud
odin run examples/network
```

The network example binds only to loopback and uses operation timeouts. It is a local exercise, not an Internet-facing server. CI compiles and runs both examples with the book's pinned official monthly `dev-2026-10` release.

## References

- [Source, ownership and verification checklist](references/checklist.md)
