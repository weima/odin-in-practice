package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_replace_exact_replaces_when_the_count_matches :: proc(t: ^testing.T) {
    result, err := replace_exact("one two one", "one", "1", 2)
    defer delete(result.text)
    testing.expect_value(t, err, Edit_Error.None)
    testing.expect_value(t, result.found, 2)
    testing.expect_value(t, result.text, "1 two 1")
}

@(test)
test_replace_exact_refuses_when_the_count_differs :: proc(t: ^testing.T) {
    result, err := replace_exact("one two one", "one", "1", 1)
    defer delete(result.text)
    testing.expect_value(t, err, Edit_Error.Count_Mismatch)
    // It still reports how many it found, so the caller can say why it refused.
    testing.expect_value(t, result.found, 2)
    testing.expect_value(t, result.text, "")
}

@(test)
test_replace_exact_edge_cases :: proc(t: ^testing.T) {
    // Expecting zero and finding zero is a valid no-op; the result is still owned.
    none, none_err := replace_exact("abc", "x", "y", 0)
    defer delete(none.text)
    testing.expect_value(t, none_err, Edit_Error.None)
    testing.expect_value(t, none.text, "abc")

    // An empty needle would match everywhere, so it is refused.
    _, empty_err := replace_exact("abc", "", "y", 1)
    testing.expect_value(t, empty_err, Edit_Error.Empty_Old_Text)

    // Matches do not overlap: "aa" occurs once in "aaa".
    overlap, overlap_err := replace_exact("aaa", "aa", "b", 1)
    defer delete(overlap.text)
    testing.expect_value(t, overlap_err, Edit_Error.None)
    testing.expect_value(t, overlap.text, "ba")

    // Multi-line text is just text.
    lines, lines_err := replace_exact("a\nb\nc\n", "b\nc", "X", 1)
    defer delete(lines.text)
    testing.expect_value(t, lines_err, Edit_Error.None)
    testing.expect_value(t, lines.text, "a\nX\n")
}

// Each test works in its own fresh temporary directory.
temp_root :: proc(t: ^testing.T, name: string) -> string {
    pattern := fmt.tprintf("odin-textproc-%s-*", name)
    root, err := os.make_directory_temp("", pattern, context.allocator)
    testing.expect_value(t, err, nil)
    return root
}

write_text :: proc(path, content: string, mode := os.Permissions{.Read_User, .Write_User}) {
    _ = os.write_entire_file(path, content, mode)
}

read_text :: proc(path: string) -> string {
    data, _ := os.read_entire_file(path, context.temp_allocator)
    return string(data)
}

@(test)
test_replace_in_file_edits_atomically_and_keeps_the_mode :: proc(t: ^testing.T) {
    root := temp_root(t, "edit")
    defer delete(root)
    defer os.remove_all(root)
    path := fmt.tprintf("%s/script.sh", root)
    write_text(path, "echo old\n", os.Permissions{.Read_User, .Write_User, .Execute_User})

    report, err := replace_in_file(path, "old", "new", 1, false)
    testing.expect_value(t, err, Edit_Error.None)
    testing.expect_value(t, report.found, 1)
    testing.expect(t, report.changed)
    testing.expect_value(t, read_text(path), "echo new\n")
    // No temporary file is left behind, and an executable file stays executable.
    testing.expect(t, !os.exists(fmt.tprintf("%s.tmp", path)))
    info, _ := os.stat(path, context.temp_allocator)
    testing.expect(t, .Execute_User in info.mode)
}

@(test)
test_dry_run_and_refused_edits_leave_the_file_untouched :: proc(t: ^testing.T) {
    root := temp_root(t, "refuse")
    defer delete(root)
    defer os.remove_all(root)
    path := fmt.tprintf("%s/a.txt", root)
    write_text(path, "x x\n")

    dry, dry_err := replace_in_file(path, "x", "y", 2, true)
    testing.expect_value(t, dry_err, Edit_Error.None)
    testing.expect(t, dry.changed, "a dry run reports the change it would make")
    testing.expect_value(t, read_text(path), "x x\n")

    wrong, wrong_err := replace_in_file(path, "x", "y", 1, false)
    testing.expect_value(t, wrong_err, Edit_Error.Count_Mismatch)
    testing.expect_value(t, wrong.found, 2)
    testing.expect_value(t, read_text(path), "x x\n")
}

@(test)
test_replace_in_file_refuses_binary_oversized_and_missing_files :: proc(t: ^testing.T) {
    root := temp_root(t, "refuse-kinds")
    defer delete(root)
    defer os.remove_all(root)

    binary := fmt.tprintf("%s/bin", root)
    write_text(binary, "ab\x00cd")
    _, binary_err := replace_in_file(binary, "ab", "x", 1, false)
    testing.expect_value(t, binary_err, Edit_Error.Binary_File)

    big := fmt.tprintf("%s/big", root)
    write_text(big, "0123456789")
    _, big_err := replace_in_file(big, "0", "x", 1, false, max_bytes = 5)
    testing.expect_value(t, big_err, Edit_Error.Too_Large)

    _, missing_err := replace_in_file(fmt.tprintf("%s/nope", root), "a", "b", 1, false)
    testing.expect_value(t, missing_err, Edit_Error.Read_Failed)
}

@(test)
test_a_failed_atomic_write_removes_its_temporary_and_keeps_the_target :: proc(t: ^testing.T) {
    root := temp_root(t, "atomic")
    defer delete(root)
    defer os.remove_all(root)
    // A non-empty directory cannot be replaced by a file, so the rename fails
    // after the temporary was written completely.
    target := fmt.tprintf("%s/target", root)
    _ = os.make_directory_all(fmt.tprintf("%s/keep", target))

    err := write_file_atomic(target, []byte{'n', 'e', 'w'}, os.Permissions{.Read_User, .Write_User})
    testing.expect_value(t, err, Edit_Error.Write_Failed)
    testing.expect(t, !os.exists(fmt.tprintf("%s.tmp", target)), "the temporary must be removed")
    testing.expect(t, os.is_dir(target), "the existing target must be untouched")
}

@(test)
test_grep_streams_lines_with_numbers_and_survives_long_lines :: proc(t: ^testing.T) {
    root := temp_root(t, "grep")
    defer delete(root)
    defer os.remove_all(root)
    path := fmt.tprintf("%s/log.txt", root)
    long := strings.repeat("z", 100, context.temp_allocator)
    write_text(path, fmt.tprintf("a 1\n%s 2\nb 33\nlast 4", long))

    // A 16-byte line limit: the 100-byte line is skipped, not buffered.
    result, err := grep_file(path, `\d+`, max_line_bytes = 16)
    defer destroy_grep_result(&result)
    testing.expect_value(t, err, Grep_Error.None)
    testing.expect_value(t, result.skipped_long_lines, 1)
    testing.expect_value(t, len(result.matches), 3)
    if len(result.matches) == 3 {
        testing.expect_value(t, result.matches[0], Match{line = 1, text = "a 1"})
        testing.expect_value(t, result.matches[1].line, 3)
        // The last line has no trailing newline and is still found.
        testing.expect_value(t, result.matches[2], Match{line = 4, text = "last 4"})
    }
}

@(test)
test_grep_caps_matches_and_rejects_a_bad_pattern :: proc(t: ^testing.T) {
    root := temp_root(t, "grep-cap")
    defer delete(root)
    defer os.remove_all(root)
    path := fmt.tprintf("%s/many.txt", root)
    write_text(path, "x\nx\nx\nx\n")

    capped, capped_err := grep_file(path, "x", max_matches = 2)
    defer destroy_grep_result(&capped)
    testing.expect_value(t, capped_err, Grep_Error.None)
    testing.expect_value(t, len(capped.matches), 2)
    testing.expect(t, capped.truncated, "hitting the cap must be reported")

    _, bad_err := grep_file(path, "(unclosed")
    testing.expect_value(t, bad_err, Grep_Error.Bad_Pattern)
}
