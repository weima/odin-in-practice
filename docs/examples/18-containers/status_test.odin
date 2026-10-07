package main
import "core:testing"
@(test)
test_only_known_container_states_are_accepted :: proc(t: ^testing.T) {
    for value in ([7]string{"created","running","paused","restarting","removing","exited","dead"}) {
        testing.expect(t, valid_status(value))
    }
    testing.expect(t, !valid_status(""))
    testing.expect(t, !valid_status("running; touch unwanted"))
    testing.expect(t, !valid_status("healthy")) // Health is not lifecycle state.
}
