#!/bin/sh
# The brief's reproduction: cold build, add a private function to the Lox
# port's leaf module `value`, then edit its body; prints each build's
# module_build counts and wall time. usage: repro.sh COMPILER SOURCE WORK
set -eu
M=$1; S=$2; P=$3
rm -rf "$P"; mkdir -p "$P"; cp -r "$S"/. "$P"/; cd "$P"
step() {
  start=$(date +%s.%N)
  counts=$("$M" build main.my --project -o lox --cache-dir=c --report 2>&1 | grep -o '"module_build":{[^}]*}')
  end=$(date +%s.%N)
  printf '%s %s %.3fs\n' "$1" "$counts" "$(echo "$end - $start" | bc)"
}
step cold
printf '\ndef probe_edit() -> int:\n    return 0\n' >> value.my
step add-private
sed -i '$s/return .*/return 11/' value.my
step body-edit
sed -i '$s/return .*/return 12/' value.my
step body-edit-2
sed -i '$s/return .*/return 13/' value.my
step body-edit-3
