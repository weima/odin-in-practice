# Odin packages and dependencies

Use this when an Odin change adds files, creates an import boundary, exposes a helper, or introduces third-party source. The bundle includes the complete curated `.odin` source and focused test at [`examples/05-packages/`](../examples/05-packages/README.md), not only a link to the book. Inspect the relevant source and test as working reference code, then adapt it to the project and installed compiler rather than guessing at syntax or package behavior.

## Choose the smallest useful boundary

- **One package, multiple files:** keep cohesive CLI mechanics together when files share declarations and evolve together. A directory's `.odin` files with the same package declaration compile together. Split files by responsibility (entry point, argument handling, output) for navigation, not as a visibility trick.
- **A separate package:** use a subdirectory when a named responsibility has a stable caller-facing API, has independent tests/reuse, or benefits from hiding its internal implementation. Imports then make the dependency explicit. Avoid tiny wrapper packages that only rename one call.
- **CLI shape:** keep argument parsing, usage/error messages and exit status at the command boundary. Put independent domain transformations behind a package API only when this makes ownership and tests clearer. Do not start by designing a universal command framework.

## Imports and visibility

Package membership comes from directory and `package` declaration; imports are per source file, not shared across package files. Import a package path where used. Collection prefixes organize import paths: `core:fmt` comes from Odin's installed core source collection, while `vendor:` names the installed vendor collection. They are source lookup locations, not registries or downloads. Use `odin root` to inspect what the current compiler installation provides. For project-owned code, prefer a clear relative package import or a deliberately configured collection; do not add a collection alias just to avoid a short relative path.

Declarations are public by default. This lets an importer name them. Narrow visibility deliberately:

- `@(private="package")`: declaration is usable inside that package, including its other source files, but not by importing packages.
- `@(private="file")`: declaration is usable only from the source file where declared.

There is no `protected` visibility inherited by subclasses; Odin does not organize code through class inheritance. Visibility is a compile-time language boundary, not a security mechanism. Keep the imported API small and test it through the caller-visible contract. Per-file imports mean tests also declare their own imports.

## Keep dependencies reproducible

Odin has no official package manager that automatically resolves and locks third-party packages. Prefer Odin's built-in collections or code already controlled by the project. If you vendor a dependency:

1. Record canonical upstream URL, immutable release/tag or commit, license, and any local patch.
2. Keep imported source at a project-controlled, stable path; avoid implicit machine-local paths and moving branches.
3. Review source and target/compiler compatibility before upgrading.
4. Update the recorded version deliberately and rerun compile checks and focused tests.

Do not build dependency plumbing for a dependency that is not actually needed. This guide does not prescribe a universal registry, package manifest or update service.

## Apply and verify the bundled example

From the book repository root, with the pinned compiler on `PATH`:

```sh
odin check docs/examples/05-packages/cli
odin run docs/examples/05-packages/cli
odin run docs/examples/05-packages/cli -- Ada
TZ=UTC odin test docs/examples/05-packages/label
```

The CLI's `main.odin` and `args.odin` are one package. It imports sibling package `label` using a relative package path. `greeting` is the public API, `normalized_name` is package-private and is implemented in a different source file, and `PREFIX` is file-private. The API returns allocator-owned text; callers release it. The focused test exercises normal and empty names and releases both results.
