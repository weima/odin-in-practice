# Packages and visibility

This small program keeps its entry point and CLI-specific usage text in the same `cli` package, then imports a sibling `label` package through its public `greeting` procedure. `label` keeps its string prefix file-local and its normalization helper package-local. The returned greeting is allocated with the caller's current allocator; the CLI and test both release it with `delete`.

Run from the repository root with the pinned Odin compiler:

```sh
odin check docs/examples/05-packages/cli
odin run docs/examples/05-packages/cli
odin run docs/examples/05-packages/cli -- Ada
TZ=UTC odin test docs/examples/05-packages/label
```

Expected program output:

```text
Hello, world!
Hello, Ada!
```

The two `.odin` files in `cli/` compile together because they declare `package main` and share a directory. The `label/` directory is a separate package; `cli/main.odin` imports it as `label`. Each file that uses an import declares that import itself. `label.greeting` is the supported API. Implementation details are hidden using Odin's `@(private="file")` and `@(private="package")` attributes—not by naming convention alone.
