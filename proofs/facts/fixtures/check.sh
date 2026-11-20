#!/bin/sh
# Run the Lean checker on every fixture and compare its verdict lines with the `.expected` file beside it.
# Usage: sh fixtures/check.sh   (from proofs/facts, after `lake build`)
set -u
cd "$(dirname "$0")/.."
status=0
for f in fixtures/*.fact-certificate; do
  base=${f%.fact-certificate}
  got=$(.lake/build/bin/factcheck "$f" | grep -v '^summary' | sed 's|^[^ ]* ||')
  want=$(cat "$base.expected")
  if [ "$got" != "$want" ]; then
    echo "FAIL $f"
    echo "  want: $want"
    echo "  got:  $got"
    status=1
  fi
done
[ $status -eq 0 ] && echo "fixtures ok"
exit $status
