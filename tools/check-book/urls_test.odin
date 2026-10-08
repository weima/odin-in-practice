package main

import "core:testing"

@(test)
test_split_link_separates_scheme_host_path_and_fragment :: proc(t: ^testing.T) {
    cases := []struct {
        link:                             string,
        scheme, netloc, path, fragment: string,
    } {
        {"chapters/a.html", "", "", "chapters/a.html", ""},
        {"chapters/a.html#top", "", "", "chapters/a.html", "top"},
        {"a.html?x=1#frag", "", "", "a.html", "frag"},
        {"a.html#frag?notquery", "", "", "a.html", "frag?notquery"},
        {"#only-fragment", "", "", "", "only-fragment"},
        {"https://example.org/p/q#f", "https", "example.org", "/p/q", "f"},
        {"mailto:someone@example.org", "mailto", "", "someone@example.org", ""},
        {"//cdn.example.org/x.js", "", "cdn.example.org", "/x.js", ""},
        {"/root/relative.css", "", "", "/root/relative.css", ""},
        {"data:text/plain;base64,AAAA", "data", "", "text/plain;base64,AAAA", ""},
        {"", "", "", "", ""},
    }
    for item in cases {
        parts := split_link(item.link)
        testing.expectf(t, parts.scheme == item.scheme, "%q: scheme %q", item.link, parts.scheme)
        testing.expectf(t, parts.netloc == item.netloc, "%q: netloc %q", item.link, parts.netloc)
        testing.expectf(t, parts.path == item.path, "%q: path %q", item.link, parts.path)
        testing.expectf(
            t,
            parts.fragment == item.fragment,
            "%q: fragment %q",
            item.link,
            parts.fragment,
        )
    }
}

@(test)
test_a_colon_after_the_first_path_segment_is_not_a_scheme :: proc(t: ^testing.T) {
    // "dir/page:1.html" has a ':' but "dir/page" is not a scheme (it contains '/').
    parts := split_link("dir/page:1.html")
    testing.expect_value(t, parts.scheme, "")
    testing.expect_value(t, parts.path, "dir/page:1.html")

    // A scheme must start with a letter.
    digits := split_link("1abc:rest")
    testing.expect_value(t, digits.scheme, "")
}

@(test)
test_unquote_decodes_valid_escapes_and_leaves_malformed_ones :: proc(t: ^testing.T) {
    cases := []struct {
        input, want: string,
    } {
        {"a%20b", "a b"},
        {"cli%2Dlinux.html", "cli-linux.html"},
        {"%E2%82%AC", "\u20ac"},
        {"plus+stays", "plus+stays"}, // unlike a form decoder, '+' is not a space
        {"100%", "100%"}, // a trailing '%' is kept
        {"%zz", "%zz"}, // not hex: kept as written
        {"%2", "%2"}, // too short: kept as written
        {"%%41", "%A"}, // the first '%' is not an escape, the second is
        {"", ""},
    }
    for item in cases {
        got := unquote(item.input)
        testing.expectf(t, got == item.want, "unquote(%q): %q, want %q", item.input, got, item.want)
        delete(got)
    }
}

@(test)
test_resolve_normalizes_dots_and_absolute_paths :: proc(t: ^testing.T) {
    cases := []struct {
        dir, link, want: string,
    } {
        {"/site/chapters", "a.html", "/site/chapters/a.html"},
        {"/site/chapters", "../index.html", "/site/index.html"},
        {"/site/chapters", "./x/../a.html", "/site/chapters/a.html"},
        {"/site/chapters", "/abs/p.html", "/abs/p.html"},
        {"/site/chapters", "../../../etc/passwd", "/etc/passwd"},
    }
    for item in cases {
        got := resolve_link(item.dir, item.link)
        message := "%q + %q: %q, want %q"
        testing.expectf(t, got == item.want, message, item.dir, item.link, got, item.want)
        delete(got)
    }
}

@(test)
test_is_within_requires_a_whole_path_component :: proc(t: ^testing.T) {
    testing.expect(t, is_within("/site", "/site"))
    testing.expect(t, is_within("/site", "/site/a/b.html"))
    testing.expect(t, !is_within("/site", "/site-other/a.html"), "a name prefix is not inside")
    testing.expect(t, !is_within("/site", "/etc/passwd"))
}
