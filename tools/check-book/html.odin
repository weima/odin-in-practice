package main

import "core:encoding/entity"
import "core:strings"

// What the checker needs from one generated page.
//
// Strings may point into the HTML text passed to parse_page, so keep that text alive as
// long as the Page. Anything else is allocated with context.allocator and never freed:
// the program runs the whole check inside one arena.
Page :: struct {
    ids:      map[string]struct{},
    links:    [dynamic]string,
    chapters: [dynamic]string,
}

// One start tag, reduced to the three attributes the checker reads. An attribute with no
// value counts as empty, like Python's None, and an empty one is never a link or an id.
Start_Tag :: struct {
    name:         string,
    id:           string,
    href:         string,
    src:          string,
    self_closing: bool,
}

// parse_page reads HTML the way Python's html.parser does for the cases that matter to
// the checker, and is deliberately not a general HTML parser. mkdocs output is HTML, not
// XML, so a tag scanner is the right tool: core:encoding/xml rejects it.
parse_page :: proc(html: string) -> Page {
    page: Page
    heading: strings.Builder
    in_heading := false

    position := 0
    for position < len(html) {
        rest := html[position:]

        if rest[0] != '<' {
            end := strings.index_byte(rest, '<')
            end = len(rest) if end < 0 else end
            if in_heading {
                strings.write_string(&heading, rest[:end])
            }
            position += end
            continue
        }

        consumed, is_markup := skip_markup(rest)
        if is_markup {
            position += consumed
            continue
        }

        if strings.has_prefix(rest, "</") && len(rest) > 2 && is_letter(rest[2]) {
            close := strings.index_byte(rest, '>')
            if close < 0 {
                position = write_remainder(&heading, in_heading, html, position)
                continue
            }
            name := rest[2:tag_name_length(rest[2:]) + 2]
            if strings.equal_fold(name, "h2") && in_heading {
                note_chapter(&page, strings.to_string(heading))
                in_heading = false
            }
            position += close + 1
            continue
        }

        if len(rest) > 1 && is_letter(rest[1]) {
            tag, length, complete := read_start_tag(rest)
            if !complete {
                position = write_remainder(&heading, in_heading, html, position)
                continue
            }
            position += length
            note_tag(&page, tag)
            if strings.equal_fold(tag.name, "h2") {
                strings.builder_reset(&heading)
                in_heading = true
            }
            if !tag.self_closing && is_raw_text_element(tag.name) {
                position = skip_raw_text(html, position, tag.name, &heading, in_heading)
            }
            continue
        }

        // A '<' that does not start a tag is ordinary text.
        if in_heading {
            strings.write_byte(&heading, '<')
        }
        position += 1
    }
    return page
}

// write_remainder handles input that ends inside a construct that never closes. Python
// treats it as text, so it adds nothing to the page. It only keeps heading text complete.
write_remainder :: proc(
    heading: ^strings.Builder,
    in_heading: bool,
    html: string,
    from: int,
) -> int {
    if in_heading {
        strings.write_string(heading, html[from:])
    }
    return len(html)
}

// skip_markup passes over a comment, a CDATA section, a doctype or a processing
// instruction. It reports how many bytes to skip, and whether `rest` starts with one.
// An unfinished one skips to the end of the input.
skip_markup :: proc(rest: string) -> (consumed: int, is_markup: bool) {
    terminator := ""
    start := 0
    switch {
    case strings.has_prefix(rest, "<!--"):
        terminator, start = "-->", 4
    case strings.has_prefix(rest, "<![CDATA["):
        terminator, start = "]]>", 9
    case strings.has_prefix(rest, "<!"), strings.has_prefix(rest, "<?"):
        terminator, start = ">", 2
    case:
        return 0, false
    }
    close := strings.index(rest[start:], terminator)
    if close < 0 {
        return len(rest), true
    }
    return start + close + len(terminator), true
}

is_raw_text_element :: proc(name: string) -> bool {
    return strings.equal_fold(name, "script") || strings.equal_fold(name, "style")
}

// skip_raw_text moves past the body of a <script> or <style> element, up to its closing
// tag, which the main loop then reads. The body is data, not markup. If the element never
// closes, the rest of the input is its body.
skip_raw_text :: proc(
    html: string,
    from: int,
    name: string,
    heading: ^strings.Builder,
    in_heading: bool,
) -> int {
    body := html[from:]
    for offset := 0; offset + 2 + len(name) <= len(body); offset += 1 {
        if body[offset] != '<' || body[offset + 1] != '/' {
            continue
        }
        if strings.equal_fold(body[offset + 2:offset + 2 + len(name)], name) {
            if in_heading {
                strings.write_string(heading, body[:offset])
            }
            return from + offset
        }
    }
    return len(html)
}

// read_start_tag reads `<name attributes>`. `complete` is false when the input ends first.
read_start_tag :: proc(rest: string) -> (tag: Start_Tag, length: int, complete: bool) {
    name_length := tag_name_length(rest[1:])
    tag.name = rest[1:1 + name_length]
    position := 1 + name_length

    for {
        // Between attributes: spaces, and a '/' that is not part of "/>".
        for position < len(rest) && is_between_attributes(rest, position) {
            position += 1
        }
        if position >= len(rest) {
            return
        }
        if rest[position] == '/' {
            tag.self_closing = true
            position += 1
        }
        if rest[position] == '>' {
            return tag, position + 1, true
        }

        // The first byte of a name may be anything, even '='; the rest stop at "= \t/>".
        start := position
        position += 1
        for position < len(rest) && !is_attribute_name_end(rest[position]) {
            position += 1
        }
        attribute := rest[start:position]
        for position < len(rest) && is_space(rest[position]) {
            position += 1
        }

        value := ""
        if position < len(rest) && rest[position] == '=' {
            for position < len(rest) && rest[position] == '=' {
                position += 1
            }
            for position < len(rest) && is_space(rest[position]) {
                position += 1
            }
            if position >= len(rest) {
                return
            }
            if rest[position] == '"' || rest[position] == '\'' {
                quote := rest[position]
                close := strings.index_byte(rest[position + 1:], quote)
                if close < 0 {
                    return
                }
                value = rest[position + 1:position + 1 + close]
                position += close + 2
            } else {
                begin := position
                for position < len(rest) && !is_space(rest[position]) && rest[position] != '>' {
                    position += 1
                }
                value = rest[begin:position]
            }
        }

        // A later attribute of the same name replaces an earlier one.
        switch {
        case strings.equal_fold(attribute, "id"):
            tag.id = unescape(value)
        case strings.equal_fold(attribute, "href"):
            tag.href = unescape(value)
        case strings.equal_fold(attribute, "src"):
            tag.src = unescape(value)
        }
    }
}

is_tag_end :: proc(rest: string, position: int) -> bool {
    return position < len(rest) && rest[position] == '>'
}

// A '/' between attributes is skipped, unless it begins "/>".
is_between_attributes :: proc(rest: string, position: int) -> bool {
    c := rest[position]
    return is_space(c) || (c == '/' && !is_tag_end(rest, position + 1))
}

is_tag_name_end :: proc(c: byte) -> bool {
    return is_space(c) || c == '/' || c == '>'
}

is_attribute_name_end :: proc(c: byte) -> bool {
    return is_tag_name_end(c) || c == '='
}

// tag_name_length counts the bytes of a tag name: up to whitespace, '/' or '>'.
tag_name_length :: proc(text: string) -> int {
    length := 0
    for length < len(text) && !is_tag_name_end(text[length]) {
        length += 1
    }
    return length
}

// note_tag records the ids and links one start tag contributes.
note_tag :: proc(page: ^Page, tag: Start_Tag) {
    if tag.id != "" {
        page.ids[tag.id] = {}
    }
    target := ""
    switch {
    case strings.equal_fold(tag.name, "a"), strings.equal_fold(tag.name, "link"):
        target = tag.href
    case strings.equal_fold(tag.name, "img"), strings.equal_fold(tag.name, "script"):
        target = tag.src
    }
    if target != "" {
        append(&page.links, target)
    }
}

// note_chapter records a numbered heading with any letter suffix so the exact-set check can
// reject unsupported identifiers such as 17b, as well as accept 13a and 17a.
note_chapter :: proc(page: ^Page, raw_heading: string) {
    text := strings.trim_space(unescape(raw_heading))
    digits := 0
    for digits < len(text) && text[digits] >= '0' && text[digits] <= '9' {
        digits += 1
    }
    if digits == 0 {
        return
    }
    end := digits
    for end < len(text) && is_letter(text[end]) {
        end += 1
    }
    if end < len(text) && text[end] == '.' {
        // Clone: `text` may point into the heading buffer, which the next <h2> reuses.
        append(&page.chapters, strings.clone(text[:end]))
    }
}

// unescape decodes HTML entities such as &amp; and &#49;. Text with no '&' is returned
// as is, without allocating. Text the decoder rejects is kept as written.
unescape :: proc(text: string) -> string {
    if !strings.contains_rune(text, '&') {
        return text
    }
    decoded, err := entity.decode_xml(text)
    if err != nil {
        return text
    }
    return decoded
}

is_letter :: proc(c: byte) -> bool {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

is_space :: proc(c: byte) -> bool {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f'
}
