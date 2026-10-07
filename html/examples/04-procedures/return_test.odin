package main
import "core:testing"

@(test)
test_independent_type_parameters_may_differ_or_match :: proc(t: ^testing.T) {
    number, text := pair(i32(7), "hello")
    testing.expect_value(t, number, i32(7))
    testing.expect_value(t, text, "hello")
    left, right := pair(i32(7), i32(9))
    testing.expect_value(t, left, i32(7))
    testing.expect_value(t, right, i32(9))
}

@(test)
test_named_results_are_zero_on_the_early_failure_path :: proc(t: ^testing.T) {
    quotient, ok := divide_named(2, 0)
    testing.expect_value(t, quotient, f64(0))
    testing.expect(t, !ok)
}

@(test)
test_named_and_explicit_results_match_in_this_example :: proc(t: ^testing.T) {
    for input in ([3][2]f64{{8, 2}, {0, 2}, {2, 0}}) {
        quotient, ok := divide_named(input[0], input[1])
        expected, expected_ok := divide_explicit(input[0], input[1])
        testing.expect_value(t, quotient, expected)
        testing.expect_value(t, ok, expected_ok)
    }
    quotient, ok := divide_named(0, 2)
    testing.expect_value(t, quotient, f64(0))
    testing.expect(t, ok) // Zero quotient does not mean failure.
}

@(test)
test_no_result_return_runs_cleanup_and_returns_to_caller :: proc(t: ^testing.T) {
    value, cleanups := 0, 0
    write_if_requested(false, &value, &cleanups)
    testing.expect_value(t, value, 0)
    testing.expect_value(t, cleanups, 1)
    write_if_requested(true, &value, &cleanups)
    testing.expect_value(t, value, 7)
    testing.expect_value(t, cleanups, 2)
}
