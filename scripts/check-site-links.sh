#!/bin/sh
# check-site-links.sh: every relative link in the built documentation site must reach a file (lane GH-8.1).
#
# Reads each `href="..."` and `src="..."` attribute of the tags of every .html file under SITE_DIR (code shown on a page is
# escaped, so an example `<a href=...>` in a guide is text, not a link). A link to another site (http:, https:, mailto: and
# the like) and a bare `#fragment` are not checked; a path is resolved from the page that holds it (a path that starts with
# SITE_URL, default /selka/, from the site's root), its `#fragment` and `?query` dropped, and a folder means its index.html.
# Prints one line for each link that reaches nothing, then the counts, and exits 1 if there was any. Fragments are not checked.
#
# usage: scripts/check-site-links.sh [SITE_DIR]      (default book, where scripts/build-site.sh writes the site)
set -eu
site=${1:-book}
site_url=${SITE_URL:-/selka/}
test -d "$site" || { echo "check-site-links: no folder $site (run scripts/build-site.sh first)" >&2; exit 2; }

root=$(cd "$site" && pwd -P)
pairs=$(mktemp)
trap 'rm -f "$pairs"' EXIT
tab=$(printf '\t')
find "$site" -name '*.html' | sort | while IFS= read -r page; do
    grep -oE '<[a-zA-Z][^>]*>' "$page" | grep -oE ' (href|src)="[^"]*"' | sed -E 's/^ (href|src)="//; s/"$//' | sort -u |
        awk -v page="$page" '{ print page "\t" $0 }'
done > "$pairs"

pages=$(find "$site" -name '*.html' | wc -l)
links=0
broken=0
dir=
last=
while IFS=$tab read -r page link; do
    case $link in
        '' | '#'* | //*) continue ;;
    esac
    case ${link%%[#?/]*} in
        *:*) continue ;;
    esac
    links=$((links + 1))
    target=${link%%[#?]*}
    case $target in
        "$site_url"*) path=$site/${target#"$site_url"} ;;
        /*) path=/nonexistent/outside-site-url ;;
        *)
            test "$page" = "$last" || { dir=$(dirname "$page"); last=$page; }
            path=$dir/$target
            ;;
    esac
    case $target in
        *..*) # a path that climbs out of the site reaches the repository, not the site
            real=$(cd "$(dirname "$path")" 2>/dev/null && pwd -P) || real=
            case $real/ in
                "$root"/*) ;;
                *) path=/nonexistent/outside-site ;;
            esac
            ;;
    esac
    if [ -f "$path" ] || { [ -d "$path" ] && [ -f "$path/index.html" ]; }; then
        continue
    fi
    broken=$((broken + 1))
    echo "$page: link \"$link\" reaches no file"
done < "$pairs"

echo "check-site-links: $links relative links in $pages pages, $broken broken"
test "$broken" -eq 0
