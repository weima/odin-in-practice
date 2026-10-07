// Companion to pointers.html; original teaching example for the pinned Odin edition.
package main

import "core:fmt"

main :: proc() {
    values := [3]int{10, 20, 30}
    p: [^]int = raw_data(values[:])
    assert(p[1] == 20) // We know this index is valid from values.
    view := p[:len(values)]
    view[2] = 99
    assert(values[2] == 99)
    fmt.println("multi-pointer plus trusted extent becomes a view")
}
