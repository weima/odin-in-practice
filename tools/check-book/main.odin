package main

import "core:flags"
import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:strings"

EXIT_OK :: 0
EXIT_FINDINGS :: 1
EXIT_ERROR :: 2

// Python's version showed only this many; the rest are counted, not lost.
MAX_ERRORS_SHOWN :: 50

USAGE :: `check-book: validate the generated reader without fetching external links.

Usage:
  check-book [--root DIR] [--all]

Reads DIR/html (default DIR is the current directory), DIR/mkdocs.yml,
DIR/tools/legacy-anchors.json and the SVGs under DIR/docs/assets.

Exit status: 0 the book passes, 1 problems were found, 2 the check could not run.
`

Arguments :: struct {
    root: string `usage:"The book's repository root (default: the current directory)."`,
    all:  bool `usage:"Show every problem, not only the first 50."`,
}

main :: proc() {
    // The whole run shares one arena: nothing is freed one piece at a time.
    arena: virtual.Arena
    if virtual.arena_init_growing(&arena) != nil {
        fmt.eprintln("check-book: out of memory")
        os.exit(EXIT_ERROR)
    }
    context.allocator = virtual.arena_allocator(&arena)
    os.exit(run(os.args[1:]))
}

run :: proc(args: []string) -> int {
    for argument in args {
        if argument == "--help" || argument == "-h" {
            fmt.print(USAGE)
            return EXIT_OK
        }
    }

    options := Arguments {
        root = ".",
    }
    if flags.parse(&options, args, .Unix) != nil {
        fmt.eprint(USAGE)
        return EXIT_ERROR
    }

    config_path := fmt.aprintf("%s/mkdocs.yml", options.root)
    config, read_err := os.read_entire_file(config_path, context.allocator)
    if read_err != nil {
        fmt.eprintfln("check-book: cannot read %s: %v", config_path, read_err)
        return EXIT_ERROR
    }
    prefix, found := site_prefix(string(config))
    if !found {
        fmt.eprintfln("check-book: %s has no top-level site_url", config_path)
        return EXIT_ERROR
    }

    report := check_site(options.root, prefix)
    if len(report.errors) > 0 {
        shown := len(report.errors) if options.all else min(len(report.errors), MAX_ERRORS_SHOWN)
        for message in report.errors[:shown] {
            fmt.eprintln(message)
        }
        if len(report.errors) > shown {
            fmt.eprintfln("... and %d more", len(report.errors) - shown)
        }
        return EXIT_FINDINGS
    }
    fmt.printfln(
        "%d HTML pages: local links/assets/anchors pass; chapters 1–31 plus 13a and SVG XML pass",
        report.pages,
    )
    return EXIT_OK
}

// site_prefix returns the path part of mkdocs.yml's top-level site_url, for example
// "/odin-in-practice/" for https://weima.github.io/odin-in-practice/. It reads the one
// line it needs instead of parsing YAML. A nested key of the same name does not count.
site_prefix :: proc(config: string) -> (prefix: string, found: bool) {
    KEY :: "site_url:"
    rest := config
    for line in strings.split_lines_iterator(&rest) {
        if !strings.has_prefix(line, KEY) {
            continue
        }
        value := line[len(KEY):]
        if comment := strings.index(value, " #"); comment >= 0 {
            value = value[:comment]
        }
        value = strings.trim_space(value)
        value = strings.trim(value, "\"'")
        if value == "" {
            return "", false
        }
        return split_link(value).path, true
    }
    return "", false
}
