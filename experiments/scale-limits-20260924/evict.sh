#!/usr/bin/env bash
# Frontend cache receipts at one tier: an edit check, then an unchanged edit-and-revert check,
# printing the evicted/retained fields. Usage: evict.sh WORKDIR COMPILER
set -u
work=$1
compiler=$2
export TMPDIR=/home/epentland/.cache/mylang-tmp
cd "$work"
mid=$3
receipt() { grep -o '"syntax_hits":[0-9]*\|"syntax_stored":[0-9]*\|"verdict_hits":[0-9]*\|"evicted":[0-9]*,"retained_bytes":[0-9]*' | head -4 | tr '\n' ' '; echo; }
sed -i 's/+ 7[0-9]*) *# EDIT_BODY/+ 7777)  # EDIT_BODY/' "$mid"
echo "edit check:      $("$compiler" check main.my --report 2>&1 | receipt)"
echo "unchanged check: $("$compiler" check main.my --report 2>&1 | receipt)"
sed -i 's/+ 7777) *# EDIT_BODY/+ 7778)  # EDIT_BODY/' "$mid"
echo "edit check 2:    $("$compiler" check main.my --report 2>&1 | receipt)"
du -sh .mylang-cache/frontend 2>/dev/null
