// Shared, bounded NDJSON framing/schema for the three pipeline stages.
package records

import "core:encoding/json"
import "core:os"
import "core:unicode/utf8"

MAX_LINE :: 65536
MAX_FILE_BYTES :: 1048576
MAX_RECORDS :: 100000
Error :: enum { None, Read, Write, Line_Too_Long, Schema, Budget }
Record :: struct { path: string, bytes: i64 }
Summary :: struct { files, bytes: i64 }
Reader :: struct {
    chunk: [4096]u8,
    cursor, available: int,
    line: [MAX_LINE]u8,
    eof: bool,
}

// Returned line borrows r.line and expires on the next call.
next :: proc(r: ^Reader) -> (line: []u8, present: bool, err: Error) {
    used := 0
    for {
        if r.cursor == r.available {
            if r.eof { return r.line[:used], used != 0, .None }
            n, read_err := os.read(os.stdin, r.chunk[:])
            if read_err != nil && read_err != .EOF { return nil, false, .Read }
            r.cursor, r.available = 0, n
            r.eof = read_err == .EOF || n == 0
            if n == 0 { return r.line[:used], used != 0, .None }
        }
        byte := r.chunk[r.cursor]
        r.cursor += 1
        if byte == '\n' { return r.line[:used], true, .None }
        if used == len(r.line) { return nil, false, .Line_Too_Long }
        r.line[used] = byte
        used += 1
    }
}

// Copy out only the integer. The parsed path is used before its owner is destroyed.
parse_size :: proc(line: []u8) -> (bytes: i64, err: Error) {
    value, parse_err := json.parse(string(line), spec=.JSON, parse_integers=true, allocator=context.allocator)
    defer json.destroy_value(value, context.allocator)
    if parse_err != nil { return 0, .Schema }
    object, is_object := value.(json.Object)
    if !is_object || len(object) != 2 { return 0, .Schema }
    path_value, has_path := object["path"]
    path, is_string := path_value.(json.String)
    size_value, has_size := object["bytes"]
    size, is_integer := size_value.(json.Integer)
    if !has_path || !is_string || len(path) == 0 || len(path) > 4096 || !utf8.valid_string(path) ||
        !has_size || !is_integer || size < 0 || size > MAX_FILE_BYTES { return 0, .Schema }
    for byte in transmute([]u8)path { if byte == 0 { return 0, .Schema } }
    return size, .None
}

write_stdout :: proc(data: []u8) -> Error {
    used := 0
    for used < len(data) {
        n, write_err := os.write(os.stdout, data[used:])
        if write_err != nil || n <= 0 { return .Write }
        used += n
    }
    return .None
}

emit :: proc(value: any) -> Error {
    encoded, marshal_err := json.marshal(value, {spec=.JSON}, context.allocator)
    defer delete(encoded)
    if marshal_err != nil { return .Schema }
    if len(encoded) > MAX_LINE { return .Line_Too_Long }
    if err := write_stdout(encoded); err != .None { return err }
    return write_stdout([]u8{'\n'})
}
