#!/bin/sh
# Checks `cacheplan` on its fixtures. Run from anywhere; CACHEPLAN overrides the executable.
#
#   plan/*.req, *.rep   requests the test runner sent the planner (real-*, real-v1 in the version-one protocol) and random graphs (random-*), each with the
#                       cache-plan component's reply: `cacheplan diff` must agree on every one.
#   the replay checks   build a record over a scratch directory and change the directory five ways; `cacheplan replay`
#                       must say unchanged for none of them, and `STALE` where only the stat tuple is unchanged.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
exe=${CACHEPLAN:-$here/../.lake/build/bin/cacheplan}
root=$(cd "$here/../../.." && pwd)

"$exe" selftest
"$exe" diff "$here"/plan/*.req

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/dir"
printf 'alpha' > "$tmp/dir/a.txt"
printf 'beta' > "$tmp/dir/b.txt"
printf 'binary' > "$tmp/program"
export FIXTURE_VARIABLE=one

# write a record of the scratch directory as it is now; $1 names the file, extra python after it can tweak the inputs
record() {
  A=$("$exe" digest "$tmp/dir/a.txt") B=$("$exe" digest "$tmp/dir/b.txt") P=$("$exe" digest "$tmp/program") \
  L=$("$exe" listing "$tmp/dir") TMP="$tmp" OUT="$1" python3 - <<'PY'
import json, os, subprocess
tmp = os.environ["TMP"]
def stat(path):
    s = os.stat(path)
    return {"size": s.st_size, "inode": s.st_ino, "mtime": s.st_mtime_ns, "ctime": s.st_ctime_ns}
inputs = [
    {"kind": "file", "name": tmp + "/dir/a.txt", "digest": os.environ["A"]},
    {"kind": "file", "name": tmp + "/dir/b.txt", "digest": os.environ["B"], "stamp": stat(tmp + "/dir/b.txt")},
    {"kind": "file", "name": tmp + "/dir/missing.txt"},
    {"kind": "exists", "name": tmp + "/dir/missing.txt", "present": False},
    {"kind": "listing", "name": tmp + "/dir", "filter": "all", "digest": os.environ["L"]},
    {"kind": "variable", "name": "FIXTURE_VARIABLE", "value": "one"},
    {"kind": "variable", "name": "FIXTURE_UNSET"},
]
payload = {"key": "0" * 64, "inputs": inputs, "program": tmp + "/program", "digest": os.environ["P"], "stamp": stat(tmp + "/program"), "report": ""}
open(os.environ["OUT"], "w").write(json.dumps({"version": "core-build-replay-v4", "payload": json.dumps(payload), "checksum": "x"}))
PY
}

expect() { # expected truth, message, record
  out=$("$exe" replay "$3" --stdlib "$root/src/stdlib" || true)
  case "$out" in
    *"truth=$1"*) echo "ok   $2" ;;
    *) echo "FAIL $2"; echo "$out"; exit 1 ;;
  esac
}

record "$tmp/record.json"
expect true "unchanged directory, variable and program" "$tmp/record.json"

printf 'alphA' > "$tmp/dir/a.txt"
expect false "same-size edit of a file read by digest" "$tmp/record.json"
printf 'alpha' > "$tmp/dir/a.txt"
expect true "put back" "$tmp/record.json"

touch "$tmp/dir/b.txt"
expect true "a touch alone changes nothing" "$tmp/record.json"

printf 'x' > "$tmp/dir/missing.txt"
expect false "a file that was looked for appears (and the listing and the probe change)" "$tmp/record.json"
rm "$tmp/dir/missing.txt"
expect true "gone again" "$tmp/record.json"

printf 'gamma' > "$tmp/dir/c.txt"
expect false "a new file in a listed directory" "$tmp/record.json"
rm "$tmp/dir/c.txt"

FIXTURE_VARIABLE=two expect false "a variable changes" "$tmp/record.json"
FIXTURE_UNSET=1 expect false "an unset variable appears" "$tmp/record.json"

# only the stat tuple is unchanged: the bytes differ from what the record's digest says (the racy window)
printf 'BETA' > "$tmp/dir/b.txt.new"
cp -p "$tmp/dir/b.txt" "$tmp/dir/b.txt.old"
record "$tmp/stale.json"
python3 - "$tmp" <<'PY'
import json, sys
path = sys.argv[1] + "/stale.json"
e = json.load(open(path))
p = json.loads(e["payload"])
for item in p["inputs"]:
    if item["name"].endswith("/b.txt"):
        item["digest"] = "ab" * 32   # the digest of other bytes, with the stat tuple of the file as it is
e["payload"] = json.dumps(p)
json.dump(e, open(path, "w"))
PY
out=$("$exe" replay "$tmp/stale.json" --stdlib "$root/src/stdlib" || true)
case "$out" in
  *STALE*) echo "ok   an unchanged stat tuple over changed bytes is reported STALE" ;;
  *) echo "FAIL stale"; echo "$out"; exit 1 ;;
esac
echo "fixtures ok"
