#!/usr/bin/env bash
set -euo pipefail

eda_worktree=${EDA_WORKTREE:-/home/epentland/ai/canopy/eda/.claude/worktrees/mylang-svg-benchmark-20260921}
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
out=${OUT_DIR:-$repo_root/.tmp/full-svg-benchmark-20260921}
zig=${ZIG:-/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig}
embed=$out/stdlib-embed

mkdir -p "$out/cache-fast" "$out/cache-safe" "$out/global-cache" "$embed"
cp "$repo_root/experiments/full-svg-benchmark/netlisp_bench.zig" "$eda_worktree/src/netlisp_bench.zig"
cat > "$out/build_options.zig" <<'EOF'
pub const build_id: ?[]const u8 = null;
EOF

python3 - "$eda_worktree/stdlib" "$embed" <<'PY'
from pathlib import Path
import shutil, sys
source, output = map(Path, sys.argv[1:])
paths = sorted(path.relative_to(source) for path in source.rglob("*.sexp"))
lines = [
    "pub const Entry = struct { path: []const u8, bytes: []const u8 };",
    "pub const entries = [_]Entry{",
]
for relative in paths:
    destination = output / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source / relative, destination)
    name = relative.as_posix()
    lines.append(f'    .{{ .path = "lib/{name}", .bytes = @embedFile("{name}") }},')
lines.append("};")
(output / "stdlib_embed.zig").write_text("\n".join(lines) + "\n")
PY

build_one() {
    mode=$1
    suffix=$2
    ZIG_GLOBAL_CACHE_DIR="$out/global-cache" \
    ZIG_LOCAL_CACHE_DIR="$out/cache-$suffix" \
    "$zig" build-exe -fllvm "-O$mode" \
        --dep build_options --dep stdlib_embed \
        -Mroot=src/netlisp_bench.zig \
        -Mbuild_options="$out/build_options.zig" \
        -Mstdlib_embed="$embed/stdlib_embed.zig" \
        -femit-bin="$out/netlisp-llvm-$suffix" \
        >"$out/netlisp-llvm-$suffix.build.stdout" \
        2>"$out/netlisp-llvm-$suffix.build.stderr"
}

cd "$eda_worktree"
build_one ReleaseFast fast
build_one ReleaseSafe safe
