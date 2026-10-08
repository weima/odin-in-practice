# Dogfood: using Coffee Shop to extend "Odin in Practice"

This page records the needs analysis, the plan, and the outcome of using [Coffee Shop](https://github.com/weima/coffee-shop), a local tool that runs parallel Pi Workers in isolated Git worktrees, to extend this book. Findings about Coffee Shop itself are in the last section; the matching proposals are in [its v0.2.0 roadmap](https://github.com/weima/coffee-shop/blob/main/PLAN.md#roadmap-v020). The rules the Workers follow are [`standards.md`](../standards.md) and [`workers.md`](../workers.md) in this repository.

## 1. What the book needs

Coffee Shop was built using the book as its Odin reference. Everything below cost real time while building it, and the book covers it little or not at all. "Coverage" counts the book's chapters and examples (`grep`, then read in context).

| Lesson from Coffee Shop | Where it bit | Book coverage |
| --- | --- | --- |
| `fmt.tprintf` returns temp-allocator memory: deleting it crashes; `fmt.aprintf` memory must be freed | A segfault on the second Herdr tab | Conceptual note in ch. 11 only; no trap shown |
| `fmt` treats `{` as a directive, so a JSON template mangles | Two test failures | None |
| A result name in a proc cannot be re-declared with `:=` (`Direct shadowing of the named return value`) | `run_herdr` | None |
| `:=` mixing existing and new names in one scope | Several tests | One unrelated hit |
| Default parameters must be constants (`now := time.now()`) | `next_brew_id` | Mentioned, no failing example |
| `for c, i in s` yields byte offsets, not a rune count | A review comment | Three passing mentions |
| `make_directory_all` can fail when two processes create the same directory | A real lost Worker report | None |
| Atomic replace (temp file, fsync, rename); append-only log plus snapshot | `state.odin` | One unrelated hit |
| Process identity: PID plus start time, zombies count as dead, `/proc/<pid>/stat` parsing | Cancel and recovery | Linux lab covers `/proc`, not identity |
| Killing a child leaves its children; process groups and `setsid` | Cancel | `process_kill` appears once in a capstone |
| Cancellation needs confirmed exit, else "unknown", never "completed" | Settle logic | None |
| Black-box CLI tests: build the binary, fake executables first on `PATH`, explicit environment, polling with deadlines | `e2e_test.odin` | None |
| `testing.expect_value`'s last parameter is a source location, not a message | Compile error | None |
| The book has no single verification command; CI repeats loops inline | Needed for the Filter | Absent |

Not in scope: new numbered chapters. `tools/check-book.py` asserts the chapter headings are exactly 1-31, so new material goes into existing chapters as unnumbered `###` subsections, plus runnable companions under `docs/examples/`.

## 2. Plan

Constraints discovered while planning:

- Examples must pass `odin check` (every `main.odin`) and the listed test suites. The compiler is the official `dev-2026-10` release the book already pins.
- `html/` and the offline ZIP are generated and tracked. Workers never rebuild them; one integration step does.
- `.venv` and `node_modules` are gitignored, so Stations lack them. Workers validate links with `mkdocs build --strict -d <scratch>`, using `.venv` through the Recipe's `share` list.
- Parallel Workers must not edit the same text. Each owns new files plus one distinct section of a chapter.

### Wave 1: independent additions (run in parallel, two at a time)

| Shot | Owns | Verification |
| --- | --- | --- |
| `durable-files` | `cli-linux.md` ch. 12 and 14 subsections; `docs/examples/12-durable-state/` | `odin check`, `odin test`, strict mkdocs |
| `supervision` | `cli-linux.md` ch. 15 subsection; `docs/examples/15-supervision/` | the same, tests run three times |
| `e2e-testing` | `cli-linux.md` ch. 21 subsection; `docs/examples/21-e2e-cli/` | the same, tests run three times |
| `ownership-traps` | `cli-linux.md` ch. 9 subsection; `docs/examples/09-ownership-traps/` | the same |
| `language-traps` | `odin-foundations.md` ch. 3-4 subsections; `docs/examples/04-language-traps/` | the same |
| `verify-entrypoint` | `justfile` | `just check`, `just test`, `just site` all pass |

### Wave 2: depends on wave 1

| Shot | Owns | Why it waits |
| --- | --- | --- |
| `workbook` | `workbook.md`: exercises and solutions, glossary terms, source trail | Needs the wave 1 text |
| `source-audit` | read-only report | Checks every API claim in the new text against the bundled Odin source |

### Integration (done by the Barista, once)

Apply each Shot's changes, update the example lists in `docs/examples/README.md`, the CI workflow and the justfile, rebuild `html/` and the offline ZIP, then run the book's own checks. Nothing is pushed.

Gates: every new example passes under `odin check` and `odin test` on `dev-2026-10`; `mkdocs build --strict` passes; `python tools/check-book.py` passes; no claim about compiler behaviour appears without a command that reproduces it.

## 3. Outcome and findings about Coffee Shop

### Result

Both waves are done and integrated into one branch, `dogfood-odin-book`.

- **Wave 1** (six Shots, two at a time): five chapter sections with tested companion packages, and a `justfile` that verifies the book. One Shot (`ownership-traps`) finished having done nothing and was re-run with the repository's own rules.
- **Wave 2** (two Shots in parallel): workbook exercises K-O, ten glossary terms and fourteen source-trail rows; and a read-only audit that re-checked every claim in the five sections.
- **Integration** was done by the Barista, not the Workers: each Shot's report and diff was read and re-verified, then applied and committed as one commit per topic. Workers never committed.

| | Added to the book |
| --- | --- |
| Chapter sections | 5 topics, about 340 lines in chapters 3, 4, 9, 12, 14, 15 and 21 |
| Companion packages | 5 (`04-language-traps`, `09-ownership-traps`, `12-durable-state`, `15-supervision`, `21-e2e-cli`), about 900 lines of Odin |
| Workbook | 5 exercises, 10 glossary terms, 14 source-trail rows, 11 source links |
| Tooling | `justfile`, `standards.md`, `workers.md`; CI and `docs/examples/README.md` list the new suites |

Every one of the 13 suites passes under `just verify`, the strict site build passes, and `tools/check-book.py` passes (chapters still exactly 1-31). The updated CI workflow has not yet run on GitHub.

### What reading the Workers' output found

The Workers' reports said everything passed. Reading the work found real defects that tests did not:

- Text that leaked the author's machine into a public book (`/home/...` and scratch paths) and tests that wrote to fixed `/tmp` paths named after Worker scratch directories.
- A code fragment that cannot compile (`"PATH=" + runtime_string`; Odin only concatenates constants).
- A paragraph that treated "did not crash once" as nearly safe, against the book's own standard.
- An independent audit then re-ran every claim: it confirmed 100, and found four wrong or stale sentences and four code defects (a temporary file left behind on some failures, an `/proc` probe that conflated "gone" with "unreadable", an assert where the code should clean up, and test cleanup that could hang). All were fixed, with tests.

### Findings about Coffee Shop

Findings 1-10 came up during Wave 1; 11-14 during Wave 2.

1. **A busy Worker looks dead.** `pi --print` prints only its final answer, so a running Worker's pane shows just the command line and `status` says only `running`. The first Wave 1 Shots were mistaken for stuck at about four minutes, while their Stations were gaining files and their Pi processes were active. Planned in [the v0.2.0 roadmap](https://github.com/weima/coffee-shop/blob/main/PLAN.md#roadmap-v020), item 1.
2. **Every Shot uses the same model and thinking level.** The book's Shots range from a one-file `justfile` to multi-section chapters with reproduced experiments. Planned in item 2.
3. **`share` worked as designed.** The book's gitignored `.venv` was linked into each Station, so Workers could run `mkdocs build --strict` into a scratch directory without installing anything and without dirtying the tracked `html/`.
4. **Nothing names the repository.** The Herdr workspace is `Coffee Shop <brew-id>` and the Git branches are `coffee-shop-<brew-id>-<shot-id>`, whichever repository the Brew is working on. Working on the Odin book, every label still says Coffee Shop. Planned as item 3 of the roadmap.
5. **Two Workers is a bottleneck.** The first book Brew has six independent Shots, so with a Scale of two it runs in three rounds, with most Shots waiting. Planned as item 4 of the roadmap (up to five).
6. **Prompts are awkward as inline JSON, and shared text gets pasted into every Shot.** The Wave 1 Recipe is about 35 KB of escaped strings, generated by a script, and the same ~3 KB block of rules is repeated in all six Shots. Planned as item 5 of the roadmap (`prompt_file`, `order_file`, and a shared preamble).
7. **A Shot can complete having done nothing.** `ownership-traps` finished with exit code 0, `completed`, and an empty Changes list. Its entire report was a plan ending "May I proceed with that design?": Pi in `--print` mode asked a question nobody could answer and exited. Coffee Shop records exit code 0 as `completed`, and the Oreo's decisions list did not mention it (a read-only task legitimately changes nothing, so "no changes" alone cannot be the signal). Mitigation used here: the shared Worker rules now say "you are not interactive, never ask", and the Barista reads every report. Planned as item 6 of the roadmap (a completion marker and an `incomplete` state).
8. **A Shot can complete with a progress note as its report.** `verify-entrypoint`'s whole report was "I fixed the `check` recipe and restarted the requested verification sequence." No results. The `justfile` turned out to be correct, but only because the Barista re-ran every recipe. Same root cause as finding 7: exit code 0 is all Coffee Shop requires. The shared rules now state that the last message must be a real report and that nothing may be reported while a check is unverified.
9. **Sharing one rules file by path works.** The re-run of `ownership-traps` took its shared rules from one file instead of 3 KB pasted into the prompt, which shrank to the 2.2 KB that is unique to the Shot. The Worker read the file, did not ask for permission, ran every check, and delivered a full report. It also reported a place where reality contradicted my brief: deleting a `tprintf` result did not crash in isolation, although it had crashed Coffee Shop. That is the behaviour the book's standards ask for (say so, and call it undefined). Caveats: nothing guarantees a Worker reads the file, and the file can change under a running Brew. Both are addressed by item 5.
10. **The rules were in the wrong repository.** They first lived in Coffee Shop's own repository, and every prompt quoted an absolute path into it. Rules for the book belong to the book. They now live here as `standards.md` (what a correct change is, which also lets the Filter's review run, since it had reported "standards.md is missing") and `workers.md` (how Workers behave). Coffee Shop needs a convention and automatic delivery for this. Planned as item 7 of its roadmap. This page was moved here from Coffee Shop for the same reason.
11. **The Filter worked on a repository it had never seen.** In Wave 2 it found the book's `justfile`, ran `just test` in each Station (it passed), and ran a read-only review against the book's `standards.md`. The review made two sound findings, both against the book's own standards: Exercise K called declarations "rejected" without quoting the compiler's errors, and the new subsections lacked unique anchors. Both were fixed. This is the same Filter that, one wave earlier, had to report "standards.md is missing in the Beans repository", which is what finding 10 fixed.
12. **A read-only Shot is useful, and Coffee Shop kept it read-only.** The `source-audit` Shot had no files to change, and its Station stayed clean while it re-ran every claim. It was the most valuable Shot of the exercise: 100 claims confirmed, 8 defects found, several in code the Barista had already accepted.
13. **The Filter's note about `node_modules` is noise here.** Every Shot's Oreo said "Beans has `node_modules` but this Station does not; if the checks need it, add it to the Recipe's `share` list", although the book's `just test` passed. The book's `node_modules` is only for rendering diagrams. A suggestion should appear when a check failed or could not run, not when everything passed.
14. **Coffee Shop has the same liveness defect the audit found in the book's example.** `identity_alive` returns `false` for any failure to read `/proc/<pid>/stat`, and the supervisor treats `false` as "the Worker died" (`settle.odin`). On a host that hides other processes (a `hidepid` mount) or on a transient read error, a live Worker would be recorded as `interrupted`. The fix is the one the book now teaches: three outcomes (alive, gone, unknown), where only evidence of absence says gone, and unknown is never recorded as an exit.
15. **The liveness defect in finding 14 is fixed.** Coffee Shop's probe now has three answers (alive, gone, unknown); only evidence of absence says gone, and an unknown Worker is left `running` rather than recorded as interrupted. The same audit-then-fix loop that found it in the book's example found it in Coffee Shop.
16. **The audit paid for itself a second time, on code the Barista had just written and tested.** After the text-processing chapter and its tool were written, a read-only audit Shot re-checked every claim and probed the scanner with adversarial input. It found one wrong claim and five defects: a tool that blocked forever on a FIFO, a check that could pass on a tree it never read, mixed line endings, a missed chain after a block comment, a shared temporary name, and a limit the chapter said was honoured but was not. The Shot's Station stayed clean. Writing code and auditing it are different jobs, and the second is worth giving to a fresh reader with no stake in the first.
17. **The first fix for one of those defects was itself wrong.** Refusing a FIFO by calling `os.stat` first hangs, because `os.stat` opens the file and a FIFO blocks until a writer appears. A test for the case caught it, by running for two minutes instead of failing. The same root cause (`os.is_dir` opens the path) explained a second, unrelated failure. Both are now in the book's chapter and the skill. A regression test that hangs rather than fails is worth writing deliberately for exactly this kind of defect.
