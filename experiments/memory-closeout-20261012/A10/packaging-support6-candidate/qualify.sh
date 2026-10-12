#!/usr/bin/env bash
# Run only after the coordinator accepts A08's initial Support6 Debug component
# qualification. This provisions the one independent ReleaseFast compiler; it
# does not select a package default or rewrite the immutable historical seed.
set -euo pipefail
if [[ $# -ne 2 ]]; then
    echo 'usage: qualify.sh FROZEN_SUPPORT6_TREE CACHE_ISOLATED_COMPONENT_BUILDER' >&2
    exit 2
fi
A10_PACKAGE_SOURCE=$(realpath "$1")
A10_PACKAGE_BUILDER=$(realpath "$2")
A10_PACKAGE_EVIDENCE=$(cd -- "$(dirname -- "$0")" && pwd)
A10_PACKAGE_WORKER=$(git -C "$A10_PACKAGE_EVIDENCE" rev-parse --show-toplevel)
A10_PACKAGE_PRIVATE="$A10_PACKAGE_WORKER/.tmp/memory-closeout/A10/owned-pin-support6-5167c588"
A10_PACKAGE_PIN="$A10_PACKAGE_EVIDENCE/candidate-pin.json"
A10_PACKAGE_ARCHIVE="$A10_PACKAGE_PRIVATE/source.tar"
A10_PACKAGE_PREFIX="$A10_PACKAGE_PRIVATE/install"
cd "$A10_PACKAGE_SOURCE"
source /home/epentland/.config/mylang/dev-env.sh
export MYLANG_COMPONENT_CACHE="$A10_PACKAGE_PRIVATE/component-cache"
python3 -B - "$A10_PACKAGE_PIN" "$A10_PACKAGE_ARCHIVE" "$A10_PACKAGE_EVIDENCE/preparation.json" "$A10_PACKAGE_SOURCE" <<'PY'
import hashlib, json, pathlib, subprocess, sys
pin = json.loads(pathlib.Path(sys.argv[1]).read_text())
with pathlib.Path(sys.argv[2]).open('rb') as source:
    assert hashlib.file_digest(source, 'sha256').hexdigest() == pin['archive_sha256']
evidence = json.loads(pathlib.Path(sys.argv[3]).read_text())
root = pathlib.Path(sys.argv[4])
assert subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip() == pin['commit']
assert not subprocess.check_output(['git', '-C', str(root), 'status', '--porcelain', '--untracked-files=all'], text=True).strip()
assert pin['commit'] == evidence['source_revision']
guardian = root.parent / 'guardian-zig'
assert subprocess.check_output(['git', '-C', str(guardian), 'rev-parse', 'HEAD'], text=True).strip() == evidence['guardian_revision']
assert not subprocess.check_output(['git', '-C', str(guardian), 'status', '--porcelain', '--untracked-files=all'], text=True).strip()
for name, digest in evidence['source_paths_sha256'].items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, name
PY
scripts/build-slot.sh build "$A10_PACKAGE_BUILDER" \
    --root "$A10_PACKAGE_SOURCE" --zig "$ZIG" \
    --cache-dir "$MYLANG_COMPONENT_CACHE" \
    --install-dir "$A10_PACKAGE_PREFIX/libexec/mylang/components" \
    --owned-compiler-pin "$A10_PACKAGE_PIN" --seed-source "$A10_PACKAGE_ARCHIVE"
scripts/build-slot.sh build python3 -B selfhost/test_component_native.py \
    --zig "$ZIG" --builder "$A10_PACKAGE_BUILDER" \
    --component-dir "$A10_PACKAGE_PREFIX/libexec/mylang/components" \
    --owned-compiler-pin "$A10_PACKAGE_PIN" --seed-source "$A10_PACKAGE_ARCHIVE"
