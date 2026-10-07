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
    "examples/05-packages/README.md",
    "examples/05-packages/cli/main.odin",
    "examples/05-packages/label/label.odin",
)
missing = [path for path in required if not (skill / path).is_file()]
assert not missing, f"Skill bundle is incomplete: {', '.join(missing)}"

with ZipFile(archive, "w", compression=ZIP_DEFLATED) as output:
    for file in sorted(skill.rglob("*")):
        if file.is_file():
            output.write(file, Path("odin-companion") / file.relative_to(skill))

with ZipFile(archive) as result:
    assert result.testzip() is None, "Skill archive failed CRC verification"
    names = set(result.namelist())
    assert all(f"odin-companion/{path}" in names for path in required)
print(f"Odin companion skill: {len(names)} files, {archive.stat().st_size} bytes")
