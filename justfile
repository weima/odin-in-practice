set shell := ["bash", "-euo", "pipefail", "-c"]

# Check every book example package with a main.odin file.
check:
    while IFS= read -r -d '' source; do odin check "${source%/main.odin}"; done < <(find docs/examples -name main.odin -print0 | sort -z)

# Run the test suites listed in CI and the additional README label suite.
test:
    TZ=UTC odin test docs/examples/04-procedures
    TZ=UTC odin test docs/examples/05-packages/label
    TZ=UTC odin test docs/examples/10-pointers/tests
    TZ=UTC odin test docs/examples/11-memory-philosophy/tests
    TZ=UTC odin test docs/examples/17-networking/http-client
    TZ=UTC odin test docs/examples/18-containers
    TZ=UTC odin test docs/examples/19-parallel
    TZ=UTC odin test docs/examples/21-capstone/records

# Assert the three Odin companion-skill CLI and network examples.
skill-examples:
    test "$(odin run docs/skills/odin-companion/examples/cli -- Ada --loud)" = 'HELLO, Ada!'
    test "$(odin run docs/skills/odin-companion/examples/cli -- Ada)" = 'Hello, Ada.'
    test "$(timeout 10s odin run docs/skills/odin-companion/examples/network)" = 'TCP loopback: exact read, reply, and half-close checked'

# Build the site into a temporary directory; never write generated html/.
site:
    site_dir="$(mktemp -d)"; trap 'rm -rf "$site_dir"' EXIT; source .venv/bin/activate; mkdocs build --strict -d "$site_dir"

# Run all local book verification recipes.
verify: check test skill-examples site
