#!/bin/sh

set -eu

app_root="${APP_ROOT:-/app}"

# Remove a Vite marker left behind by an interrupted host-side dev server.
rm -f "${app_root}/public/hot"

exec php-fpm -F
