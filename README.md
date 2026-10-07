# Odin in Practice

**Read the book: https://weima.github.io/odin-in-practice/**

A 31-chapter, source-guided book for programmers learning Odin through practical systems work: ownership, memory, Linux command-line tools, networking, Docker, parallel programming, and FFmpeg/libav.

## Markdown source; HTML for readers

- **Edit `docs/**/*.md`**, not the generated HTML.
- Mermaid sources live in `docs/diagrams/*.mmd`; rendering produces local SVGs in `docs/assets/diagrams/`.
- Precise pointer diagrams and the original illustrated cover remain SVG.
- **The prebuilt `html/` folder is retained in the repository.** Open `html/index.html` to read without installing publishing tools.
- [Download the complete offline reader](https://weima.github.io/odin-in-practice/odin-in-practice-offline.zip), extract it, and open its `index.html`. Styles, diagrams, code companions, and the skill ZIP are local. External references still require the internet.
- Search may need a local HTTP server because browser restrictions apply to workers/fetches on `file:` URLs. `python3 -m http.server --bind 127.0.0.1 --directory html 8000` serves the already-built reader without internet access.

| Part | Markdown source | Topics |
| --- | --- | --- |
| Foundations | [Chapters 1–4](docs/chapters/odin-foundations.md) | Packages, values, procedures, bare returns, independent generic types |
| CLI and Linux | [Chapters 5–9, 12–16, 20–22](docs/chapters/cli-linux.md) | Arguments, errors, allocators, files, processes, tests, composition |
| Pointers | [Chapter 10](docs/chapters/pointers.md) | Aliases, headers, views, lifetime and foreign pointers |
| Memory philosophy | [Chapter 11](docs/chapters/memory-philosophy.md) | Allocation strategy, context, errors and rollback |
| Networking | [Chapter 17](docs/chapters/networking.md) | TCP/UDP, framing, deadlines and a loopback HTTP adapter |
| Docker | [Chapter 18](docs/chapters/containers.md) | Port 1333, interactive shells, network peers, bind mounts and volumes |
| Parallel programming | [Chapter 19](docs/chapters/parallel-programming.md) | Threads, ownership, synchronization, cancellation and pools |
| FFmpeg and libav | [Chapters 23–28](docs/chapters/ffmpeg-libav.md) | Probing, JSON, foreign calls, decoding, remuxing and timestamps |
| Workbook | [Chapters 29–31](docs/chapters/workbook.md) | Exercises, glossary and pinned source trail |

Existing chapter page names and explicit anchors are retained. MkDocs uses `use_directory_urls: false`, so `docs/chapters/networking.md` becomes `html/chapters/networking.html` and keeps the public `.html` route.

## Build and preview

The publishing tools are **MkDocs + Material**, with Mermaid CLI generating SVGs before the site build. Python dependencies are hash-locked in `requirements.txt`; Node dependencies are locked in `package-lock.json`. Use Node 24 and Python 3.12 or later. The companion examples and CI use Odin's pinned official monthly `dev-2026-10` release.

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install --require-hashes -r requirements.txt
npm ci
npm run diagrams
mkdocs build --strict
python tools/check-book.py
python tools/package-offline.py
```

After editing a diagram, rerun `npm run diagrams`. Preview Markdown edits with `mkdocs serve --dev-addr 127.0.0.1:8000`. Before committing, rebuild the tracked `html/` reader and offline ZIP. Do not edit generated files by hand.

## GitHub Actions and Pages

The complete workflow is [`.github/workflows/pages.yml`](.github/workflows/pages.yml). CI selects the Ubuntu runner's preinstalled `/usr/bin/google-chrome` through `PUPPETEER_EXECUTABLE_PATH`, avoiding the downloaded Chrome-for-Testing sandbox failure. Chromium sandboxing remains enabled; the workflow does not disable AppArmor or use `--no-sandbox`. Puppeteer also skips its browser download when this executable is selected.

One-time repository setup:

1. Push the completed branch and bring the reviewed changes into `main`.
2. Open **Settings → Pages → Build and deployment → Source** and select **GitHub Actions**.
3. In **Actions**, open **Build and publish the book**. A main-branch update runs it automatically; **Run workflow** can rebuild `main` manually.
4. If a protected `github-pages` environment requires approval, approve that deployment under your repository's policy.
5. Check the deployment URL shown by the workflow and download the offline reader from the book.

The build job installs the locked dependencies, downloads and SHA-256 verifies the pinned official Odin release, checks all 18 standalone book packages, runs the book's Odin tests and the companion-skill CLI/network examples, renders Mermaid SVGs, builds HTML with strict link validation, checks the generated reader, and creates the offline ZIP. The deploy job publishes the freshly built `html/` artifact only for `main`. Changes submitted for review build without publishing. The workflow **does not commit or push generated files back to your branch**; it does not create or merge a change request. Its deployment uses GitHub's automatic token, not a personal access token.

Publishing dependencies currently report a low-severity transitive KaTeX advisory (GHSA-238p-pmpm-9mq7). The diagrams are trusted repository inputs with strict Mermaid security, and KaTeX is not shipped as a reader runtime. Do not use this build as an arbitrary untrusted-diagram rendering service; dependency updates need a fresh rendering check rather than a forced automatic downgrade.

The committed reader provides an immediately usable offline copy at each locally rebuilt revision; Actions separately rebuilds the published website and downloadable archive from Markdown. The automated workflow has to run on GitHub before its remote deployment can be claimed verified.

## Run the Odin companions

Reference compiler: Odin's official monthly **`dev-2026-10`** release (compiler-reported version `dev-2026-10-nightly:84bc3fc`), source commit [`84bc3fc2100b0f7880a3af37f71bccdcda41c6f9`](https://github.com/odin-lang/Odin/commit/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9). This is a pinned monthly release, not a promise of semver-style language stability. Inspect your installed compiler/library before copying implementation-specific APIs.

```sh
odin version
odin run docs/examples/04-procedures
TZ=UTC odin test docs/examples/04-procedures
odin run docs/examples/19-parallel
TZ=UTC odin test docs/examples/19-parallel
```

Each complete program has its own package directory. Inline fragments, pseudocode, and intentional compiler-failure experiments are labeled. Tests and reusable helpers stay alongside the relevant program.

The loopback/CLI integration lab builds the HTTP adapter and four CLI commands, then runs `python3 docs/examples/verify_systems.py`. The Docker recipes are explicit local exercises; no image pull, container launch, or daemon operation is implied by the book build. The read-only Odin Docker companion defaults to a dry run.

The native media companion targets **FFmpeg 6.x** (avformat 60, avcodec 60, avutil 58), needs development headers/linker metadata, and is built with `sh docs/examples/26-libav-decode/build.sh`. Generated binaries/fixtures are not publishing inputs.

## Download the companion skill

The optional [Odin companion skill](docs/skills/odin-companion/README.md) is bundled with the book as a [folder ZIP](docs/skills/odin-companion.zip). Read `SKILL.md` and customize it with your preferred skill-creation tool. Nothing installs globally or changes reader agent configuration automatically.

## Verification evidence

With the pinned compiler on Linux:

- The procedures companion demonstrates bare returns, deferred cleanup, and independent type inference; four tests passed with memory tracking.
- The parallel companion built and produced checksum `83333335000`; seven tests passed with memory tracking. This is correctness evidence, not a speedup claim or exhaustive schedule coverage.
- HTTP parsing, Docker state parsing, and CLI records tests passed. Eighteen loopback HTTP/CLI scenarios passed, including filtering, malformed/oversized input, timeout cleanup, launch failure, and refusal to publish partial upstream success.
- Native decode/remux passed sixteen generated-fixture scenarios, including ffprobe comparisons, timestamp preservation, frame budgets, protocol/path rejection, non-overwrite behavior, and no Valgrind-reported errors/definite leaks in the tested decode/remux paths.
- The pointer and memory examples and TCP/UDP loopback demonstrations were checked separately. The earlier 26-chapter edition also had eight checked/built programs, eight focused tests, and nineteen runtime scenarios.

These results do not claim every exercise, codec, platform, Docker recipe, or arbitrary input has been validated. Docker runtime execution, deployment permissions, and the GitHub-hosted workflow remain separate verification obligations.

## Cover and attribution

The original SVG cover depicts the mythological Odin and two ravens beside a code page. It reflects the name's origin, not language-design symbolism. Ginger Bill describes Odin as [a mythological codename that stuck](https://forum.odin-lang.org/t/origin-of-the-name-odin/794).

This is an independent learning book, not an official Odin/FFmpeg specification or endorsement. Upstream source retains its own license, including [Odin's zlib license](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/LICENSE).
