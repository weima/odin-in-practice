"""Package and validate the self-contained Odin companion skill."""
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
skill = ROOT / "docs/skills/odin-companion"
archive = ROOT / "docs/skills/odin-companion.zip"
required = (
    "SKILL.md",
    "README.md",
    "references/checklist.md",
    "references/packages.md",
    "references/file-processing.md",
    "examples/05-packages/README.md",
    "examples/05-packages/cli/main.odin",
    "examples/05-packages/label/label.odin",
    "examples/13a-text-processing/main.odin",
    "examples/13a-text-processing/source.odin",
)
missing = [path for path in required if not (skill / path).is_file()]
assert not missing, f"Skill bundle is incomplete: {', '.join(missing)}"

# Examples copied from the book must stay identical to the book's own, so the skill
# never teaches code that the book's tests no longer cover.
bundled_from_book = ("05-packages", "13a-text-processing")
for name in bundled_from_book:
    canonical_example = ROOT / "docs/examples" / name
    bundled_example = skill / "examples" / name
    canonical_sources = {path.relative_to(canonical_example) for path in canonical_example.rglob("*.odin")}
    bundled_sources = {path.relative_to(bundled_example) for path in bundled_example.rglob("*.odin")}
    assert canonical_sources == bundled_sources, f"Bundled Odin source files differ from the book example: {name}"
    for relative_path in canonical_sources:
        assert (canonical_example / relative_path).read_bytes() == (bundled_example / relative_path).read_bytes(), (
            f"Bundled Odin source is out of sync: {name}/{relative_path}"
        )

with ZipFile(archive, "w", compression=ZIP_DEFLATED) as output:
    for file in sorted(skill.rglob("*")):
        if file.is_file():
            output.write(file, Path("odin-companion") / file.relative_to(skill))

with ZipFile(archive) as result:
    assert result.testzip() is None, "Skill archive failed CRC verification"
    names = set(result.namelist())
    assert all(f"odin-companion/{path}" in names for path in required)
print(f"Odin companion skill: {len(names)} files, {archive.stat().st_size} bytes")
