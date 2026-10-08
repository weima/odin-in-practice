package main

import "core:time"
import "core:unicode"

// The stand-in matches the shape needed to teach named-result assignment.
fake_process :: proc() -> (int, []byte, []byte, string) {
	stdout := make([]byte, 3)
	stderr := make([]byte, 3)
	stdout[0], stdout[1], stdout[2] = 'o', 'u', 't'
	stderr[0], stderr[1], stderr[2] = 'e', 'r', 'r'
	return 0, stdout, stderr, ""
}

named_results :: proc() -> (stdout, stderr: []byte, err: string) {
	state, child_stdout, child_stderr, process_err := fake_process()
	_ = state
	stdout = child_stdout
	stderr = child_stderr
	err = process_err
	return
}

// Existing names are assigned with =; this proc has no named results.
assign_existing :: proc() -> (int, []byte, []byte, string) {
	state, stdout, stderr, err := fake_process()
	delete(stdout)
	delete(stderr)
	state, stdout, stderr, err = fake_process()
	return state, stdout, stderr, err
}

fixed_time :: proc(now: time.Time) -> time.Time {
	return now
}

// A zero Time means "use the current time" for this API's chosen convention.
time_with_sentinel :: proc(now: time.Time = {}) -> time.Time {
	if now == {} {
		return time.now()
	}
	return now
}

// Keep the common call short without making a runtime value a default.
time_now :: proc() -> time.Time {
	return fixed_time(time.now())
}

// This identifier policy is bytewise by design: ASCII letters/digits first,
// then ASCII letters/digits, '-' or '_', with a 1..64 byte limit.
valid_ascii_id :: proc(s: string) -> bool {
	if len(s) == 0 || len(s) > 64 {
		return false
	}
	for byte, i in s {
		valid := byte >= 'a' && byte <= 'z' || byte >= 'A' && byte <= 'Z' || byte >= '0' && byte <= '9'
		if i == 0 {
			if !valid { return false }
		} else if !valid && byte != '-' && byte != '_' {
			return false
		}
	}
	return true
}

// This parallel policy iterates Unicode code points instead of UTF-8 bytes.
valid_rune_id :: proc(s: string) -> bool {
	if len(s) == 0 { return false }
	for r, i in s {
		valid := unicode.is_letter(r) || unicode.is_digit(r)
		if i == 0 {
			if !valid { return false }
		} else if !valid && r != '-' && r != '_' {
			return false
		}
	}
	return true
}
