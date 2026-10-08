#+build linux
package main

import "core:os"
import "core:sys/posix"
import "core:testing"
import "core:time"

start :: proc(command: []string) -> (os.Process, Process_Identity, bool) {
    process, err := os.process_start(os.Process_Desc{command = command})
    if err != nil {return {}, {}, false}
    start_time, _, ok := read_proc_stat(process.pid)
    if !ok {
        // Do not leave a child running just because its identity cannot be read.
        _ = os.process_kill(process)
        _, _ = os.process_wait(process, timeout = 5 * time.Second)
        return {}, {}, false
    }
    return process, Process_Identity{pid = process.pid, start_time = start_time}, true
}

// Kill and reap a child. The wait is bounded and its outcome is checked, so a
// child that cannot be stopped fails this test instead of hanging the suite.
cleanup :: proc(t: ^testing.T, process: os.Process, identity: Process_Identity) {
    _, state, exists := read_proc_stat(identity.pid)
    if exists && (state == 'Z' || identity_alive(identity)) {
        if state !=
           'Z' {testing.expect(t, os.process_kill(process) == nil, "could not kill the child")}
        _, wait_err := os.process_wait(process, timeout = 5 * time.Second)
        testing.expect(t, wait_err == nil, "the child did not exit after SIGKILL")
    }
}

@(test)
current_process_identity_is_alive :: proc(t: ^testing.T) {
    identity, ok := current_identity()
    testing.expect(t, ok)
    testing.expect(t, identity_alive(identity))
    wrong := identity
    wrong.start_time += 1
    testing.expect(t, !identity_alive(wrong))
}

@(test)
command_name_with_close_paren_parses :: proc(t: ^testing.T) {
    start_time, state, ok := parse_proc_stat(
        "77 (name ) with (parens)) S 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 4242",
    )
    testing.expect(t, ok && state == 'S' && start_time == 4242)
}

@(test)
zombie_counts_as_gone :: proc(t: ^testing.T) {
    process, identity, ok := start([]string{"sh", "-c", "exit 0"})
    testing.expect(t, ok)
    if !ok {return}
    defer cleanup(t, process, identity)

    zombie := false
    for _ in 0 ..< 100 {
        _, state, found := read_proc_stat(identity.pid)
        if found && state == 'Z' {
            zombie = true
            break
        }
        time.sleep(1 * time.Millisecond)
    }
    testing.expect(t, zombie)
    testing.expect(t, !identity_alive(identity))
}

@(test)
cancel_reports_already_gone :: proc(t: ^testing.T) {
    process, identity, ok := start([]string{"sh", "-c", "exit 0"})
    testing.expect(t, ok)
    if !ok {return}
    defer cleanup(t, process, identity)
    for _ in 0 ..< 100 {
        _, state, found := read_proc_stat(identity.pid)
        if found && state == 'Z' {break}
        time.sleep(1 * time.Millisecond)
    }
    testing.expect(t, cancel(process, identity, time.Second) == .Already_Gone)
}

@(test)
cancel_confirms_cooperative_exit :: proc(t: ^testing.T) {
    process, identity, ok := start([]string{"sleep", "30"})
    testing.expect(t, ok)
    if !ok {return}
    defer cleanup(t, process, identity)
    testing.expect(t, cancel(process, identity, 2 * time.Second) == .Cancelled)
}

@(test)
cancel_reports_interrupted_for_ignoring_child :: proc(t: ^testing.T) {
    // setsid makes the child and its sleep grandchild one cleanable process group.
    process, identity, ok := start([]string{"setsid", "sh", "-c", "trap '' TERM; sleep 30"})
    testing.expect(t, ok)
    if !ok {return}
    defer {
        // Kill the whole group; a failure is reported, not ignored.
        testing.expect(
            t,
            posix.kill(-posix.pid_t(identity.pid), .SIGKILL) == .OK,
            "could not kill the process group",
        )
        cleanup(t, process, identity)
    }
    // Let the shell install its ignored-SIGTERM disposition before signaling.
    time.sleep(100 * time.Millisecond)
    testing.expect(t, cancel(process, identity, 30 * time.Millisecond) == .Interrupted)
}

@(test)
liveness_separates_gone_from_unknown :: proc(t: ^testing.T) {
    identity := Process_Identity {
        pid        = 77,
        start_time = 4242,
    }
    running := "77 (x) S 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 4242"
    zombie := "77 (x) Z 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 4242"
    reused := "77 (x) S 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 9999"
    garbage := "not a stat line"

    testing.expect_value(t, classify(identity, transmute([]byte)running, nil), Liveness.Alive)
    // Evidence the process is gone: a zombie, a reused PID, or no such entry.
    testing.expect_value(t, classify(identity, transmute([]byte)zombie, nil), Liveness.Gone)
    testing.expect_value(t, classify(identity, transmute([]byte)reused, nil), Liveness.Gone)
    testing.expect_value(t, classify(identity, nil, os.General_Error.Not_Exist), Liveness.Gone)
    // No evidence either way: any other read failure (Invalid_File stands in for
    // a platform error such as a permission problem) or text that does not parse.
    testing.expect_value(
        t,
        classify(identity, nil, os.General_Error.Invalid_File),
        Liveness.Unknown,
    )
    testing.expect_value(t, classify(identity, transmute([]byte)garbage, nil), Liveness.Unknown)
}
