#+build linux
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

Process_Identity :: struct {
    pid:        int,
    start_time: u64,
}

Cancel_Result :: enum {
    Cancelled,
    Interrupted,
    Already_Gone,
}

// What reading /proc says about a saved identity. Only evidence of absence may
// say Gone; a read that failed or text that does not parse proves nothing.
Liveness :: enum {
    Alive,
    Gone,
    Unknown,
}

current_identity :: proc() -> (identity: Process_Identity, ok: bool) {
    pid := os.get_pid()
    start_time, _, found := read_proc_stat(int(pid))
    if !found {return {}, false}
    return {int(pid), start_time}, true
}

// Gone means a missing entry, a zombie, or a different start time (the PID now
// belongs to another process). Anything else that is not Alive is Unknown.
classify :: proc(identity: Process_Identity, data: []byte, read_err: os.Error) -> Liveness {
    if read_err == os.General_Error.Not_Exist {return .Gone}
    if read_err != nil {return .Unknown}
    start_time, state, ok := parse_proc_stat(string(data))
    if !ok {return .Unknown}
    if state == 'Z' || start_time != identity.start_time {return .Gone}
    return .Alive
}

identity_liveness :: proc(identity: Process_Identity) -> Liveness {
    data, err := os.read_entire_file(
        fmt.tprintf("/proc/%d/stat", identity.pid),
        context.temp_allocator,
    )
    return classify(identity, data, err)
}

identity_alive :: proc(identity: Process_Identity) -> bool {
    return identity_liveness(identity) == .Alive
}

// Parses Linux /proc/<pid>/stat. The comm field ends at the last ')'.
parse_proc_stat :: proc(text: string) -> (start_time: u64, state: u8, ok: bool) {
    close_paren := strings.last_index_byte(text, ')')
    if close_paren < 0 {return}
    fields := strings.fields(text[close_paren + 1:], context.temp_allocator)
    if len(fields) < 20 || len(fields[0]) != 1 {return}
    parsed_time, parsed := strconv.parse_u64(fields[19])
    return parsed_time, fields[0][0], parsed
}

read_proc_stat :: proc(pid: int) -> (start_time: u64, state: u8, ok: bool) {
    data, err := os.read_entire_file(fmt.tprintf("/proc/%d/stat", pid), context.temp_allocator)
    if err != nil {return}
    return parse_proc_stat(string(data))
}

// The caller owns process and must eventually wait it, including after timeout.
cancel :: proc(
    process: os.Process,
    identity: Process_Identity,
    deadline: time.Duration,
) -> Cancel_Result {
    switch identity_liveness(identity) {
    case .Gone:
        _, _ = os.process_wait(process, timeout = 0)
        return .Already_Gone
    case .Unknown:
        // Cannot tell whether it is running, so claim neither gone nor cancelled.
        return .Interrupted
    case .Alive:
    }
    if os.process_terminate(process) != nil {
        if identity_liveness(identity) == .Gone {
            _, _ = os.process_wait(process, timeout = 0)
            return .Already_Gone
        }
        return .Interrupted
    }
    state, err := os.process_wait(process, timeout = deadline)
    if err == nil && state.exited {return .Cancelled}
    return .Interrupted
}
