# CLI and Linux

<a id="cli-contract"></a>

Part II · Command-line programs

## 5. The command-line contract

Imagine a byte-counting tool that prints `Opening file…` followed by `42`. It looks friendly in a terminal. Now put it in a pipeline whose next stage expects an integer. The program has not become less correct internally; we have discovered that its interface was never defined carefully enough.

A CLI has several independent channels. The first design task is to decide what each means. In this book, stdout carries results, stderr carries diagnostics, and a nonzero exit status says that the requested operation did not succeed. Help requested explicitly is a successful operation, not an invalid-argument error.

| Channel | Purpose | Typical use |
| --- | --- | --- |
| Arguments | Values supplied when the program starts. | Paths, modes, and short options. |
| stdin | Input stream from a pipe, redirect, or terminal. | Large or composable data input. |
| stdout | Normal result. | Text or machine-readable output to pipe or file. |
| stderr | Diagnostics and usage errors. | Warnings that should not corrupt piped output. |
| Exit status | Success or failure summary for the caller. | Shell conditionals and automation. |

In shell, `command >result.txt` redirects stdout, `command 2>errors.txt` redirects stderr, and `producer | consumer` connects stdout to stdin. A CLI that mixes progress messages into stdout can break pipelines. Keep the result channel clean.

### A small convention that scales

- Print a concise usage line when required input is missing.
- Send usage errors and diagnostics to stderr.
- Return zero for success and non-zero when the requested operation fails.
- Do not print a success-shaped result after an error.
- Use a stable, documented output format when scripts consume the result.

These are interface decisions. Changing them can break scripts even if the new implementation is faster. Specify a successful empty result separately from a failed operation: zero bytes in an empty file is real data; zero bytes because opening failed is not.

### The library makes a similar distinction

Read [core/flags/util.odin](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/flags/util.odin). `print_errors` writes parsing and validation diagnostics to stderr, but sends explicitly requested usage to stdout. `parse_or_exit` selects exit status zero for a `Help_Request` and one for the other errors. No arguments plus a missing requirement gets usage on stderr.

That is not an arbitrary distinction between two print procedures. The same-looking usage text can answer a successful help request or explain a failed invocation. The context determines the channel and status. If you introduce your own convention of status two for invalid input, do not assume the library’s convenience wrapper follows it.

```sh
./tool > result.txt 2> diagnostics.txt
status=$?
printf 'status=%s\n' "$status"
```

Capture `$?` immediately: another command replaces it. For a pipeline, the default status normally comes from its final command. A producer can fail while a consumer succeeds; in Bash or Zsh, consider `set -o pipefail` when testing that composite behavior. A terminal transcript alone cannot establish any of these contracts.

**Exercise 5.1.** Capture stdout, stderr and exit status independently for explicit help, missing input, an empty input file, and a failed open. Decide which cases represent successful empty data rather than failure. Then make a producer fail before a succeeding consumer and compare the pipeline status with and without `pipefail`.

<a id="arguments"></a>

Chapter 6 · Your first CLI

## 6. Arguments and a first useful tool

What is an argument: a word, a string, or part of a command line? By the time an ordinary Linux program starts, the shell has already interpreted quoting and constructed an argument vector. `"Ada Lovelace"` is one string. The quote characters are normally no longer present. Splitting that string again would undo the caller’s work.

`os.args` exposes that vector. Index zero conventionally identifies the invocation; it need not be an absolute path or a trustworthy executable identity. User arguments start at index one. This complete program uses the distinction:

```odin
package main

import "core:fmt"
import "core:os"

main :: proc() {
    if len(os.args) < 2 {
        fmt.eprintln("usage: hello <name>")
        os.exit(2)
    }

    fmt.printf("Hello, %s!\n", os.args[1])
}
```

Save it as `main.odin`. Try both execution paths:

```sh
odin run . -- Ada
odin build . -out:hello
./hello Ada
./hello
```

The compiler's `--` separates compiler options from the program arguments in the run command. The built program receives the program arguments, not that separator. When invoking the executable directly, pass the arguments normally.

### Where those strings came from

Follow `get_args` in [core/os/process.odin](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/process.odin). On the ordinary Unix route it makes a slice of Odin string headers from `runtime.args__`. The runtime entry code saved the C argument vector before invoking our application. This path allocates the slice of headers; converting each C string does not imply a separate clone of all its bytes.

For this initial example `os.exit(2)` is safe to use before we acquire any resources. It exits the process directly; it is not a return from `main`. Later examples will keep work in a procedure that returns a status, allowing deferred cleanup to finish before the top-level exit. This small structural choice prevents a large class of misleading cleanup examples.

**Predict, then run.** Compare `./hello Ada Lovelace`, `./hello "Ada Lovelace"`, and `./hello ""`. The last invocation supplies an argument of length zero; it is not the same as supplying no argument.

**Exercise 6.1.** Change the tool so it joins and prints every name from `os.args[1:]`. Try zero, one, and several names. Do not assume there is exactly one positional argument.

**Subtle watch-out:** `os.args[0]` is the executable name. With no user arguments, the user slice is empty; indexing it before checking length is an out-of-bounds bug. Preserve spaces inside each argument—shell tokenization already happened before Odin starts.

One possible direction

Iterate over `os.args[1:]` with a `for` loop and print one name per line. This avoids adding a custom string-joining utility before you need one.

<a id="flags"></a>

Chapter 7 · A maintainable interface

## 7. A real flag parser

Our greeting now needs a boolean switch and a positional name. We could write another loop over strings. The cost is not the loop itself; it is the expanding collection of rules about missing values, unknown options, help, and type conversion. `core:flags` already supplies that machinery. Its model is an annotated struct, so the interface has a representation we can inspect and test.

```odin
package main

import "core:flags"
import "core:fmt"
import "core:os"

Options :: struct {
    name: string `args:"pos=0,required" usage:"Name to greet."`,
    loud: bool   `usage:"Print an enthusiastic greeting."`,
}

main :: proc() {
    options: Options
    flags.parse_or_exit(&options, os.args, .Unix)

    if options.loud {
        fmt.printfln("HELLO, %s!", options.name)
    } else {
        fmt.printfln("Hello, %s.", options.name)
    }
}
```

Try:

```sh
odin run . -- Ada
odin run . -- Ada --loud
odin run . -- --help
odin run . --
```

With Unix-style parsing, options commonly look like `--name=value`, `--name value`, or a boolean switch such as `--loud`. The package also supports Odin-style arguments. Pick a style and document it; the two formats are not mixed in one parse.

### Read the struct as user documentation

The `required` tag expresses an input contract. The `usage` tag becomes help text. The struct field name provides the default flag name; underscores in flag names map to dashes. You can add a field such as `limit: int` and the parser converts the text to an integer or reports a parse error.

Additional positional arguments can be collected in the conventional `overflow` field. A successful conversion to `int` establishes syntax and representability, not the domain rule that a preview limit must be nonnegative and reasonably small.

### Two parsers? No: a parser and its boundary wrapper

Read [parsing.odin](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/flags/parsing.odin) alongside [util.odin](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/flags/util.odin). `parse` receives user arguments, normally `os.args[1:]`, and returns an error union. `parse_or_exit` receives the whole vector, extracts the program name, drops element zero, then invokes `parse`. Giving the wrapper an already-sliced vector makes the first user argument masquerade as the executable name.

Inside `parse`, the parser validates the struct, tracks supplied fields and positional slots in bit arrays, then dispatches to the selected parsing style. Unix parsing also tracks how many following arguments a flag consumes. After syntactic parsing, `validate_arguments` checks requirements if validation is enabled and no earlier error remains. This sequence explains why required fields are checked at the end, rather than being treated as a property of the initial zero-valued struct.

For package tests and reusable code, call the returning parser. For a tiny executable, the exit wrapper can be convenient:

```odin
// Fragment with the Options type and flags import above.
options: Options
err := flags.parse(&options, []string{"Ada", "--loud"}, .Unix)
// Examine err before using options as validated input.
```

### Parsing has an ownership boundary too

The parser’s comment says persistent model allocations occur when appending to a dynamic array, setting a map value, or setting a C string. The caller must free allocations stored in the model. Do not generalize “the parser cleans up its bit arrays” into “the parser frees every field it populated.” Plain string fields may refer to argument storage rather than owning new copies; consult the relevant assignment path before extending their lifetime.

Keep the initial interface small: typed values, required arguments, and help. Add custom setters only when a real domain representation requires them.

**Exercise 7.1.** Add `limit: int` with help text. Choose a default. What should happen when the user supplies a negative number? Add a rule and test it.

**Subtle watch-out:** successful integer parsing does not mean the value is valid for your domain. Test both `--limit -1` and the zero boundary; parser syntax and your semantic range check are separate concerns.

**Design question.** Is a path positional or a named `--input` option? Choose based on whether the tool naturally processes one main input or many independent options. Consistency matters more than fashion.

<a id="errors"></a>

Part III · Failure and ownership

## 8. Errors, cleanup, and ownership

A familiar rule says “check the error before using the result.” It is a good rule, but incomplete. What if a procedure allocated some data and then failed? The result may be invalid as an answer yet still matter as a resource that must be released. Odin’s multiple return values let an API represent both facts at once.

```odin
allocator := context.allocator
data, err := os.read_entire_file_from_path(path, allocator)
defer delete(data, allocator)
if err != nil {
    fmt.eprintln("cannot read input: ", err)
    return 1
}
// Use data only after establishing success.
```

This fragment belongs in a procedure returning `int`; `path`, `fmt`, and `os` must be in scope. Cleanup is deliberately registered before interpreting the error, because the whole-file reader can return allocated partial data on a read failure. For other APIs, register cleanup only when their returned resource is valid. The resource pattern is:

1. Read the procedure’s failure and ownership contract.
2. Request the resource and determine what was acquired, including on failure.
3. Register the matching cleanup for resources the caller owns.
4. Use the result only when its success preconditions hold.

`defer` schedules a statement until the surrounding scope exits. Multiple deferred statements execute in reverse declaration order. The closer the cleanup appears to acquisition, the easier it is to audit early returns.

> Resource question: “If this line returns early, who closes or frees what I already acquired?”

### A return unwinds a scope; process exit does not

Read [os.exit](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/process.odin). It calls the runtime’s direct process exit and explicitly warns that `@(fini)` procedures are not run. It also does not return through the active Odin scopes, so their deferred statements are not executed. This is why resource-owning examples should not call it in the middle of their work.

```odin
// Structural fragment: work owns resources; main owns the process boundary.
run :: proc() -> int {
    // Acquire resources, defer their cleanup, return a status.
    return 0
}
main :: proc() {
    status := run() // run's cleanup completes before this returns.
    os.exit(status)
}
```

The distinction matters even when the OS eventually reclaims heap memory and descriptors. A deferred flush, removal of a temporary file, or publication of a finished output is application behavior, not something the kernel can infer.

In [file\_util.odin](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/file_util.odin), the path-based whole-file helper opens, defers close, and delegates to the file-based reader. A partial byte slice may survive a read error. This gives us two separate audits: who closes the handle, and who releases returned bytes? The answer is the helper for the first and the caller for the second.

### Report the right amount

A user should learn what failed and what to try next. Avoid dumping internal implementation details or printing both a low-level error and a second confusing wrapper message. In a reusable procedure, return a useful error to the caller; at the CLI boundary, turn it into stderr output and a non-zero exit.

<a id="memory"></a>

Chapter 9 · Storage and lifetime

## 9. Memory and allocators

Suppose a parser allocates a result without an allocator parameter. Where did the memory come from? “The heap” is too vague an answer in Odin. An Odin-convention call carries a scope-local context, and allocation often uses `context.allocator`. The visible arguments are not the whole policy.

Start with lifetime rather than allocator fashion. A returned result must survive until its last consumer is finished. Scratch may be discarded together. A long-lived container must not retain views into scratch that was reset after a call.

A practical first rule: data that must outlive the current operation uses an allocator whose lifetime covers that use; short-lived scratch data can use temporary storage; owned dynamic arrays and maps are deleted when no longer needed. Always check each API's ownership contract.

```odin
items := make([dynamic]string)
defer delete(items)

append(&items, "alpha")
append(&items, "beta")

for item in items {
    fmt.println(item)
}
```

This snippet assumes `core:fmt` is imported. The dynamic array owns backing memory; `append` may move or grow that backing storage, so keep using the array value rather than holding an old pointer into its storage across a growth.

### Follow the lifetime

Before allocating, ask three questions: who owns the result, how long is it needed, and where is it freed? For `os.read_entire_file_from_path`, the supplied allocator receives the bytes, and the caller releases them with `delete`. For `os.lookup_env`, the chosen allocator owns the returned string when the variable is found.

### The allocator is a protocol represented by two fields

In [runtime/core.odin](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/base/runtime/core.odin), `Allocator` contains a procedure and a data pointer. Its procedure receives an allocation mode, size, alignment, old memory and size, and source location. The modes include allocation, freeing, resizing, freeing everything, and feature queries. A request can fail with `Out_Of_Memory` or `Mode_Not_Implemented`; an allocator is not obliged to implement every strategy.

This explains why an arena and a heap can share the interface without sharing individual-free behavior. It also explains why “I called delete” and “the allocator reclaimed these bytes immediately” are different claims.

### One container remembers; one view does not

Compare `delete_dynamic_array` and `delete_slice` in [core\_builtin.odin](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/base/runtime/core_builtin.odin). The dynamic-array overload uses the allocator stored in the array header and a capacity-based allocation size. The slice overload receives an allocator, defaulting to the current context, and uses the slice length. Changing the context between allocating a slice and deleting it can therefore select the wrong allocator. Save the chosen allocator or pass it explicitly.

The same file’s `_append_elems` grows capacity geometrically in this version, copies incoming elements, and returns an appended count plus an optional allocator error. Its growth formula is an observation, not a promised factor for all future releases. If allocation fails, partial progress is possible; code that requires every element must inspect both results rather than relying on the convenient form that omits the error.

A copied dynamic-array header still names the same backing storage. Two headers are not two independent owners. Growing one can leave the other describing old memory; deleting both can double-free. Keep one owner and pass borrowed views only while it remains stable.

A dynamic array of strings adds another layer: deleting the array releases the element storage, not every independently allocated string target. Literal strings in our example need no such cleanup. Owned cloned strings would. Ownership follows allocations, not punctuation.

**Source experiment.** Print length and capacity after each append; compare the observed growth with `_append_elems`. Do not assert those capacities as your application’s API. Then explain why `clear(&items)` retains capacity while `delete(items)` releases backing storage without automatically resetting every copied header.

![How an Odin allocator context flows through calls](../assets/diagrams/allocator-context.svg)

The scope-local context makes a cross-cutting choice available to nested Odin calls. The trade-off is that allocation behavior is not always visible in a procedure’s parameter list.

[Editable Mermaid source](../diagrams/allocator-context.mmd).

**Exercise 9.1.** Move allocation into a repeated operation and compare cleanup at the end of each iteration with cleanup only at the end of the command. Use an allocator/debugging tool to inspect the lifetime, then restore the correct owner.

**Subtle watch-out:** a short process may appear to “work” without freeing memory because the OS reclaims it at exit. That does not make the ownership correct for a long-running CLI or service. Also, a `defer` runs at its lexical scope exit; check which scope contains it.

<a id="files"></a>

Part IV · The operating system

## 12. Files are bytes

We want to count a file. The obvious approach is to ask the operating system for its size. Does that count its readable bytes? For a normal immutable disk file, often yes. For `/proc`, a pipe, or a file being changed concurrently, the question is different. Metadata is a report about an object; reading observes a sequence of bytes.

Our first implementation reads the input and counts what it receives. That makes the result easy to explain, at the cost of retaining the whole input. Text interpretation comes later: a byte count must not be labeled a character count.

For a small input, `os.read_entire_file_from_path` is direct and readable. It returns bytes and an error. This complete tool reports the byte count:

```odin
package main

import "core:fmt"
import "core:os"

run :: proc() -> int {
    if len(os.args) != 2 {
        fmt.eprintln("usage: count-bytes <path>")
        return 2
    }

    path := os.args[1]
    allocator := context.allocator
    data, err := os.read_entire_file_from_path(path, allocator)
    defer delete(data, allocator)
    if err != nil {
        fmt.eprintln("read failed: ", err)
        return 1
    }

    fmt.printfln("%s: %d bytes", path, len(data))
    return 0
}

main :: proc() {
    status := run()
    os.exit(status)
}
```

Build and use it:

```sh
odin check .
odin build . -out:count-bytes
./count-bytes main.odin
./count-bytes /proc/self/status
```

The last path is Linux-specific. It reads a kernel-provided view of the current process through `procfs`; it is not a normal disk file. Run `cat /proc/self/status` to compare. Some fields vary with the kernel and environment.

### Whole-file or streaming?

Whole-file reading is simple, but uses memory proportional to file size. It fits configuration files and modest inputs. For large files, open a file and process bounded chunks. Each read can return fewer bytes than the buffer length. Track exactly how many bytes were returned, handle end-of-file, and do not assume a single read fills the buffer.

### The whole-file helper has two algorithms

Read [read\_entire\_file\_from\_file](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/file_util.odin). It first asks for a size that fits in `int`. If the size is positive, it allocates that many bytes and reads until the slice is filled or a read reports an error. EOF becomes successful completion with the slice shortened to the bytes actually read.

If no usable positive size exists, it reads with a 1024-byte local buffer and appends to a dynamic array until completion. This is how a zero-size-reporting procfs file can still produce data. But a small *read buffer* does not imply bounded *total memory*: the accumulating dynamic array can grow for as long as input arrives.

Now challenge the positive-size branch. What if the file grows after the size query? This version’s loop fills the original allocation and stops; it does not promise to keep reading newly appended bytes. If the file shrinks, EOF shortens the result. The helper is useful, but it does not provide an atomic snapshot of a mutating file. State whether your application accepts that behavior.

The fallback also treats `Broken_Pipe` as completion in this revision. Do not silently apply that normalization to every lower-level read loop. The abstraction boundary decides which events count as normal completion.

`os.read` in [file.odin](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/file.odin) returns a count and an error; ordinary file EOF is `0, .EOF`. Opening establishes handle ownership, and a successful open should be paired with close. The count describes this read, not the buffer’s capacity.

**Exercise 12.1.** Compare the result for an empty file, a short text file, and a multi-megabyte file. Which approach should your real tool use, and what evidence supports that choice?

**Subtle watch-out:** a successful read call may return fewer bytes than requested without reaching EOF. Streaming code must process the returned count and continue; a fixed buffer is not a promise of a full read.

<a id="streams"></a>

## 13. Streams, pipes, and bounded work

The file-counting example has one uncomfortable property: a ten-gigabyte input asks us to retain ten gigabytes even though the answer is a single number. We do not need a more ingenious allocator. We need an algorithm that forgets bytes after counting them.

A Unix pipeline supplies bytes over time rather than handing us a complete array. The read boundaries depend on buffering and scheduling, not on our records. Let us separate the amount of data processed from the amount retained.

```sh
./count-bytes main.odin
./count-bytes main.odin >result.txt
./count-bytes missing.txt 2>error.txt
cat main.odin | wc -l
```

The count-bytes example reads a named path, not stdin; the final line uses existing tools to demonstrate stream composition. A natural next version accepts `-` to mean stdin. Its input loop should read a fixed-size buffer, process each returned range, and stop cleanly at EOF rather than accumulating an unlimited stream.

![A bounded stream-reading loop](../assets/diagrams/stream-pipeline.svg)

Use the returned byte count, not the buffer capacity. A read may be short without reaching EOF, and a logical record can cross a buffer boundary.

[Editable Mermaid source](../diagrams/stream-pipeline.mmd).

### A count-only loop with a fixed memory budget

This procedure is an extractable Odin example requiring `core:os`. It borrows a handle: the caller closes it if the caller opened it, but should not close inherited stdin merely because a helper has finished counting.

```odin
count_stream :: proc(input: ^os.File) -> (total: u64, err: os.Error) {
    buffer: [4096]u8
    for {
        n, read_err := os.read(input, buffer[:])
        if u64(n) > max(u64) - total {
            return total, .Invalid_Argument
        }
        total += u64(n)
        if read_err == .EOF { return total, nil }
        if read_err != nil { return total, read_err }
        if n == 0 { return total, .Unexpected_EOF }
    }
}
```

The buffer is reused; only the total survives an iteration. The no-progress branch avoids an accidental infinite loop for an unusual stream that returns zero without EOF. The overflow check ensures our counter cannot silently wrap on an extraordinarily long input. Here it reports a general invalid-argument error; a larger application could define a more descriptive domain error.

A byte counter need not interpret `buffer[:n]`. A parser must. Never inspect the unfilled tail as if it were new input: it contains old or irrelevant bytes. If you retain a preview, copy at most the remaining preview budget before the next read reuses the buffer.

### What the OS wrapper actually does

[os.read](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/file.odin) delegates through the file’s stream procedure. The POSIX implementation in [file\_posix.odin](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/file_posix.odin) caps a request, calls `posix.read`, maps zero to EOF, and maps a negative result to an error. Its shown read branch does not supply an automatic retry loop for every interruption. Do not import assumptions about another language’s I/O library.

The count loop above adds bytes before interpreting the error. That structure also accommodates interfaces that can return useful bytes with a terminal condition. It is not an invitation to ignore the error; success is reported only on the completion condition we chose.

### Bounded memory is not bounded time

A file can be larger than memory, a pipe may never close, and a producer may send data more slowly than expected. Bounded processing keeps memory use predictable. For network or pipe programs, also decide how to handle partial messages, cancellation, and broken pipes; a stream boundary is not automatically a record boundary.

Keep diagnostics on stderr so they do not contaminate machine-readable stdout. Test the behavior with a pipe and redirection, not only by watching the terminal.

**Exercise 13.1.** Add stdin support to `count-bytes`. Preserve path mode, document how `-` selects stdin, and test a short pipeline plus a large stream.

**Subtle watch-out:** pipes carry arbitrary chunks, not lines or complete records. A single read can split a logical record—or combine several—so parse state must survive buffer boundaries.

<a id="environment"></a>

## 14. Environment and process context

Suppose a tool uses `HOME` to find configuration. An empty value and an absent variable might both print as nothing. Should they mean the same thing? Only if we have deliberately chosen that contract. Checking the text alone throws away the distinction before we can decide.

Environment, working directory, inherited handles, and identity are inputs too. Odin’s implicit allocator context is a separate concept; it is not the process environment with a different name.

```odin
package main

import "core:fmt"
import "core:os"

main :: proc() {
    home, found := os.lookup_env("HOME", context.allocator)
    if !found {
        fmt.eprintln("HOME is not set")
        os.exit(1)
    }
    defer delete(home)

    fmt.printfln("HOME=%s", home)
}
```

`lookup_env` returns both a value and a boolean. A found empty value is different from a variable that was not set. By contrast, `get_env` returns an empty string for both cases; use the lookup form when that distinction matters.

```text
HOME= odin run .
env -u HOME ./your-program
pwd
id
```

These commands let you test empty versus unset input. Do not infer trust from the fact that a value arrived through the environment. A working directory also changes the interpretation of every relative path; repeat your test from a different directory before declaring the path contract complete.

### Allocation is part of this overload

[env.odin](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/env.odin) groups two `lookup_env` overloads. The allocating overload takes a key and allocator and returns a string plus `found`. The buffer overload instead takes a backing buffer and returns a string plus an error. Similar names do not imply identical failure shapes or ownership.

For the no-CRT Linux implementation in [env\_linux.odin](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/env_linux.odin), the lookup scans stored key/value entries and uses an index of minus one to signal absence. An empty value can still have a valid index. The allocating path clones the found string; the buffer path copies into the supplied buffer or reports `Buffer_Full`. The returned buffer-backed string is a borrowed view, not an owner.

That file also contains a warning about synchronizing the no-CRT environment implementation with third-party code linked to libc. We should not turn one platform branch into a universal claim about environment mutation across all foreign libraries. Prefer stable startup configuration when possible, and isolate environment-changing tests from concurrent consumers.

**Exercise 14.1 · Explain the difference.** Design three results for a configuration key: absent, present but empty, and present with text. Then choose deliberately which results trigger a default. Run both shell cases above rather than simulating absence with an empty string.

<a id="child-process"></a>

## 15. Starting child processes

We already have programs that count, probe, and transform files. Invoking them can be simpler than rebuilding them as libraries. The important boundary is not “inside or outside Odin”; it is the contract for arguments, output, completion, and ownership.

`Process_Desc.command` is an argument vector, not a shell script. A filename containing a semicolon remains one argument when passed as one string. That removes shell interpretation, but does not prevent the child from interpreting a leading dash as its own option.

```odin
package main

import "core:fmt"
import "core:os"

run :: proc() -> int {
    desc := os.Process_Desc{
        command = []string{"printf", "child says hello\n"},
    }
    state, stdout, stderr, err := os.process_exec(desc, context.allocator)
    defer delete(stdout)
    defer delete(stderr)

    if err != nil {
        fmt.eprintln("could not run child: ", err)
        return 1
    }

    fmt.printfln("exit=%d success=%t", state.exit_code, state.success)
    fmt.print(string(stdout))
    if len(stderr) > 0 {
        fmt.eprintln(string(stderr))
    }
    return 0 if state.success && state.exit_code == 0 else 1
}

main :: proc() {
    status := run()
    os.exit(status)
}
```

Try running it and then change the command to a missing executable. A spawn error differs from a child process that starts successfully and exits with a non-zero code; inspect both the returned error and `state.exit_code`.

**Security rule:** do not concatenate untrusted input into a shell command. Pass an executable and separate arguments. If a shell is genuinely required, make that boundary explicit and validate every value for the shell language being used.

### Captured output has a cost

`process_exec` captures stdout and stderr in memory until the child exits. That is convenient for short commands with bounded output. For long-running commands, large output, or interactive processes, use the lower-level process and pipe APIs so output can be consumed as it arrives. Decide who owns each pipe end and close unused ends; otherwise a reader may never observe EOF.

### Read the capture helper as a resource graph

In [process\_exec](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/process.odin), two pipes are created, one per output channel. A nested scope installs their write ends in a copy of the descriptor and starts the child. The parent closes its write ends when that scope exits, including on failure. Why so early? An extra open write end can stop a reader from observing EOF even after the child is finished.

The helper alternates checking the two read ends and appends received bytes to two dynamic arrays. This avoids simply reading stdout to completion while ignoring a full stderr pipe, but it still accumulates both outputs without a built-in size budget. Its 1024-byte scratch buffer is not a cap on captured output. The final byte slices belong to the supplied allocator, including when an error is returned; register their deletion before interpreting the error.

The descriptor’s stdout and stderr must remain nil when using capture: the helper asserts that you have not simultaneously requested redirection. Lower-level `process_start` uses those handles differently; nil there shuts a channel down rather than automatically inheriting a terminal. Convenience and primitive APIs are not interchangeable.

### Finding the executable is another input boundary

Read the Linux [\_process\_start](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/process_linux.odin) path. In this revision, a name without a slash searches the parent’s PATH, then checks the current directory as a fallback. It converts each argument and environment entry into a C string before execution. A supplied environment replaces the child environment; it is not a patch. The executable search occurs using the parent’s environment, so a child-only PATH does not necessarily control that search.

For a controlled service, an approved absolute executable path is clearer than relying on a mutable PATH and working directory. Reject embedded NUL bytes before crossing a C-string boundary. Also check both the API error and the child exit code; on Linux `success` reflects a zero normal exit, while its meaning is not identical on every platform.

Do not treat `process_exec` as a timeout mechanism. Its synchronous capture waits for completion. Choose lower-level supervision when cancellation or an output budget is a requirement, and drain both output channels while the child is running.

<a id="linux"></a>

Part V · Linux systems thinking

## 16. Linux as a systems-programming lab

Opening `/proc/self/status` is a useful trap for our intuition. We may expect a file’s contents to belong to a persistent object and its size metadata to predict what a read returns. Procfs challenges both assumptions: the kernel generates a view, and `self` identifies the process performing the open.

Start with `core:os`. Going below it should answer a concrete requirement, such as retrieving a Linux-specific status structure or using an event facility. Lower-level code adds obligations; it does not automatically add correctness.

### Think in resources and boundaries

### Process

A running program has an identity, arguments, environment, working directory, and exit status. A child process is a separate program with its own lifetime.

### File descriptor

A small OS-level handle used for files, pipes, terminals, and other streams. Ask who owns it, which side reads or writes, and who closes it.

### Memory

Every buffer has a lifetime and an owner. Allocation choice is part of the program's resource contract, not a decorative implementation detail.

### System call

A controlled transition from user code into the kernel. It has a defined calling convention, return convention, and error model.

Linux exposes useful interfaces through filesystems such as `/proc` and `/sys`, but those are interfaces, not promises that every file behaves like ordinary persistent storage. Document when a tool depends on a Linux-specific path or kernel facility.

### When to go below `core:os`

1. Write down the capability you need.
2. Search the current Odin package docs and source for an existing wrapper.
3. Prefer the wrapper when it covers your requirement.
4. If direct Linux APIs are needed, read the version-matched `core:sys/linux` declarations and examples.
5. Record argument types, ownership, return values, error handling, and platform limits in your code or design notes.

### Trace one abstraction boundary, not the entire kernel

Follow `os.read` from [file.odin](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/file.odin) into the selected stream procedure. Then compare [the POSIX implementation](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/file_posix.odin) with [core/sys/linux](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/sys/linux). A portable procedure can delegate to different target code. Its name alone does not establish which path you compiled.

A useful trace records the handle representation, request buffer and length, platform call, and translated error. Notice what is lost at the translation boundary: the shown POSIX read path maps negative results to a general error rather than exposing every errno as a distinct language-level value. If an application genuinely needs to distinguish interruption from another event, first find an API that preserves the required information.

[Runtime entry code](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/base/runtime/entry_unix.odin) supplies another concrete lesson: target branches contain different syscall numbers and startup forms. Copying an amd64 number into another architecture is not portable low-level programming. Read the selected declarations and test the actual target you claim to support.

A read from procfs is also not a whole-system snapshot. Values can change between reads, kernel versions add fields, and access permissions can differ in containers. When inspecting PID text, test your own parsing rule with a small fixture, then test the live path separately.

**Lab 16.1.** Read `/proc/self/status` with the file-reading example. Find the process ID with `grep '^Pid:'`. Repeat after invoking the program from a shell pipeline. Which details are stable, and which are environment-dependent?

**Subtle watch-out:** `/proc/self` means the process that opens the path. When your Odin program opens it, the PID is the Odin process—not necessarily the shell, the pipeline producer, or the process that later reads the captured output.

<a id="testing"></a>

## 20. Build, test, debug, and inspect

A program can type-check, pass package tests, and still fail when someone runs it from another directory. None of those observations contradicts the others. They answer different questions. Debugging becomes easier when we stop treating “the tests passed” as a single universal certificate.

First identify the boundary that failed: compilation, package behavior, process behavior, linking, or runtime loading. Then choose the smallest experiment that can distinguish your competing explanations.

```sh
odin check .
odin run .
odin test .
odin build . -out:tool
```

Use `odin check` after a small edit. Use `odin test` when the package contains tests. Build an executable when you need to test process invocation, shell pipelines, exit codes, or deployment behavior. Consult `odin help` for flags supported by your installed compiler.

### Test behavior, not spelling

For a CLI, test the interface a caller sees: normal output, stderr on failure, exit status, paths with spaces, empty input, unreadable files, and large input. For a parser, test missing and malformed arguments. For child execution, test both spawn failure and a child that exits unsuccessfully.

| Question | Experiment |
| --- | --- |
| Does success output stay clean? | Pipe stdout to another command while redirecting stderr separately. |
| Does a missing path fail? | Run with a path that does not exist and inspect both output streams and exit code. |
| Is memory proportional to input? | Compare whole-file reading with a bounded streaming design on a large file. |
| Does the child run safely? | Pass arguments containing spaces and punctuation as separate strings. |

### Build the experiment before choosing the explanation

Read the startup sequence in [entry\_unix.odin](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/base/runtime/entry_unix.odin) and the process boundary in [process.odin](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/process.odin). A missing executable, a failed child, and a successfully executed program whose output violates our format are three different failures. A link failure occurs before any of those runtime paths. Make the classification before changing code.

For an allocation suspicion, isolate a package-level operation and use the test runner’s allocator tracking. For a pipeline failure, build the executable and capture stdout, stderr, and status. For a library-loading failure, inspect the linked artifact with `ldd` only for executables you trust, and compare installed development libraries with runtime libraries. Debug information makes breakpoints and stack traces more useful, but it does not add a test oracle.

```sh
odin build . -debug -out:tool
./tool 'path with spaces' > out.txt 2> err.txt
status=$?
printf '%s\n' "$status"
```

Change one input or one implementation decision at a time. If a large file triggers the problem, reduce its size or structure until the trigger is clear. Preserve that case as a fixture. “It stopped happening after three unrelated edits” is weaker evidence than a failure that disappears after one targeted change and returns when that change is reversed.

<a id="testing-specs"></a>

Part VI · Tests and specifications

## 21. Tests as executable specifications

Our preview function promises to return at most a requested number of bytes. Four length checks sound convincing. But an implementation that always returns the *last* bytes could pass those checks too. The first question in test design is therefore not “how many tests?” It is “which incorrect implementations would this assertion allow?”

We will specify both content and lifetime. A preview is a view over the first bytes, not a newly allocated copy. That is a deliberate API choice; callers must keep the input alive.

Odin discovers tests by the `@(test)` attribute, not by a special filename. Keep production code and test procedures in the same package directory; a name such as `preview_test.odin` is a useful convention, while every file still declares the same package.

![How Odin runs package tests](../assets/diagrams/test-boundaries.svg)

Each test is an ordinary Odin procedure with the runner’s `^testing.T` parameter. The test runner also tracks memory by default.

[Editable Mermaid source](../diagrams/test-boundaries.mmd).

### A small package contract

`preview.odin`

```odin
package preview

preview :: proc(data: []u8, limit: int) -> []u8 {
    if limit <= 0 {
        return data[:0]
    }
    n := len(data)
    if n > limit {
        n = limit
    }
    return data[:n]
}
```

`preview_test.odin`

```odin
package preview

import "core:testing"

@(test)
test_preview_truncates :: proc(t: ^testing.T) {
    bytes := [3]u8{1, 2, 3}
    testing.expect_value(t, len(preview(bytes[:], 2)), 2)
}

@(test)
test_preview_handles_empty_input :: proc(t: ^testing.T) {
    bytes := [1]u8{1}
    testing.expect_value(t, len(preview(bytes[:0], 2)), 0)
}

@(test)
test_preview_keeps_short_input :: proc(t: ^testing.T) {
    bytes := [3]u8{1, 2, 3}
    testing.expect_value(t, len(preview(bytes[:], 9)), 3)
}

@(test)
test_preview_is_empty_for_nonpositive_limit :: proc(t: ^testing.T) {
    bytes := [3]u8{1, 2, 3}
    testing.expect_value(t, len(preview(bytes[:], 0)), 0)
    testing.expect_value(t, len(preview(bytes[:], -1)), 0)
}
```

Run the package tests with `odin test .`. These four tests specify length boundaries; they do not yet prove that the prefix bytes are correct. Add the following test to the same test file:

```odin
@(test)
test_preview_borrows_the_prefix :: proc(t: ^testing.T) {
    bytes := [3]u8{1, 2, 3}
    result := preview(bytes[:], 2)
    if !testing.expect_value(t, len(result), 2) { return }
    testing.expect_value(t, result[0], u8(1))
    testing.expect_value(t, result[1], u8(2))
    result[0] = 9
    testing.expect_value(t, bytes[0], u8(9))
}
```

The length guard matters: expectations report failures but normally continue execution. Indexing after a failed length expectation would produce a secondary bounds fault that obscures the original contract violation. The mutation check deliberately specifies aliasing; it would be the wrong assertion for an API that promised an independent copy.

### How an expectation becomes a failed test

Read [testing.odin](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/testing/testing.odin). `expect` logs an error when its condition is false, then returns that condition. `expect_value` compares suitable values and logs the expression, expected value, and observed value. Neither function directly increments `T.error_count` in its body.

Follow the next boundary into [logging.odin](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/testing/logging.odin): `test_logger_proc` increments the test error count for error-level or higher messages, clones log text using a runner-owned allocator, and sends a reporting event. [runner.odin](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/testing/runner.odin) installs that logger in the test context before invoking the test procedure.

This is the context system doing useful work. It lets ordinary library calls report through a test-specific logger. It also explains why replacing `context.logger` casually inside a test can interfere with the failure-recording mechanism. An assertion is not magic simply because its function is named `expect`; the surrounding runner supplies part of its meaning.

### Memory tracking has a defined reach

In this revision the runner enables tracking by default, creates task allocators and tracking wrappers, and checks remaining tracked allocations and bad frees after the test and its registered cleanups. The feature can find missing cleanup along the tracked allocation path. It cannot certify every foreign allocator, borrowed pointer lifetime, race, or dangling view. FFmpeg allocations are not automatically accounted for by Odin’s tracking allocator.

`testing.cleanup` records a procedure, data pointer, and a copy of the registration context. The runner executes those cleanups in reverse order, with special handling for faulted tests. The source recommends ordinary `defer` for usual cases; stronger cleanup has stricter requirements because a fault in it can take down the runner.

The test seed is another explicit contract: `T.seed` lets randomized tests repeat a recorded seed. Tests may run concurrently, so file paths, process environment, and mutable globals are not implicitly isolated. A serial run can diagnose sharing, but does not make a shared-state design safe.

### Make the specification useful

- Test ordinary results and boundaries: empty input, the smallest and largest accepted values, and limits just below or above the boundary.
- Test rejected input and failure results, not only the happy path.
- Keep each test independent; the runner may execute tests on multiple threads.
- Use `defer` for ordinary cleanup and avoid shared mutable state between tests.
- When a package has nested packages, use `-all-packages` only when you intend to run their tests too.

These are package-level tests. For observable process behavior—stdout, stderr, exit status, pipes, and child-process failures—use the CLI checks from Chapter 20 as well. A unit test can specify a function’s result; it cannot prove that the executable’s external contract is correct.

**Exercise 21.1.** Add a function that validates a preview limit. Write tests for a valid value, zero, a negative value, and a value beyond the allowed maximum. Make the test names describe the contract, then run `odin test .`.

**Subtle watch-out:** an assertion that the compiler removes is not a test result. Use `core:testing` expectations for test outcomes, and check the test command’s exit status in automation.

<a id="capstone"></a>

Part VII · Put the pieces together

## 22. Capstone: a small file inspector

We can now build a tool whose implementation we can explain rather than merely operate. `odin-inspect` reports the number of bytes actually read and a bounded preview. It is intentionally not a replacement for `file` or `hexdump`. The exercise is to join contracts we have already examined without losing their distinctions.

Keep one vertical slice working at each stage. A perfect preview parser is not useful if the executable silently reports success on a missing file. Conversely, a good process boundary does not prove that the preview contains the first bytes.

### Stage A: define the contract

- Required positional path.
- `-` means stdin in a later stage.
- `--limit N` caps the preview size.
- Normal result goes to stdout; errors go to stderr.
- Invalid arguments and failed reads produce non-zero exit status.

### Stage B: implement the simplest useful version

Use `core:flags` for parsing, `core:os` for file access, an allocator chosen for the input lifetime, and `defer` for cleanup. First report byte length. Confirm that an empty file reports zero and that a missing path fails clearly.

### Stage C: bound memory

Replace whole-file loading with a fixed-size buffer and streaming reads. Keep a running byte count. Store only the first `limit` bytes for display; continue reading or stop early according to the contract you choose. Write down that trade-off: stopping early is faster, while reading to EOF gives the full byte count.

### Stage D: make it testable

1. Test a zero-byte file.
2. Test a short ASCII file.
3. Test UTF-8 text and verify byte count is not described as character count.
4. Test a large file and observe memory behavior.
5. Test a path containing spaces.
6. Test a missing path and an invalid limit.
7. Test redirected stdout and stderr separately.

### A resource and evidence ledger

| Resource or claim | Owner or evidence | Common mistaken assumption |
| --- | --- | --- |
| Opened input handle | The input-opening scope closes it. | A borrowed stdin handle is owned in the same way. |
| Fixed read buffer | One local buffer reused by the loop. | A retained view stays unchanged after the next read. |
| Preview allocation | One explicit allocator and one release path. | Deleting a subslice is equivalent to freeing its original owner. |
| Byte count | Sum of successful returned ranges. | The size reported before reading is an immutable snapshot. |
| CLI success | Output channels and exit status tested together. | Printing the expected number establishes the whole contract. |

Use the [whole-file helper](https://github.com/odin-lang/Odin/blob/84bc3fc2100b0f7880a3af37f71bccdcda41c6f9/core/os/file_util.odin) as a deliberately simple Stage B baseline, then replace retention with Chapter 13’s streaming approach. Do not merely change its scratch-buffer size: the accumulating container is what makes whole-file memory proportional to input.

The peak input-memory budget is the fixed buffer plus preview capacity, with small bookkeeping. Counting to EOF still performs work proportional to input and can wait forever on a producer that never closes. If you choose to stop after the preview is full, label the result as a preview, not a complete byte count.

**Adversarial fixture.** Feed a stream whose first read ends halfway through a UTF-8 sequence, then a stream whose record delimiter crosses the buffer boundary. Byte preview mode may display hex without decoding. Text mode needs a different contract and retained decoder state. Do not quietly turn one into the other.

### Stage E: add Linux-specific learning

Try the inspector against `/proc/self/status`. Make Linux-only assumptions explicit in help or docs. If you add a Linux-specific API, explain why `core:os` was not sufficient and tie the code to the Odin source version you tested.

### Stage F: compose four programs through a checked record format

The [runnable pipeline](../examples/README.md#http-and-cli-integration-lab) supplies four packages: [inspect](../examples/21-capstone/inspect/main.odin), [select](../examples/21-capstone/select/main.odin), [summarize](../examples/21-capstone/summarize/main.odin), and [run-pipeline](../examples/21-capstone/run-pipeline/main.odin). They compose through one newline-delimited JSON record per input: exactly `{"path": string, "bytes": integer}`. The final summary is exactly `{"files": integer, "bytes": integer}`. JSON escapes spaces, quotes and newlines in paths; splitting on spaces would not be an equivalent protocol.

`inspect` counts actual input bytes, `select MIN_BYTES` filters records, and `summarize` accumulates totals. The shared [records package](../examples/21-capstone/records/records.odin) bounds a line at 65,536 bytes, an inspected input file at 1 MiB, and the record count at 100,000. These are the lab's explicit budgets, not recommendations for every CLI. A borrowed line view expires on the next read: copy anything you must retain.

After following the build instructions, try the managed composition from the repository root:

```sh
docs/examples/21-capstone/.build/run-pipeline \
  "$(pwd)/docs/examples/21-capstone/.build" 10 ./README.md
```

A shell pipeline can deliver a downstream summary even when an upstream command later fails. Checking a pipeline's final exit status does not retract stdout already consumed. The runner therefore starts downstream first, owns and closes its pipe endpoints, waits for all three stages under a shared ten-second budget, checks every result, and only then publishes a final summary of at most 256 bytes. On failure it emits no success stdout and cleans up its direct children.

**Trade-off:** waiting before reading would deadlock if output could fill the pipe. Here the tiny final-output bound is part of the proof; do not generalize that pattern to an arbitrary subprocess. Nor is timing out a direct child a promise that every descendant or remote operation has stopped.

**Exercise 22.1.** Inspect an empty file, a UTF-8 file, and a path containing quotes or a newline. Then include a missing file after a valid one. Compare each stage's stdout/exit status with the runner's all-stage publication policy. Explain why byte count is not character count and why partial upstream records do not authorize a successful final summary.

**Exercise 22.2.** Feed an unknown JSON field, an oversized line, a negative byte count, and a source exceeding the file budget. Run the supplied integration harness. State which boundary rejects each input and who releases the relevant buffer/handle.

**Capstone done when:** another developer can run it from the README, predict its output and exit status, understand who owns every buffer and handle, and reproduce the tests without your terminal history.
