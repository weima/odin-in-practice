// A bounded, loopback-only HTTP GET client using the installed curl CLI.
// Not a reusable high-throughput client; see the chapter's production boundary checklist.
package main

import "core:fmt"
import "core:os"
import "core:strconv"

MAX_BODY :: 65536

split_response :: proc(output: []u8) -> (body: []u8, status: int, ok: bool) {
    if len(output) < 4 || output[len(output)-4] != '\n' { return nil, 0, false }
    code := output[len(output)-3:]
    for digit in code { if digit < '0' || digit > '9' { return nil, 0, false } }
    status = int(code[0]-'0')*100 + int(code[1]-'0')*10 + int(code[2]-'0')
    if status < 100 || status > 599 { return nil, 0, false }
    return output[:len(output)-4], status, true
}

run :: proc() -> int {
    if len(os.args) != 3 {
        fmt.eprintln("usage: http-client PORT /ok|/missing|/oversize|/slow")
        return 2
    }
    port, port_ok := strconv.parse_int(os.args[1])
    if !port_ok || port < 1 || port > 65535 { return 2 }
    path := os.args[2]
    if path != "/ok" && path != "/missing" && path != "/oversize" && path != "/slow" { return 2 }
    url := fmt.aprintf("http://127.0.0.1:%d%s", port, path)
    defer delete(url)
    command := []string{
        "/usr/bin/timeout", "--signal=TERM", "--kill-after=1s", "5s",
        "/usr/bin/curl", "--disable", "--silent", "--show-error",
        "--connect-timeout", "1", "--max-time", "2",
        "--max-filesize", "65536", "--proto", "=http",
        "--noproxy", "*", "--write-out", "\n%{http_code}", "--", url,
    }
    state, stdout, stderr, launch_err := os.process_exec({command=command}, context.allocator)
    defer delete(stdout)
    defer delete(stderr)
    if launch_err != nil { fmt.eprintln("launch:", launch_err); return 1 }
    if !state.success || state.exit_code != 0 {
        fmt.eprint(string(stderr))
        fmt.eprintfln("transport failed: child exit=%d", state.exit_code)
        return 1
    }
    body, status, ok := split_response(stdout)
    if !ok || len(body) > MAX_BODY { fmt.eprintln("invalid/beyond-budget response"); return 1 }
    if status < 200 || status >= 300 { fmt.eprintfln("HTTP status=%d", status); return 3 }
    // The response body borrows stdout; consume it before its owner is deleted.
    fmt.print(string(body))
    return 0
}

main :: proc() { status := run(); os.exit(status) }

