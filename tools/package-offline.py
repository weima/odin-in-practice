"""Package the prebuilt reader; never include the archive inside itself."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parents[1]
reader = root / 'html'
archive = reader / 'odin-in-practice-offline.zip'
assert (reader / 'index.html').is_file(), 'Build the reader first'
with ZipFile(archive, 'w', compression=ZIP_DEFLATED) as output:
    for file in sorted(reader.rglob('*')):
        if file.is_file() and file != archive:
            output.write(file, Path('odin-in-practice') / file.relative_to(reader))
with ZipFile(archive) as result:
    assert result.testzip() is None
    count = len(result.namelist())
print(f'Offline reader: {count} files, {archive.stat().st_size} bytes')
