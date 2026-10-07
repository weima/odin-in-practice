// Companion to memory-philosophy.html; original teaching example for the pinned Odin edition.
package main

import "core:fmt"
import "core:mem"

reject_requests :: proc(data: rawptr, mode: mem.Allocator_Mode,
    size, alignment: int, old_memory: rawptr, old_size: int,
    location := #caller_location) -> ([]byte, mem.Allocator_Error) {
    #partial switch mode {
    case .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed:
        return nil, .Out_Of_Memory
    case .Free:
        return nil, nil // This allocator has issued no allocations.
    case:
        return nil, .Mode_Not_Implemented
    }
}

main :: proc() {
    rejecting := mem.Allocator{procedure = reject_requests}
    p, err := new(int, rejecting)
    assert(p == nil && err == .Out_Of_Memory)
    fmt.println("allocation failure is a result; no target was dereferenced")
}
