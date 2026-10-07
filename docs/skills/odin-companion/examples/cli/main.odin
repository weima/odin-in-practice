// A complete small CLI using Odin's typed flags parser.
package main

import "core:flags"
import "core:fmt"
import "core:os"

Options :: struct {
    name: string `args:"pos=0,required" usage:"Name to greet."`,
    loud: bool   `usage:"Print an enthusiastic greeting."`,
}

main :: proc() {
    options: Options
    flags.parse_or_exit(&options, os.args, .Unix)

    if options.loud {
        fmt.printfln("HELLO, %s!", options.name)
    } else {
        fmt.printfln("Hello, %s.", options.name)
    }
}
