package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

PREFIX :: "/book/"
CHAPTER_ERROR :: "chapter headings are not exactly 1–31 plus 13a:"

// Each test builds its own small book in a fresh temporary directory.
temp_root :: proc(t: ^testing.T, name: string) -> string {
    pattern := fmt.tprintf("check-book-%s-*", name)
    root, err := os.make_directory_temp("", pattern, context.temp_allocator)
    testing.expect_value(t, err, nil)
    return root
}

write :: proc(root, relative, content: string) {
    path := fmt.tprintf("%s/%s", root, relative)
    slash := strings.last_index_byte(path, '/')
    _ = os.make_directory_all(path[:slash])
    _ = os.write_entire_file(path, content)
}

// A book that passes every check: chapters 1-31 plus 13a, an index with an anchor, a
// 404 page, a legacy anchor and a well-formed SVG. Tests then break one thing.
valid_book :: proc(t: ^testing.T, name: string) -> string {
    root := temp_root(t, name)
    chapters := strings.builder_make(context.temp_allocator)
    for number in 1 ..= 31 {
        fmt.sbprintf(&chapters, `<h2 id="c%d">%d. Chapter</h2>`, number, number)
    }
    strings.write_string(&chapters, `<h2 id="c13a">13a. Inserted chapter</h2>`)
    write(root, "html/chapters/all.html", strings.to_string(chapters))
    write(root, "html/index.html", `<h1 id="top">Top</h1><a href="chapters/all.html#c5">five</a>`)
    write(root, "html/404.html", `<a href="/book/index.html#top">home</a>`)
    write(root, "tools/legacy-anchors.json", `{"index.html": ["top"]}`)
    svg := `<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0"/></svg>`
    write(root, "docs/assets/ok.svg", svg)
    return root
}

errors_of :: proc(root: string) -> [dynamic]string {
    return check_site(root, PREFIX).errors
}

expect_one_error :: proc(
    t: ^testing.T,
    errors: [dynamic]string,
    want: string,
    loc := #caller_location,
) {
    testing.expectf(t, len(errors) == 1, "want exactly one error, got %v", errors, loc = loc)
    if len(errors) > 0 {
        testing.expect_value(t, errors[0], want, loc)
    }
}

@(test)
test_a_valid_book_passes :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)
    root := valid_book(t, "valid")
    defer os.remove_all(root)

    report := check_site(root, PREFIX)
    testing.expectf(t, len(report.errors) == 0, "unexpected errors: %v", report.errors)
    testing.expect_value(t, report.pages, 3)
}

@(test)
test_a_missing_page_an_anchor_and_a_path_outside_are_reported :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)

    cases := []struct {
        name, link, want: string,
    } {
        {"page", "chapters/nope.html", "index.html: missing: chapters/nope.html"},
        {"anchor", "chapters/all.html#nope", "index.html: missing anchor: chapters/all.html#nope"},
        {"self-anchor", "#nope", "index.html: missing anchor: #nope"},
        {"outside", "../../escape.html", "index.html: outside reader: ../../escape.html"},
        {"rooted", "/abs/page.html", "index.html: outside reader: /abs/page.html"},
    }
    for item in cases {
        root := valid_book(t, item.name)
        defer os.remove_all(root)
        page := fmt.tprintf(`<h1 id="top">T</h1><a href="%s">x</a>`, item.link)
        write(root, "html/index.html", page)
        expect_one_error(t, errors_of(root), item.want)
    }
}

@(test)
test_links_that_are_not_checked_are_skipped :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)
    root := valid_book(t, "skipped")
    defer os.remove_all(root)

    write(root, "html/data.txt", "not a page")
    write(
        root,
        "html/index.html",
        `<h1 id="top">T</h1><a href="https://example.org/x#y">a</a>` +
        `<a href="mailto:me@example.org">b</a><a href="//cdn.example.org/x.js">c</a>` +
        `<a href="data:text/plain,hi">d</a><a href="data.txt#not-checked">e</a>` +
        `<a href="#top">f</a><a href="chapters/all.html?x=1#c13a">g</a>`,
    )
    testing.expectf(t, len(errors_of(root)) == 0, "unexpected errors: %v", errors_of(root))
}

@(test)
test_percent_escapes_in_paths_and_anchors_are_decoded :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)
    root := valid_book(t, "percent")
    defer os.remove_all(root)

    write(root, "html/space page.html", `<p id="a b">x</p>`)
    write(root, "html/index.html", `<h1 id="top">T</h1><a href="space%20page.html#a%20b">x</a>`)
    testing.expectf(t, len(errors_of(root)) == 0, "unexpected errors: %v", errors_of(root))
}

@(test)
test_a_link_to_a_directory_means_its_index_page :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)
    root := valid_book(t, "directory")
    defer os.remove_all(root)

    write(root, "html/sub/index.html", `<p id="here">x</p>`)
    write(root, "html/empty/readme.txt", `no index`)
    page := `<h1 id="top">T</h1><a href="sub/#here">ok</a><a href="empty/">bad</a>`
    write(root, "html/index.html", page)
    expect_one_error(t, errors_of(root), "index.html: missing: empty/")
}

@(test)
test_the_404_page_may_use_root_relative_links_under_the_site_prefix :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)
    root := valid_book(t, "notfound")
    defer os.remove_all(root)

    // Passing in valid_book. The same link on any other page leaves the reader.
    write(root, "html/chapters/other.html", `<a href="/book/index.html">home</a>`)
    expect_one_error(t, errors_of(root), "chapters/other.html: outside reader: /book/index.html")

    // A 404 page anywhere in the tree gets the rule, and a broken target is still found.
    write(root, "html/chapters/other.html", "")
    write(root, "html/sub/404.html", `<a href="/book/gone.html">x</a>`)
    expect_one_error(t, errors_of(root), "sub/404.html: missing: /book/gone.html")
}

@(test)
test_chapter_headings_must_be_exactly_the_expected_set :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)

    cases := []struct {
        name, replace, with: string,
    } {
        {"missing-13a", `<h2 id="c13a">13a. Inserted chapter</h2>`, ``},
        {"extra-13b", `13a. Inserted`, `13b. Inserted`},
        {"duplicate", `<h2 id="c13a">13a. Inserted chapter</h2>`, `<h2>13a. A</h2><h2>13a. B</h2>`},
        {"missing-1", `<h2 id="c1">1. Chapter</h2>`, ``},
        {"extra-32", `<h2 id="c13a">`, `<h2>32. Surplus</h2><h2 id="c13a">`},
        // Same number of headings, wrong set: 7 is missing and 8 appears twice.
        {"swapped", `<h2 id="c7">7. Chapter</h2>`, `<h2>8. Chapter</h2>`},
    }
    for item in cases {
        root := valid_book(t, item.name)
        defer os.remove_all(root)
        path := fmt.tprintf("%s/html/chapters/all.html", root)
        data, _ := os.read_entire_file(path, context.temp_allocator)
        changed, _ := strings.replace(string(data), item.replace, item.with, 1)
        write(root, "html/chapters/all.html", changed)

        errors := errors_of(root)
        testing.expectf(t, len(errors) == 1, "%s: want one error, got %v", item.name, errors)
        if len(errors) > 0 {
            testing.expectf(
                t,
                strings.has_prefix(errors[0], CHAPTER_ERROR + " ['"),
                "%s: %q",
                item.name,
                errors[0],
            )
        }
    }
}

@(test)
test_chapters_are_only_counted_in_the_chapters_directory :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)
    root := valid_book(t, "elsewhere")
    defer os.remove_all(root)

    // A numbered h2 on another page is not a chapter, so it changes nothing.
    write(root, "html/index.html", `<h1 id="top">T</h1><h2>99. Not a chapter</h2>`)
    testing.expectf(t, len(errors_of(root)) == 0, "unexpected errors: %v", errors_of(root))
}

@(test)
test_legacy_anchors_must_still_exist :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)
    root := valid_book(t, "legacy")
    defer os.remove_all(root)

    write(root, "tools/legacy-anchors.json", `{"index.html": ["top", "gone"]}`)
    expect_one_error(t, errors_of(root), "legacy page or explicit anchor missing: index.html")

    write(root, "tools/legacy-anchors.json", `{"nowhere.html": ["top"]}`)
    expect_one_error(t, errors_of(root), "legacy page or explicit anchor missing: nowhere.html")
}

@(test)
test_a_malformed_svg_is_reported_and_a_valid_one_is_not :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)
    root := valid_book(t, "svg")
    defer os.remove_all(root)

    write(root, "docs/assets/nested/broken.svg", `<svg><path d="M0 0"></svg>`)
    errors := errors_of(root)
    testing.expectf(t, len(errors) == 1, "want one error, got %v", errors)
    if len(errors) > 0 {
        message := errors[0]
        testing.expectf(
            t,
            strings.has_prefix(message, "invalid SVG XML: docs/assets/nested/broken.svg"),
            "%q",
            message,
        )
    }
}

@(test)
test_an_unreadable_legacy_file_and_an_empty_site_are_reported :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)

    root := temp_root(t, "empty")
    defer os.remove_all(root)
    errors := errors_of(root)
    testing.expectf(t, len(errors) >= 1, "an empty directory is not a book")
    found := false
    for message in errors {
        if message == "No generated HTML found; build the book first" {
            found = true
        }
    }
    testing.expectf(t, found, "missing the empty-site message in %v", errors)

    broken := valid_book(t, "badjson")
    defer os.remove_all(broken)
    write(broken, "tools/legacy-anchors.json", `{not json`)
    bad := errors_of(broken)
    wanted := len(bad) == 1 && strings.has_prefix(bad[0], "cannot read tools/legacy-anchors.json")
    testing.expectf(t, wanted, "%v", bad)
}
