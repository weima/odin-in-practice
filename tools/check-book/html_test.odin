package main

import "core:testing"

// The scanner allocates freely and never frees: the program runs it inside one arena.
// Tests use the temporary allocator and release it at the end.

expect_links :: proc(t: ^testing.T, page: Page, want: []string, loc := #caller_location) {
    testing.expect_value(t, len(page.links), len(want), loc)
    for item, index in want {
        if index < len(page.links) {
            testing.expect_value(t, page.links[index], item, loc)
        }
    }
}

@(test)
test_ids_and_links_come_from_the_tags_the_checker_knows :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)

    page := parse_page(
        `<link href="style.css"><a id="top" href="chapters/a.html#x">a</a>` +
        `<img src="logo.png"/><script src="app.js"></script>` +
        `<p id="intro">text</p><form action="ignored.html"><use href="#sprite"/>`,
    )
    expect_links(t, page, {"style.css", "chapters/a.html#x", "logo.png", "app.js"})
    testing.expect(t, "top" in page.ids)
    testing.expect(t, "intro" in page.ids)
    testing.expect_value(t, len(page.ids), 2)
}

@(test)
test_attribute_quoting_case_and_entities :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)

    page := parse_page(
        `<A HREF='single.html'>x</A><a href=bare.html>x</a>` +
        `<a href="a.html?x=1&amp;y=2#f&amp;g">x</a><a href=" spaced.html ">x</a>`,
    )
    expect_links(t, page, {"single.html", "bare.html", "a.html?x=1&y=2#f&g", " spaced.html "})
}

@(test)
test_empty_and_valueless_attributes_are_not_links_or_ids :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)

    page := parse_page(`<a href>x</a><a href="">x</a><a id="">x</a><p id>x</p><a name="y">x</a>`)
    expect_links(t, page, {})
    testing.expect_value(t, len(page.ids), 0)
}

@(test)
test_script_style_and_comments_hide_their_contents :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)

    page := parse_page(
        `<script>var s = '<a href="in-script.html" id="in-script">';</script>` +
        `<style>a::after { content: "<a href='in-style.html'>" }</style>` +
        `<!-- <a href="in-comment.html" id="in-comment"> -->` +
        `<SCRIPT>x = "</scrip" + "t>";</SCRIPT><a href="real.html" id="real">x</a>`,
    )
    expect_links(t, page, {"real.html"})
    testing.expect_value(t, len(page.ids), 1)
    testing.expect(t, "real" in page.ids)
}

@(test)
test_doctype_cdata_and_processing_instructions_are_skipped :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)

    page := parse_page(
        `<!DOCTYPE html><?xml version="1.0"?><![CDATA[ <a href="no.html"> ]]>` +
        `<a href="yes.html">x</a>`,
    )
    expect_links(t, page, {"yes.html"})
}

@(test)
test_chapter_numbers_come_from_the_start_of_each_h2 :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)

    page := parse_page(
        `<h2 id="a">5. The contract<a class="headerlink" href="#a">&para;</a></h2>` +
        `<h2>13a. Text processing</h2>` +
        `<h2>17a. Worker activity</h2>` +
        `<h2>  <span>7.</span> Nested</h2>` +
        `<h2>Contents</h2>` +
        `<h2>12 no dot</h2>` +
        `<h2>5.5 section</h2>` +
        `<h2>&#49;&#48;. Entities</h2>` +
        `<h2>13b. Unsupported suffix must stay visible to the exact-set check</h2>` +
        `<h3>9. a level-3 heading</h3>` +
        `</h2><p>9. outside</p>`,
    )
    want := []string{"5", "13a", "17a", "7", "5", "10", "13b"}
    testing.expect_value(t, len(page.chapters), len(want))
    for item, index in want {
        if index < len(page.chapters) {
            testing.expect_value(t, page.chapters[index], item)
        }
    }
}

@(test)
test_a_new_h2_discards_an_unclosed_one :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)

    page := parse_page(`<h2>1. never closed<h2>2. second</h2>`)
    testing.expect_value(t, len(page.chapters), 1)
    testing.expect_value(t, page.chapters[0], "2")
}

@(test)
test_a_literal_less_than_is_text_not_a_tag :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)

    page := parse_page(`<h2>3. a < b and 1<2</h2><a href="x.html">x</a>`)
    testing.expect_value(t, len(page.chapters), 1)
    expect_links(t, page, {"x.html"})
}

@(test)
test_truncated_input_ends_cleanly :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)

    inputs := []string {
        ``,
        `<`,
        `<a`,
        `<a href=`,
        `<a href="unterminated`,
        `<a href="x.html"`,
        `<!--`,
        `<!-- never closed <a href="x.html">`,
        `<script>never closed <a href="x.html">`,
        `</`,
        `<h2>1. text`,
    }
    for input in inputs {
        page := parse_page(input)
        // An unfinished tag, comment or script is text, so it yields no link. Python's
        // HTMLParser does the same; a scanner that hangs here would hang the run.
        testing.expectf(t, len(page.links) == 0, "%q found links %v", input, page.links)
        testing.expectf(t, len(page.ids) == 0, "%q found ids", input)
    }
}
