package main

import "core:os"
import "core:strings"
import "core:testing"

// Every test gets its own fresh temporary directory, so tests never collide with
// each other, with a second run, or with another user.
root_for_test :: proc(name: string) -> string {
    pattern, _ := strings.concatenate({"odin-durable-state-", name, "-*"})
    defer delete(pattern)
    path, _ := os.make_directory_temp("", pattern, context.allocator)
    return path
}
reset :: proc(root: string) { _ = os.remove_all(root); _ = os.make_directory_all(root) }

@(test)
test_round_trip_replays_log :: proc(t: ^testing.T) {
    root := root_for_test("round-trip"); reset(root); defer delete(root); defer _ = os.remove_all(root)
    testing.expect_value(t, create(root, "one").kind, Error_Kind.None)
    testing.expect_value(t, transition(root, "one", "running").kind, Error_Kind.None)
    snapshot, err := load(root); defer destroy_snapshot(&snapshot)
    testing.expect_value(t, err.kind, Error_Kind.None)
    testing.expect_value(t, snapshot.sequence, 1)
    testing.expect_value(t, snapshot.items[0].status, "running")
}

@(test)
test_invalid_transition_changes_nothing :: proc(t: ^testing.T) {
    root := root_for_test("invalid"); reset(root); defer delete(root); defer _ = os.remove_all(root)
    _ = create(root, "one")
    err := transition(root, "one", "done")
    testing.expect_value(t, err.kind, Error_Kind.Invalid_Transition)
    snapshot, load_err := load(root); defer destroy_snapshot(&snapshot)
    testing.expect_value(t, load_err.kind, Error_Kind.None)
    testing.expect_value(t, snapshot.sequence, 0)
    testing.expect_value(t, snapshot.items[0].status, "queued")
}

@(test)
test_partial_last_line_reports_its_line :: proc(t: ^testing.T) {
    root := root_for_test("partial"); reset(root); defer delete(root); defer _ = os.remove_all(root)
    _ = create(root, "one")
    path := log_path(root); defer delete(path)
    _ = os.write_entire_file(path, "{}\npartial")
    _, err := load(root)
    testing.expect_value(t, err.kind, Error_Kind.Partial_Line)
    testing.expect_value(t, err.line, 2)
}

@(test)
test_snapshot_log_disagreement_is_conflict :: proc(t: ^testing.T) {
    root := root_for_test("conflict"); reset(root); defer delete(root); defer _ = os.remove_all(root)
    _ = create(root, "one")
    snapshot := Snapshot{sequence = 1, items = make([dynamic]Item, 1)}
    defer delete(snapshot.items)
    snapshot.items[0] = Item{"one", "running"}
    _ = write_snapshot(root, snapshot)
    _, err := load(root)
    testing.expect_value(t, err.kind, Error_Kind.Conflict)
}

@(test)
test_failed_atomic_temp_open_keeps_old_file :: proc(t: ^testing.T) {
    root := root_for_test("atomic"); reset(root); defer delete(root); defer _ = os.remove_all(root)
    target, _ := strings.concatenate({root, "/state"}); defer delete(target); temp, _ := strings.concatenate({target, ".tmp"}); defer delete(temp)
    _ = os.write_entire_file(target, "old")
    _ = os.make_directory_all(temp)
    err := atomic_write(target, []byte{'n', 'e', 'w'})
    testing.expect_value(t, err.kind, Error_Kind.IO)
    data, read_err := os.read_entire_file_from_path(target, context.allocator); defer delete(data)
    testing.expect_value(t, read_err, os.Error(nil))
    testing.expect_value(t, transmute(string)data, "old")
}

@(test)
test_existing_directory_is_success :: proc(t: ^testing.T) {
    root := root_for_test("mkdir"); defer delete(root); defer _ = os.remove_all(root)
    target, _ := strings.concatenate({root, "/new/nested"}); defer delete(target)
    testing.expect_value(t, ensure_directory(target), true) // creates both levels
    testing.expect_value(t, ensure_directory(target), true) // already there: still success
}

@(test)
test_failed_rename_leaves_no_temporary_file :: proc(t: ^testing.T) {
    root := root_for_test("rename"); defer delete(root); defer _ = os.remove_all(root)
    // A non-empty directory cannot be replaced by a file, so the rename fails
    // after the temporary has been written completely.
    target, _ := strings.concatenate({root, "/state"}); defer delete(target)
    inner, _ := strings.concatenate({target, "/keep"}); defer delete(inner)
    temp, _ := strings.concatenate({target, ".tmp"}); defer delete(temp)
    _ = os.make_directory_all(target)
    _ = os.write_entire_file(inner, "x")

    err := atomic_write(target, []byte{'n', 'e', 'w'})
    testing.expect_value(t, err.kind, Error_Kind.IO)
    testing.expect(t, !os.exists(temp), "the temporary file must be removed after a failed rename")
    testing.expect(t, os.exists(inner), "the existing target must be untouched")
}
