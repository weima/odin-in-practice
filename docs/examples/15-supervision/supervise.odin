#+build linux
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

Process_Identity :: struct {
    pid: int,
    start_time: u64,
}

Cancel_Result :: enum {
    Cancelled,
    Interrupted,
    Already_Gone,
}

current_identity :: proc() -> Process_Identity {
    pid := os.get_pid()
    start_time, _, ok := read_proc_stat(int(pid))
    assert(ok)
    return {int(pid), start_time}
}

identity_alive :: proc(identity: Process_Identity) -> bool {
    start_time, state, ok := read_proc_stat(identity.pid)
    return ok && state != 'Z' && start_time == identity.start_time
}

// Parses Linux /proc/<pid>/stat. The comm field ends at the last ')'.
parse_proc_stat :: proc(text: string) -> (start_time: u64, state: u8, ok: bool) {
    close_paren := strings.last_index_byte(text, ')')
    if close_paren < 0 { return }
    fields := strings.fields(text[close_paren+1:], context.temp_allocator)
    if len(fields) < 20 || len(fields[0]) != 1 { return }
    parsed_time, parsed := strconv.parse_u64(fields[19])
    return parsed_time, fields[0][0], parsed
}

read_proc_stat :: proc(pid: int) -> (start_time: u64, state: u8, ok: bool) {
    data, err := os.read_entire_file(fmt.tprintf("/proc/%d/stat", pid), context.temp_allocator)
    if err != nil { return }
    return parse_proc_stat(string(data))
}

// The caller owns process and must eventually wait it, including after timeout.
cancel :: proc(process: os.Process, identity: Process_Identity, deadline: time.Duration) -> Cancel_Result {
    if !identity_alive(identity) {
        _, _ = os.process_wait(process, timeout=0)
        return .Already_Gone
    }
    if os.process_terminate(process) != nil {
        if !identity_alive(identity) {
            _, _ = os.process_wait(process, timeout=0)
            return .Already_Gone
        }
        return .Interrupted
    }
    state, err := os.process_wait(process, timeout=deadline)
    if err == nil && state.exited { return .Cancelled }
    return .Interrupted
}
