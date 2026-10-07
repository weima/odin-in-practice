// Linux + FFmpeg 6 companion. Build the narrow C bridge with ./build.sh first.
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

foreign import bridge {".build/bridge.a", "system:avformat", "system:avcodec", "system:avutil"}
Report :: struct { packets, frames, audio_samples: i64, streams: i32 }
#assert(size_of(Report) == 32)
foreign bridge {
    book_abi_ok :: proc() -> i32 ---
    book_error :: proc(status: i32, buffer: rawptr, length: u64) -> i32 ---
    book_decode :: proc(path: cstring, max_frames, milliseconds: i64, report: ^Report) -> i32 ---
    book_remux :: proc(path, destination: cstring, max_bytes, milliseconds: i64, report: ^Report) -> i32 ---
}

valid_c_input :: proc(value: string) -> bool {
    if len(value) == 0 || value[0] != '/' { return false }
    for byte in transmute([]u8)value { if byte == 0 { return false } }
    return true
}
run :: proc() -> int {
    if len(os.args) < 3 || len(os.args) > 4 {
        fmt.eprintln("usage: media decode ABSOLUTE_INPUT [MAX_FRAMES] | media remux ABSOLUTE_INPUT ABSOLUTE_NEW_STAGING_FILE")
        return 2
    }
    mode, path := os.args[1], os.args[2]
    if mode != "decode" && mode != "remux" || !valid_c_input(path) { return 2 }
    if book_abi_ok() == 0 { fmt.eprintln("FFmpeg header/runtime major version mismatch"); return 1 }
    input, allocation_err := strings.clone_to_cstring(path, context.allocator)
    if allocation_err != nil { return 1 }
    defer delete(input)
    report: Report
    result: i32
    if mode == "decode" {
        limit: i64 = 10000
        if len(os.args) == 4 {
            parsed, parsed_ok := strconv.parse_int(os.args[3])
            if !parsed_ok || parsed < 1 || parsed > 1000000 { return 2 }
            limit = i64(parsed)
        }
        result = book_decode(input, limit, 5000, &report)
    } else {
        if len(os.args) != 4 || !valid_c_input(os.args[3]) { return 2 }
        destination, err := strings.clone_to_cstring(os.args[3], context.allocator)
        if err != nil { return 1 }
        defer delete(destination)
        result = book_remux(input, destination, 16*1024*1024, 5000, &report)
    }
    if result < 0 {
        diagnostic: [256]u8
        _ = book_error(result, &diagnostic[0], u64(len(diagnostic)))
        end := 0
        for end < len(diagnostic) && diagnostic[end] != 0 { end += 1 }
        fmt.eprintfln("media failure: code=%d message=%s partial_packets=%d partial_frames=%d",
            result, string(diagnostic[:end]), report.packets, report.frames)
        return 1
    }
    fmt.printfln("packets=%d frames=%d audio_samples=%d streams=%d",
        report.packets, report.frames, report.audio_samples, report.streams)
    return 0
}
main :: proc() { status := run(); os.exit(status) }
