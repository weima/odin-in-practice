package main

import "core:fmt"
import "core:os"

main :: proc() {
    input, output: [10_000]i64
    for &value, i in input { value = i64(i)-5_000 }
    err := parallel_squares(input[:], output[:], 4)
    if err != .None {
        fmt.eprintln("parallel computation failed:", err)
        os.exit(1)
    }
    checksum: i64
    for value in output { checksum += value }
    assert(checksum == 83_333_335_000)
    fmt.println("four workers; verified checksum:", checksum)
}
