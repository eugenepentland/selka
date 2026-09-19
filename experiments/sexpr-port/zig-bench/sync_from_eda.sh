#!/usr/bin/env bash
# Re-vendor the sexpr closure this benchmark project builds.
#
# The `eda` checkout is treated as READ-ONLY: this only copies files out of it.
# Re-run after changing the Zig reader so the benchmark keeps compiling exactly
# what the goldens compare against.
#
#   EDA_ROOT=/path/to/eda bash sync_from_eda.sh
set -euo pipefail

EDA_ROOT="${EDA_ROOT:-/home/epentland/ai/canopy/eda}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$EDA_ROOT/src/sexpr/printer.zig" ]; then
    echo "error: no eda sexpr reader under $EDA_ROOT" >&2
    exit 2
fi

cp "$EDA_ROOT/src/sexpr/ast.zig" \
   "$EDA_ROOT/src/sexpr/tokenizer.zig" \
   "$EDA_ROOT/src/sexpr/parser.zig" \
   "$EDA_ROOT/src/sexpr/printer.zig" \
   "$DIR/src/sexpr/"
cp "$EDA_ROOT/src/infra/fs.zig" "$DIR/src/infra/"

git -C "$EDA_ROOT" rev-parse HEAD > "$DIR/EDA_REVISION"
echo "vendored sexpr closure from $EDA_ROOT @ $(cat "$DIR/EDA_REVISION")"
