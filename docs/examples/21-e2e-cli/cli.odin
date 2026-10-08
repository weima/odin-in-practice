package main

import "core:fmt"
import "core:os"

run :: proc() -> int {
    command := make([]string, len(os.args), context.temp_allocator)
    command[0] = "uppercase-tool"
    copy(command[1:], os.args[1:])
    state, stdout, stderr, err := os.process_exec({command = command}, context.allocator)
    defer delete(stdout)
    defer delete(stderr)
    if err != nil {
        fmt.eprintln("could not start uppercase-tool: ", err)
        return 2
    }
    if !state.success {
        fmt.eprintf("uppercase-tool failed with exit code %d\n", state.exit_code)
        return 1
    }
    fmt.print(string(stdout))
    return 0
}
