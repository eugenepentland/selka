#!/bin/sh
# A 3-module project: main -> b -> a. `b.total` uses record a.Leaf only inside its body. A cold
# module build succeeds; after a defaulted field is added to a.Leaf the incremental
# module-by-module build fails with `mylang: host failure: InvalidNativeManifest` (exit 2)
# while `--whole-program` builds the same tree fine.
# usage: repro.sh COMPILER [WORKDIR] [--gc-runtime]     (fails the same way with and without)
set -u
M=$1; W=${2:-/tmp/invalid-native-manifest}; EXTRA=${3:-}
rm -rf "$W"; mkdir -p "$W"; cd "$W"
cat > a.my <<'SRC'
module a

public record Leaf:
    x: int
    name: bytes

public def make_leaf(v: int) -> Leaf:
    return Leaf(x=v, name=b"a")
SRC
cat > b.my <<'SRC'
module b
import a

public def total(v: int) -> int:
    leaf = a.make_leaf(v)
    return leaf.x + len(leaf.name)
SRC
cat > main.my <<'SRC'
module main
import b

def main() -> int:
    return b.total(3)
SRC
echo "== cold module build"
"$M" build main.my --project -o inc --cache-dir=cache --report $EXTRA 2>&1 | grep -o '"module_build":{[^}]*}'
sed -i 's/^    name: bytes$/    name: bytes\n    extra: int = 0/' a.my
echo "== incremental module build after adding 'extra: int = 0' to a.Leaf"
"$M" build main.my --project -o inc --cache-dir=cache --report $EXTRA 2>&1 | grep -o '"module_build":{[^}]*}\|mylang: host failure.*'
echo "== whole-program build of the same tree"
"$M" build main.my --project --whole-program -o whole --cache-dir=cache-whole $EXTRA >/dev/null 2>&1 && echo "built ok" || echo "FAILED"
