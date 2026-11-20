#!/usr/bin/env bash
# precommit.sh: was the commit hook's Guardian check, run without committing. Guardian was turned off on
# 18 November 2026 (lane GH-2), so there is nothing to check; the script stays because lane cards and
# `scripts/lane/handback.sh` still call it. It prints one line and exits 0, whatever its arguments.
echo "Guardian is off since GH-2; nothing to check"
exit 0
