package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_cli_process_contract :: proc(t: ^testing.T) {
    root, root_err := os.make_directory_temp("", "odin-e2e-cli-*", context.allocator)
    if root_err != nil { testing.expect(t, false, "cannot create fixture root"); return }
    defer delete(root)
    defer _ = os.remove_all(root)
    bin := fmt.tprintf("%s/bin", root)
    if os.make_directory_all(bin) != nil { testing.expect(t, false, "cannot create fake-bin directory"); return }
    binary := fmt.tprintf("%s/cli", root)
    script := fmt.tprintf("%s/uppercase-tool", bin)
    if os.write_entire_file(script, `#!/bin/sh
printf '<%s>\n' "$@" > "$ARG_LOG"
if [ -n "$FAKE_TOOL_DOWN" ]; then echo tool-down >&2; exit 7; fi
printf 'CANNED OUTPUT\n'
`) != nil { testing.expect(t, false, "cannot write fake executable"); return }
    chmod, _, chmod_stderr, chmod_err := os.process_exec({command = []string{"chmod", "+x", script}}, context.allocator)
    defer delete(chmod_stderr)
    testing.expect_value(t, chmod_err, os.Error(nil))
    testing.expect_value(t, chmod.exit_code, 0)

    build, _, build_err, build_os_err := os.process_exec({command = []string{"odin", "build", ".", fmt.tprintf("-out:%s", binary)}, working_dir = "docs/examples/21-e2e-cli"}, context.allocator)
    defer delete(build_err)
    testing.expect_value(t, build_os_err, os.Error(nil))
    testing.expect_value(t, build.exit_code, 0)

    env, env_err := test_environment(bin, fmt.tprintf("%s/args", root), "")
    testing.expect_value(t, env_err, os.Error(nil))
    success, out, stderr, start_err := os.process_exec({command = []string{binary, "two words", `say "hi"`}, env = env}, context.allocator)
    defer delete(out)
    defer delete(stderr)
    testing.expect_value(t, start_err, os.Error(nil))
    testing.expect_value(t, success.exit_code, 0)
    testing.expect_value(t, string(out), "CANNED OUTPUT\n")
    testing.expect_value(t, string(stderr), "")
    args, args_err := os.read_entire_file(fmt.tprintf("%s/args", root), context.temp_allocator)
    testing.expect_value(t, args_err, os.Error(nil))
    testing.expect_value(t, string(args), "<two words>\n<say \"hi\">\n")

    down_env, _ := test_environment(bin, fmt.tprintf("%s/args", root), "1")
    failed, failed_out, failed_err, _ := os.process_exec({command = []string{binary}, env = down_env}, context.allocator)
    defer delete(failed_out)
    defer delete(failed_err)
    testing.expect_value(t, failed.exit_code, 1)
    testing.expect_value(t, string(failed_out), "")
    testing.expect_value(t, string(failed_err), "uppercase-tool failed with exit code 7\n")

    missing_env, _ := test_environment(fmt.tprintf("%s/no-bin", root), fmt.tprintf("%s/args", root), "")
    missing, missing_out, missing_err, _ := os.process_exec({command = []string{binary}, env = missing_env}, context.allocator)
    defer delete(missing_out)
    defer delete(missing_err)
    testing.expect_value(t, missing.exit_code, 2)
    testing.expect_value(t, string(missing_out), "")
    testing.expect(t, strings.contains(string(missing_err), "could not start uppercase-tool:"), string(missing_err))
}

test_environment :: proc(bin, log, down: string) -> ([]string, os.Error) {
    inherited, err := os.environ(context.temp_allocator)
    if err != nil { return nil, err }
    env := make([]string, len(inherited)+3, context.temp_allocator)
    n := 0
    for entry in inherited {
        if strings.has_prefix(entry, "PATH=") || strings.has_prefix(entry, "ARG_LOG=") || strings.has_prefix(entry, "FAKE_TOOL_DOWN=") { continue }
        env[n] = entry
        n += 1
    }
    env[n] = fmt.tprintf("PATH=%s:/usr/bin:/bin", bin)
    env[n+1] = fmt.tprintf("ARG_LOG=%s", log)
    env[n+2] = fmt.tprintf("FAKE_TOOL_DOWN=%s", down)
    return env, nil
}
