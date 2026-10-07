package main
import "core:testing"
@(test)
test_foreign_path_contract :: proc(t: ^testing.T) {
    testing.expect(t, valid_c_input("/tmp/local fixture.wav"))
    testing.expect(t, !valid_c_input(""))
    testing.expect(t, !valid_c_input("https://example.invalid/media"))
    testing.expect(t, !valid_c_input("relative.wav"))
    testing.expect(t, !valid_c_input("/tmp/short\x00long"))
}
