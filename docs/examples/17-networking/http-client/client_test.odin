package main
import "core:testing"

@(test)
test_http_response_keeps_body_and_status_separate :: proc(t: ^testing.T) {
    body, status, ok := split_response(transmute([]u8)string("hello\n200"))
    testing.expect(t, ok)
    testing.expect_value(t, status, 200)
    testing.expect_value(t, string(body), "hello")
}
@(test)
test_http_404_is_still_a_transport_response :: proc(t: ^testing.T) {
    _, status, ok := split_response(transmute([]u8)string("missing\n404"))
    testing.expect(t, ok)
    testing.expect_value(t, status, 404)
}
@(test)
test_http_truncated_status_is_rejected :: proc(t: ^testing.T) {
    _, _, ok := split_response(transmute([]u8)string("200"))
    testing.expect(t, !ok)
}
@(test)
test_http_non_status_trailer_is_rejected :: proc(t: ^testing.T) {
    _, _, ok := split_response(transmute([]u8)string("body\nx00"))
    testing.expect(t, !ok)
}
