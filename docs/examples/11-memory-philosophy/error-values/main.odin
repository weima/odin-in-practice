// Companion to memory-philosophy.html; original teaching example for the pinned Odin edition.
package main

import "core:fmt"

Ratio_Error :: enum { None, Zero_Denominator }

checked_ratio :: proc(numerator, denominator: f64) ->
    (ratio: f64, err: Ratio_Error) {
    if denominator == 0 { return 0, .Zero_Denominator }
    return numerator / denominator, nil
}

explicit_adjustment :: proc(a, b: f64) -> (value: f64, err: Ratio_Error) {
    ratio, ratio_err := checked_ratio(a, b)
    if ratio_err != nil { return 0, ratio_err }
    return ratio + 1, nil
}

propagated_adjustment :: proc(a, b: f64) -> (value: f64, err: Ratio_Error) {
    ratio := checked_ratio(a, b) or_return
    return ratio + 1, nil
}

main :: proc() {
    value, err := propagated_adjustment(6, 2)
    assert(value == 4 && err == nil)
    failed_value, failed_err := propagated_adjustment(6, 0)
    assert(failed_value == 0 && failed_err == .Zero_Denominator)
    explicit_value, explicit_err := explicit_adjustment(6, 0)
    assert(explicit_value == failed_value && explicit_err == failed_err)
    fmt.println("the failure branch remains; its propagation spelling is shorter")
}
