#!/bin/sh
# check-site-pages.sh: the documentation site holds the user guides and nothing else (lane GH-8.1).
#
# 1. docs/SUMMARY.md, the book's table of contents, names exactly the pages `src/user_docs.zig` lists (`selka docs` prints them)
#    and docs/introduction.md; a guide added to the list without a line in SUMMARY.md would never be published.
# 2. SITE_DIR has the .html page of each of them, and no file that docs/ holds beside its Markdown (the audits and experiments).
# Prints one line for each fault, then the page count, and exits 1 if there was any.
#
# usage: scripts/check-site-pages.sh [SITE_DIR]      (default book, where scripts/build-site.sh writes the site)
set -eu
export LC_ALL=C # sort and comm must agree
cd "$(dirname "$0")/.."
site=${1:-book}
test -d "$site" || { echo "check-site-pages: no folder $site (run scripts/build-site.sh first)" >&2; exit 2; }
listed=$(mktemp)
summarised=$(mktemp)
strays=$(mktemp)
trap 'rm -f "$listed" "$summarised" "$strays"' EXIT
sed -n 's|.*\.path = "docs/\([^"]*\)".*|\1|p' src/user_docs.zig | sort > "$listed"
sed -n 's|^.*](\([^)]*\.md\))$|\1|p' docs/SUMMARY.md | grep -v '^introduction\.md$' | sort > "$summarised"

faults=0
fault() {
    echo "$1"
    faults=$((faults + 1))
}
for page in $(comm -23 "$listed" "$summarised"); do
    fault "docs/$page is listed in src/user_docs.zig but not in docs/SUMMARY.md"
done
for page in $(comm -13 "$listed" "$summarised"); do
    fault "docs/SUMMARY.md names docs/$page, which src/user_docs.zig does not list"
done
for page in introduction.md $(cat "$listed"); do
    test -f "$site/${page%.md}.html" || fault "$site/${page%.md}.html is missing: the site lacks docs/$page"
done
(cd docs && find . -type f ! -name '*.md') | while IFS= read -r file; do
    test ! -e "$site/$file" || echo "$site/$file is a docs/ file that is not a guide"
done > "$strays"
while IFS= read -r line; do
    fault "$line"
done < "$strays"

echo "check-site-pages: $(($(wc -l < "$listed") + 1)) pages (the guides and the introduction), $faults faults"
test "$faults" -eq 0
