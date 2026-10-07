# Workbook and references

<a id="workbook"></a>

## 29. Workbook: exercises and solutions

The aim of these exercises is not to reproduce the examples from memory. It is to test the mental model that made those examples seem obvious. Before running each case, predict the output, status, ownership, and relevant lifetime. If the observation differs, identify which assumption failed.

Try each exercise before opening the solution. A useful answer includes the rejected alternatives: why an empty string cannot represent absence, why a fixed scratch buffer need not imply bounded total memory, and why a successful child process can still return data we cannot use.

### Exercise A · Usage is part of the interface

Make the greeting program fail when no name is given. Print usage to stderr and return a non-zero status. Then redirect stdout and stderr to separate files. Which file contains the usage message?

**Subtle watch-out:** test the exit code as well as the text. A usage line printed to stderr with exit status zero still tells a shell script that the command succeeded.

Solution sketch

Check `len(os.args)` before reading `os.args[1]`. Call `fmt.eprintln` for the usage line, then `os.exit(2)`. The usage message should be in the stderr file.

### Exercise B · Empty is not missing

Read the `HOME` environment variable. Test the program once with `HOME=` and once with `env -u HOME`. Make its output distinguish the two cases.

**Subtle watch-out:** a truthiness check on the string confuses “present but empty” with “not set.” Use the separate found flag.

Solution sketch

Use `os.lookup_env`. The boolean tells whether the variable exists; the returned string can still be empty when it does.

### Exercise C · Spawn failure versus exit failure

Run a child program that exists but returns non-zero. Compare it with a nonexistent executable. Report both distinctly.

**Subtle watch-out:** spawning successfully is not the same as the child succeeding. Check both the returned error and the child’s exit state; do not overwrite one with the other.

Solution sketch

A missing executable produces an error from process execution. A child that starts and exits non-zero returns a process state whose exit code reports the child's result. Check both the error and the returned state.

### Exercise D · Bound the input

Design the file inspector so it never keeps more than one fixed-size read buffer plus the requested preview in memory. State the maximum memory use in terms of the buffer size and limit.

**Subtle watch-out:** if you continue reading after the preview is full, count bytes without appending them. A preview limit does not automatically limit total memory or total work.

Solution sketch

Use a fixed byte buffer for each read and store at most `limit` preview bytes. Memory is bounded by the buffer plus the preview and small bookkeeping, rather than the full file size.

### Exercise E · Challenge your API

Write a test matrix for the inspector. Include normal input, empty input, bad arguments, missing files, large input, and output redirection. For each case, specify expected stdout, stderr, and exit status before running the test.

**Subtle watch-out:** avoid brittle assertions about OS-specific error wording. Assert stable behavior and your own diagnostic contract, not a kernel message that can change across systems.

Solution sketch

Keep one row per observable behavior. A successful size report belongs on stdout with exit status zero; invalid input and failed reads produce a concise stderr diagnostic and non-zero status. Add exact output only when the output format is a deliberate contract.

### Exercise F · Same length, wrong bytes

Change the preview implementation to return the last `n` bytes instead of the first. Which Chapter 21 tests fail? Restore the implementation, then change it to allocate a copy. Which test distinguishes copying from borrowing?

Reasoning

The original four length tests allow a suffix implementation. The content assertions reject it. The mutation assertion rejects an independent copy because this particular API promises a borrowed prefix. That assertion would be inappropriate for a copy-returning API. Tests should distinguish contracts, not declare that one ownership choice is always right.

### Exercise G · The allocator changed

A helper allocates a slice with allocator A, then its caller changes `context.allocator` to B before deleting the slice. Explain the likely problem without running an invalid free. Compare the runtime’s slice and dynamic-array delete overloads.

Reasoning

The slice header has no allocator field; its default deletion uses the current context. Pass the saved allocator A explicitly. The dynamic-array header retains an allocator, but copying that header still does not create an independent allocation. “Remembers the allocator” does not mean “safe to delete every copy.”

### Exercise H · Fixed buffer, growing process

The process capture helper reads with a 1024-byte buffer. A child writes a gigabyte to stdout. Is the parent’s memory bounded to about a kilobyte? Trace the source path that settles the question.

Reasoning

No. `process_exec` appends chunks to dynamic output arrays. The read buffer is bounded; retained output is not. Streaming consumption requires a different lifecycle and simultaneous attention to both stdout and stderr. A process timeout alone is not a memory budget.

### Exercise I · A successful expectation?

Read `testing.expect`, then find where a false result becomes a failed test. Why is assigning a different logger to the context inside a test a decision that deserves care?

Reasoning

The expectation logs an error. The runner-installed logger increments the test’s error count and forwards a reporting event. Replacing the logger can bypass that path. The expectation’s boolean is also available for control flow; use it to stop before unsafe indexing after a failed prerequisite.

### Exercise J · Units survive type checking

Rescale a timestamp of 48000 ticks from `1/48000` to `1/1000`. Explain why using an `i64` on both sides does not establish correctness. Then explain why a decoder’s send-side EAGAIN should trigger a receive call rather than a sleep.

Reasoning

The destination timestamp is 1000 ticks for one second. The integers have different units despite identical types. FFmpeg’s helpers also preserve unknown-timestamp conventions. Decoder EAGAIN is a state-machine transition: output consumption changes the state; elapsed wall time is not the required operation.

**Completion test.** Explain one result from each source trail without quoting the function body. Then write the smallest experiment that could disprove your explanation. If your test cannot fail for a plausible wrong implementation, strengthen the oracle rather than simply adding more cases.

<a id="glossary"></a>

## 30. Pocket glossary

A glossary is useful when it keeps adjacent concepts apart. “String,” “owned string,” and “C string” are not interchangeable. Nor are “compiled,” “linked,” and “ran successfully.” Use these definitions to ask more precise questions, not to replace an API’s specific contract.

| Term | Working meaning |
| --- | --- |
| Package | A directory-based unit of Odin source; files in it share a package name. |
| Procedure | A typed callable unit of code, declared with `proc`. |
| Allocator | A strategy for obtaining and releasing memory, passed explicitly to many core APIs. |
| Slice | A view over a sequence of elements; it does not by itself say who owns the backing storage. |
| Dynamic array | A header for resizable backing storage, including length, capacity, and an allocator. A copied header aliases the allocation; ownership must still be assigned by the program. |
| Borrowed / owned | A borrowed value depends on another resource's lifetime; an owner is responsible for its release. The type alone may not enforce the distinction. |
| Context | Scope-local policies implicitly available to Odin-convention calls, including allocators and a logger; not the same as the process environment. |
| Capacity / length | Reserved element storage versus the currently meaningful element range; neither establishes an element's nested ownership. |
| C string | A pointer to bytes terminated by NUL, unlike an Odin string's pointer-plus-length representation. |
| Type specialization | A polymorphic procedure adapted to the inferred or supplied types; it does not invent operations unsupported by those types. |
| Implementation observation | A fact about the inspected revision, such as a growth formula or scratch-buffer size; not automatically a permanent API promise. |
| Oracle | The rule that decides whether a test result is correct. A weak oracle can allow many wrong implementations to pass. |
| EAGAIN / draining | In the codec protocol, a request to make progress on the opposite side versus completion of delayed output after end-of-input is accepted. |
| Defer | A statement scheduled to run when its surrounding scope exits; defers run in reverse declaration order. |
| File descriptor | An operating-system handle commonly used for files, pipes, and standard streams. |
| Process | A running program with its own arguments, environment, working directory, and exit status. |
| EOF | End of a stream: no more bytes are available from that input. It is not the same as a delimiter between records. |
| Syscall | A defined request from a program to the operating-system kernel. |
| ABI | The binary-level conventions that let separately compiled code and the operating system communicate. |
| Container | A media file format that stores streams, metadata and timing, such as MP4 or Matroska. |
| Demuxer / muxer | A demuxer separates container input into streams and packets; a muxer packages output streams and packets. |
| Packet / frame | A packet carries compressed stream data; a frame carries decoded audio samples or video pixels. |
| Time base | A rational unit that gives meaning to integer media timestamps. |
| Opaque handle | A pointer passed to a C API whose structure layout is intentionally not accessed by the caller. |
| Data-oriented programming | A way of designing around the data being processed, its layout and access patterns, and the procedures that transform it. |
| AoS / SoA | Array of structures keeps fields together per item; structure of arrays groups each field into its own sequence. |

<a id="sources"></a>

## 31. Official references and source trail

The source walkthroughs in this edition were read from the runtime and core libraries at the official monthly `dev-2026-10` release. Its compiler reports `dev-2026-10-nightly:84bc3fc`; the source commit is [`84bc3fc2100b0f7880a3af37f71bccdcda41c6f9`](https://github.com/odin-lang/Odin/commit/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9). Repository links below are pinned to it rather than to a moving branch.

This is library and runtime source evidence, not a claim to have audited the entire compiler. The installed distribution does not contain the compiler's complete C++ source. Where this book explains language semantics, use the official language guide and a small compiler experiment; where it explains a library mechanism, follow the named symbol in the pinned source.

### A source trail with a question attached

| Path and symbols | Question answered | Chapters |
| --- | --- | --- |
| `base/runtime/entry_unix.odin` · startup and entry branches | Who establishes context and arguments before application code? | 1–2, 14–15 |
| `base/runtime/core.odin` · Context, Allocator, Raw\_String, Raw\_Slice, Raw\_Dynamic\_Array, Raw\_Map | What does the small value store, and what remains outside it? | 3, 9, interludes |
| `base/runtime/core_builtin.odin` · delete\_slice, delete\_dynamic\_array, \_append\_elems | Which allocator is used, what does growth do, and can it fail? | 3, 9 |
| `core/flags/parsing.odin` · parse | How do syntax, required-field tracking, and final validation relate? | 7 |
| `core/flags/util.odin` · parse\_or\_exit, print\_errors | Who removes the executable argument and chooses channels/status? | 5–7 |
| `core/os/process.odin` · get\_args, exit, Process\_Desc, process\_exec | How are argument headers made, and what resources does capture retain? | 6, 8, 13, 19 |
| `core/os/process_linux.odin` · \_process\_start | Which PATH is searched and how are argument/environment vectors formed? | 13, 19 |
| `core/os/file_util.odin` · read\_entire\_file\_from\_file | Why can a zero reported size still produce bytes? | 8, 10, 17 |
| `core/os/file.odin` and `file_posix.odin` · read and stream procedure | What counts as EOF and where are platform errors translated? | 11, 14 |
| `core/os/env.odin` and `env_linux.odin` · lookup overloads | How do missing, empty, allocated, and buffer-backed values differ? | 12 |
| `core/testing/testing.odin` · expect\_value, cleanup, T | What is comparable, when does execution continue, and who owns cleanup? | 4, 16 |
| `core/testing/logging.odin` and `runner.odin` · test\_logger\_proc | How is a logged expectation failure recorded? | 16 |
| `core/encoding/json/types.odin`, `parser.odin`, `unmarshal.odin` | Which syntax is accepted, and who destroys a parsed tree? | 19 |
| `core/strings/strings.odin` · clone\_to\_cstring, string\_from\_ptr | Who supplies termination, and which conversion only borrows? | 21, 23 |

To reproduce a reading, run `odin root`, open the local path, find the symbol, and compare the relevant branch with the pinned link. Do not call runtime-private helpers from application code merely because this book uses them to explain behavior. The public operation remains the intended interface.

### Official documentation and inspected sources

- [Odin overview](https://odin-lang.org/docs/overview/) — declarations, packages, control flow, types, polymorphism, foreign imports and examples.
- [Running tests](https://odin-lang.org/docs/testing/) — the `@(test)` attribute, test procedures, expectations and runner behavior.
- [Package docs: `core:testing`](https://pkg.odin-lang.org/core/testing/) — test expectations, cleanup, and runner options.
- [Odin FAQ](https://odin-lang.org/docs/faq/) — the designers’ stated goals and rationale for language choices including data-oriented programming, allocators, context and error handling.
- [Odin: Binding to C](https://odin-lang.org/news/binding-to-c/) — foreign imports, ABI types, C strings, structs, unions and pointers.
- [Official documentation index](https://odin-lang.org/docs/) — language guide, FAQ, tutorials, and articles.
- [Package docs: `core:flags`](https://pkg.odin-lang.org/core/flags/) — parsing styles, tags, validation, help, and errors.
- [Package docs: `core:os`](https://pkg.odin-lang.org/core/os/) — files, environment, standard streams, and processes.
- [Flags example source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/flags/example/example.odin) — a complete annotated-options example.
- [Flags parser source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/flags/parsing.odin) — parsing styles and the public parser contract.
- [Environment source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/env.odin) — how lookup distinguishes an unset variable from an empty one.
- [Process source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/process.odin) — process descriptors, execution, captured output, and wait state.
- [File utility source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/file_util.odin) — whole-file read helpers and allocation behavior.
- [Linux system packages](https://github.com/odin-lang/Odin/tree/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/sys/linux) — Linux-specific APIs in Odin's core library.
- [Runtime representations and context](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/base/runtime/core.odin) — raw headers, allocator modes, and scope policies.
- [Built-in operations](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/base/runtime/core_builtin.odin) — allocator selection for deletion and the public append path.
- [Unix entry source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/base/runtime/entry_unix.odin) — initialization, application entry, and cleanup.
- [Flags boundary wrapper](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/flags/util.odin) — executable-argument removal, help, and exit status.
- [File operations](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/file.odin) — read counts, EOF, and stream dispatch.
- [Testing source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/testing/testing.odin) — expectations, caller diagnostics, and cleanup.
- [Test runner](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/testing/runner.odin) and [test logging](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/testing/logging.odin) — contexts, allocation tracking, and failure recording.
- [JSON source](https://github.com/odin-lang/Odin/tree/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/encoding/json) — syntax policies, value trees, and cleanup.
- [String source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/strings/strings.odin) — clones, C-string termination, and borrowed views.
- [Creator’s explanation of the name](https://forum.odin-lang.org/t/origin-of-the-name-odin/794) — a mythological project codename that stuck.
- [FFmpeg documentation](https://ffmpeg.org/documentation.html) — official user and developer documentation index.
- [ffmpeg command documentation](https://ffmpeg.org/ffmpeg.html) — options, stream selection, streamcopy, transcoding and filtering.
- [ffprobe command documentation](https://ffmpeg.org/ffprobe.html) — stream/format inspection and machine-readable output.
- [libavformat API](https://ffmpeg.org/doxygen/trunk/group__lavf.html) — demuxing, muxing and format contexts.
- [libavcodec send/receive API](https://ffmpeg.org/doxygen/trunk/group__lavc__encdec.html) — decoder and encoder state-machine contract.
- [FFmpeg demuxing\_decoding.c example](https://ffmpeg.org/doxygen/trunk/demuxing__decoding_8c.html) — a complete official packet-to-frame decode example.
- [libavutil error API](https://ffmpeg.org/doxygen/trunk/group__lavu__error.html) — error codes and `av_strerror`.

**A reading loop for API questions:** predict the contract; read the package docs; inspect the relevant implementation; write a tiny experiment; compare the result with your prediction. If they differ, update your model before adding more code.
