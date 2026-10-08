package main

import "core:bufio"
import "core:os"
import "core:strings"
import "core:text/regex"

DEFAULT_MAX_BYTES :: 16 * 1024 * 1024

Edit_Report :: struct {
    found:        int,
    bytes_before: int,
    bytes_after:  int,
    changed:      bool,
}

// Reads a whole text file, refusing one that is too large or looks binary. Reading
// everything is fine for source files; for unbounded input, stream (see grep_file).
// The caller owns the returned text and its mode.
read_text_file :: proc(
    path: string,
    max_bytes: int,
    allocator := context.allocator,
) -> (
    text: string,
    mode: os.Permissions,
    err: Edit_Error,
) {
    info, stat_err := os.stat(path, context.temp_allocator)
    if stat_err != nil {
        return "", {}, .Read_Failed
    }
    if int(info.size) > max_bytes {
        return "", {}, .Too_Large
    }
    data, read_err := os.read_entire_file(path, allocator)
    if read_err != nil {
        delete(data, allocator)
        return "", {}, .Read_Failed
    }
    // A NUL byte almost never appears in text, so it is a cheap test for binary data.
    if strings.contains_rune(string(data), 0) {
        delete(data, allocator)
        return "", {}, .Binary_File
    }
    return string(data), info.mode, .None
}

// Replaces the file's contents without ever exposing a half-written file: write a
// sibling temporary, flush and sync it, close it, then rename it over the target.
// A rename within one directory is atomic; across filesystems it would fail. Every
// failure after the open removes the temporary. A refused write leaves the old
// target untouched.
write_file_atomic :: proc(path: string, data: []byte, mode: os.Permissions) -> Edit_Error {
    temp, _ := strings.concatenate({path, ".tmp"}, context.temp_allocator)
    file, open_err := os.open(temp, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, mode)
    if open_err != nil {
        return .Write_Failed
    }
    written, write_err := os.write(file, data)
    ok := write_err == nil && written == len(data) && os.flush(file) == nil && os.sync(file) == nil
    // Close exactly once, whether or not the writes worked, then replace the target.
    close_err := os.close(file)
    if !ok || close_err != nil || os.rename(temp, path) != nil {
        _ = os.remove(temp)
        return .Write_Failed
    }
    return .None
}

// The edit this tool is for: an exact-count replacement in one file. With dry_run
// it computes and reports the change but writes nothing.
replace_in_file :: proc(
    path, old, new: string,
    expected: int,
    dry_run: bool,
    max_bytes := DEFAULT_MAX_BYTES,
) -> (
    report: Edit_Report,
    err: Edit_Error,
) {
    text, mode, read_err := read_text_file(path, max_bytes)
    if read_err != .None {
        return {}, read_err
    }
    defer delete(text)

    replaced, replace_err := replace_exact(text, old, new, expected)
    report.found = replaced.found
    if replace_err != .None {
        return report, replace_err
    }
    defer delete(replaced.text)

    report.bytes_before = len(text)
    report.bytes_after = len(replaced.text)
    report.changed = replaced.text != text
    if dry_run || !report.changed {
        return report, .None
    }
    return report, write_file_atomic(path, transmute([]byte)replaced.text, mode)
}

Grep_Error :: enum {
    None,
    Bad_Pattern,
    Open_Failed,
    Read_Failed,
}

Match :: struct {
    line: int, // 1-based
    text: string, // owned by the Grep_Result
}

Grep_Result :: struct {
    matches:            [dynamic]Match,
    skipped_long_lines: int, // lines longer than max_line_bytes, never buffered
    truncated:          bool, // stopped at max_matches
}

destroy_grep_result :: proc(result: ^Grep_Result) {
    for match in result.matches {
        delete(match.text)
    }
    delete(result.matches)
    result^ = {}
}

// Finds lines matching a regular expression, reading the file through a fixed-size
// buffer: memory use is bounded by max_line_bytes and max_matches, not by the size
// of the file. A line longer than max_line_bytes is counted and skipped rather than
// buffered; a final line without a newline is still searched.
grep_file :: proc(
    path, pattern: string,
    max_line_bytes := 4096,
    max_matches := 1000,
) -> (
    result: Grep_Result,
    err: Grep_Error,
) {
    expression, pattern_err := regex.create(pattern)
    if pattern_err != nil {
        return {}, .Bad_Pattern
    }
    defer regex.destroy(expression)

    file, open_err := os.open(path)
    if open_err != nil {
        return {}, .Open_Failed
    }
    defer os.close(file)

    reader: bufio.Reader
    bufio.reader_init(&reader, os.to_stream(file), max_line_bytes)
    defer bufio.reader_destroy(&reader)

    line_number := 0
    for {
        slice, read_err := bufio.reader_read_slice(&reader, '\n')
        if read_err == .Buffer_Full {
            // Too long to hold. Discard the rest of the line without keeping it.
            result.skipped_long_lines += 1
            line_number += 1
            skip_rest_of_line(&reader)
            continue
        }
        if len(slice) == 0 && read_err != nil {
            if read_err != .EOF {
                err = .Read_Failed
            }
            break
        }
        line_number += 1
        line := strings.trim_right(string(slice), "\r\n")
        capture, matched := regex.match(expression, line)
        if matched {
            if len(result.matches) >= max_matches {
                regex.destroy(capture)
                result.truncated = true
                break
            }
            append(&result.matches, Match{line_number, strings.clone(line)})
        }
        regex.destroy(capture)
        if read_err != nil {
            break
        }
    }
    return result, err
}

skip_rest_of_line :: proc(reader: ^bufio.Reader) {
    for {
        slice, err := bufio.reader_read_slice(reader, '\n')
        if err != .Buffer_Full {
            return
        }
        _ = slice
    }
}
