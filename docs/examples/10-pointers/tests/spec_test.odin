package pointer_specs

import "core:testing"

@(test)
test_pointer_copy_shares_target :: proc(t: ^testing.T) {
    value := 1
    independent := value
    p := &value
    q := p
    q^ = 9
    testing.expect_value(t, value, 9)
    testing.expect_value(t, independent, 1)
}

@(test)
test_slice_headers_are_separate_but_elements_are_shared :: proc(t: ^testing.T) {
    backing := [3]int{1, 2, 3}
    a := backing[:]
    b := a[:1]
    b[0] = 7
    testing.expect_value(t, len(a), 3)
    testing.expect_value(t, len(b), 1)
    testing.expect_value(t, a[0], 7)
}

@(test)
test_retargeting_one_pointer_leaves_the_other :: proc(t: ^testing.T) {
    first, second := 1, 2
    p := &first
    q := p
    p = &second
    testing.expect_value(t, p^, 2)
    testing.expect_value(t, q^, 1)
}

@(test)
test_multi_pointer_view_borrows_array :: proc(t: ^testing.T) {
    backing := [2]int{4, 5}
    p := raw_data(backing[:])
    view := p[:len(backing)]
    view[1] = 8
    testing.expect_value(t, backing[1], 8)
}

@(test)
test_reference_iteration_mutates_elements :: proc(t: ^testing.T) {
    backing := [3]int{1, 2, 3}
    for &item in backing { item *= 2 }
    testing.expect_value(t, backing, [3]int{2, 4, 6})
}
