#!/bin/bash
# =========================================================
# Подстановка домена: закрывает деплой-подготовку одной командой.
#
# Запуск из корня проекта:
#   tools/set-domain.sh https://example.com
#
# Что делает:
#   1. в index.html и en/index.html подставляет домен в блок между
#      SITE-URL:BEGIN и SITE-URL:END
#      (og:url, og:image, twitter:card, canonical, hreflang, JSON-LD)
#      и снимает HTML-комментарий, если блок им обёрнут;
#   2. создаст robots.txt и sitemap.xml с абсолютными адресами.
#
# Скрипт можно запускать повторно — например, при переезде с
# github.io на свой домен: он заменит прежний адрес на новый.
#
# Маркеры стоят на отдельных строках. Содержимое между ними — рабочий
# HTML. Комментарий вокруг тегов скрипт снимает: раньше он смотрел
# только на первую строку блока и оставлял canonical внутри <!-- -->.
# =========================================================

set -euo pipefail

cd "$(dirname "$0")/.."

if [ $# -ne 1 ]; then
  echo "Использование: tools/set-domain.sh https://example.com" >&2
  exit 1
fi

SITE_URL="${1%/}"

case "$SITE_URL" in
  https://*|http://*) ;;
  *) echo "Адрес должен начинаться с https:// или http://" >&2; exit 1 ;;
esac

case "$SITE_URL" in
  https://|http://) echo "Адрес пустой: нужен домен, например https://swingsync.app" >&2; exit 1 ;;
esac

SITE_URL="$SITE_URL" python3 - <<'PY'
import os
import re
import sys
from urllib.parse import urlparse

site = os.environ["SITE_URL"]
BEGIN = "SITE-URL:BEGIN"
END = "SITE-URL:END"

# Для GitHub Pages вида https://user.github.io/repo/ пути в robots.txt должны
# включать подпапку репозитория: Disallow: /preview/ там ни на что не действует,
# потому что сайт живёт не в корне домена.
prefix = urlparse(site).path.rstrip("/")


def process(path, locale):
    """locale — путь локали внутри сайта: '/' для ru, '/en/' для en."""
    lines = open(path, encoding="utf-8").read().split("\n")

    try:
        begin = next(i for i, l in enumerate(lines) if BEGIN in l)
        end = next(i for i, l in enumerate(lines) if END in l)
    except StopIteration:
        sys.exit(f"{path}: не найден блок {BEGIN}…{END}")

    block = lines[begin + 1:end]
    # Комментарий может начинаться не с первой строки блока
    # (так и было: пояснение закрывалось на -->, а теги оставались внутри).
    kept = []
    for line in block:
        stripped = line.strip()
        if stripped in ("<!--", "-->"):
            continue
        if stripped.startswith("<!--") and stripped.endswith("-->"):
            continue
        kept.append(line)

    # Заглушку меняем на первом запуске, прежний адрес — при повторном.
    if any("__SITE_URL__" in l for l in kept):
        kept = [l.replace("__SITE_URL__", site) for l in kept]
        mode = "подставлен домен"
    else:
        canonical = None
        for l in kept:
            match = re.search(r'rel="canonical" href="([^"]+)"', l)
            if match:
                canonical = match.group(1)
                break
        if not canonical or not canonical.endswith(locale):
            sys.exit(f"{path}: не нашёл прежний canonical с путём {locale}")

        # Меняем только базовую часть: путь локали должен остаться на месте,
        # иначе /en/ при переезде превратится в корень.
        previous_base = canonical[:-len(locale)]
        kept = [l.replace(previous_base, site) for l in kept]
        mode = f"заменён прежний адрес {previous_base}"

    if any("__SITE_URL__" in l for l in kept):
        sys.exit(f"{path}: осталась заглушка __SITE_URL__")

    open(path, "w", encoding="utf-8").write(
        "\n".join(lines[:begin + 1] + kept + lines[end:])
    )

    live = [l for l in kept if l.strip() and not l.strip().startswith("<!--")]
    print(f"  {path}: {mode}, рабочих строк — {len(live)}")


for path, locale in (("index.html", "/"), ("en/index.html", "/en/")):
    process(path, locale)

robots = f"""User-agent: *
Allow: /

# Эти папки на сайте не используются: fonts/ и tools/ — исходники,
# screens/ и preview/ — материалы для сборки и ревью. При деплое их
# копировать не нужно, но если уедут — пусть не попадают в индекс.
Disallow: {prefix}/fonts/
Disallow: {prefix}/tools/
Disallow: {prefix}/screens/
Disallow: {prefix}/preview/

Sitemap: {site}/sitemap.xml
"""
open("robots.txt", "w", encoding="utf-8").write(robots)

alternates = f"""    <xhtml:link rel="alternate" hreflang="ru" href="{site}/"/>
    <xhtml:link rel="alternate" hreflang="en" href="{site}/en/"/>
    <xhtml:link rel="alternate" hreflang="x-default" href="{site}/"/>"""

sitemap = f"""<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
        xmlns:xhtml="http://www.w3.org/1999/xhtml">
  <url>
    <loc>{site}/</loc>
{alternates}
  </url>
  <url>
    <loc>{site}/en/</loc>
{alternates}
  </url>
</urlset>
"""
open("sitemap.xml", "w", encoding="utf-8").write(sitemap)
print("  создано: robots.txt, sitemap.xml")

from html.parser import HTMLParser

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
        if tag == "meta" and d.get("name") == "twitter:card":
            self.tags.append("twitter:card")

for path in ("index.html", "en/index.html"):
    parser = Seo()
    parser.feed(open(path, encoding="utf-8").read())
    for need in ("canonical", "alternate", "og:image", "twitter:card"):
        if need not in parser.tags:
            sys.exit(f"{path}: тег {need} не виден парсеру — блок SITE-URL внутри комментария")
    print(f"  {path}: парсер видит canonical, hreflang, og:image")
PY

echo
echo "Проверка:"
if grep -rn "__SITE_URL__" index.html en/index.html robots.txt sitemap.xml; then
  echo "  ОШИБКА: остались заглушки" >&2
  exit 1
fi
echo "  заглушек не осталось"
echo "  canonical (ru): $(grep -o 'rel="canonical" href="[^"]*"' index.html | head -1 | sed 's/.*href="//;s/"//')"
echo "  canonical (en): $(grep -o 'rel="canonical" href="[^"]*"' en/index.html | head -1 | sed 's/.*href="//;s/"//')"
echo "  адресов в sitemap: $(grep -c '<loc>' sitemap.xml)"
echo
echo "Дальше: открыть страницу локально, затем проверить превью ссылки в Telegram —"
echo "он кеширует его надолго, поэтому лучше убедиться сразу."
