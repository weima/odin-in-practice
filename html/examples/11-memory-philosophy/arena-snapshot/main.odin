// Companion to memory-philosophy.html; original teaching example for the pinned Odin edition.
package main

import "core:fmt"
import "core:mem"
import "core:mem/virtual"

make_snapshot :: proc(scratch_allocator, result_allocator: mem.Allocator) ->
    (result: []int, err: mem.Allocator_Error) {
    context.allocator = scratch_allocator
    scratch := make([]int, 3) or_return
    scratch[0], scratch[1], scratch[2] = 10, 20, 30
    result = make([]int, len(scratch), result_allocator) or_return
    copy(result, scratch)
    return
}

run :: proc() -> mem.Allocator_Error {
    persistent := context.allocator
    arena: virtual.Arena
    virtual.arena_init_growing(&arena) or_return
    defer virtual.arena_destroy(&arena)

    result, err := make_snapshot(virtual.arena_allocator(&arena), persistent)
    defer delete(result, persistent)
    if err != nil { return err }
    virtual.arena_free_all(&arena)
    assert(result[0] == 10 && result[2] == 30)
    assert(context.allocator == persistent)
    fmt.println("result survived scratch reset because its elements were copied")
    return nil
}

main :: proc() {
    err := run()
    assert(err == nil, "allocation failed in arena example")
}
