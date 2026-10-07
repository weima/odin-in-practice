package label

@(private="package")
normalized_name :: proc(name: string) -> string {
    if len(name) == 0 {
        return "world"
    }
    return name
}
