#!/bin/bash
# Заливка dist/ на Cloudflare Pages.
#
# Токен и id аккаунта — в .env в корне репозитория (файл в gitignore):
#   CLOUDFLARE_API_TOKEN=...
#   CLOUDFLARE_ACCOUNT_ID=...
#
# Права токена: Account / Cloudflare Pages / Edit,
# Account / Account Settings / Read,
# Zone / Zone / Read и Zone / DNS / Edit на зону advantace.app.

set -euo pipefail

cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
  echo "Нет CLOUDFLARE_API_TOKEN. Создай .env по .env.example и не коммить его." >&2
  exit 1
fi

if [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
  echo "Нет CLOUDFLARE_ACCOUNT_ID. Он на обзоре зоны advantace.app, справа." >&2
  exit 1
fi

tools/export-site.sh

if command -v wrangler >/dev/null 2>&1; then
  wrangler pages deploy dist --project-name=advantace --branch=main --commit-dirty=true
else
  npx --yes wrangler@4 pages deploy dist --project-name=advantace --branch=main --commit-dirty=true
fi
