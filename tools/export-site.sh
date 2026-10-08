#!/bin/bash
# Публичный набор файлов в dist/.
# Исходники screens/, fonts/, tools/ и неиспользуемый logo-512.png
# в выгрузку не входят: на страницах они не нужны.

set -euo pipefail

cd "$(dirname "$0")/.."

rm -rf dist
mkdir -p dist/en

cp index.html 404.html robots.txt sitemap.xml dist/
cp en/index.html dist/en/index.html
rsync -a --exclude '.DS_Store' --exclude 'logo-512.png' assets/ dist/assets/

python3 - <<'PY'
from html.parser import HTMLParser
from pathlib import Path

class Seo(HTMLParser):
    def __init__(self):
        super().__init__()
        self.tags = []

    def handle_starttag(self, tag, attrs):
        d = dict(attrs)
        if tag == "link" and d.get("rel") in ("canonical", "alternate"):
            self.tags.append(d["rel"])
        if tag == "meta" and d.get("property") == "og:image":
            self.tags.append("og:image")

for path in ("dist/index.html", "dist/en/index.html"):
    parser = Seo()
    parser.feed(Path(path).read_text(encoding="utf-8"))
    missing = [name for name in ("canonical", "alternate", "og:image") if name not in parser.tags]
    if missing:
        raise SystemExit(f"{path}: нет тегов {', '.join(missing)}")

root = Path("dist")
banned = [p for p in root.rglob("*") if p.name in {".DS_Store", "logo-512.png"} or p.suffix == ".ttf"]
if banned:
    raise SystemExit("в dist попало лишнее: " + ", ".join(str(p) for p in banned))
print("dist готов, seo-теги на месте")
PY
