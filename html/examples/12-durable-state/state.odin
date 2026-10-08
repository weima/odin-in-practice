package main

import "core:encoding/json"
import "core:os"
import "core:strings"

Item :: struct { id: string, status: string }
Snapshot :: struct { sequence: int, items: [dynamic]Item }
Event :: struct { sequence: int, item_id: string, from: string, to: string }
Error_Kind :: enum { None, IO, Partial_Line, Conflict, Invalid_Transition }
Error :: struct { kind: Error_Kind, line: int }

snapshot_path :: proc(root: string) -> string { path, _ := strings.concatenate({root, "/snapshot.json"}); return path }
log_path :: proc(root: string) -> string { path, _ := strings.concatenate({root, "/events.ndjson"}); return path }

ensure_directory :: proc(path: string) -> bool {
    if os.is_dir(path) { return true }
    err := os.make_directory_all(path)
    return err == nil || (err == .Exist && os.is_dir(path))
}

atomic_write :: proc(path: string, data: []byte) -> Error {
    temp, _ := strings.concatenate({path, ".tmp"})
    defer delete(temp)
    file, err := os.open(temp, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, os.Permissions{.Read_User, .Write_User})
    if err != nil { return Error{kind = .IO} }
    n, write_err := os.write(file, data)
    written := write_err == nil && n == len(data) && os.flush(file) == nil && os.sync(file) == nil
    // Close exactly once, whether or not the writes worked, then replace the target.
    // Every failure after the open removes the temporary, so none is left behind.
    close_err := os.close(file)
    if !written || close_err != nil || os.rename(temp, path) != nil {
        _ = os.remove(temp)
        return Error{kind = .IO}
    }
    return Error{}
}

write_snapshot :: proc(root: string, snapshot: Snapshot) -> Error {
    bytes, err := json.marshal(snapshot, json.Marshal_Options{spec = .JSON, pretty = true})
    defer delete(bytes)
    if err != nil { return Error{kind = .IO} }
    path := snapshot_path(root)
    defer delete(path)
    return atomic_write(path, bytes)
}

create :: proc(root: string, item_id: string) -> Error {
    if !ensure_directory(root) { return Error{kind = .IO} }
    items := make([dynamic]Item, 1)
    items[0] = Item{item_id, "queued"}
    snap := Snapshot{items = items}
    defer delete(items)
    path := log_path(root)
    defer delete(path)
    if err := os.write_entire_file(path, ""); err != nil { return Error{kind = .IO} }
    return write_snapshot(root, snap)
}

valid_transition :: proc(from, to: string) -> bool {
    return (from == "queued" && to == "running") || (from == "running" && to == "done")
}

transition :: proc(root, item_id, to: string) -> Error {
    snapshot, err := load(root)
    if err.kind != .None { return err }
    defer destroy_snapshot(&snapshot)
    index := -1
    for item, i in snapshot.items { if item.id == item_id { index = i; break } }
    if index < 0 || !valid_transition(snapshot.items[index].status, to) { return Error{kind = .Invalid_Transition} }
    status_copy, clone_err := strings.clone(to)
    if clone_err != nil { return Error{kind = .IO} }
    event := Event{snapshot.sequence + 1, item_id, snapshot.items[index].status, to}
    bytes, marshal_err := json.marshal(event, json.Marshal_Options{spec = .JSON})
    defer delete(bytes)
    if marshal_err != nil { delete(status_copy); return Error{kind = .IO} }
    line := make([]byte, len(bytes)+1)
    defer delete(line)
    copy(line, bytes); line[len(bytes)] = '\n'
    path := log_path(root)
    defer delete(path)
    if err = append_file(path, line); err.kind != .None { delete(status_copy); return err }
    delete(snapshot.items[index].status)
    snapshot.items[index].status = status_copy
    snapshot.sequence = event.sequence
    return write_snapshot(root, snapshot)
}

append_file :: proc(path: string, data: []byte) -> Error {
    file, err := os.open(path, os.O_WRONLY|os.O_APPEND|os.O_CREATE, os.Permissions{.Read_User, .Write_User})
    if err != nil { return Error{kind = .IO} }
    defer os.close(file)
    n, write_err := os.write(file, data)
    if write_err != nil || n != len(data) || os.sync(file) != nil { return Error{kind = .IO} }
    return Error{}
}

load :: proc(root: string) -> (Snapshot, Error) {
    path := snapshot_path(root)
    defer delete(path)
    data, err := os.read_entire_file_from_path(path, context.allocator)
    defer delete(data)
    if err != nil { return Snapshot{}, Error{kind = .IO} }
    snapshot: Snapshot
    if json.unmarshal_string(transmute(string)data, &snapshot, .JSON) != nil { return Snapshot{}, Error{kind = .IO} }
    log := log_path(root)
    defer delete(log)
    events_data, log_err := os.read_entire_file_from_path(log, context.allocator)
    defer delete(events_data)
    if log_err != nil { destroy_snapshot(&snapshot); return Snapshot{}, Error{kind = .IO} }
    events := transmute(string)events_data
    if len(events) > 0 && events[len(events)-1] != '\n' {
        line := 1
        for c in events { if c == '\n' { line += 1 } }
        destroy_snapshot(&snapshot)
        return Snapshot{}, Error{kind = .Partial_Line, line = line}
    }
    replay := make([dynamic]Item, len(snapshot.items))
    defer delete(replay)
    for item, i in snapshot.items { replay[i] = Item{item.id, "queued"} }
    seq := 0
    line_start := 0
    for i := 0; i < len(events); i += 1 {
        if events[i] != '\n' { continue }
        event: Event
        if json.unmarshal_string(events[line_start:i], &event, .JSON) != nil || event.sequence != seq+1 {
            delete(event.item_id); delete(event.from); delete(event.to)
            destroy_snapshot(&snapshot); return Snapshot{}, Error{kind = .Conflict}
        }
        found := false
        for item, j in replay {
            if item.id == event.item_id {
                if item.status != event.from || !valid_transition(event.from, event.to) {
                    delete(event.item_id); delete(event.from); delete(event.to)
                    destroy_snapshot(&snapshot); return Snapshot{}, Error{kind = .Conflict}
                }
                replay[j].status = "running" if event.to == "running" else "done"
                found = true
                break
            }
        }
        if !found {
            delete(event.item_id); delete(event.from); delete(event.to)
            destroy_snapshot(&snapshot); return Snapshot{}, Error{kind = .Conflict}
        }
        seq = event.sequence
        delete(event.item_id); delete(event.from); delete(event.to)
        line_start = i+1
    }
    if seq != snapshot.sequence { destroy_snapshot(&snapshot); return Snapshot{}, Error{kind = .Conflict} }
    for item, i in snapshot.items {
        if item.status != replay[i].status { destroy_snapshot(&snapshot); return Snapshot{}, Error{kind = .Conflict} }
    }
    return snapshot, Error{}
}

destroy_snapshot :: proc(snapshot: ^Snapshot) {
    for item in snapshot.items { delete(item.id); delete(item.status) }
    delete(snapshot.items)
    snapshot^ = Snapshot{}
}
