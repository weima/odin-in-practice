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

<a id="dogfood-exercise-k"></a>

### Exercise K · Runes, offsets, and declarations

Before running anything, predict the three rune values and byte offsets from ranging over `"Aé🙂"`, and the value of `len(s)` and `s[1]`. Then, inside a procedure whose results are `(stdout, stderr: []byte, err: string)`, classify these declarations as accepted or rejected and explain the fix:

```odin
state, child_stdout, child_stderr, process_err := fake_process()
state, stdout, stderr, process_err := fake_process()
code, out, status := second()
```

Treat each of the first two lines as the only declaration in the procedure's top scope. Assume `code` and `out` already exist in the current scope for the last line. Finally, predict whether `now: time.Time = time.now()` is a valid default parameter.

**Subtle watch-out:** the index from a string range is a byte offset, not a rune ordinal; and a new name on the left of `:=` does not permit redeclaring other names in the same scope.

Solution sketch

`"Aé🙂"` has seven bytes. Ranging yields U+41 at byte 0, U+E9 at byte 1, and U+1F642 at byte 3; `s[1]` is the first UTF-8 byte of `é` (195), not the rune. The first declaration is valid when its names are new. The second shadows the named results and is rejected; use distinct locals then assign to `stdout` and `stderr`, or assign the returned values with `=` after declaring only genuinely new locals. The third is rejected because `code` and `out` already exist; use `=` and declare `status` separately, or use fresh local names. A runtime call such as `time.now()` is not a constant default; accept the time as an argument or use a wrapper that supplies `time.now()` at runtime. The pinned compiler reports, verbatim, `Direct shadowing of the named return value 'stdout' in this scope` (and the same for `stderr`) for the second line; `Redeclaration of 'code' in this scope` (and for `out`) for the third; and `Default parameter must be a constant, got time.now()` for the default parameter. The pinned examples and tests in `docs/examples/04-language-traps/` exercise the rune offsets, valid assignment patterns, and runtime-time alternatives.

<a id="dogfood-exercise-l"></a>

### Exercise L · Who owns the formatted bytes?

For each line below, predict the lifetime/ownership bug before running it, then state the rule it violates. Assume the braces are intended to produce JSON and `x` is `"7"`:

```odin
value := fmt.tprintf("order=%d", 7)
delete(value)
saved := fmt.tprintf("order=%d", 7)
_ = mem.free_all(context.temp_allocator)
fmt.println(saved)
json_text := fmt.tprintf("{\"order\":%s}", x)
```

Which result is caller-owned, which is borrowed scratch, and which formatter is a poor choice for a JSON template?

**Subtle watch-out:** undefined behaviour is not disproved by a run that happens not to crash; a temporary result can also appear intact until its allocator is reset.

Solution sketch

`tprintf` returns temporary-allocator storage: do not `delete` it, and do not use it after the temporary allocator is reset. The first line violates the allocator ownership rule; the second violates the borrowed value's lifetime. Clone into an allocator whose lifetime covers the use, or use an allocating formatter and delete its result with the same allocator. `fmt` interprets braces as formatting syntax, so a JSON-looking format string can produce a format diagnostic rather than JSON. Escape literal braces for the format language, concatenate fixed fragments for a deliberately simple case, or marshal a typed value with `json.marshal`. The pinned ownership companion tests these outcomes and ownership boundaries.

<a id="dogfood-exercise-m"></a>

### Exercise M · Two files, several crash points

A state writer opens the snapshot and overwrites it in place, then appends an event to its log. Two processes can also call “create state directory” at the same time. Predict what each process may observe at directory creation, and describe the persisted files if a crash happens during snapshot writing or after snapshot replacement but before the log append. How should a reader detect inconsistency, and what recovery claim can it honestly make?

**Subtle watch-out:** a valid JSON snapshot by itself does not prove that it agrees with the event history; a crash can leave a syntactically valid but stale or ahead-of-log state.

Solution sketch

Directory creation is a race: one caller may create it while another receives `.Exist`. Treat that result as success only after confirming the path is a directory. An in-place write can leave a truncated or partial snapshot if interrupted. If the snapshot is replaced first and the process stops before appending, the snapshot is ahead of the log. Validate complete log lines, sequence numbers, and replayed state against the snapshot; report a partial record or conflict instead of silently declaring success. Without a journal/transaction or an explicit repair source, the honest policy is to preserve evidence and require an explicit recovery decision. A sibling temporary file plus checked sync and rename avoids exposing a half-written single snapshot file, but does not make a two-file update transactional. The durable-state companion tests directory reuse, atomic replacement failure, partial lines, and snapshot/log disagreement.

<a id="dogfood-exercise-n"></a>

### Exercise N · A PID is not a process identity

A supervisor stores only PID 812 and later finds that PID in `/proc`. Describe how PID reuse can fool it. Given a `/proc/812/stat` line whose parenthesized command name contains spaces and `)`, explain how to locate the state and start-time fields. Then explain why killing the direct child may leave its grandchild running, and what result to record if exit cannot be confirmed before the deadline.

**Subtle watch-out:** splitting the whole line on spaces or stopping at the first `)` mis-parses `comm`; a successful signal request is not evidence that the process exited.

Solution sketch

Pair the PID with field 22 (`starttime`) from `/proc/<pid>/stat`; treat state `Z` as already exited, not live. Find the last `)` ending the command field, then split the suffix: state (field 3) is token 0 and start time (field 22) is token 19. A signal to the child does not automatically reach descendants. On Linux, launch through the external `setsid` utility and signal that process group when the whole group is the cancellation unit; calling `setsid` in the supervisor would change the supervisor, not its already-started child. Keep unrelated work out of the group. Record `Interrupted` (unknown), not `Cancelled`, when exit or identity cannot be confirmed by the deadline. The Linux companion tests the parser, zombie case, and cancellation outcomes.

<a id="dogfood-exercise-o"></a>

### Exercise O · Make the CLI test repeatable

A black-box test passes on one machine and flakes on another. It sleeps for a fixed duration and assumes the command has finished, writes all runs under one fixed temporary path, and inherits the developer's `PATH`. Redesign the test setup and completion check. Explain what happens when `Process_Desc.env` contains only a replacement `PATH`, and how a test can replace selected variables without making the rest of the child environment accidental.

**Subtle watch-out:** a longer fixed sleep is still a timing guess; process tests also need cleanup on assertion and timeout paths.

Solution sketch

Give each run a fresh temporary directory and remove it after the child and its files are cleaned up. Replace external dependencies with a local fake executable and fixed outputs. Poll process state with a finite deadline, then kill and wait on timeout rather than assuming a delay means completion. `Process_Desc.env` is the full child environment, not a set of additions; supplying only `PATH` discards all other variables. Start from `os.environ`, remove each key being overridden, then append controlled replacements. The pinned black-box example constructs this environment and asserts stdout, stderr, and exit status separately.

<a id="dogfood-exercise-p"></a>

### Exercise P · A correct count of the wrong thing

A file contains the three lines `count`, `account` and `count`. A tool is asked to replace `count` with `total`, expecting exactly 2 occurrences. Predict what it does. Then it is run again with the expectation corrected to 3: predict the file. What should the author have changed instead of the number?

**Subtle watch-out:** an exact count guards against *surprises*, not against a search text that is not specific enough. A count that matches by accident still produces a wrong file.

Solution sketch

The first run is refused: `textproc: refused: found 3 occurrence(s), expected 2; f.txt is unchanged`, with exit status 1. The count was the signal that the assumption was wrong, and the file is untouched. Raising the expectation to 3 is the wrong response, because `count` also occurs inside `account`; the replacement succeeds and leaves `total`, `actotal`, `total`. The fix is to make the search text unique: search for the whole three-line block, `count`, `account`, `count`, which occurs once. The lesson is that the count and the specificity of the text work together.

<a id="dogfood-exercise-q"></a>

### Exercise Q · Which semicolons separate statements?

For each line below, say which `;` characters separate two statements, what a plain search for `;` would report, and what a masked copy of line 2 looks like. Then say why the masked copy must keep the original length.

```odin
a := 1; b := 2
s := "x; y"
for i := 0; i < 3; i += 1 {
```

**Subtle watch-out:** a `;` is not a separator merely because it is a `;`. Context decides, and a flat search cannot see context.

Solution sketch

Only the first line has a separator. The `;` in line 2 is inside a string, and the two in line 3 belong to a `for` header, where they separate the initializer, the condition and the step. A plain search reports four `;` characters, three of them wrong. The masked copy of line 2 is `s := "    "`: the quotes stay, the contents become spaces. Keeping the length and the newlines means that every offset and line number found in the masked copy points at the same place in the original, so the tool can report `file:line:column` or edit the original text at the offsets it found.

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
| Temporary allocator (borrowed scratch) | An allocator for short-lived values that may be invalidated when temporary storage is reset. A result allocated there is borrowed, not caller-owned memory to delete. |
| Undefined behaviour | Program behavior for which the language or API gives no valid guarantee. An experiment that appears to work does not make it defined or safe. |
| Atomic replace | Writing a complete sibling temporary file and renaming it over one target so readers do not see a partially written target. It does not make updates to multiple files transactional or guarantee power-loss durability. |
| Append-only log | A sequence of records added at the end rather than rewriting prior records. It preserves history only if incomplete records and replay conflicts are detected. |
| Snapshot | A saved summary of current state, commonly validated against replayed log history. It is not proof by itself that the history and current state agree. |
| Process identity | A process reference that pairs its PID with a start-time value to distinguish a later process that reuses the PID. On Linux, the inspected example obtains the start time from `/proc/<pid>/stat`. |
| Zombie | A process that has exited but whose parent has not yet collected its exit status. It is not a live process to cancel. |
| Process group | A set of related processes that can receive a group signal together. Signaling a child PID alone does not signal its descendants. |
| Black-box test | A test that invokes the built executable as a separate process and checks its externally visible behavior. It complements, rather than replaces, package tests. |
| Fake executable | A controlled local program or script substituted for an external dependency during a test. It makes arguments, output, and failure status reproducible without depending on the real tool. |
| Exact-count replacement | A text replacement that states how many occurrences it expects and refuses when the count differs. It guards against surprises, but the search text must also be specific enough. |
| Masked copy | A copy of source text in which the contents of comments, strings and raw strings are blanked, keeping the length and the newlines, so a plain search sees only code and every offset still matches the original. |
| Bounded streaming | Processing input through a fixed-size buffer so that memory depends on limits the program chose, such as line length and result count, and not on the size of the input. |
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
| `core/unicode/utf8/utf8.odin` and `core/unicode/letter.odin` · decoding and character properties | What does bytewise input mean, and when should text be decoded as runes? | 3–4 |
| `core/time/time.odin` · now | Why can a runtime clock read not be a constant default parameter? | 4 |
| `core/fmt/fmt.odin` · `tprintf`, `aprintf`, `bprintf`, `sbprintf` families | Who owns formatted output, which lifetime backs it, and how are literal braces parsed? | 9 |
| `core/strings/builder.odin` · Builder and `builder_destroy` | Who owns builder-backed formatted bytes and how is its storage released? | 9 |
| `core/encoding/json/marshal.odin` · `marshal` | How do you encode a typed value as JSON and receive allocated output? | 9, 12 |
| `core/os/path.odin` · `make_directory_all`; `core/os/path_linux.odin` · `_mkdir_all` | What does recursive directory creation report when the directory already exists, and how does Linux create its path components? | 12 |
| `core/os/file.odin`, `file_linux.odin`, and `file_posix.odin` · flush, sync, rename | How can a single state file be replaced without exposing a partial write, and what durability is not promised? | 12 |
| `core/os/user.odin` · `user_state_dir`; `core/path/filepath/path.odin` · `is_abs` and `join` | How is the default state root chosen and how is an override validated? | 14 |
| `core/os/process.odin` · `Process_Desc`, `process_start`, `process_wait`, `process_terminate`, `process_kill`, `process_exec` | What environment does a child receive, how is it started, cancelled, waited, and captured? | 15, 21 |
| `core/os/process_linux.odin` · `_process_start`, `_process_wait`, `_process_kill`, `_process_terminate` | Which Linux process and PATH behaviors implement the public process operations? | 15, 21 |
| `core/strings/strings.odin` and `core/strconv/strconv.odin` · `last_index_byte`, `fields`, `parse_u64` | How can `/proc/<pid>/stat` be parsed when `comm` contains spaces or `)`? | 15 |
| `core/sys/posix/unistd.odin` · `setsid`; `core/sys/posix/signal.odin` · `killpg` | How can Linux process-group cancellation reach descendants, and what does it affect? | 15 |
| `core/os/temp_file.odin` · `make_directory_temp`; `core/os/env.odin` · `environ` | How can tests isolate paths and construct a controlled child environment? | 21 |
| `core/testing/testing.odin` · `expect_value`, `expect` | Which arguments are source/expression metadata, and how do you provide a custom expectation message? | 21 |
| `core/bufio/reader.odin` · `reader_init`, `reader_read_slice` | Whose memory is a returned line, and what happens when a line is longer than the buffer? | 13a |
| `core/text/regex/regex.odin` · `create`, `match`, `destroy` | How is a pattern compiled once, what does a capture hold, and who frees it? | 13a |

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
- [Unicode UTF-8 source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/unicode/utf8/utf8.odin) and [Unicode letter properties](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/unicode/letter.odin) — UTF-8 decoding and rune classification.
- [Time source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/time/time.odin) — runtime clock reads.
- [Formatting source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/fmt/fmt.odin) — formatting syntax and `t`, `a`, `b`, and builder-backed output families.
- [String builder source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/strings/builder.odin) — builder storage and destruction.
- [JSON marshal source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/encoding/json/marshal.odin) — typed JSON encoding and allocated output.
- [OS path source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/path.odin) and [Linux path implementation](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/path_linux.odin) — recursive directory creation and its public error contract.
- [OS file source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/file.odin), [Linux file source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/file_linux.odin), and [POSIX file source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/file_posix.odin) — flush, sync, and rename paths.
- [User directories source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/user.odin) and [filepath source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/path/filepath/path.odin) — state-directory defaults and path validation.
- [Linux process source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/process_linux.odin) — Linux process startup, wait, and signaling paths.
- [POSIX session source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/sys/posix/unistd.odin) and [POSIX signal source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/sys/posix/signal.odin) — `setsid` and process-group signaling.
- [Temporary-directory source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/temp_file.odin) — isolated temporary directories for tests.
- [Buffered reader source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/bufio/reader.odin) — fixed-size buffering, `reader_read_slice` and `Buffer_Full`.
- [Regular-expression source](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/text/regex/regex.odin) — compiling patterns, matching, and capture ownership.
- [Creator’s explanation of the name](https://forum.odin-lang.org/t/origin-of-the-name-odin/794) — a mythological project codename that stuck.
- [FFmpeg documentation](https://ffmpeg.org/documentation.html) — official user and developer documentation index.
- [ffmpeg command documentation](https://ffmpeg.org/ffmpeg.html) — options, stream selection, streamcopy, transcoding and filtering.
- [ffprobe command documentation](https://ffmpeg.org/ffprobe.html) — stream/format inspection and machine-readable output.
- [libavformat API](https://ffmpeg.org/doxygen/trunk/group__lavf.html) — demuxing, muxing and format contexts.
- [libavcodec send/receive API](https://ffmpeg.org/doxygen/trunk/group__lavc__encdec.html) — decoder and encoder state-machine contract.
- [FFmpeg demuxing\_decoding.c example](https://ffmpeg.org/doxygen/trunk/demuxing__decoding_8c.html) — a complete official packet-to-frame decode example.
- [libavutil error API](https://ffmpeg.org/doxygen/trunk/group__lavu__error.html) — error codes and `av_strerror`.

**A reading loop for API questions:** predict the contract; read the package docs; inspect the relevant implementation; write a tiny experiment; compare the result with your prediction. If they differ, update your model before adding more code.
