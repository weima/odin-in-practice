package main

import "core:encoding/json"
import "core:encoding/xml"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

// What a check found. `pages` is how many generated HTML pages were read.
Report :: struct {
    pages:  int,
    errors: [dynamic]string,
}

NO_PAGES_MESSAGE :: "No generated HTML found; build the book first"

// Chapters 1-31 are stable identifiers; 13a and 17a were inserted later without renumbering.
expected_chapters :: proc() -> []string {
    chapters: [dynamic]string
    for number in 1 ..= 31 {
        append(&chapters, fmt.aprintf("%d", number))
    }
    append(&chapters, "13a")
    append(&chapters, "17a")
    return chapters[:]
}

// check_site validates the generated reader under `root` without fetching external
// links: every local link, asset and anchor resolves, the chapter headings are exactly
// the expected set, the legacy anchors still exist, and every SVG is well-formed XML.
//
// `site_prefix` is the path of the hosted site (from mkdocs.yml's site_url), which the
// hosted 404 page uses for its root-relative links. Everything allocated lives in
// context.allocator and is never freed: the program runs inside one arena.
check_site :: proc(root, site_prefix: string) -> Report {
    report: Report
    root_path, _ := filepath.abs(root)
    site, _ := filepath.join({root_path, "html"})

    files: [dynamic]string
    list_files(site, ".html", &files)
    slice.sort(files[:])

    pages: map[string]Page
    for file in files {
        data, err := os.read_entire_file(file, context.allocator)
        if err != nil {
            add_error(&report, "cannot read %s: %v", relative_to(site, file), err)
            continue
        }
        pages[file] = parse_page(string(data))
    }
    report.pages = len(pages)

    check_links(&report, site, site_prefix, files[:], pages)
    check_chapters(&report, site, files[:], pages)
    check_legacy_anchors(&report, root_path, site, pages)
    check_svgs(&report, root_path)

    if len(pages) == 0 {
        append(&report.errors, NO_PAGES_MESSAGE)
    }
    return report
}

check_links :: proc(
    report: ^Report,
    site, site_prefix: string,
    files: []string,
    pages: map[string]Page,
) {
    for file in files {
        page, found := pages[file]
        if !found {
            continue
        }
        name := relative_to(site, file)
        for link in page.links {
            parts := split_link(link)
            if parts.scheme != "" || parts.netloc != "" || strings.has_prefix(link, "//") {
                continue
            }
            path := unquote(parts.path)

            // MkDocs intentionally gives the hosted 404 page root-relative URLs.
            destination := file
            if filepath.base(file) == "404.html" && strings.has_prefix(path, site_prefix) {
                destination = resolve_link(site, path[len(site_prefix):])
            } else if path != "" {
                destination = resolve_link(filepath.dir(file), path)
            }
            if is_directory(destination) {
                destination, _ = filepath.join({destination, "index.html"})
            }

            switch {
            case !is_within(site, destination):
                add_error(report, "%s: outside reader: %s", name, link)
            case !os.exists(destination):
                add_error(report, "%s: missing: %s", name, link)
            case parts.fragment != "":
                target, is_page := pages[destination]
                if is_page && unquote(parts.fragment) not_in target.ids {
                    add_error(report, "%s: missing anchor: %s", name, link)
                }
            }
        }
    }
}

check_chapters :: proc(report: ^Report, site: string, files: []string, pages: map[string]Page) {
    chapters_dir, _ := filepath.join({site, "chapters"})
    found: [dynamic]string
    for file in files {
        if filepath.dir(file) == chapters_dir {
            page := pages[file]
            for number in page.chapters {
                append(&found, number)
            }
        }
    }
    slice.sort(found[:])

    expected := expected_chapters()
    slice.sort(expected)
    if !slice.equal(found[:], expected) {
        listing := strings.builder_make()
        strings.write_string(&listing, "[")
        for number, index in found {
            strings.write_string(&listing, ", " if index > 0 else "")
            fmt.sbprintf(&listing, "'%s'", number)
        }
        strings.write_string(&listing, "]")
        add_error(
            report,
            "chapter headings are not exactly 1–31 plus 13a and 17a: %s",
            strings.to_string(listing),
        )
    }
}

// Old links to a page and an anchor keep working only while that anchor exists.
check_legacy_anchors :: proc(report: ^Report, root_path, site: string, pages: map[string]Page) {
    path, _ := filepath.join({root_path, "tools", "legacy-anchors.json"})
    data, read_err := os.read_entire_file(path, context.allocator)
    if read_err != nil {
        add_error(report, "cannot read tools/legacy-anchors.json: %v", read_err)
        return
    }
    value, parse_err := json.parse(data)
    routes, is_object := value.(json.Object)
    if parse_err != nil || !is_object {
        add_error(report, "cannot read tools/legacy-anchors.json: not a JSON object")
        return
    }

    for route, wanted in routes {
        full, _ := filepath.join({site, route})
        page, found := pages[full]
        ids, is_array := wanted.(json.Array)
        ok := found && is_array
        if ok {
            for item in ids {
                id, is_string := item.(json.String)
                if !is_string || id not_in page.ids {
                    ok = false
                }
            }
        }
        if !ok {
            add_error(report, "legacy page or explicit anchor missing: %s", route)
        }
    }
}

// An SVG that is not well-formed XML breaks the page that embeds it, so parse each one.
check_svgs :: proc(report: ^Report, root_path: string) {
    assets, _ := filepath.join({root_path, "docs", "assets"})
    files: [dynamic]string
    list_files(assets, ".svg", &files)
    slice.sort(files[:])
    for file in files {
        document, err := xml.load_from_file(file)
        if err != .None {
            add_error(report, "invalid SVG XML: %s: %v", relative_to(root_path, file), err)
        }
        xml.destroy(document)
    }
}

// list_files collects the regular files under `directory` whose name ends in `suffix`.
// A directory that does not exist yields nothing, as a recursive glob would.
list_files :: proc(directory, suffix: string, files: ^[dynamic]string) {
    entries, err := os.read_all_directory_by_path(directory, context.temp_allocator)
    if err != nil {
        return
    }
    for entry in entries {
        full, _ := filepath.join({directory, entry.name})
        #partial switch entry.type {
        case .Directory:
            list_files(full, suffix, files)
        case .Regular:
            if strings.has_suffix(entry.name, suffix) {
                append(files, full)
            }
        }
    }
}

// is_directory classifies without opening the path, so an unreadable directory is still
// a directory (see the 13a chapter: os.is_dir opens its argument).
is_directory :: proc(path: string) -> bool {
    info, err := os.lstat(path, context.temp_allocator)
    return err == nil && info.type == .Directory
}

relative_to :: proc(base, path: string) -> string {
    if is_within(base, path) && len(path) > len(base) {
        return path[len(base) + 1:]
    }
    return path
}

add_error :: proc(report: ^Report, format: string, args: ..any) {
    append(&report.errors, fmt.aprintf(format, ..args))
}
