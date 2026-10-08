#+build linux
package main

import "core:fmt"

main :: proc() {
    identity := current_identity()
    fmt.printfln("pid=%d start_time=%d alive=%t", identity.pid, identity.start_time, identity_alive(identity))
}
