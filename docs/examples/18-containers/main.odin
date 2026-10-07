// Read-only Docker inspection, with an explicit execution opt-in and a fixed lab target.
// Docker daemon access is privileged. Read README.md before using --execute.
package main
import "core:fmt"
import "core:os"
import "core:strings"

LAB_NAME :: "odin-book-lab"
valid_status :: proc(value: string) -> bool {
    return value == "created" || value == "running" || value == "paused" ||
        value == "restarting" || value == "removing" || value == "exited" || value == "dead"
}
run :: proc() -> int {
    if len(os.args) == 1 {
        fmt.println("dry run: inspect only odin-book-lab; pass --execute after verifying Docker context default")
        return 0
    }
    if len(os.args) != 2 || os.args[1] != "--execute" { return 2 }
    command := []string{
        "/usr/bin/timeout", "--signal=TERM", "--kill-after=1s", "5s",
        "/usr/bin/docker", "--context", "default", "inspect",
        "--format", "{{.State.Status}}", LAB_NAME,
    }
    state, stdout, stderr, err := os.process_exec({command=command}, context.allocator)
    defer delete(stdout)
    defer delete(stderr)
    if err != nil { fmt.eprintln("launch failure:", err); return 1 }
    if !state.success || state.exit_code != 0 {
        fmt.eprint(string(stderr))
        fmt.eprintfln("inspect failed: child exit=%d", state.exit_code)
        return 1
    }
    if len(stdout) > 32 { fmt.eprintln("unexpected inspection output size"); return 1 }
    status := strings.trim_space(string(stdout))
    if !valid_status(status) { fmt.eprintln("unrecognized container status"); return 1 }
    fmt.println(status)
    return 0
}
main :: proc() { status := run(); os.exit(status) }
