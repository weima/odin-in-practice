// Companion to pointers.html; original teaching example for the pinned Odin edition.
package main

import "core:fmt"

increment :: proc(target: ^int) -> bool {
    if target == nil { return false }
    target^ += 1
    return true
}

retarget :: proc(slot: ^^int, target: ^int) {
    slot^ = target
}

main :: proc() {
    count := 41
    copy := count
    p := &count
    q := p
    assert(increment(p))
    assert(count == 42 && q^ == 42 && copy == 41)

    other := 99
    p = &other
    assert(p^ == 99 && q^ == 42)
    retarget(&p, &count)
    assert(p == q)
    assert(!increment(nil))
    fmt.println("value copies, aliases, retargeting, and nil: checked")
}
