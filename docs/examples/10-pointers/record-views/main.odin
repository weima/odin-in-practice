// Companion to pointers.html; original teaching example for the pinned Odin edition.
package main

import "core:fmt"

Record :: struct {
    count: int,
    values: []int,
    selected: ^int,
}

main :: proc() {
    backing := [3]int{10, 20, 30}
    a := Record{count = 3, values = backing[:], selected = &backing[1]}
    b := a
    b.count = 99
    b.values[0] = 7
    b.selected^ = 8
    assert(a.count == 3 && b.count == 99)
    assert(a.values[0] == 7 && backing[1] == 8)

    b.values = b.values[:1]
    assert(len(a.values) == 3 && len(b.values) == 1)
    fmt.println("separate headers, shared targets: checked")
}
