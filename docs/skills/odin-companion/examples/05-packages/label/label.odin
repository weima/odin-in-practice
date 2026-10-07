package label

import "core:strings"

@(private="file")
PREFIX :: "Hello, "

// This entry point is public by default and is the package's deliberate API.
greeting :: proc(name: string) -> string {
    return strings.concatenate({PREFIX, normalized_name(name), "!"}, allocator=context.allocator)
}

