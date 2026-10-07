package main
import "core:fmt"
import "core:os"
import "core:unicode/utf8"
import records "../records"

scan_one :: proc(path: string) -> records.Error {
    if len(path) == 0 || len(path) > 4096 || !utf8.valid_string(path) { return .Schema }
    file, open_err := os.open(path)
    if open_err != nil { return .Read }
    defer os.close(file)
    total: i64
    buffer: [4096]u8
    for {
        n, read_err := os.read(file, buffer[:])
        if read_err != nil && read_err != .EOF { return .Read }
        if i64(n) > records.MAX_FILE_BYTES - total { return .Budget }
        total += i64(n)
        if read_err == .EOF || n == 0 { break }
    }
    return records.emit(records.Record{path=path, bytes=total})
}
run :: proc() -> int {
    if len(os.args) == 2 && os.args[1] == "--help" {
        fmt.println("usage: inspect -- FILE... (at most 64 UTF-8 paths; 1 MiB per file)")
        return 0
    }
    if len(os.args) < 3 || len(os.args) > 66 || os.args[1] != "--" { return 2 }
    for path in os.args[2:] {
        if err := scan_one(path); err != .None { fmt.eprintfln("inspect: %s path=%q", err, path); return 1 }
    }
    return 0
}
main :: proc() { status := run(); os.exit(status) }
