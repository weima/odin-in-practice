package main

import "core:fmt"

// Named results are local result variables, initially zero-initialized.
divide_named :: proc(numerator, denominator: f64) -> (quotient: f64, ok: bool) {
    if denominator == 0 { return }
    quotient = numerator / denominator
    ok = true
    return
}

// Same observable results here, with explicit return expressions.
divide_explicit :: proc(numerator, denominator: f64) -> (f64, bool) {
    if denominator == 0 { return 0, false }
    return numerator / denominator, true
}

// Independent type parameters may resolve to different or identical types.
pair :: proc(a: $S, b: $T) -> (S, T) { return a, b }

// This proc has no results. Returning exits only this call; defer still runs.
write_if_requested :: proc(write: bool, value, cleanups: ^int) {
    defer cleanups^ += 1
    if !write { return }
    value^ = 7
}

main :: proc() {
    number, text := pair(i32(7), "hello")
    assert(number == i32(7) && text == "hello")
    left, right := pair(i32(7), i32(9))
    assert(left == i32(7) && right == i32(9))
    fmt.println("independent types:", number, text, "; identical types:", left, right)
    for input in ([3][2]f64{{8, 2}, {0, 2}, {2, 0}}) {
        quotient, ok := divide_named(input[0], input[1])
        explicit_quotient, explicit_ok := divide_explicit(input[0], input[1])
        assert(quotient == explicit_quotient && ok == explicit_ok)
        fmt.printfln("%g / %g -> quotient=%g ok=%v", input[0], input[1], quotient, ok)
    }
    value, cleanups := 0, 0
    write_if_requested(false, &value, &cleanups)
    assert(value == 0 && cleanups == 1)
    write_if_requested(true, &value, &cleanups)
    assert(value == 7 && cleanups == 2)
    fmt.println("no-result early return exits the call, and its deferred cleanup runs")
}
