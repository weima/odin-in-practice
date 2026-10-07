package memory_specs

import "core:mem"
import "core:mem/virtual"
import "core:testing"

@(test)
test_copy_survives_arena_reset :: proc(t: ^testing.T) {
    arena: virtual.Arena
    init_err := virtual.arena_init_growing(&arena)
    if !testing.expect(t, init_err == nil) { return }
    defer virtual.arena_destroy(&arena)
    allocator := context.allocator
    scratch, err := make([]int, 2, virtual.arena_allocator(&arena))
    if !testing.expect(t, err == nil) { return }
    scratch[0], scratch[1] = 7, 9
    owned, owned_err := make([]int, 2, allocator)
    defer delete(owned, allocator)
    if !testing.expect(t, owned_err == nil) { return }
    copy(owned, scratch)
    virtual.arena_free_all(&arena)
    testing.expect_value(t, owned[0], 7)
    testing.expect_value(t, owned[1], 9)
}

@(test)
test_individual_arena_free_is_not_implemented :: proc(t: ^testing.T) {
    arena: virtual.Arena
    init_err := virtual.arena_init_growing(&arena)
    if !testing.expect(t, init_err == nil) { return }
    defer virtual.arena_destroy(&arena)
    allocator := virtual.arena_allocator(&arena)
    p, err := new(int, allocator)
    if !testing.expect(t, err == nil) { return }
    free_err := free(p, allocator)
    testing.expect_value(t, free_err, mem.Allocator_Error.Mode_Not_Implemented)
}

@(test)
test_defer_runs_on_early_return :: proc(t: ^testing.T) {
    cleanup_count := 0
    operation :: proc(count: ^int) -> bool {
        defer count^ += 1
        return false
    }
    testing.expect(t, !operation(&cleanup_count))
    testing.expect_value(t, cleanup_count, 1)
}

@(test)
test_block_defer_runs_before_function_exit :: proc(t: ^testing.T) {
    cleanup_count := 0
    {
        defer cleanup_count += 1
        testing.expect_value(t, cleanup_count, 0)
    }
    testing.expect_value(t, cleanup_count, 1)
}

@(test)
test_local_context_change_does_not_change_caller :: proc(t: ^testing.T) {
    original := context.allocator
    local_policy :: proc() {
        context.allocator = mem.Allocator{}
        // Do not allocate through the intentionally empty policy.
    }
    local_policy()
    testing.expect(t, context.allocator == original)
}
