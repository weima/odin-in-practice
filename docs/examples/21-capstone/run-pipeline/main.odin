// Compose the three bounded, owned Odin commands without a shell.
// Run with an absolute trusted binary directory and 1..64 input paths.
package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:time"
import records "../records"

valid_summary :: proc(data: []u8) -> bool {
    value, err := json.parse(string(data), spec=.JSON, parse_integers=true)
    defer json.destroy_value(value, context.allocator)
    if err != nil { return false }
    object, is_object := value.(json.Object)
    if !is_object || len(object) != 2 { return false }
    files_value, has_files := object["files"]
    bytes_value, has_bytes := object["bytes"]
    files, files_integer := files_value.(json.Integer)
    bytes, bytes_integer := bytes_value.(json.Integer)
    return has_files && has_bytes && files_integer && bytes_integer && files >= 0 &&
        files <= records.MAX_RECORDS && bytes >= 0 && bytes <= files * records.MAX_FILE_BYTES
}

run :: proc() -> int {
    if len(os.args) < 4 || len(os.args) > 67 || len(os.args[1]) == 0 || os.args[1][0] != '/' {
        fmt.eprintln("usage: run-pipeline ABSOLUTE_TRUSTED_BINARY_DIRECTORY MIN_BYTES FILE...")
        return 2
    }
    minimum, minimum_ok := strconv.parse_int(os.args[2])
    if !minimum_ok || minimum < 0 || minimum > records.MAX_FILE_BYTES { return 2 }
    paths := [3]string{
        fmt.aprintf("%s/inspect", os.args[1]),
        fmt.aprintf("%s/select", os.args[1]),
        fmt.aprintf("%s/summarize", os.args[1]),
    }
    defer for path in paths { delete(path) }
    inspect_args: [dynamic]string
    defer delete(inspect_args)
    _, append_err := append(&inspect_args, paths[0], "--")
    if append_err != nil { return 1 }
    _, append_err = append(&inspect_args, ..os.args[3:])
    if append_err != nil { return 1 }

    endpoints: [6]^os.File
    defer for file in endpoints { if file != nil { os.close(file) } }
    for pair := 0; pair < 3; pair += 1 {
        reader, writer, pipe_err := os.pipe()
        if pipe_err != nil { fmt.eprintln("pipe:", pipe_err); return 1 }
        endpoints[pair*2], endpoints[pair*2+1] = reader, writer
    }
    descs := [3]os.Process_Desc{
        {command=inspect_args[:], stdout=endpoints[1], stderr=os.stderr},
        {command=[]string{paths[1], os.args[2]}, stdin=endpoints[0], stdout=endpoints[3], stderr=os.stderr},
        {command=[]string{paths[2]}, stdin=endpoints[2], stdout=endpoints[5], stderr=os.stderr},
    }
    processes: [3]os.Process
    active: [3]bool
    // These commands never spawn descendants. Killing an arbitrary process tree
    // is a different problem; do not copy this into a generic job supervisor.
    defer for index := 0; index < len(processes); index += 1 {
        if active[index] {
            _ = os.process_kill(processes[index])
            _, reap_err := os.process_wait(processes[index])
            if reap_err != nil { fmt.eprintln("cleanup wait:", reap_err) }
        }
    }
    started := time.tick_now()
    for index in ([3]int{2, 1, 0}) {
        process, start_err := os.process_start(descs[index])
        if start_err != nil { fmt.eprintfln("start stage=%d: %s", index, start_err); return 1 }
        processes[index], active[index] = process, true
    }
    // Parent must not retain intermediate read/write ends: a spare writer can
    // keep the downstream reader waiting for EOF forever. Only final read stays.
    for index in ([5]int{0, 1, 2, 3, 5}) {
        os.close(endpoints[index])
        endpoints[index] = nil
    }
    for index in ([3]int{2, 1, 0}) {
        remaining := max(time.Duration(0), 10*time.Second - time.tick_since(started))
        state, wait_err := os.process_wait(processes[index], timeout=remaining)
        if wait_err != nil { fmt.eprintfln("wait stage=%d: %s", index, wait_err); return 1 }
        active[index] = false // Successful wait has released this process handle.
        if !state.success || !state.exited || state.exit_code != 0 {
            fmt.eprintfln("failed stage=%d exit=%d", index, state.exit_code)
            return 1
        }
    }
    // This specific summarizer emits at most one tiny JSON record. It therefore
    // cannot fill a normal pipe before exit. Arbitrary outputs need concurrent
    // draining with a cap; waiting before reading is not a general pattern.
    buffer: [256]u8
    used := 0
    for {
        n, read_err := os.read(endpoints[4], buffer[used:])
        if read_err != nil && read_err != .EOF { return 1 }
        used += n
        if used == len(buffer) { fmt.eprintln("summary exceeds fixed output budget"); return 1 }
        if n == 0 || read_err == .EOF { break }
    }
    if !valid_summary(buffer[:used]) { fmt.eprintln("invalid final summary"); return 3 }
    if records.write_stdout(buffer[:used]) != .None { return 1 }
    return 0
}
main :: proc() { status := run(); os.exit(status) }
