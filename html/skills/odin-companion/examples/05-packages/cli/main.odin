package main

import "core:fmt"
import "core:os"
import label "../label"

run :: proc() -> int {
    name := "world"
    if len(os.args) > 2 {
        fmt.eprintln("usage:", usage)
        return 2
    }
    if len(os.args) == 2 {
        name = os.args[1]
    }
    greeting := label.greeting(name)
    defer delete(greeting)
    fmt.println(greeting)
    return 0
}

main :: proc() {
    os.exit(run())
}
