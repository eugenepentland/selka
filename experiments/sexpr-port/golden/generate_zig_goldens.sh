#!/usr/bin/env bash
# Regenerate every golden in experiments/sexpr-port/golden/*.txt by running the
# REAL Zig S-expression printer from the sibling `eda` repo.
#
# The `eda` repo is treated as READ-ONLY: this script never writes inside it.
# Instead it materialises a build directory under /tmp holding nothing but a
# `src` symlink to "$EDA_ROOT/src" and a copy of golden/harness.zig, then runs
#
#   (cd "$TMP_DIR" && zig run harness.zig -- "$input")
#
# and captures stdout verbatim as the golden. See golden/harness.zig for why the
# symlink plus the root `process_io` declaration are required.
#
# Usage:
#   bash experiments/sexpr-port/golden/generate_zig_goldens.sh [--help]
#
# Environment:
#   EDA_ROOT               sibling Zig repo (default: /home/epentland/ai/canopy/eda)
#   SEXPR_GOLDEN_TMP       build dir          (default: /tmp/sexpr-golden)
#   SEXPR_GOLDEN_SKIP_LARGE=1  skip the two ~185 kB real EDA files
#
# Side effects, all inside this repo:
#   golden/<name>.txt      exact stdout bytes of the Zig printer for <input>
#   golden/manifest.tsv    "name<TAB>input-path" for golden_compare.py
#
# The input path in the manifest is relative to the repo root for in-repo
# fixtures and absolute for the two out-of-repo EDA files. The script is
# re-runnable: it rebuilds the /tmp directory from scratch and rewrites the
# manifest, then overwrites one .txt per input.

set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PORT_DIR="$REPO_ROOT/experiments/sexpr-port"
EDA_ROOT="${EDA_ROOT:-/home/epentland/ai/canopy/eda}"
TMP_DIR="${SEXPR_GOLDEN_TMP:-/tmp/sexpr-golden}"
MANIFEST="$SCRIPT_DIR/manifest.tsv"

case "${1:-}" in
    -h|--help)
        sed -n '2,34p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    "") ;;
    *) echo "error: unknown argument: $1 (try --help)" >&2; exit 2 ;;
esac

if ! command -v zig >/dev/null 2>&1; then
    echo "error: zig is not on PATH" >&2
    exit 2
fi
if [ ! -f "$EDA_ROOT/src/sexpr/printer.zig" ]; then
    echo "error: no eda printer at $EDA_ROOT/src/sexpr/printer.zig" >&2
    echo "       set EDA_ROOT to the sibling Zig checkout" >&2
    exit 2
fi

mkdir -p "$SCRIPT_DIR"
: > "$MANIFEST"

echo "==> building reference harness in $TMP_DIR"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
ln -s "$EDA_ROOT/src" "$TMP_DIR/src"
cp "$SCRIPT_DIR/harness.zig" "$TMP_DIR/harness.zig"
echo "    src -> $EDA_ROOT/src"

# Compile once up front so a harness compilation error is reported exactly once,
# before any golden is (over)written.
( cd "$TMP_DIR" && zig build-exe harness.zig -femit-bin="$TMP_DIR/harness" >/dev/null )

# golden_one NAME INPUT
#   runs the reference printer over INPUT (absolute) and writes golden/NAME.txt,
#   appending the repo-relative (or absolute) path to the manifest.
golden_one() {
    local name="$1" input="$2"
    if [ ! -f "$input" ]; then
        echo "    MISSING  $name <- $input (skipped)" >&2
        return 0
    fi
    "$TMP_DIR/harness" "$input" > "$SCRIPT_DIR/$name.txt"
    local bytes
    bytes="$(wc -c < "$SCRIPT_DIR/$name.txt" | tr -d ' ')"
    local mpath
    case "$input" in
        "$REPO_ROOT"/*) mpath="${input#"$REPO_ROOT"/}" ;;
        *) mpath="$input" ;;
    esac
    printf '%s\t%s\n' "$name" "$mpath" >> "$MANIFEST"
    printf '    golden  %-26s %9s bytes  <- %s\n' "$name.txt" "$bytes" "$mpath"
}

echo "==> writing goldens"
for f in "$PORT_DIR"/fixtures/layout/*.sexp; do
    golden_one "$(basename "$f" .sexp)" "$f"
done
golden_one units "$PORT_DIR/fixtures/units.sexp"
golden_one spi "$REPO_ROOT/experiments/schematic/fixtures/spi.sexp"
golden_one lmx2595rhar "$REPO_ROOT/experiments/schematic/fixtures/lmx2595rhar.sexp"
golden_one straps-synth-lmx2595 "$REPO_ROOT/experiments/schematic/fixtures/straps-synth-lmx2595.sexp"

if [ "${SEXPR_GOLDEN_SKIP_LARGE:-0}" = "1" ]; then
    echo "==> skipping large EDA files (SEXPR_GOLDEN_SKIP_LARGE=1)"
else
    golden_one poe-pd-flyback-tps23757 \
        "$EDA_ROOT/projects/designs/lib/modules/poe-pd-flyback-tps23757.sexp"
    golden_one remora-rf \
        "$EDA_ROOT/projects/designs/src/boards/remora-rf/remora-rf.sexp"
fi

echo "==> done: $(grep -c . "$MANIFEST" || true) goldens, manifest $MANIFEST"
