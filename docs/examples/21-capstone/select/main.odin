package main
import "core:fmt"
import "core:os"
import "core:strconv"
import records "../records"

run :: proc() -> int {
    if len(os.args) != 2 { fmt.eprintln("usage: select MIN_BYTES"); return 2 }
    minimum, minimum_ok := strconv.parse_int(os.args[1])
    if !minimum_ok || minimum < 0 || minimum > records.MAX_FILE_BYTES { return 2 }
    reader: records.Reader
    count := 0
    for {
        line, present, read_err := records.next(&reader)
        if read_err != .None { fmt.eprintln("select framing:", read_err); return 1 }
        if !present { return 0 }
        count += 1
        if count > records.MAX_RECORDS { fmt.eprintln("select record budget"); return 1 }
        bytes, schema_err := records.parse_size(line)
        if schema_err != .None { fmt.eprintln("select schema:", schema_err); return 3 }
        if bytes < i64(minimum) { continue }
        if records.write_stdout(line) != .None || records.write_stdout([]u8{'\n'}) != .None { return 1 }
    }
}
main :: proc() { status := run(); os.exit(status) }
