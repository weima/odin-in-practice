package main

import "core:testing"

@(test)
test_site_prefix_is_the_path_of_site_url :: proc(t: ^testing.T) {
    yaml := "site_name: Book\nsite_url: https://weima.github.io/odin-in-practice/\nnav: []\n"
    nested := "nav:\n  site_url: https://nested.example.org/no/\n"
    cases := []struct {
        config, want: string,
        found:        bool,
    } {
        {yaml, "/odin-in-practice/", true},
        {"site_url: \"https://example.org/a/b/\"\n", "/a/b/", true},
        {"site_url: 'https://example.org/q/'   # where it is hosted\n", "/q/", true},
        {"site_url: https://example.org\n", "", true},
        {"site_url:    https://example.org/x/   \r\n", "/x/", true},
        {nested, "", false}, // only a top-level key counts
        {"site_name: Book\n", "", false},
        {"site_url:\n", "", false},
        {"", "", false},
    }
    for item in cases {
        got, found := site_prefix(item.config)
        testing.expectf(t, found == item.found, "%q: found %v", item.config, found)
        testing.expectf(t, got == item.want, "%q: got %q, want %q", item.config, got, item.want)
    }
}
