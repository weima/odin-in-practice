package main

import "core:strings"
import "core:testing"

@(test)
valid_event_is_normalized :: proc(t: ^testing.T) {
    event, ok := parse_activity(
        `{"version":1,"worker":"worker-7","sequence":12,"kind":"progress"}`,
    )
    testing.expect(t, ok)
    testing.expect_value(t, event.version, 1)
    testing.expect_value(t, worker_id(&event), "worker-7")
    testing.expect_value(t, event.sequence, 12)
    testing.expect_value(t, event.kind, Activity_Kind.Progress)
}

@(test)
rejects_invalid_schema_and_values :: proc(t: ^testing.T) {
    testing.expect(t, !parse_ok(`{"version":2,"worker":"worker-7","sequence":1,"kind":"started"}`))
    testing.expect(t, !parse_ok(`{"version":1,"worker":"worker-7","sequence":0,"kind":"started"}`))
    testing.expect(t, !parse_ok(`{"version":1,"worker":"worker-7","sequence":1,"kind":"secret"}`))
    testing.expect(
        t,
        !parse_ok(
            `{"version":1,"worker":"worker-7","sequence":1,"kind":"started","prompt":"private"}`,
        ),
    )
    testing.expect(t, !parse_ok(`{"version":1,"worker":"bad id","sequence":1,"kind":"started"}`))
}

@(test)
rejects_malformed_and_oversized_lines :: proc(t: ^testing.T) {
    testing.expect(t, !parse_ok(`{"version":1,"worker":`))
    testing.expect(
        t,
        !parse_ok(`{"version":1,"worker":"worker-7","sequence":1,"kind":"started"} trailing`),
    )
    oversized, err := strings.repeat(`x`, MAX_ACTIVITY_LINE_BYTES + 1, context.temp_allocator)
    testing.expect(t, err == nil)
    testing.expect(t, !parse_ok(oversized))
}

parse_ok :: proc(line: string) -> bool {
    _, ok := parse_activity(line)
    return ok
}
