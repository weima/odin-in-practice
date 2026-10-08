package main

import "core:encoding/json"

MAX_ACTIVITY_LINE_BYTES :: 512
MAX_WORKER_ID_BYTES :: 48

Activity_Kind :: enum {
    Started,
    Progress,
    Blocked,
    Completed,
    Failed,
}

Activity_Event :: struct {
    version:    u8,
    worker:     [MAX_WORKER_ID_BYTES]u8,
    worker_len: int,
    sequence:   i64,
    kind:       Activity_Kind,
}

worker_id :: proc(event: ^Activity_Event) -> string {
    return string(event.worker[:event.worker_len])
}

// line excludes its terminating newline; the caller enforces framing and this byte limit.
parse_activity :: proc(line: string) -> (event: Activity_Event, ok: bool) {
    if len(line) == 0 || len(line) > MAX_ACTIVITY_LINE_BYTES {return}

    parser := json.make_parser_from_string(
        line,
        spec = .JSON,
        parse_integers = true,
        allocator = context.temp_allocator,
    )
    value, err := json.parse_value(&parser)
    if err != .None {return}
    defer json.destroy_value(value, context.temp_allocator)
    if parser.curr_token.kind != .EOF {return}

    object, is_object := value.(json.Object)
    if !is_object || len(object) != 4 {return}

    version_value, has_version := object["version"]
    worker_value, has_worker := object["worker"]
    sequence_value, has_sequence := object["sequence"]
    kind_value, has_kind := object["kind"]
    if !has_version || !has_worker || !has_sequence || !has_kind {return}

    version, is_version := version_value.(json.Integer)
    worker, is_worker := worker_value.(json.String)
    sequence, is_sequence := sequence_value.(json.Integer)
    kind, is_kind := kind_value.(json.String)
    if !is_version || !is_worker || !is_sequence || !is_kind {return}
    if version != 1 ||
       sequence <= 0 ||
       len(worker) == 0 ||
       len(worker) > MAX_WORKER_ID_BYTES {return}

    for c in worker {
        if !((c >= 'a' && c <= 'z') ||
               (c >= 'A' && c <= 'Z') ||
               (c >= '0' && c <= '9') ||
               c == '_' ||
               c == '-' ||
               c == '.') {
            return
        }
    }

    activity_kind, valid_kind := parse_kind(kind)
    if !valid_kind {return}

    event.version = 1
    event.worker_len = len(worker)
    copy(event.worker[:], worker)
    event.sequence = sequence
    event.kind = activity_kind
    return event, true
}

parse_kind :: proc(value: string) -> (kind: Activity_Kind, ok: bool) {
    switch value {
    case "started":
        return .Started, true
    case "progress":
        return .Progress, true
    case "blocked":
        return .Blocked, true
    case "completed":
        return .Completed, true
    case "failed":
        return .Failed, true
    }
    return {}, false
}
