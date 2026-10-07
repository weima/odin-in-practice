// Companion to pointers.html; original teaching example for the pinned Odin edition.
package main

import "core:fmt"
import "core:mem"

Counter :: struct { value: int }

create_counter :: proc(allocator: mem.Allocator) ->
    (result: ^Counter, err: mem.Allocator_Error) {
    result = new(Counter, allocator) or_return
    result.value = 42
    return
}

run :: proc() -> mem.Allocator_Error {
    allocator := context.allocator
    owner, err := create_counter(allocator)
    if err != nil { return err }
    defer free(owner, allocator)
    borrowed := owner
    borrowed.value += 1
    assert(owner.value == 43)
    fmt.println("one allocation owner; borrowed access ends before free")
    return nil
}

main :: proc() {
    err := run()
    assert(err == nil, "allocation failed in pointer example")
}
