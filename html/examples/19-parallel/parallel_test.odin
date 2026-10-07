package main

import "core:mem"
import "core:testing"

@(test)
matches_sequential :: proc(t: ^testing.T) {
    input, output: [2_049]i64
    for &value, i in input { value = i64(i)-1_024 }
    for workers in ([]int{1, 2, 3, 16}) {
        testing.expect(t, parallel_squares(input[:], output[:], workers) == .None)
        for value, i in output { testing.expect(t, value == input[i]*input[i]) }
    }
}

@(test)
empty_and_small :: proc(t: ^testing.T) {
    testing.expect(t, parallel_squares(nil, nil, 4) == .None)
    input := [1]i64{MAX_VALUE}
    output: [1]i64
    testing.expect(t, parallel_squares(input[:], output[:], 16) == .None)
    testing.expect(t, output[0] == MAX_VALUE*MAX_VALUE)
}

@(test)
rejects_sizes_and_workers :: proc(t: ^testing.T) {
    input: [2]i64
    output: [1]i64
    testing.expect(t, parallel_squares(input[:], output[:], 1) == .Invalid_Size)
    testing.expect(t, parallel_squares(nil, nil, 0) == .Invalid_Workers)
    testing.expect(t, parallel_squares(nil, nil, MAX_WORKERS+1) == .Invalid_Workers)
}

@(test)
rejects_aliases :: proc(t: ^testing.T) {
    buffer := [4]i64{1, 2, 3, 4}
    testing.expect(t, parallel_squares(buffer[:], buffer[:], 2) == .Overlapping_Buffers)
    testing.expect(t, parallel_squares(buffer[:3], buffer[1:], 2) == .Overlapping_Buffers)
    testing.expect(t, parallel_squares(buffer[1:], buffer[:3], 2) == .Overlapping_Buffers)
    // Adjacent non-overlapping ranges in one allocation are valid.
    testing.expect(t, parallel_squares(buffer[:2], buffer[2:], 2) == .None)
    testing.expect(t, buffer[2] == 1 && buffer[3] == 4)
}

@(test)
cancelled_before_start :: proc(t: ^testing.T) {
    input := [3]i64{1, 2, 3}
    output := [3]i64{-1, -1, -1}
    stop: i32 = 1 // Initialized before publication; no concurrent writer here.
    testing.expect(t, parallel_squares(input[:], output[:], 3, &stop) == .Cancelled)
    testing.expect(t, output == [3]i64{-1, -1, -1})
}

@(test)
computation_error_is_not_success :: proc(t: ^testing.T) {
    input := [3]i64{1, MAX_VALUE+1, 3}
    output: [3]i64
    testing.expect(t, parallel_squares(input[:], output[:], 3) == .Value_Out_Of_Range)
}

Budget :: struct {
    backing: mem.Allocator,
    limit, allocations, frees: int,
}

limited :: proc(data: rawptr, mode: mem.Allocator_Mode, size, alignment: int,
    old_memory: rawptr, old_size: int, location := #caller_location) -> ([]byte, mem.Allocator_Error) {
    budget := cast(^Budget)data
    #partial switch mode {
    case .Alloc, .Alloc_Non_Zeroed:
        if budget.allocations >= budget.limit { return nil, .Out_Of_Memory }
        bytes, err := budget.backing.procedure(budget.backing.data, mode, size, alignment,
            old_memory, old_size, location)
        if err == nil { budget.allocations += 1 }
        return bytes, err
    case .Free:
        if old_memory != nil { budget.frees += 1 }
    }
    return budget.backing.procedure(budget.backing.data, mode, size, alignment,
        old_memory, old_size, location)
}

@(test)
cleans_up_partial_creation :: proc(t: ^testing.T) {
    input, output: [100]i64
    original := context.allocator
    budget := Budget{backing = original, limit = 1}
    context.allocator = mem.Allocator{procedure = limited, data = &budget}
    err := parallel_squares(input[:], output[:], 4)
    context.allocator = original
    testing.expect(t, err == .Thread_Create_Failed)
    testing.expect(t, budget.allocations == 1 && budget.frees == 1)
}
