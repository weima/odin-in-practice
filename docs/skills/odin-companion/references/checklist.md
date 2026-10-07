# Source and verification checklist

## Find the right edition

The book's baseline is Odin's official monthly `dev-2026-10` release, source commit `84bc3fc2100b0f7880a3af37f71bccdcda41c6f9`. The compiler reports `dev-2026-10-nightly:84bc3fc`; this is a pinned release asset, not semver-style language stability. Record the reader's actual `odin version`; do not assume newer signatures match.

Use `odin root` to locate installed `base/`, `core/` and `vendor/`. Search for the symbol and inspect its implementation, platform selection, error results and allocation behavior. Resolve renamed files from the installation rather than trusting a remembered filename. Check installed compiler help for available options.

Read the relevant book chapter and companion when the book is available locally. Otherwise this folder remains usable on its own; it does not require a private machine path, a global skill installation or the author's environment.

## Select only the relevant branch

- **Packages, imports or visibility:** read [the package guide](packages.md) and inspect the directory layout. Keep same-responsibility files in one package; make a subpackage only for a deliberate API boundary. Imports are declared per file, declarations are public by default, and `@(private="package")` / `@(private="file")` narrow access. For a complete checked pattern, run the bundled [`05-packages` example](../examples/05-packages/README.md).
- **Pointers and memory:** distinguish pointer binding from target mutation; copied slice/string/allocator headers can share storage. Trace the owner, allocation domain, lifetime and every cleanup/rollback path. Arena reset invalidates outstanding borrows.
- **Errors:** inspect ordinary return types and required-result rules. Propagate errors without misclassifying partial output as success; keep cleanup separate from transactional rollback.
- **Parallel work:** identify immutable input, disjoint writes or one synchronized invariant. Preserve stable descriptors and allocator state. Join before freeing borrowed memory, handle partial startup failure, and distinguish stop requests from completion. Threads/pools are not JavaScript Promises or compiler-supported await.
- **Processes and networking:** keep argv separate from shell text, define framing and output limits, own every handle, and establish deadlines at blocking operations. A killed client does not prove a remote or daemon-side operation stopped.
- **Containers:** distinguish illustrative recipes from tested deployment. Verify image/runtime ABI, CPU/memory limits, signal behavior, readiness, secrets and output publication. Use only an explicitly approved disposable daemon.
- **C/libav:** verify header and runtime versions, layout, calling convention, string lifetime and callbacks. Follow packet/frame ownership, EAGAIN retry and EOF drain contracts. Keep failed output in staging and define publication independently.

## Establish evidence

Use the repository's existing package layout and checks. Typical Odin commands are:

```sh
odin version
odin check path/to/package
odin build path/to/package
odin test path/to/package
```

Use a separate package for mutually exclusive main programs. Add a narrow behavioral regression test instead of a generic new test framework. Cover the ownership/error boundary changed by the task. Use loopback and disposable media fixtures where applicable.

Record exact outcomes, not merely commands that were planned. Passing tests do not prove every schedule safe, every deployment ready, or every foreign codec compatible. Time compiled code against an equivalent sequential baseline before making performance claims.

## Optional book context

The companion was authored for **Odin in Practice**:

- Readable book: https://weima.github.io/odin-in-practice/
- Source and runnable companions: https://github.com/weima/odin-in-practice

These public links are supplementary, not required for loading this skill. Local compiler declarations remain the API authority.
