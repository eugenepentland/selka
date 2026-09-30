#!/usr/bin/env bash
# Default-value edits across modules: each incremental `--project` build must be
# byte-identical to a fresh `--whole-program` build. Usage: oracle.sh MYLANG
# Works on a copy under $TMPDIR (or /tmp); never edits this directory.
set -u
M=${1:?usage: oracle.sh /path/to/mylang}
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/default-oracle.XXXXXX")
cp "$here"/*.my "$work"/
cd "$work" || exit 2
fail=0
step() {
  r=$("$M" build main.my --project -o inc --cache-dir="$work/c" --report 2>&1); rc=$?
  comp=$(printf '%s' "$r" | grep -o '"module_build":{[^}]*}' | head -1)
  rm -rf "$work/w"
  "$M" build main.my --project --whole-program -o whole --cache-dir="$work/w" >/dev/null 2>&1; wc=$?
  if [ "$rc" -eq 0 ] && [ "$wc" -eq 0 ]; then
    if cmp -s inc whole; then m=MATCH; else m=DIFF; fail=1; fi
  else
    m="incremental=$rc whole=$wc"; [ "$rc" -eq "$wc" ] || fail=1
  fi
  echo "$1: $m $comp | output: $(./inc 2>&1 | tr '\n' ' ')"
}
step cold
sed -i 's/retries: int = 3/retries: int = 4/' shapes.my; step "record int default 3->4"
sed -i 's/label: str = "a"/label: str = "bb"/' shapes.my; step "record str default a->bb"
sed -i 's/factor: int = 2/factor: int = 3/' shapes.my; step "parameter default 2->3"
printf '\npublic record Unused:\n    z: int = 1\n' >> shapes.my; step "add unused public record"
sed -i 's/z: int = 1/z: int = 9/' shapes.my; step "unused record default 1->9"
echo "work dir: $work"
exit $fail
