# Odin in Practice companion skill

Download **this whole folder**, including `references/`, alongside the book. It contains one portable, editable skill—not a plugin, runtime service or installer.

## Use it

1. Read `SKILL.md` and `references/checklist.md`; the `examples/` directory contains complete CLI and loopback TCP packages.
2. Copy the folder into the skill directory supported by your coding agent, or explicitly ask the agent to read its `SKILL.md`.
3. Supply your project and request. Let the agent inspect your installed compiler instead of assuming the book's pinned release matches.

Folder discovery and invocation depend on the chosen agent. This book does not automatically install the skill globally, modify agent configuration or register it in a project's `AGENTS.md`.

## Make it your own

Give the folder to your preferred skill-creation tool, for example `create-skill` or `skill-creator`, and ask:

> Adapt this Odin companion skill to my project's compiler, target platforms and checks. Keep source-backed API verification and ownership/error boundaries. Put project-specific detail in local references and keep the main skill compact.

Rename the skill and its folder together if you want both versions. Replace examples of commands with your actual project checks, add references for your targets, and remove branches you do not use. Validate the resulting frontmatter and local links with your agent's skill tooling.

Run the examples from this skill folder with `odin run examples/cli -- Ada --loud` and `odin run examples/network`. The checklist records the book's baseline for comparison; it does not install the reader's compiler. There are no author-specific paths, credentials or dependencies on the rest of the book folder. The book and its runnable examples provide optional additional context.
