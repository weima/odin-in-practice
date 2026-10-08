"""Validate the generated reader without fetching external links."""
from __future__ import annotations
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit
import json
import re
import yaml
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / 'html'
config = yaml.safe_load((ROOT / 'mkdocs.yml').read_text())
site_prefix = urlsplit(config['site_url']).path

class Page(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.ids: set[str] = set()
        self.links: list[str] = []
        self.chapters: list[int] = []
        self.h2: list[str] | None = None
    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        ident = values.get('id')
        if ident:
            self.ids.add(ident)
        target = values.get('href') if tag == 'a' else values.get('src') if tag in ('img', 'script') else values.get('href') if tag == 'link' else None
        if target:
            self.links.append(target)
        if tag == 'h2':
            self.h2 = []
    def handle_data(self, data: str) -> None:
        if self.h2 is not None:
            self.h2.append(data)
    def handle_endtag(self, tag: str) -> None:
        if tag == 'h2' and self.h2 is not None:
            match = re.match(r'^(\d+)\.', ''.join(self.h2).strip())
            if match:
                self.chapters.append(int(match.group(1)))
            self.h2 = None

pages: dict[Path, Page] = {}
for file in sorted(SITE.rglob('*.html')):
    page = Page()
    page.feed(file.read_text())
    pages[file.resolve()] = page
errors: list[str] = []
for file, page in pages.items():
    for link in page.links:
        parts = urlsplit(link)
        if parts.scheme or parts.netloc or link.startswith('//'):
            continue
        path = unquote(parts.path)
        # MkDocs intentionally gives the hosted 404 page root-relative URLs.
        if file.name == '404.html' and path.startswith(site_prefix):
            destination = (SITE / path[len(site_prefix):]).resolve()
        else:
            destination = (file.parent / path).resolve() if path else file
        if destination.is_dir():
            destination /= 'index.html'
        if not destination.is_relative_to(SITE.resolve()):
            errors.append(f'{file.relative_to(SITE)}: outside reader: {link}')
        elif not destination.exists():
            errors.append(f'{file.relative_to(SITE)}: missing: {link}')
        elif parts.fragment and destination in pages and unquote(parts.fragment) not in pages[destination].ids:
            errors.append(f'{file.relative_to(SITE)}: missing anchor: {link}')
chapters = [n for file, page in pages.items() if file.parent == (SITE / 'chapters').resolve() for n in page.chapters]
if Counter(chapters) != Counter(range(1, 33)):
    errors.append(f'chapter headings are not exactly 1–32: {sorted(chapters)}')
legacy = json.loads((ROOT / 'tools/legacy-anchors.json').read_text())
for route, ids in legacy.items():
    page = pages.get((SITE / route).resolve())
    if page is None or not set(ids).issubset(page.ids):
        errors.append(f'legacy page or explicit anchor missing: {route}')
for file in (ROOT / 'docs/assets').rglob('*.svg'):
    ET.parse(file)
assert pages, 'No generated HTML found; build the book first'
assert not errors, '\n'.join(errors[:50])
print(f'{len(pages)} HTML pages: local links/assets/anchors pass; chapters 1–32 and SVG XML pass')
