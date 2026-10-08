# Standards for Odin in Practice

These standards apply to every change to the book: chapters, companion code and diagrams. People and automated Workers follow them, and an automated review checks changes against them.

## Truth

- Reproduce every claim about compiler, library or operating-system behaviour with the pinned compiler (official release `dev-2026-10`; `odin version` prints `dev-2026-10-nightly:84bc3fc`). Quote real compiler errors verbatim.
- If a source of the claim (a bug report, a project's experience, a brief) disagrees with what you observe, say so in the text. Do not smooth it over.
- "It did not crash once" is not "it is safe". Undefined behaviour must be named as undefined, even when an experiment happened to survive it.
- Confirm library names and signatures in the bundled source (`$(odin root)/core/...`). Link Odin source at the pinned commit `84bc3fc2100b0f7880a3af37f71bccdcda41c6f9`, in the link style the existing chapters use, and make sure each linked file exists there.

## Structure

- The chapter headings are exactly 1-31 plus 13a and 17a (`tools/check-book/` enforces this). Add new numbered chapters only when the user explicitly approves them; otherwise add material as unnumbered `###` subsections inside the relevant chapter. Never renumber existing chapters.
- Where a file uses explicit anchors (`<a id="...">`), give every new subsection a unique one.
- Add; do not rewrite existing text without a reason a reviewer can see.
- `html/` and the offline ZIP are generated. Never edit them by hand; rebuild them once, when the change is complete.

## Style

- Second person, precise, and honest about trade-offs. Short code blocks that compile.
- Call out ownership and failure wherever they matter. Label Linux-specific material as such.
- Match the tone and depth of the neighbouring sections.

## Companion code

- A new example lives in `docs/examples/<chapter>-<topic>/`: a library package plus `_test.odin` tests. Add a `main.odin` only when it helps teaching, because CI compiles every `main.odin`.
- Tests use `core:testing`, pass under `TZ=UTC odin test <dir>`, show no memory-leak warnings, touch nothing outside a temporary directory, and need no network.
- Code that is meant to fail to compile is never committed as a compiling package. Show it as a verified transcript in the chapter.
- Keep it small and readable; the example is for teaching.
- Format Odin code with `odinfmt` and the repository's `odinfmt.json`: 4 spaces, 100 columns, LF line endings. `odinfmt` defaults to CRLF, so always pass the config. Put one statement on each line; `odinfmt` does not split statements chained with `;`, so split them first. The existing examples use 4-space indentation and stay within about 110 columns.

## Verification

- `just verify` runs everything: `check` (every example package), `test` (every suite), `skill-examples` and `site` (`mkdocs build --strict` into a temporary directory). All four must pass.
- Every new example package must be added to the `justfile`, to `docs/examples/README.md` and to the CI workflow.
