#!/usr/bin/env bash
# Exit 0 when the log's `Build Summary:` line reports every step succeeded (N/N, N > 0).
awk '/^Build Summary:/ { split($3, a, "/"); if (a[1] == a[2] && a[1] > 0) ok = 1 } END { exit !ok }' "$1"
