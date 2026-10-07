package label

import "core:testing"

@(test)
test_greeting :: proc(t: ^testing.T) {
    ada := greeting("Ada")
    defer delete(ada)
    world := greeting("")
    defer delete(world)
    testing.expect_value(t, ada, "Hello, Ada!")
    testing.expect_value(t, world, "Hello, world!")
}
