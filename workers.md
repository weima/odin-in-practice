# Rules for automated Workers

These rules apply to Pi Workers that Coffee Shop starts in a Station (a Git worktree) of this repository. Read [standards.md](standards.md) as well: it says what a correct change is, and this file says how to behave while making one.

## Behaviour

- You are not interactive. No person is watching and nobody will answer. Never ask for permission, confirmation or clarification, and never stop to propose a plan and wait. Make the reasonable choice, state it in your report, and carry on.
- If something truly blocks you, say exactly what blocked you and still finish everything that is not blocked.
- Your final message is the deliverable, not a progress note. "I fixed it and restarted verification" is not a report.

## Scope

- Change only the files your task assigns to you. Never edit `html/`, `README.md`, `docs/index.md`, `docs/examples/README.md`, `mkdocs.yml`, `tools/`, `.github/`, `justfile`, package files, or any chapter or section that is not yours.
- Do not commit, push, create branches, install packages, run `npm`, or run the Mermaid diagram build.
- Do experiments in a scratch directory under `/tmp/<your-shot-id>/`.

## Verify before you report

- If `odin` is not found, run `source ~/.zshrc`.
- Run `odin check <dir>` and `TZ=UTC odin test <dir>` for each package you added; run the tests three times in a row when processes or timing are involved.
- Check the links with `. .venv/bin/activate && mkdocs build --strict -d /tmp/<your-shot-id>-site`. The `.venv` in your Station may be a link to a shared environment: install nothing. Never run `mkdocs` without `-d`; that would rewrite the tracked `html/`.
- If a check fails, fix the cause and run it again until it passes. Do not report while anything is failing or unverified.
- Finish with `git status --short`. Only your own files may appear (an untracked `.pi/` folder is not yours and may be ignored).

## Your report

State, in this order: the files you created or changed; what the new text teaches; each verification command with its real result; every place where reality differed from your brief; and your open questions.
