#!/bin/sh
# Self-test compiler for edit_fuzz.py: runs the real compiler ($REAL_MYLANG) but corrupts the
# incremental executable (one appended byte) whenever a project source holds a `fz_a<N>` name,
# i.e. once a start-alloc edit has been applied. The fuzzer must report a mismatch, save a
# reproducer, and --minimize must shrink it to that one edit.
#   REAL_MYLANG=/path/to/mylang edit_fuzz.py --compiler ./sabotage.sh ...
"$REAL_MYLANG" "$@"
status=$?
out=""
prev=""
for arg in "$@"; do
  [ "$prev" = "-o" ] && out=$arg
  [ "$arg" = "--whole-program" ] && exit $status
  prev=$arg
done
if [ $status -eq 0 ] && [ -n "$out" ] && grep -qs 'fz_a[0-9]' ./*.my; then
  printf 'x' >> "$out"
fi
exit $status
