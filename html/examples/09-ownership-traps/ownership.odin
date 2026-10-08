package main

import "base:runtime"
import "core:fmt"
import "core:strings"

// temp_format returns a borrowed string valid only until temporary storage is reset.
temp_format :: proc(value: string) -> string {
    return fmt.tprintf("value=%s", value)
}

// allocated_format returns a string owned by allocator; caller must delete it there.
allocated_format :: proc(value: string, allocator: runtime.Allocator) -> string {
    return fmt.aprintf("value=%s", value, allocator = allocator)
}

// buffer_format returns a view into buf; caller owns buf, not the returned string.
buffer_format :: proc(buf: []byte, value: string) -> string {
    return fmt.bprintf(buf, "value=%s", value)
}

// builder_format returns a view into builder storage; caller owns the builder.
builder_format :: proc(builder: ^strings.Builder, value: string) -> string {
    return fmt.sbprintf(builder, "value=%s", value)
}

Owner :: struct {
    value:     string,
    allocator: runtime.Allocator,
}

// owner_make clones borrowed into allocator. The caller owns the returned Owner.
owner_make :: proc(
    borrowed: string,
    allocator: runtime.Allocator,
) -> (
    Owner,
    runtime.Allocator_Error,
) {
    owned, err := strings.clone(borrowed, allocator)
    if err != nil {
        return {}, err
    }
    return Owner{owned, allocator}, nil
}

// owner_destroy releases the string allocated by owner_make.
owner_destroy :: proc(owner: ^Owner) {
    delete(owner.value, owner.allocator)
    owner^ = {}
}
