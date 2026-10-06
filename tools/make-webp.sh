#!/bin/bash
# =========================================================
# Сборка WebP для скриншотов лендинга.
#
# Источники:  screens/screen-<экран>_<локаль>.png
# Результат:  assets/img/screen-<экран>_<локаль>.webp
#
# Запуск из корня проекта:  tools/make-webp.sh
#
# Качество 85 при 1179×2556 даёт ~90–135 КБ на файл вместо ~0,9–1,1 МБ
# у PNG; при таком масштабе разница с исходником не видна даже в 1:1.
# Альфа-канал (скруглённые углы экспорта) сохраняется.
# =========================================================

set -euo pipefail

cd "$(dirname "$0")/.."
QUALITY="${QUALITY:-85}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "Нужен python3." >&2
  exit 1
fi

if ! python3 -c "import PIL" >/dev/null 2>&1; then
  cat >&2 <<'MSG'
Нужен Pillow — на нём держится конвертация, других кодировщиков
(cwebp, ImageMagick) скрипт не требует.

  python3 -m pip install --user Pillow
MSG
  exit 1
fi

shopt -s nullglob
SOURCES=(screens/screen-*.png)

if [ ${#SOURCES[@]} -eq 0 ]; then
  echo "В screens/ нет файлов screen-*.png — нечего собирать." >&2
  exit 1
fi

mkdir -p assets/img

QUALITY="$QUALITY" python3 - "${SOURCES[@]}" <<'PY'
import os
import sys
from PIL import Image

quality = int(os.environ["QUALITY"])
failed = 0

for src in sys.argv[1:]:
    name = os.path.basename(src)
    dst = os.path.join("assets/img", name[:-4] + ".webp")

    # Имя должно различать экран и локаль: screen-home_ru.png и т.п.
    if "_ru" not in name and "_en" not in name:
        print(f"  пропуск {name}: в имени нет локали _ru / _en")
        continue

    try:
        image = Image.open(src)
    except Exception as error:
        print(f"  ошибка {name}: {error}")
        failed += 1
        continue

    image.save(dst, "WEBP", quality=quality, method=6)

    with Image.open(dst) as check:
        if check.size != image.size:
            print(f"  ошибка {name}: размер поплыл ({check.size} вместо {image.size})")
            failed += 1
            continue

    print(f"  {name}  {os.path.getsize(src) / 1024:6.0f} КБ  ->  "
          f"{os.path.basename(dst)}  {os.path.getsize(dst) / 1024:5.0f} КБ  "
          f"{check.size[0]}×{check.size[1]}")

sys.exit(1 if failed else 0)
PY

echo
echo "Проверь страницу глазами: снимок мог быть сделан в другом разрешении —"
echo "тогда поправь aspect-ratio у .phone-screen в assets/site.css"
echo "и width/height у <img> в index.html и en/index.html."
