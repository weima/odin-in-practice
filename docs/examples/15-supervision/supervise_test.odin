#+build linux
package main

import "core:os"
import "core:sys/posix"
import "core:testing"
import "core:time"

start :: proc(command: []string) -> (os.Process, Process_Identity, bool) {
    process, err := os.process_start(os.Process_Desc{command = command})
    if err != nil { return {}, {}, false }
    return process, Process_Identity{pid = process.pid, start_time = process_start_time(process.pid)}, true
}

process_start_time :: proc(pid: int) -> u64 {
    start_time, _, ok := read_proc_stat(pid)
    assert(ok)
    return start_time
}

cleanup :: proc(process: os.Process, identity: Process_Identity) {
    _, state, exists := read_proc_stat(identity.pid)
    if exists && (state == 'Z' || identity_alive(identity)) {
        if state != 'Z' { _ = os.process_kill(process) }
        _, _ = os.process_wait(process)
    }
}

@(test)
current_process_identity_is_alive :: proc(t: ^testing.T) {
    identity := current_identity()
    testing.expect(t, identity_alive(identity))
    wrong := identity
    wrong.start_time += 1
    testing.expect(t, !identity_alive(wrong))
}

@(test)
command_name_with_close_paren_parses :: proc(t: ^testing.T) {
    start_time, state, ok := parse_proc_stat("77 (name ) with (parens)) S 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 4242")
    testing.expect(t, ok && state == 'S' && start_time == 4242)
}

@(test)
zombie_counts_as_gone :: proc(t: ^testing.T) {
    process, identity, ok := start([]string{"sh", "-c", "exit 0"})
    testing.expect(t, ok)
    if !ok { return }
    defer cleanup(process, identity)

    zombie := false
    for _ in 0..<100 {
        _, state, found := read_proc_stat(identity.pid)
        if found && state == 'Z' { zombie = true; break }
        time.sleep(1 * time.Millisecond)
    }
    testing.expect(t, zombie)
    testing.expect(t, !identity_alive(identity))
}

@(test)
cancel_reports_already_gone :: proc(t: ^testing.T) {
    process, identity, ok := start([]string{"sh", "-c", "exit 0"})
    testing.expect(t, ok)
    if !ok { return }
    defer cleanup(process, identity)
    for _ in 0..<100 {
        _, state, found := read_proc_stat(identity.pid)
        if found && state == 'Z' { break }
        time.sleep(1 * time.Millisecond)
    }
    testing.expect(t, cancel(process, identity, time.Second) == .Already_Gone)
}

@(test)
cancel_confirms_cooperative_exit :: proc(t: ^testing.T) {
    process, identity, ok := start([]string{"sleep", "30"})
    testing.expect(t, ok)
    if !ok { return }
    defer cleanup(process, identity)
    testing.expect(t, cancel(process, identity, 2*time.Second) == .Cancelled)
}

@(test)
cancel_reports_interrupted_for_ignoring_child :: proc(t: ^testing.T) {
    // setsid makes the child and its sleep grandchild one cleanable process group.
    process, identity, ok := start([]string{"setsid", "sh", "-c", "trap '' TERM; sleep 30"})
    testing.expect(t, ok)
    if !ok { return }
    defer {
        _ = posix.kill(-posix.pid_t(identity.pid), .SIGKILL)
        cleanup(process, identity)
    }
    // Let the shell install its ignored-SIGTERM disposition before signaling.
    time.sleep(100 * time.Millisecond)
    testing.expect(t, cancel(process, identity, 30*time.Millisecond) == .Interrupted)
}
