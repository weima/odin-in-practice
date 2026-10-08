package main

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:testing"

@(test)
test_allocated_result_is_released_by_caller :: proc(t: ^testing.T) {
	original := context.allocator
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, original)
	context.allocator = mem.tracking_allocator(&track)
	value := allocated_format("tea", context.allocator)
	testing.expect_value(t, value, "value=tea")
	delete(value, context.allocator)
	context.allocator = original
	testing.expect_value(t, len(track.allocation_map), 0)
	mem.tracking_allocator_destroy(&track)
}

@(test)
test_temporary_result_is_not_owned_by_context_allocator :: proc(t: ^testing.T) {
	original := context.allocator
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, original)
	context.allocator = mem.tracking_allocator(&track)
	value := temp_format("tea")
	testing.expect_value(t, value, "value=tea")
	context.allocator = original
	testing.expect_value(t, len(track.allocation_map), 0)
	mem.tracking_allocator_destroy(&track)
}

@(test)
test_buffer_and_builder_results_borrow_their_backing_storage :: proc(t: ^testing.T) {
	buf: [32]byte
	borrowed_buffer := buffer_format(buf[:], "tea")
	testing.expect_value(t, borrowed_buffer, "value=tea")

	builder: strings.Builder
	strings.builder_init(&builder)
	borrowed_builder := builder_format(&builder, "tea")
	testing.expect_value(t, borrowed_builder, "value=tea")
	strings.builder_destroy(&builder)
}

@(test)
test_owner_clones_temporary_result_and_destroy_releases_it :: proc(t: ^testing.T) {
	original := context.allocator
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, original)
	context.allocator = mem.tracking_allocator(&track)
	owner, err := owner_make(temp_format("tea"), context.allocator)
	testing.expect(t, err == nil)
	testing.expect_value(t, owner.value, "value=tea")
	owner_destroy(&owner)
	context.allocator = original
	testing.expect_value(t, len(track.allocation_map), 0)
	mem.tracking_allocator_destroy(&track)
}

@(test)
test_formatting_braces_and_json_marshalling :: proc(t: ^testing.T) {
	bad := fmt.tprintf("{\"order\":%s}", "7")
	testing.expect_value(t, bad, "%!(MISSING CLOSE BRACE)order\":7}")
	good := fmt.tprintf("{{\"order\":%s}}", "7")
	testing.expect_value(t, good, "{\"order\":7}")
	joined, err := strings.concatenate([]string{"{\"order\":", "7", "}"})
	testing.expect(t, err == nil)
	testing.expect_value(t, joined, "{\"order\":7}")
	delete(joined)
}
