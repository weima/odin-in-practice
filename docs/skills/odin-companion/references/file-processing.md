# File and text processing in Odin

Use this when a task is to edit, search or check files. It exists so the default is not a throwaway script in another language. The bundled example is `examples/13a-text-processing/` (the same package as the book's chapter 13a).

## Choose the smallest tool that is precise enough

| The job | Use |
| --- | --- |
| One edit in one file | The harness's edit tool or the editor: the change is visible and reviewed. |
| Search or filter lines | `rg`, `grep`, `sed`, `awk`. |
| Reshape JSON | `jq`. |
| A repeatable job that must refuse a wrong assumption, understand syntax, or carry its own tests | The bundled Odin example, or a small program built on its patterns. |

Odin is not more precise by itself. A type checker will not notice that the wrong occurrence was replaced. Precision comes from the rules below and from tests. Building the example takes about a second and a half and running it is instantaneous, so a compiled tool is not a heavy choice.

Do not write an ad hoc script in another language for a repeatable file edit just because it is quicker to start. If the project already standardizes on a scripting language, follow the project, and still apply the rules below.

## Rules for any tool that edits files

1. **State the assumption and count it.** An edit means "this text occurs exactly N times". Count first and refuse when the count differs. Report the count found so the failure is explainable.
2. **Take the text from files, not from shell arguments.** Quoting cannot alter a file's content, and a multi-line snippet is just a file.
3. **Offer a dry run** that reports the change and writes nothing. Use it first for bulk edits.
4. **Replace atomically.** Write a uniquely named sibling temporary file (created exclusively, so two writers never share one), flush and sync it, close it, rename it over the target, and remove the temporary on every failure after the open. Pass the original file mode to the new file. A refused or failed edit leaves the original untouched.
5. **Refuse what you cannot handle:** a file containing a NUL byte (binary), a file above a size limit, an empty search text, and anything that is not a regular file. A FIFO blocks a reader forever, and renaming a temporary over a symlink replaces the link instead of editing its target. Classify the path with `os.lstat` before opening it.
6. **Bound memory for input that may be large.** Read through a fixed-size buffer with limits on line length and result count, and report what was skipped or truncated instead of silently dropping it.
7. **Never search source code with a flat search.** A `;` inside a string, a character literal or a comment looks like a separator. Mask first: copy the source and blank the contents of comments, strings and raw strings, keeping the length and the newlines, then search the copy.
8. **Use distinct exit codes.** 0 success, 1 a refusal or findings (the tool worked and the answer is "no"), 2 a usage or I/O error.
9. **Verify the tool like a program.** Test that a refused edit changes nothing and leaves no temporary, that a transformation is idempotent, that bounds hold, and run it on real input. Break a rule on purpose and confirm a test fails.

## What the example contains

`examples/13a-text-processing/` is one package behind one command with four subcommands.

```sh
odin build examples/13a-text-processing -out:textproc
./textproc replace FILE --old-file OLD --new-file NEW [--count N] [--dry-run]
./textproc check PATH [--max-columns N]
./textproc split FILE [--write]
./textproc grep PATTERN FILE [--max-line-bytes N] [--max-matches N]
TZ=UTC odin test examples/13a-text-processing
```

- `replace_exact` and `replace_in_file` implement rules 1, 3, 4 and 5.
- `grep_file` implements rule 6 with `core:bufio` and `core:text/regex`.
- `mask_source`, `find_separators`, `check_source` and `split_statements` implement rule 7. `check` only reports, so run it first; `split --write` rewrites a file, so compile and run the tests afterwards.

## Library facts to check, not assume

These were observed with the pinned `dev-2026-10` compiler; confirm them on yours.

- `strings.replace_all` returns the original string, unallocated, with `was_allocation == false` when nothing matches. Deleting its result unconditionally frees memory you do not own. Build the result yourself, or check the flag.
- `bufio.reader_read_slice` returns a view into the reader's buffer. Copy what you keep before the next read. When the buffer fills before the delimiter it returns `.Buffer_Full` and consumes the buffer, so skip the rest of the line by reading until a slice ends it. The smallest buffer `reader_init` accepts is 16 bytes, so a smaller requested line limit is raised to 16; report the limit actually applied.
- `core:text/regex` exists. `regex.create` compiles a pattern, `regex.match` returns a capture that you must `regex.destroy`, and a capture lists the whole match and then each group.
- The file mode in the `os.lstat` result (`info.mode`) is a permission set that can be passed to `os.open` or `os.write_entire_file`, which is how an edit keeps an executable file executable.
- `os.stat` and `os.is_dir` open the path in this release, so both **block on a FIFO**, and `os.is_dir` reports an unreadable directory as "not a directory". `os.lstat` reports the type without opening anything. `os.get_absolute_path` also blocks on a symlink to a FIFO.
- Odin block comments nest.
- `odinfmt` (from OLS) defaults to CRLF line endings, so pass a config with `"newline_style": "LF"`. It normalizes layout but does not split statements chained with `;`; split them first, then format.

## Report

State the command run, the count found versus expected, whether the file changed, and the verification you ran (tests, `check`, a compile after any `split`).
