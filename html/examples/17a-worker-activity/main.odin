package main

import "core:fmt"

main :: proc() {
    event, ok := parse_activity(
        `{"version":1,"worker":"worker-7","sequence":12,"kind":"progress"}`,
    )
    if !ok {
        fmt.eprintln("invalid activity event")
        return
    }
    fmt.printfln("worker=%s sequence=%d kind=%v", worker_id(&event), event.sequence, event.kind)
}
