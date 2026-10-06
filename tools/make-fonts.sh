#!/bin/bash
# =========================================================
# Сборка WebP-шрифтов для лендинга.
#
# Источники:  fonts/*.ttf          (копия из rallyiOS/fonts)
# Результат:  assets/fonts/*.woff2
#
# Запуск из корня проекта:  tools/make-fonts.sh
#
# Что делает: конвертирует TTF в woff2 (сжатие Brotli) и заодно
# вырезает из Inter греческий, вьетнамский и прочие наборы, которых
# на странице нет, — остаются латиница, кириллица и пунктуация.
# Вид текста не меняется: те же файлы, те же начертания.
#
# Требует fonttools и brotli:  python3 -m pip install --user fonttools brotli
# =========================================================

set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v python3 >/dev/null 2>&1; then
  echo "Нужен python3." >&2
  exit 1
fi

if ! python3 -c "import fontTools, brotli" >/dev/null 2>&1; then
  cat >&2 <<'MSG'
Нужны fonttools и brotli:

  python3 -m pip install --user fonttools brotli
MSG
  exit 1
fi

shopt -s nullglob
SOURCES=(fonts/*.ttf)

if [ ${#SOURCES[@]} -eq 0 ]; then
  echo "В fonts/ нет файлов *.ttf — нечего собирать." >&2
  exit 1
fi

mkdir -p assets/fonts

python3 - "${SOURCES[@]}" <<'PY'
import os
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

# Латиница, латиница-1 (в ней « » · × § ©), кириллица и кириллица-доп.,
# общая пунктуация (— – « » “ ”), № и ₽. Всё, что реально встречается
# на страницах, проверено: вне этих диапазонов символов нет.
INTER = "U+0000-00FF,U+0400-04FF,U+0500-052F,U+2000-206F,U+2116,U+20BD"

# Space Grotesk стоит только на цифрах: номера шагов и значения метрик.
# Поэтому ему хватает цифр, разделителей и тире-заглушки.
DIGITS = "U+0020-0039,U+0025,U+002B-002F,U+003A,U+00A0,U+2000-206F,U+2212"

# Чем проверяем результат: каждый символ обязан найтись в готовом файле.
INTER_PROBE = "AaZz09.,;:!?—–«»“”№ЁёЯя§©·×₽"
DIGITS_PROBE = "0123456789.,—%"

PLAN = {
    "Inter-Regular.ttf": (INTER, INTER_PROBE),
    "Inter-Medium.ttf": (INTER, INTER_PROBE),
    "Inter-SemiBold.ttf": (INTER, INTER_PROBE),
    "SpaceGrotesk-Variable.ttf": (DIGITS, DIGITS_PROBE),
}

failed = 0

for src in sys.argv[1:]:
    name = os.path.basename(src)

    if name not in PLAN:
        print(f"  пропуск {name}: нет правил сабсета для этого файла")
        continue

    unicodes, probe = PLAN[name]
    dst = os.path.join("assets/fonts", name[:-4] + ".woff2")

    try:
        subset.main([
            src,
            f"--unicodes={unicodes}",
            "--flavor=woff2",
            f"--output-file={dst}",
        ])
    except Exception as error:
        print(f"  ошибка {name}: {error}")
        failed += 1
        continue

    # Проверяем, что после сабсета все нужные символы на месте: молча
    # вырезанная буква выглядит как подмена шрифта в одном слове.
    with TTFont(dst) as font:
        cmap = font.getBestCmap()
        missing = [c for c in probe if ord(c) not in cmap]
        glyphs = len(font.getGlyphOrder())

    if missing:
        print(f"  ОШИБКА {name}: потеряны символы {''.join(missing)!r}")
        failed += 1
        continue

    print(f"  {name:28} {os.path.getsize(src) / 1024:6.0f} КБ  ->  "
          f"{os.path.basename(dst):28} {os.path.getsize(dst) / 1024:5.0f} КБ  "
          f"{glyphs} глифов")

sys.exit(1 if failed else 0)
PY

echo
echo "Проверь страницу глазами: если сабсет срезал нужный символ, он"
echo "подменится системным шрифтом — это видно на одном слове, не на всём тексте."
