#+build linux
package main

import "core:fmt"
import "core:os"

main :: proc() {
    identity, ok := current_identity()
    if !ok {
        fmt.eprintln("could not read this process's /proc entry")
        os.exit(1)
    }
    fmt.printfln("pid=%d start_time=%d alive=%t", identity.pid, identity.start_time, identity_alive(identity))
}
