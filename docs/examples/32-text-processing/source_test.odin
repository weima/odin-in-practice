package main

import "core:strings"
import "core:testing"

@(test)
test_mask_hides_strings_and_comments_but_keeps_layout :: proc(t: ^testing.T) {
    source := "x := \"a; b\" // c; d\ny := 1;\n"
    masked := mask_source(source)
    defer delete(masked)

    testing.expect_value(t, len(masked), len(source))
    testing.expect_value(t, masked, "x := \"    \" //     \ny := 1;\n")
}

@(test)
test_mask_handles_raw_strings_nested_comments_escapes_and_chars :: proc(t: ^testing.T) {
    // A raw string spans lines; the newline inside it must survive.
    raw := mask_source("a := `p;\nq;`\n")
    defer delete(raw)
    testing.expect_value(t, raw, "a := `  \n  `\n")

    // Odin block comments nest.
    nested := mask_source("/* a /* b; */ c; */ d;")
    defer delete(nested)
    testing.expect_value(t, strings.contains(nested, ";"), true)
    testing.expect_value(t, nested[len(nested) - 2:], "d;")
    testing.expect_value(t, strings.count(nested, ";"), 1)

    // An escaped quote does not end the string.
    escaped := mask_source("s := \"say \\\"x;y\\\"\"; t := 1")
    defer delete(escaped)
    testing.expect_value(t, strings.count(escaped, ";"), 1)

    // A character literal holding a semicolon is not a separator.
    char := mask_source("c := ';'; d := 2")
    defer delete(char)
    testing.expect_value(t, strings.count(char, ";"), 1)
}

@(test)
test_check_reports_nothing_for_clean_source :: proc(t: ^testing.T) {
    findings := check_source("package main\n\nmain :: proc() {\n    x := 1\n}\n", 100)
    defer delete(findings)
    testing.expect_value(t, len(findings), 0)
}

@(test)
test_check_reports_each_kind_with_line_and_column :: proc(t: ^testing.T) {
    source := "a := 1\n\tb := 2\r\nc := 3  \nlong_line_here := 4\nd := 1; e := 2\n"
    findings := check_source(source, 15)
    defer delete(findings)

    want := []Finding {
        {line = 2, column = 1, kind = .Tab},
        {line = 2, column = 8, kind = .Carriage_Return},
        {line = 3, column = 7, kind = .Trailing_Whitespace},
        {line = 4, column = 16, kind = .Long_Line},
        {line = 5, column = 7, kind = .Statement_Chain},
    }
    testing.expect_value(t, len(findings), len(want))
    for index in 0 ..< min(len(findings), len(want)) {
        testing.expect_value(t, findings[index], want[index])
    }
}

@(test)
test_check_does_not_flag_semicolons_that_are_not_separators :: proc(t: ^testing.T) {
    clean := []string {
        "for i := 0; i < 3; i += 1 {\n}\n",
        "if x := f(); x > 0 {\n}\n",
        "s := \"a; b\"\n",
        "// a; b\n",
        "r := `a;\nb;`\n",
        "x := 1;\n", // a trailing separator with nothing after it
    }
    for source in clean {
        findings := check_source(source, 100)
        testing.expect_value(t, len(findings), 0)
        delete(findings)
    }
}

@(test)
test_check_flags_a_chain_inside_a_block :: proc(t: ^testing.T) {
    findings := check_source("if ok { a = 1; b = 2 }\n", 100)
    defer delete(findings)
    testing.expect_value(t, len(findings), 1)
    if len(findings) == 1 {
        testing.expect_value(t, findings[0].kind, Finding_Kind.Statement_Chain)
    }
}

Split_Case :: struct {
    name:   string,
    input:  string,
    output: string,
}

SPLIT_CASES :: []Split_Case {
    {"two statements", "a := 1; b := 2\n", "a := 1\nb := 2\n"},
    {"keeps the indent", "    a := 1; b := 2\n", "    a := 1\n    b := 2\n"},
    {"for header", "for i := 0; i < 3; i += 1 {\n}\n", "for i := 0; i < 3; i += 1 {\n}\n"},
    {"if header", "if x := f(); x > 0 {\n}\n", "if x := f(); x > 0 {\n}\n"},
    {"one-statement block", "if err != nil { return err }\n", "if err != nil { return err }\n"},
    {"string with semicolon", "s := \"a; b\"\n", "s := \"a; b\"\n"},
    {"comment with semicolon", "x := 1 // a; b\n", "x := 1 // a; b\n"},
    {
        "block of two",
        "    if found && state == 'Z' { zombie = true; break }\n",
        "    if found && state == 'Z' {\n        zombie = true\n        break\n    }\n",
    },
    {
        "one-line procedure",
        "f :: proc(r: string) -> string { p, _ := g(r); return p }\n",
        "f :: proc(r: string) -> string {\n    p, _ := g(r)\n    return p\n}\n",
    },
    {
        "nested blocks",
        "if a { if b { x = 1; y = 2 } }\n",
        "if a {\n    if b {\n        x = 1\n        y = 2\n    }\n}\n",
    },
}

@(test)
test_split_puts_each_statement_on_its_own_line :: proc(t: ^testing.T) {
    for item in SPLIT_CASES {
        got := split_statements(item.input)
        testing.expectf(t, got == item.output, "%s: got %q, want %q", item.name, got, item.output)
        delete(got)
    }
}

@(test)
test_split_is_idempotent_and_leaves_no_chain_behind :: proc(t: ^testing.T) {
    for item in SPLIT_CASES {
        once := split_statements(item.input)
        twice := split_statements(once)
        testing.expectf(t, once == twice, "%s: a second split changed the text", item.name)
        findings := check_source(once, 1000)
        chains := 0
        for finding in findings {
            if finding.kind == .Statement_Chain {
                chains += 1
            }
        }
        testing.expectf(t, chains == 0, "%s: %d chain(s) remain", item.name, chains)
        delete(findings)
        delete(twice)
        delete(once)
    }
}
