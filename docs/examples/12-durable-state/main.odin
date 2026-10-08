package main

import "core:os"

// A tiny runnable tour. State lives in a fresh temporary directory that is
// removed when the program ends.
main :: proc() {
    root, root_err := os.make_directory_temp("", "odin-durable-state-demo-*", context.allocator)
    if root_err != nil { return }
    defer delete(root)
    defer _ = os.remove_all(root)
    if create(root, "task") == (Error{}) {
        _ = transition(root, "task", "running")
    }
}
