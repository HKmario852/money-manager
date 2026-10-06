"""Check that every relative link and image in the README files points to an existing file.

    python tool/check_doc_links.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FILES = [ROOT / "README.md", ROOT / "docs" / "DEVELOPMENT.md", *sorted((ROOT / "docs" / "i18n").glob("README.*.md"))]
LINK = re.compile(r"""\]\(([^)\s]+)\)|(?:src|href)="([^"]+)\"""")

missing = 0
checked = 0
for md in FILES:
    for m in LINK.finditer(md.read_text(encoding="utf-8")):
        target = m.group(1) or m.group(2)
        if re.match(r"^[a-z]+:|^#|^//", target):
            continue
        checked += 1
        path = (md.parent / target.split("#")[0]).resolve()
        if not path.exists():
            missing += 1
            print(f"{md.relative_to(ROOT)}: missing {target}")

print(f"{checked} relative links in {len(FILES)} files, {missing} missing")
sys.exit(1 if missing else 0)
