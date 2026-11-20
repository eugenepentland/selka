#!/bin/sh
# build-site.sh: builds the documentation site into book/ the way the Pages workflow does (lane GH-8.1).
#
# `mdbook build` writes the pages, and also copies every file of docs/ that is not Markdown (the audits' scripts and data, the
# experiments' json) into the site beside them. Those files are not guides, so this script removes them again: what is left is
# the pages, the pictures of docs/images/ and mdBook's own files. `mdbook serve` is the live preview; it does not do this, and nothing is published from it.
#
# usage: scripts/build-site.sh     (mdbook on PATH, or MDBOOK=/path/to/mdbook)
set -eu
cd "$(dirname "$0")/.."
"${MDBOOK:-mdbook}" build
(cd docs && find . -type f ! -name '*.md' ! -path './images/*') | while IFS= read -r file; do
    rm -f "book/$file"
done
find book -depth -type d -empty -exec rmdir '{}' ';'
# docs/images/ holds the guides' pictures and stays. The introduction is README.md, whose picture paths start at the
# repository root (docs/images/...), so the pictures are also put where those paths lead from the site's root.
mkdir -p book/docs
cp -R docs/images book/docs/images
echo "site written to book/"
