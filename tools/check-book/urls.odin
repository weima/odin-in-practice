package main

import "core:path/filepath"
import "core:strings"

// A link split the way Python's urllib.parse.urlsplit splits it. Every field is a
// slice of the input, so nothing here is allocated.
Url_Parts :: struct {
    scheme:   string,
    netloc:   string,
    path:     string,
    fragment: string,
}

split_link :: proc(link: string) -> Url_Parts {
    parts: Url_Parts
    rest := link

    // A scheme is letters, digits, '+', '-' and '.', and starts with a letter. A ':' later
    // in a path ("dir/page:1.html") does not make one.
    colon := strings.index_byte(rest, ':')
    if colon > 0 && is_scheme(rest[:colon]) {
        parts.scheme = rest[:colon]
        rest = rest[colon + 1:]
    }

    if strings.has_prefix(rest, "//") {
        end := strings.index_any(rest[2:], "/?#")
        end = len(rest) if end < 0 else end + 2
        parts.netloc = rest[2:end]
        rest = rest[end:]
    }

    // The fragment is cut first, so a '?' inside it is not a query.
    hash := strings.index_byte(rest, '#')
    if hash >= 0 {
        parts.fragment = rest[hash + 1:]
        rest = rest[:hash]
    }

    query := strings.index_byte(rest, '?')
    if query >= 0 {
        rest = rest[:query]
    }

    parts.path = rest
    return parts
}

is_scheme :: proc(text: string) -> bool {
    for c, index in text {
        letter := (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
        digit := c >= '0' && c <= '9'
        if index == 0 && !letter {
            return false
        }
        if !letter && !digit && c != '+' && c != '-' && c != '.' {
            return false
        }
    }
    return true
}

// unquote decodes %XX escapes. Like Python's urllib.parse.unquote, and unlike
// core:net's percent_decode, it keeps a malformed escape as written instead of failing,
// and it never turns '+' into a space.
unquote :: proc(text: string, allocator := context.allocator) -> string {
    out := strings.builder_make(allocator)
    index := 0
    for index < len(text) {
        c := text[index]
        if c == '%' && index + 2 < len(text) {
            value := hex_pair(text[index + 1:index + 3])
            if value >= 0 {
                strings.write_byte(&out, byte(value))
                index += 3
                continue
            }
        }
        strings.write_byte(&out, c)
        index += 1
    }
    return strings.to_string(out)
}

// hex_pair returns the byte two hex digits spell, or -1 if either is not a hex digit.
hex_pair :: proc(pair: string) -> int {
    if len(pair) != 2 {
        return -1
    }
    high := hex_digit(pair[0])
    low := hex_digit(pair[1])
    if high < 0 || low < 0 {
        return -1
    }
    return high * 16 + low
}

hex_digit :: proc(c: byte) -> int {
    switch {
    case c >= '0' && c <= '9':
        return int(c - '0')
    case c >= 'a' && c <= 'f':
        return int(c - 'a') + 10
    case c >= 'A' && c <= 'F':
        return int(c - 'A') + 10
    }
    return -1
}

// resolve_link turns a link path into a cleaned absolute path, the way a browser would
// resolve it from a page in `dir`. A rooted link ignores `dir`, as in a browser.
// The caller frees the result.
resolve_link :: proc(dir, link: string, allocator := context.allocator) -> string {
    if strings.has_prefix(link, "/") {
        cleaned, _ := filepath.clean(link, allocator)
        return cleaned
    }
    joined, _ := filepath.join({dir, link}, allocator)
    return joined
}

// is_within reports whether `path` is `root` or lies under it. The check is by whole
// path component: "/site-other" is not inside "/site".
is_within :: proc(root, path: string) -> bool {
    if path == root {
        return true
    }
    return strings.has_prefix(path, root) && len(path) > len(root) && path[len(root)] == '/'
}
