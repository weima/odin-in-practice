package main

import "core:strings"

// Searching source text with plain string operations is unsafe: a ';' inside a
// string, a character literal or a comment looks exactly like a separator. The
// technique used here is to MASK first: copy the source and blank out the contents
// of every comment, string and raw string. The copy has the same length and the
// same newlines, so every position and line number still lines up with the
// original, but a plain search of the copy sees only real code.

// Returns a masked copy of `source`. The caller owns it and must delete it.
mask_source :: proc(source: string, allocator := context.allocator) -> string {
    masked := make([]u8, len(source), allocator)
    copy(masked, source)

    index := 0
    for index < len(source) {
        switch {
        case strings.has_prefix(source[index:], "//"):
            index = blank_until_newline(masked, index + 2)
        case strings.has_prefix(source[index:], "/*"):
            index = blank_block_comment(masked, index)
        case source[index] == '"' || source[index] == '\'':
            index = blank_quoted(masked, index, source[index])
        case source[index] == '`':
            index = blank_raw_string(masked, index)
        case:
            index += 1
        }
    }
    return string(masked)
}

blank :: proc(masked: []u8, index: int) {
    if masked[index] != '\n' {
        masked[index] = ' '
    }
}

blank_until_newline :: proc(masked: []u8, start: int) -> int {
    index := start
    for index < len(masked) && masked[index] != '\n' {
        masked[index] = ' '
        index += 1
    }
    return index
}

// Odin block comments nest. The outermost delimiters stay; the inside is blanked.
blank_block_comment :: proc(masked: []u8, start: int) -> int {
    depth := 0
    index := start
    for index < len(masked) {
        if index + 1 < len(masked) && masked[index] == '/' && masked[index + 1] == '*' {
            depth += 1
            if depth > 1 {
                blank(masked, index)
                blank(masked, index + 1)
            }
            index += 2
        } else if index + 1 < len(masked) && masked[index] == '*' && masked[index + 1] == '/' {
            depth -= 1
            if depth > 0 {
                blank(masked, index)
                blank(masked, index + 1)
            }
            index += 2
            if depth == 0 {
                return index
            }
        } else {
            if depth > 0 && index > start + 1 {
                blank(masked, index)
            }
            index += 1
        }
    }
    return index
}

// A string or character literal. A backslash escapes the next byte, so \" does
// not end the literal. The quotes stay; the contents are blanked.
blank_quoted :: proc(masked: []u8, start: int, quote: u8) -> int {
    index := start + 1
    for index < len(masked) && masked[index] != quote {
        if masked[index] == '\\' && index + 1 < len(masked) {
            blank(masked, index)
            index += 1
        }
        blank(masked, index)
        index += 1
    }
    return index + 1
}

// A raw string has no escapes and may span lines; newlines inside it are kept.
blank_raw_string :: proc(masked: []u8, start: int) -> int {
    index := start + 1
    for index < len(masked) && masked[index] != '`' {
        blank(masked, index)
        index += 1
    }
    return index + 1
}

Finding_Kind :: enum {
    Tab,
    Carriage_Return,
    Long_Line,
    Trailing_Whitespace,
    Statement_Chain,
}

// Positions are 1-based; the column counts bytes.
Finding :: struct {
    line:   int,
    column: int,
    kind:   Finding_Kind,
}

// Reports style problems. The caller owns the returned slice and must delete it.
check_source :: proc(
    source: string,
    max_columns: int,
    allocator := context.allocator,
) -> []Finding {
    findings: [dynamic]Finding
    findings.allocator = allocator

    masked := mask_source(source, context.temp_allocator)
    chains := find_separators(masked, context.temp_allocator)

    line_number := 1
    line_start := 0
    for line_start <= len(source) {
        line_end := line_start
        for line_end < len(source) && source[line_end] != '\n' {
            line_end += 1
        }
        text := source[line_start:line_end]

        // A carriage return before the newline is a line-ending problem, not
        // part of the line's content.
        content := text
        if strings.has_suffix(text, "\r") {
            content = text[:len(text) - 1]
        }

        first := len(findings)
        if column := strings.index_byte(content, '\t'); column >= 0 {
            append(&findings, Finding{line_number, column + 1, .Tab})
        }
        if len(content) > max_columns {
            append(&findings, Finding{line_number, max_columns + 1, .Long_Line})
        }
        trimmed := strings.trim_right(content, " \t")
        if len(trimmed) < len(content) {
            append(&findings, Finding{line_number, len(trimmed) + 1, .Trailing_Whitespace})
        }
        if len(content) < len(text) {
            append(&findings, Finding{line_number, len(content) + 1, .Carriage_Return})
        }
        for separator in chains {
            if separator >= line_start && separator < line_end {
                column := separator - line_start + 1
                append(&findings, Finding{line_number, column, .Statement_Chain})
            }
        }
        sort_by_column(findings[first:])

        line_start = line_end + 1
        line_number += 1
    }
    return findings[:]
}

sort_by_column :: proc(findings: []Finding) {
    for i in 1 ..< len(findings) {
        for j := i; j > 0 && findings[j].column < findings[j - 1].column; j -= 1 {
            findings[j], findings[j - 1] = findings[j - 1], findings[j]
        }
    }
}

// Byte offsets of the ';' characters that separate two statements on one line.
// `masked` must come from mask_source. A ';' is NOT a separator when it sits inside
// parentheses or brackets, inside the header of an if/for/switch/when (where it
// separates the initializer, the condition and the step), or when nothing but a
// comment follows it on the line.
find_separators :: proc(masked: string, allocator := context.allocator) -> []int {
    found: [dynamic]int
    found.allocator = allocator

    depth := 0 // parentheses and brackets
    header := false
    at_statement_start := true

    for index := 0; index < len(masked); index += 1 {
        c := masked[index]
        if at_statement_start && c != ' ' && c != '\t' && c != '\n' && c != '\r' {
            header = starts_header(masked[index:])
            at_statement_start = false
        }
        switch c {
        case '(', '[':
            depth += 1
        case ')', ']':
            depth -= 1
        case '{':
            if depth == 0 {
                header = false
                at_statement_start = true
            }
        case '}':
            if depth == 0 {
                at_statement_start = true
            }
        case '\n':
            if depth == 0 {
                header = false
                at_statement_start = true
            }
        case ';':
            if depth == 0 && !header {
                if code_follows_on_line(masked, index + 1) {
                    append(&found, index)
                }
                at_statement_start = true
            }
        }
    }
    return found[:]
}

starts_header :: proc(text: string) -> bool {
    for keyword in ([]string{"if", "for", "switch", "when", "else if"}) {
        if strings.has_prefix(text, keyword) {
            rest := text[len(keyword):]
            if len(rest) == 0 || rest[0] == ' ' || rest[0] == '(' || rest[0] == '{' {
                return true
            }
        }
    }
    return false
}

code_follows_on_line :: proc(masked: string, start: int) -> bool {
    for index := start; index < len(masked); index += 1 {
        switch masked[index] {
        case ' ', '\t', '\r':
        case '\n':
            return false
        case '/':
            // A comment after the ';' is not code.
            next := masked[index + 1] if index + 1 < len(masked) else 0
            return !(next == '/' || next == '*')
        case:
            return true
        }
    }
    return false
}

// Puts every ';'-separated statement on its own line, and expands a one-line
// block that holds several statements. It never touches a ';' that find_separators
// rejects. The caller owns the result.
split_statements :: proc(source: string, allocator := context.allocator) -> string {
    masked := mask_source(source, context.temp_allocator)
    separators := find_separators(masked, context.temp_allocator)
    out := strings.builder_make(allocator)

    line_start := 0
    for line_start <= len(source) {
        line_end := line_start
        for line_end < len(source) && source[line_end] != '\n' {
            line_end += 1
        }
        split_line(&out, source, masked, separators, line_start, line_end)
        if line_end < len(source) {
            strings.write_byte(&out, '\n')
        }
        line_start = line_end + 1
    }
    return strings.to_string(out)
}

split_line :: proc(
    out: ^strings.Builder,
    source, masked: string,
    separators: []int,
    start, end: int,
) {
    has_separator := false
    for separator in separators {
        if separator >= start && separator < end {
            has_separator = true
        }
    }
    if !has_separator {
        strings.write_string(out, source[start:end])
        return
    }

    // A brace pair is expanded when a separator lies inside it, however deeply.
    expanding := make(map[int]bool, 8, context.temp_allocator)
    opens := make([dynamic]int, context.temp_allocator)
    for index in start ..< end {
        switch masked[index] {
        case '{':
            append(&opens, index)
        case '}':
            if len(opens) > 0 {
                open := pop(&opens)
                for separator in separators {
                    if separator > open && separator < index {
                        expanding[open] = true
                        expanding[index] = true
                        break
                    }
                }
            }
        }
    }

    indent := leading_whitespace(source[start:end])
    level := 0
    index := start
    for index < end {
        switch {
        case slice_contains(separators, index):
            trim_trailing_spaces(out)
            new_line(out, indent, level)
            index = skip_spaces(source, index + 1, end)
        case source[index] == '{' && expanding[index]:
            strings.write_byte(out, '{')
            level += 1
            new_line(out, indent, level)
            index = skip_spaces(source, index + 1, end)
        case source[index] == '}' && expanding[index]:
            level -= 1
            trim_trailing_spaces(out)
            new_line(out, indent, level)
            strings.write_byte(out, '}')
            index += 1
        case:
            strings.write_byte(out, source[index])
            index += 1
        }
    }
}

slice_contains :: proc(values: []int, wanted: int) -> bool {
    for value in values {
        if value == wanted {
            return true
        }
    }
    return false
}

leading_whitespace :: proc(line: string) -> string {
    return line[:len(line) - len(strings.trim_left(line, " \t"))]
}

skip_spaces :: proc(source: string, index, end: int) -> int {
    at := index
    for at < end && (source[at] == ' ' || source[at] == '\t') {
        at += 1
    }
    return at
}

trim_trailing_spaces :: proc(out: ^strings.Builder) {
    for len(out.buf) > 0 {
        last := out.buf[len(out.buf) - 1]
        if last != ' ' && last != '\t' {
            break
        }
        pop(&out.buf)
    }
}

new_line :: proc(out: ^strings.Builder, indent: string, level: int) {
    strings.write_byte(out, '\n')
    strings.write_string(out, indent)
    for _ in 0 ..< level {
        strings.write_string(out, "    ")
    }
}
