# Runnable companions

Commands below run from the repository root, with the pinned Odin compiler on `PATH`. These sources are also included beside the offline HTML reader. Their directory labels are stable companion identifiers; some companions cover several chapters.

| Companion | Read or run | Focus |
| --- | --- | --- |
| [Procedures](04-procedures/main.odin) | `odin run docs/examples/04-procedures` | Bare returns, deferred cleanup, independent types |
| [Pointers](10-pointers/aliases/main.odin) | Programs under `10-pointers/`; tests under `10-pointers/tests/` | Aliases, record views, multi-pointers, owned results |
| [Memory](11-memory-philosophy/arena-snapshot/main.odin) | Programs under `11-memory-philosophy/`; tests under `11-memory-philosophy/tests/` | Scratch/result lifetime, allocation failure, explicit errors |
| [TCP](17-networking/tcp-loopback/main.odin) / [UDP](17-networking/udp-loopback/main.odin) | `odin run docs/examples/17-networking/tcp-loopback` | Loopback transport and bounded messages |
| [HTTP adapter](17-networking/http-client/main.odin) | Build and run with a loopback port and fixture path | Curl argument vector, response/body/deadline distinctions |
| [Docker inspection](18-containers/main.odin) | `odin run docs/examples/18-containers` | Dry-run default; `--execute` opts into inspecting the named local lab |
| [Parallel map](19-parallel/README.md) | `odin run docs/examples/19-parallel` | Disjoint writes, stable descriptors, joining, errors and cancellation |
| [CLI pipeline](21-capstone/run-pipeline/main.odin) | Build four stages as below | NDJSON boundaries and all-stage success before publication |
| [Native media](26-libav-decode/README.md) | Build narrow C bridge and Odin caller | Decoder retries/drain, remux timestamps, staged output |

## Focused tests

```sh
TZ=UTC odin test docs/examples/04-procedures
TZ=UTC odin test docs/examples/10-pointers/tests
TZ=UTC odin test docs/examples/11-memory-philosophy/tests
TZ=UTC odin test docs/examples/17-networking/http-client
TZ=UTC odin test docs/examples/18-containers
TZ=UTC odin test docs/examples/19-parallel
TZ=UTC odin test docs/examples/21-capstone/records
```

## HTTP and CLI integration lab

Needs Linux, Python's standard library, `/usr/bin/curl`, and `/usr/bin/timeout`. The harness creates its own loopback HTTP fixture and temporary files; it does not start Docker or contact a remote service.

```sh
mkdir -p docs/examples/17-networking/http-client/.build
odin build docs/examples/17-networking/http-client \
  -out:docs/examples/17-networking/http-client/.build/http-client
mkdir -p docs/examples/21-capstone/.build
for stage in inspect select summarize run-pipeline; do
  odin build "docs/examples/21-capstone/$stage" \
    "-out:docs/examples/21-capstone/.build/$stage"
done
python3 docs/examples/verify_systems.py
```

To use the runner yourself, pass the **absolute trusted binary directory**, a minimum byte count, and input files. Diagnostics use stderr; final stdout is published only after all stages succeed.

```sh
docs/examples/21-capstone/.build/run-pipeline \
  "$(pwd)/docs/examples/21-capstone/.build" 10 ./README.md
```

Do not mistake this bounded example for a general process-tree supervisor. Its timeout/cleanup contract concerns its direct children. The chapter explains the small final-output budget and why wait-before-read is not safe for arbitrary output.

## Docker lab

The [Docker chapter](../chapters/containers.md) explains how to run the supplied [Compose fixture](18-containers/compose.yaml), inspect your local context, connect peers, open shells, and expose host folders. These are exercises for an owned local daemon, not a build prerequisite. The Compose and container recipes were not executed during authoring verification.

## Verification limits

A passing test demonstrates the listed input/behavior on the pinned Linux environment, not arbitrary inputs or every platform. Generated binaries, native archives and fixtures belong in ignored `.build/` or `.fixtures/` directories and are excluded from the reader. Rebuild with your installed compiler rather than downloading an executable of unknown provenance.
