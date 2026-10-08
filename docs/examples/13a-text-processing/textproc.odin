package main

import "core:strings"

Edit_Error :: enum {
    None,
    Empty_Old_Text,
    Count_Mismatch,
    Read_Failed,
    Binary_File,
    Too_Large,
    Write_Failed,
}

Replace_Result :: struct {
    text:  string, // owned by the caller; empty when the replacement was refused
    found: int, // how many times `old` occurred, reported even when refused
}

// Replaces every occurrence of `old` with `new`, but only if `old` occurs exactly
// `expected` times. A wrong count means the text is not what the caller assumed,
// and an edit made on a wrong assumption is worse than no edit, so it is refused.
// Occurrences do not overlap: "aa" occurs once in "aaa".
//
// Ownership: result.text is a fresh allocation the caller must delete, whenever
// err is .None. On an error it is empty and there is nothing to free.
replace_exact :: proc(
    text, old, new: string,
    expected: int,
    allocator := context.allocator,
) -> (
    result: Replace_Result,
    err: Edit_Error,
) {
    if len(old) == 0 {
        return {}, .Empty_Old_Text
    }
    result.found = strings.count(text, old)
    if result.found != expected {
        return result, .Count_Mismatch
    }

    out := strings.builder_make(allocator)
    rest := text
    for {
        at := strings.index(rest, old)
        if at < 0 {
            break
        }
        strings.write_string(&out, rest[:at])
        strings.write_string(&out, new)
        rest = rest[at + len(old):]
    }
    strings.write_string(&out, rest)
    result.text = strings.to_string(out)
    return result, .None
}
