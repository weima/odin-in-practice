package main

import "core:flags"
import "core:fmt"
import "core:os"
import "core:strings"

// Exit codes: 0 success, 1 a refusal or findings (the tool worked, the answer is
// "no"), 2 a usage or I/O error. A script can tell "the file needs attention"
// apart from "the tool could not run".
EXIT_OK :: 0
EXIT_REFUSED :: 1
EXIT_ERROR :: 2

USAGE :: `textproc - exact, bounded, syntax-aware text processing

Usage:
  textproc replace <file> --old-file <path> --new-file <path> [--count N] [--dry-run]
  textproc check <file-or-directory> [--max-columns N]
  textproc split <file> [--write]
  textproc grep <pattern> <file> [--max-line-bytes N] [--max-matches N]
`

Replace_Arguments :: struct {
    file:     string `args:"pos=0,required" usage:"The file to edit."`,
    old_file: string `args:"required" usage:"A file holding the exact text to find."`,
    new_file: string `args:"required" usage:"A file holding the replacement text."`,
    count:    int `usage:"How many occurrences are expected (default 1)."`,
    dry_run:  bool `usage:"Report the change without writing it."`,
}

Check_Arguments :: struct {
    path:        string `args:"pos=0,required" usage:"A file or a directory of .odin files."`,
    max_columns: int `usage:"Longest allowed line (default 100)."`,
}

Split_Arguments :: struct {
    file:  string `args:"pos=0,required" usage:"The Odin source file."`,
    write: bool `usage:"Replace the file instead of printing the result."`,
}

Grep_Arguments :: struct {
    pattern:        string `args:"pos=0,required" usage:"A regular expression."`,
    file:           string `args:"pos=1,required" usage:"The file to search."`,
    max_line_bytes: int `usage:"Longest line to buffer (default 4096, at least 16)."`,
    max_matches:    int `usage:"Stop after this many matches (default 1000)."`,
}

main :: proc() {
    os.exit(run(os.args[1:]))
}

run :: proc(args: []string) -> int {
    if len(args) == 0 {
        fmt.eprint(USAGE)
        return EXIT_ERROR
    }
    switch args[0] {
    case "replace":
        return run_replace(args[1:])
    case "check":
        return run_check(args[1:])
    case "split":
        return run_split(args[1:])
    case "grep":
        return run_grep(args[1:])
    case "--help", "-h", "help":
        fmt.print(USAGE)
        return EXIT_OK
    }
    fmt.eprintfln("textproc: unknown command %q", args[0])
    fmt.eprint(USAGE)
    return EXIT_ERROR
}

run_replace :: proc(args: []string) -> int {
    options: Replace_Arguments
    if flags.parse(&options, args, .Unix) != nil {
        fmt.eprintln("textproc: invalid arguments for replace")
        return EXIT_ERROR
    }
    expected := options.count if options.count > 0 else 1

    // The text comes from files, so no shell quoting can alter it.
    old, _, old_err := read_text_file(options.old_file, DEFAULT_MAX_BYTES)
    new, _, new_err := read_text_file(options.new_file, DEFAULT_MAX_BYTES)
    defer delete(old)
    defer delete(new)
    if old_err != .None || new_err != .None {
        fmt.eprintln("textproc: could not read --old-file or --new-file")
        return EXIT_ERROR
    }

    report, err := replace_in_file(options.file, old, new, expected, options.dry_run)
    switch err {
    case .None:
        verb := "would replace" if options.dry_run else "replaced"
        fmt.printfln(
            "%s %d occurrence(s) in %s (%d -> %d bytes)",
            verb,
            report.found,
            options.file,
            report.bytes_before,
            report.bytes_after,
        )
        return EXIT_OK
    case .Count_Mismatch:
        fmt.eprintfln(
            "textproc: refused: found %d occurrence(s), expected %d; %s is unchanged",
            report.found,
            expected,
            options.file,
        )
        return EXIT_REFUSED
    case .Empty_Old_Text:
        fmt.eprintln("textproc: the text to find is empty")
    case .Read_Failed:
        fmt.eprintfln("textproc: could not read %s", options.file)
    case .Binary_File:
        fmt.eprintfln("textproc: %s looks binary (it contains a NUL byte)", options.file)
    case .Too_Large:
        fmt.eprintfln("textproc: %s is too large", options.file)
    case .Not_Regular_File:
        fmt.eprintfln("textproc: %s is not a regular file", options.file)
    case .Write_Failed:
        fmt.eprintfln("textproc: could not write %s; it is unchanged", options.file)
    }
    return EXIT_ERROR
}

run_check :: proc(args: []string) -> int {
    options: Check_Arguments
    if flags.parse(&options, args, .Unix) != nil {
        fmt.eprintln("textproc: invalid arguments for check")
        return EXIT_ERROR
    }
    max_columns := options.max_columns if options.max_columns > 0 else 100

    files, listed := odin_files(options.path)
    defer {
        for file in files {
            delete(file)
        }
        delete(files)
    }
    if !listed {
        fmt.eprintfln("textproc: could not list every directory under %s", options.path)
        return EXIT_ERROR
    }
    problems := 0
    for file in files {
        text, _, err := read_text_file(file, DEFAULT_MAX_BYTES)
        if err != .None {
            fmt.eprintfln("textproc: could not read %s", file)
            return EXIT_ERROR
        }
        findings := check_source(text, max_columns)
        for finding in findings {
            fmt.printfln("%s:%d:%d: %v", file, finding.line, finding.column, finding.kind)
        }
        problems += len(findings)
        delete(findings)
        delete(text)
    }
    return EXIT_REFUSED if problems > 0 else EXIT_OK
}

run_split :: proc(args: []string) -> int {
    options: Split_Arguments
    if flags.parse(&options, args, .Unix) != nil {
        fmt.eprintln("textproc: invalid arguments for split")
        return EXIT_ERROR
    }
    text, mode, err := read_text_file(options.file, DEFAULT_MAX_BYTES)
    if err != .None {
        fmt.eprintfln("textproc: could not read %s", options.file)
        return EXIT_ERROR
    }
    defer delete(text)
    result := split_statements(text)
    defer delete(result)

    if !options.write {
        fmt.print(result)
        return EXIT_OK
    }
    if result == text {
        fmt.printfln("%s: nothing to split", options.file)
        return EXIT_OK
    }
    if write_file_atomic(options.file, transmute([]byte)result, mode) != .None {
        fmt.eprintfln("textproc: could not write %s; it is unchanged", options.file)
        return EXIT_ERROR
    }
    fmt.printfln("%s: split", options.file)
    return EXIT_OK
}

run_grep :: proc(args: []string) -> int {
    options: Grep_Arguments
    if flags.parse(&options, args, .Unix) != nil {
        fmt.eprintln("textproc: invalid arguments for grep")
        return EXIT_ERROR
    }
    max_line_bytes := options.max_line_bytes if options.max_line_bytes > 0 else 4096
    // Report the limit that was applied, not the one that was asked for: bufio's
    // smallest buffer is MIN_LINE_BYTES.
    max_line_bytes = max(max_line_bytes, MIN_LINE_BYTES)
    max_matches := options.max_matches if options.max_matches > 0 else 1000

    result, err := grep_file(options.file, options.pattern, max_line_bytes, max_matches)
    defer destroy_grep_result(&result)
    switch err {
    case .None:
    case .Bad_Pattern:
        fmt.eprintfln("textproc: %q is not a valid regular expression", options.pattern)
        return EXIT_ERROR
    case .Open_Failed, .Read_Failed:
        fmt.eprintfln("textproc: could not read %s", options.file)
        return EXIT_ERROR
    }
    for match in result.matches {
        fmt.printfln("%s:%d:%s", options.file, match.line, match.text)
    }
    if result.skipped_long_lines > 0 {
        fmt.eprintfln(
            "textproc: skipped %d line(s) longer than %d bytes",
            result.skipped_long_lines,
            max_line_bytes,
        )
    }
    if result.truncated {
        fmt.eprintfln("textproc: stopped after %d matches", max_matches)
    }
    return EXIT_OK if len(result.matches) > 0 else EXIT_REFUSED
}

// The .odin files at `path`: the file itself, or every one below a directory.
// Hidden directories (.git, .build) are skipped. The caller owns the result.
//
// ok is false if any directory could not be listed. That must be an error: a check
// that silently inspected nothing would pass a tree it never looked at.
odin_files :: proc(path: string) -> (files: [dynamic]string, ok: bool) {
    // lstat, not is_dir: is_dir opens the path, so it reports an unreadable directory
    // as "not a directory", and the walk would then quietly treat it as a file.
    info, stat_err := os.lstat(path, context.temp_allocator)
    if stat_err != nil {
        return files, false
    }
    if info.type != .Directory {
        append(&files, strings.clone(path))
        return files, true
    }
    entries, err := os.read_all_directory_by_path(path, context.temp_allocator)
    if err != nil {
        return files, false
    }
    for entry in entries {
        full, _ := strings.concatenate({path, "/", entry.name})
        defer delete(full)
        if entry.type == .Directory {
            if !strings.has_prefix(entry.name, ".") {
                nested, nested_ok := odin_files(full)
                for file in nested {
                    append(&files, file)
                }
                delete(nested)
                if !nested_ok {
                    return files, false
                }
            }
        } else if entry.type == .Regular && strings.has_suffix(entry.name, ".odin") {
            // Symlinks inside a tree are not followed, and not read as files.
            append(&files, strings.clone(full))
        }
    }
    return files, true
}
