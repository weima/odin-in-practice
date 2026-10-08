package main

import "core:testing"
import "core:time"

@(test)
named_result_names_are_assigned_not_shadowed :: proc(t: ^testing.T) {
	stdout, stderr, err := named_results()
	defer delete(stdout)
	defer delete(stderr)
	testing.expect_value(t, string(stdout), "out")
	testing.expect_value(t, string(stderr), "err")
	testing.expect_value(t, err, "")
}

@(test)
assignment_reuses_names_and_inner_scope_can_shadow :: proc(t: ^testing.T) {
	state, stdout, stderr, err := assign_existing()
	defer delete(stdout)
	defer delete(stderr)
	testing.expect_value(t, state, 0)
	testing.expect_value(t, string(stdout), "out")
	testing.expect_value(t, string(stderr), "err")
	testing.expect_value(t, err, "")

	value := 1
	{
		value := 2
		testing.expect_value(t, value, 2)
	}
	testing.expect_value(t, value, 1)
}

@(test)
explicit_sentinel_and_wrapper_time_apis :: proc(t: ^testing.T) {
	supplied := time.Time{123}
	testing.expect_value(t, fixed_time(supplied), supplied)
	testing.expect_value(t, time_with_sentinel(supplied), supplied)
	testing.expect(t, time_with_sentinel() != {})
	testing.expect(t, time_now() != {})
}

@(test)
string_range_values_are_runes_and_byte_offsets :: proc(t: ^testing.T) {
	s := "Aé🙂"
	testing.expect_value(t, len(s), 7)
	expected_runes := [3]rune{'A', 'é', '🙂'}
	expected_offsets := [3]int{0, 1, 3}
	rune_index := 0
	for r, byte_offset in s {
		testing.expect_value(t, r, expected_runes[rune_index])
		testing.expect_value(t, byte_offset, expected_offsets[rune_index])
		rune_index += 1
	}
	testing.expect_value(t, s[1], u8(0xc3))
	testing.expect_value(t, s[2], u8(0xa9))
}

@(test)
ascii_and_rune_identifier_policies_are_distinct :: proc(t: ^testing.T) {
	testing.expect(t, valid_ascii_id("Brew-7_ok"))
	testing.expect(t, !valid_ascii_id("éclair"))
	testing.expect(t, !valid_ascii_id("-bad"))
	testing.expect(t, valid_rune_id("éclair_7"))
	testing.expect(t, !valid_rune_id("_é"))
}
