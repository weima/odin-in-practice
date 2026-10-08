package main

import "core:fmt"

main :: proc() {
    stdout, stderr, err := named_results()
    defer delete(stdout)
    defer delete(stderr)
    fmt.printfln("stdout=%s stderr=%s err=%s", stdout, stderr, err)

    s := "Aé🙂"
    fmt.printfln("len=%d", len(s))
    for r, byte_offset in s {
        fmt.printfln("rune=%U byte-offset=%d byte=%d", r, byte_offset, s[byte_offset])
    }
    fmt.printfln(
        "ASCII ID=%v, rune ID=%v",
        valid_ascii_id("Brew-7_ok"),
        valid_rune_id("éclair_7"),
    )
}
