package main
import "core:fmt"
import "core:os"
import records "../records"

run :: proc() -> int {
    if len(os.args) != 1 { return 2 }
    reader: records.Reader
    summary: records.Summary
    for {
        line, present, read_err := records.next(&reader)
        if read_err != .None { fmt.eprintln("summary framing:", read_err); return 1 }
        if !present { break }
        if summary.files >= records.MAX_RECORDS { fmt.eprintln("summary record budget"); return 1 }
        bytes, schema_err := records.parse_size(line)
        if schema_err != .None { fmt.eprintln("summary schema:", schema_err); return 3 }
        if summary.bytes > max(i64) - bytes { return 1 }
        summary.files += 1
        summary.bytes += bytes
    }
    if records.emit(summary) != .None { return 1 }
    return 0
}
main :: proc() { status := run(); os.exit(status) }
