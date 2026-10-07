# Odin in Practice

**Read the formatted book: https://weima.github.io/odin-in-practice/**

A 26-chapter, source-guided book for programmers learning Odin through Linux command-line tools and FFmpeg/libav. Explanations start with a practical question, trace a small example, challenge its assumptions, and examine trade-offs. Exercises ask readers to predict results before running code.

## Read locally

Open `index.html` in a browser. The HTML pages, CSS, diagrams, and cover are local assets; no build step, JavaScript, or server is required. External documentation and source links need internet access.

| Part | Page | Topics |
| --- | --- | --- |
| Foundations | [Chapters 1–4 and interludes](chapters/odin-foundations.html) | Packages, values, polymorphism, representation, and the C boundary |
| CLI and Linux | [Chapters 5–17](chapters/cli-linux.html) | Arguments, flags, errors, allocators, files, streams, processes, testing, and a capstone |
| FFmpeg and libav | [Chapters 18–23](chapters/ffmpeg-libav.html) | Process composition, JSON, foreign calls, codec state machines, and timestamps |
| Workbook | [Chapters 24–26](chapters/workbook.html) | Exercises, glossary, and a reproducible source trail |

## Run the examples

The reference compiler is **Odin `dev-2026-09-nightly:a2fb372`**. Runtime and core-library walkthroughs use source shipped with that installation, corresponding to upstream commit [`a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924`](https://github.com/odin-lang/Odin/commit/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924). Chapter 26 identifies the inspected paths and symbols; implementation observations are not treated as permanent API guarantees.

Use a separate directory for each example:

```sh
odin version
odin root
odin check .
odin run .
odin test .
```

Complete programs include their package and imports. Fragments and protocol pseudocode are labeled and need their surrounding declarations. The two Chapter 16 files belong in the same package directory; the additional prefix/borrowing test goes in its test file.

Linux labs require a Linux environment. Media labs also require `ffmpeg` and `ffprobe`; the direct binding targets FFmpeg 6.x and needs the installed development libraries and linker metadata. Check `pkg-config --modversion libavformat` and the installed headers before adapting it. Codec pseudocode is explanatory, not a complete decoder implementation. Use disposable local fixtures rather than production media or network inputs.

## Verification of this revision

- All eight complete Odin programs in the HTML pages passed `odin check` and `odin build` with the reference compiler.
- Eight focused tests passed with memory tracking enabled: the five preview tests, a little-endian decoder test, and two stream-counting tests.
- Nineteen local runtime scenarios passed, covering greetings, flag parsing/help, byte counts, empty/unset environment values, child execution, JSON parsing, and the libav probe’s success and failure paths. Media input was a generated disposable WAV fixture.
- Chapter numbers 1–26, local links and anchors, SVG XML, and the README’s readable-book URL were checked.
- The cover loaded at desktop and mobile sizes; all four chapter pages showed no page-level horizontal overflow at a 390-pixel viewport. Inline diagrams retain their accessible titles and descriptions.

These checks do not claim that every exercise, shell pipeline, target platform, or codec pseudocode fragment has been implemented or tested. The capstone remains a reader exercise, and implementation explanations describe the pinned revision rather than future library releases.

## Cover and name

The original SVG cover depicts the mythological Odin and two ravens alongside an Odin code page. It reflects the name’s origin, not a claim about language-design symbolism. Creator Ginger Bill says the name was simply **[a mythological codename that stuck](https://forum.odin-lang.org/t/origin-of-the-name-odin/794)**.

This is an independent learning book, not an official Odin or FFmpeg specification or an endorsement by their authors. Source walkthroughs link to upstream material and explain selected mechanisms; the upstream code retains its own license, including [Odin’s zlib license](https://github.com/odin-lang/Odin/blob/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/LICENSE).
