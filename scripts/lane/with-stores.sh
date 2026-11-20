#!/usr/bin/env bash
# with-stores.sh DIR COMMAND... : run COMMAND with the three cache variables of a guest build under DIR (XDG_CACHE_HOME=DIR/xdg,
# SELKA_CORE_RUNTIME_CACHE=DIR/rt, SELKA_STAGE_SHARED_CACHE=DIR/stage), on that command only. DIR is created. It refuses a DIR
# under ~/.cache or the folder it links to (the per-user stores a lane must never write) and unsets the caller's other store variables.
set -u
if [ $# -lt 2 ] || [ "$1" = -h ] || [ "$1" = --help ]; then
  echo "usage: with-stores.sh DIR COMMAND [ARG...]   (stores under DIR, set for COMMAND only; DIR never under ~/.cache)"
  [ "${1:-}" = -h ] || [ "${1:-}" = --help ] && exit 0; exit 2
fi
# The per-user stores live under ~/.cache/selka, which here is a symlink into ~/ai/.home-cache/mylang: refuse the logical path
# and the resolved one.
logical=$(realpath -m -s "$1"); d=$(realpath -m "$1"); shift
user_real=$(realpath -m "$HOME/.cache/selka")
for p in "$logical" "$d"; do
  case "$p/" in "$HOME/.cache/"*|"$user_real/"*) echo "with-stores.sh: $p is under ~/.cache (the per-user stores); pick a folder in your scratch" >&2; exit 2;; esac
done
mkdir -p "$d/xdg" "$d/rt" "$d/stage" || exit 2
exec env -u SELKA_COMPILER_SHARED_CACHE -u SELKA_TEST_SHARED_CACHE \
  XDG_CACHE_HOME="$d/xdg" SELKA_CORE_RUNTIME_CACHE="$d/rt" SELKA_STAGE_SHARED_CACHE="$d/stage" "$@"
