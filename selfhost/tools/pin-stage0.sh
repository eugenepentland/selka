#!/bin/sh
# Record the freshly built stage-0 binary in selfhost/stage0-pin.json.
#
# The binary (and its `qbe` sibling) must already be installed in the shared
# content-addressed cache by selfhost/tools/build-stage0.sh.  This script
# verifies the cached artifact, then rewrites the pin; it never builds, copies,
# or overwrites the artifact.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root_dir=$(CDPATH='' cd -- "$script_dir/../.." && pwd)
binary="$root_dir/zig-out/bin/selka"
qbe_binary="$root_dir/zig-out/bin/qbe"
pin_file="$root_dir/selfhost/stage0-pin.json"
cache_env="SELKA_STAGE0_CACHE"

if [ ! -f "$binary" ]; then
    echo "pin-stage0: missing $binary; run selfhost/tools/build-stage0.sh first" >&2
    exit 1
fi
if [ ! -f "$qbe_binary" ]; then
    echo "pin-stage0: missing $qbe_binary; run selfhost/tools/build-stage0.sh first" >&2
    exit 1
fi

sha=$(sha256sum "$binary" | awk '{print $1}')
qbe_sha=$(sha256sum "$qbe_binary" | awk '{print $1}')
cache_root=${SELKA_STAGE0_CACHE:-$HOME/.cache/selka/stage0}
artifact="$cache_root/$sha/selka"
qbe_artifact="$cache_root/$sha/qbe"

if [ ! -f "$artifact" ]; then
    echo "pin-stage0: missing $artifact; run selfhost/tools/build-stage0.sh first" >&2
    exit 1
fi
if [ ! -f "$qbe_artifact" ]; then
    echo "pin-stage0: missing $qbe_artifact; run selfhost/tools/build-stage0.sh first" >&2
    exit 1
fi

artifact_sha=$(sha256sum "$artifact" | awk '{print $1}')
if [ "$artifact_sha" != "$sha" ]; then
    echo "pin-stage0: refusing to pin $artifact: it has sha256 $artifact_sha but $binary is $sha" >&2
    exit 1
fi
qbe_artifact_sha=$(sha256sum "$qbe_artifact" | awk '{print $1}')
if [ "$qbe_artifact_sha" != "$qbe_sha" ]; then
    echo "pin-stage0: refusing to pin $qbe_artifact: it has sha256 $qbe_artifact_sha but $qbe_binary is $qbe_sha" >&2
    exit 1
fi

branch=$(git -C "$root_dir" rev-parse --abbrev-ref HEAD)
commit=$(git -C "$root_dir" rev-parse HEAD)
toolchain=$(zig version)

python3 - "$pin_file" "$branch" "$commit" "$toolchain" "$sha" "$artifact" "$cache_root" "$cache_env" "$root_dir" "$qbe_sha" <<'PY'
import json
import sys

(
    pin_file,
    branch,
    commit,
    toolchain,
    sha,
    artifact,
    cache_dir,
    cache_env,
    built_in,
    qbe_sha,
) = sys.argv[1:11]

data = {
    "version": "stage0-pin-v1",
    "branch": branch,
    "commit": commit,
    "toolchain": toolchain,
    "sha256": sha,
    "artifact": artifact,
    "cache_dir": cache_dir,
    "cache_env": cache_env,
    "built_in": built_in,
    "tools": {"qbe": qbe_sha},
    "rule": (
        "every selfhost harness must resolve the stage-0 compiler through "
        "selfhost/tests/stage0.py::require(); the recorded commit is the commit "
        "whose Zig sources produced this content-addressed artifact; a rebuild "
        "must produce a new artifact and be re-pinned explicitly"
    ),
}
with open(pin_file, "w", encoding="utf-8") as handle:
    handle.write(json.dumps(data, indent=2) + "\n")
PY

echo "pin-stage0: wrote $pin_file (sha256 $sha, qbe $qbe_sha, artifact $artifact)"
