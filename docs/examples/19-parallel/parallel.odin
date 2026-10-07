// Original teaching companion; core API baseline: 84bc3fc.
package main

import "core:sync"
import "core:thread"

MAX_WORKERS :: 16
MAX_ITEMS :: 1_048_576
MAX_VALUE :: i64(1_000_000_000)

Error :: enum {
    None,
    Invalid_Size,
    Invalid_Workers,
    Overlapping_Buffers,
    Thread_Create_Failed,
    Cancelled,
    Value_Out_Of_Range,
}

Shared :: struct {
    stop: i32,
    external_stop: ^i32,
}

Partition :: struct {
    input, output: []i64,
    first, limit: int,
    shared: ^Shared,
    error: Error, // Written by this partition's worker; read only after joining.
}

work :: proc(t: ^thread.Thread) {
    job := cast(^Partition)t.data
    for i in job.first..<job.limit {
        if sync.atomic_load(&job.shared.stop) != 0 ||
            (job.shared.external_stop != nil && sync.atomic_load(job.shared.external_stop) != 0) {
            job.error = .Cancelled
            return
        }
        value := job.input[i]
        if value < -MAX_VALUE || value > MAX_VALUE {
            job.error = .Value_Out_Of_Range
            sync.atomic_store(&job.shared.stop, 1)
            return
        }
        job.output[i] = value * value
    }
}

// All handles, partition descriptors and borrowed buffers stay alive until joining.
// A non-None error makes the entire output invalid, including any partial writes.
// The caller must keep input immutable and, if present, access external_stop atomically.
parallel_squares :: proc(input, output: []i64, workers: int, external_stop: ^i32 = nil) -> Error {
    if len(input) != len(output) || len(input) > MAX_ITEMS { return .Invalid_Size }
    if workers < 1 || workers > MAX_WORKERS { return .Invalid_Workers }
    if len(input) == 0 { return .None }
    in_address := uintptr(raw_data(input))
    out_address := uintptr(raw_data(output))
    byte_count := uintptr(len(input)) * size_of(i64)
    if (in_address <= out_address && out_address-in_address < byte_count) ||
        (out_address < in_address && in_address-out_address < byte_count) {
        return .Overlapping_Buffers
    }

    shared := Shared{external_stop = external_stop}
    partitions: [MAX_WORKERS]Partition
    handles: [MAX_WORKERS]^thread.Thread
    count := 0
    // destroy also joins: this path covers partial thread-creation failure.
    defer for t in handles[:count] { thread.destroy(t) }

    actual_workers := min(workers, len(input))
    for i in 0..<actual_workers {
        partitions[i] = Partition{
            input = input, output = output,
            first = len(input)*i/actual_workers,
            limit = len(input)*(i+1)/actual_workers,
            shared = &shared,
        }
        t := thread.create(work)
        if t == nil {
            sync.atomic_store(&shared.stop, 1)
            return .Thread_Create_Failed
        }
        t.data = &partitions[i]
        handles[count] = t
        count += 1
        thread.start(t)
    }
    for t in handles[:count] { thread.join(t) }
    // A computation failure outranks cancellation caused by that failure.
    for job in partitions[:count] {
        if job.error == .Value_Out_Of_Range { return job.error }
    }
    for job in partitions[:count] {
        if job.error != .None { return job.error }
    }
    return .None
}
