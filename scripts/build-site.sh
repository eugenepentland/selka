#!/bin/sh
# build-site.sh: builds the documentation site into book/ the way the Pages workflow does (lane GH-8.1).
#
# `mdbook build` writes the pages, and also copies every file of docs/ that is not Markdown (the audits' scripts and data, the
# experiments' json) into the site beside them. Those files are not guides, so this script removes them again: what is left is
# the pages and mdBook's own files. `mdbook serve` is the live preview; it does not do this, and nothing is published from it.
#
# usage: scripts/build-site.sh     (mdbook on PATH, or MDBOOK=/path/to/mdbook)
set -eu
cd "$(dirname "$0")/.."
"${MDBOOK:-mdbook}" build
(cd docs && find . -type f ! -name '*.md') | while IFS= read -r file; do
    rm -f "book/$file"
done
find book -depth -type d -empty -exec rmdir '{}' ';'
echo "site written to book/"
