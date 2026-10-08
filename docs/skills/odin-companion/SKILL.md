---
name: odin-companion
description: "Trigger: Odin code, packages, pointers, allocators, parallelism, CLI or libav. Ground changes in the installed compiler and Odin in Practice."
license: "Not specified; consult the book repository's licensing."
metadata:
  author: "weima"
  version: "1.2"
---

## Activation Contract

Load for writing, debugging, reviewing or explaining Odin code alongside the book. Use the narrowest relevant reference; do not turn a focused change into a framework or a broad rewrite.

## Hard Rules

- Treat the installed compiler and library source as authority; distinguish the book's pinned edition from the reader's compiler.
- State ownership, borrowed lifetimes, release obligations and partial-failure behavior at each boundary.
- Use native threads and documented synchronization for parallel work; never invent built-in JavaScript Promise or async/await support.
- Keep demos separate from production claims. Request permission before installing tools, accessing credentials, contacting production or starting containers.
- Keep package boundaries deliberate. Odin directories define packages; names are public by default unless restricted with a visibility attribute.
- Do not assume Odin has an official package manager or silently use an unpinned external dependency.
- For a repeatable, exactness-critical or syntax-aware file edit, use or adapt the bundled Odin file-processing example rather than an ad hoc script in another language. Use the harness's edit tool for a single edit and existing tools (`rg`, `sed`, `jq`) for simple transforms. A refused edit must leave the file unchanged.

## Decision Gates

| Task | Inspect first |
| --- | --- |
| Language or library API | Installed declarations and target implementation |
| Package layout, imports or visibility | [Package and dependency guide](references/packages.md), source directory and its imports |
| Memory or threads | Allocator state, publication, cancellation and joining |
| CLI or networking | Framing, budgets, exit/error contract and cleanup |
| Editing, searching or checking files | [File and text processing guide](references/file-processing.md) and the bundled `examples/13a-text-processing` |
| C or libav | Installed headers, ABI/version, ownership and state machine |

## Practical Package Workflow

1. Start with one directory package. Split cohesive source across files when navigation helps; same-directory files share declarations, but each file needs its own imports.
2. Create a subdirectory package only for a clear responsibility, independent reuse/testing, or an API boundary worth maintaining. Do not make a package for every file.
3. Keep the CLI entry point, argument interpretation and process exit contract close together. Separate domain operations only when they can be named and tested independently.
4. Treat declarations as public by default. Expose a small API; mark shared implementation `@(private="package")` and file-only details `@(private="file")`. There is no protected inheritance visibility.
5. Keep imports explicit at file scope. Check the local path, package declaration and imported package's actual public API rather than guessing import resolution.
6. Prefer built-in collections and project-controlled dependency source. Vendor dependencies deliberately, record upstream and exact version/commit plus license and local patches, and update/test them intentionally. Never use a moving branch or undocumented local checkout as a reproducible dependency.
7. Treat the bundled [complete package example](examples/05-packages/README.md) and its `.odin` source as a curated reference: inspect the code and test, then adapt its verified patterns instead of guessing Odin syntax or APIs. Check the CLI package, run the default and named cases, and test the imported package. Follow its cleanup for allocated return values.

## Execution Steps

1. Read [the source and verification checklist](references/checklist.md) and any branch-specific reference.
2. Record `odin version` and locate libraries with `odin root`; inspect exact signatures and source before editing.
3. Trace package directories, declarations, imports, callers, ownership and error paths. Choose the smallest boundary that gives a real benefit.
4. Make the smallest change that satisfies the request. Reuse project conventions and dependencies; do not add a package manager or general framework for a local package need.
5. Check a complete package, run focused tests, and exercise success plus the relevant failure boundary. For package work, follow commands in the runnable example and test imported package behavior.
6. Report compiler/platform, commands, results and untested obligations; attach measurements before claiming a speedup.

## Output Contract

Return changed paths, verified behavior and remaining limits. Label fragments, intentional compile failures and complete runnable programs distinctly. Do not claim visibility is a security boundary or claim dependency reproducibility without recording the source/version.

## Runnable starting points

The [CLI example](examples/cli/main.odin) uses `core:flags` to parse a required positional name and a boolean option. The [network example](examples/network/main.odin) performs a bounded TCP round trip on loopback, checks the exact byte count, and defers socket cleanup. Both are complete programs, not production templates.

```sh
odin run examples/cli -- Ada --loud
odin run examples/network
```

The network example binds only to loopback and uses operation timeouts. It is a local exercise, not an Internet-facing server. CI compiles and runs both examples with the book's pinned official monthly `dev-2026-10` release.

The [text-processing example](examples/13a-text-processing/main.odin) is a tested package behind one command for exact-count replacement, bounded streaming search, and syntax-aware checking and splitting of Odin source. Build it, run its tests, and read [the file and text processing guide](references/file-processing.md) before writing a file-editing tool.

```sh
odin build examples/13a-text-processing -out:textproc
TZ=UTC odin test examples/13a-text-processing
```

## References

- [Package boundaries, visibility and dependencies](references/packages.md)
- [Source, ownership and verification checklist](references/checklist.md)
- [File and text processing](references/file-processing.md)
