package records
import "core:testing"
@(test)
test_escaped_filename_and_integer_schema :: proc(t: ^testing.T) {
    size, err := parse_size(transmute([]u8)string(`{"path":"line\\nname","bytes":17}`))
    testing.expect_value(t, err, Error.None)
    testing.expect_value(t, size, i64(17))
}
@(test)
test_wrong_kind_and_unknown_fields_are_rejected :: proc(t: ^testing.T) {
    for line in ([4]string{
        `{"path":"a","bytes":"17"}`, `{"path":"a","bytes":-1}`,
        `{"path":"a","bytes":0,"extra":1}`, `{"path":null,"bytes":0}`,
    }) {
        _, err := parse_size(transmute([]u8)line)
        testing.expect_value(t, err, Error.Schema)
    }
}
@(test)
test_empty_and_truncated_record_are_rejected :: proc(t: ^testing.T) {
    for line in ([3]string{"", "{", `{"path":"a"}`}) {
        _, err := parse_size(transmute([]u8)line)
        testing.expect_value(t, err, Error.Schema)
    }
}
@(test)
test_advertised_file_budget_is_enforced :: proc(t: ^testing.T) {
    _, err := parse_size(transmute([]u8)string(`{"path":"a","bytes":1048577}`))
    testing.expect_value(t, err, Error.Schema)
}
