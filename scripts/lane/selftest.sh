#!/usr/bin/env bash
# selftest.sh : what can be proved about the lane kit in a few minutes, without a gate. Makes the kit of main's head when it is
# missing (kit.sh prepare), then: with-stores refuses ~/.cache; probe.sh on the skeleton, on a refused program and on a trapping
# one; newly-refused.sh with the base compiler against itself (must say 0 everywhere); the parts of finish.sh that need no gate
# (the dirty-tree refusal, the merge conflict stop, the lost-heading check after a union merge, the log classifier on saved
# text). The gate path of finish.sh and cost-check.sh's measuring are not run here. Prints one line per check; exit 1 on any FAIL.
set -u
. "$(dirname "$0")/lib.sh"
fails=0
t() {  # t NAME COMMAND-STATUS-AS-0/1 [DETAIL]
  if [ "$2" -eq 0 ]; then echo "ok    $1"; else echo "FAIL  $1 ${3:-}"; fails=$((fails + 1)); fi
}
has() { grep -qF -- "$2" <<< "$1"; }

rev=$(short_rev main); KIT=$KIT_ROOT/$rev
if [ ! -f "$KIT/READY" ]; then "$LANE_DIR/kit.sh" prepare | sed 's/^/  | /'; fi
[ -f "$KIT/READY" ] || { echo "FAIL  no READY kit"; exit 1; }
BASE=$KIT/base/bin/selka; W=$KIT_ROOT/selftest; rm -rf "$W"; mkdir -p "$W"
t "kit $rev is READY with a base compiler ($("$BASE" --version | cut -d, -f1))" 0
out=$("$LANE_DIR/kit.sh" prepare 2>&1); t "kit.sh prepare is a no-op on a READY kit" $(has "$out" "READY"; echo $?) "$out"

out=$("$LANE_DIR/with-stores.sh" "$HOME/.cache/selka/x" true 2>&1); t "with-stores.sh refuses a folder under ~/.cache" $((! $?)) "$out"
out=$("$LANE_DIR/with-stores.sh" "$W/st" sh -c 'echo "$XDG_CACHE_HOME $SELKA_CORE_RUNTIME_CACHE $SELKA_STAGE_SHARED_CACHE"')
t "with-stores.sh sets the three variables for the command only" $([ "$out" = "$W/st/xdg $W/st/rt $W/st/stage" ] && [ -z "${XDG_CACHE_HOME:-}" ]; echo $?) "$out"

printf 'func main(out: Stream) -> int:\n    return 0\n' > "$W/refused.selka"
printf 'func main(out: Stream) -> int:\n    const xs = [1, 2]\n    const i = len(xs) + 1\n    print(out, xs[i])\n    return 0\n' > "$W/trap.selka"
out=$(PROBE_STORES=$W/probe-stores "$LANE_DIR/probe.sh" --compiler "$BASE" --out "$W/probe-out" "$LANE_DIR/probe-skeleton.selka" "$W/refused.selka" "$W/trap.selka" 2>&1)
echo "$out" | sed 's/^/  | /' | cut -c1-200
t "probe.sh: the skeleton checks, runs in debug and release, same output" $(has "$out" "probe-skeleton.selka: check ok | debug+leakcheck ok | release ok | same | out: probe=1"; echo $?)
t "probe.sh: a refused program shows its code and line" $(has "$out" "refused.selka: check REFUSED E_UNUSED_CAPABILITY at line 1"; echo $?)
t "probe.sh: a trap shows its status" $(has "$out" "trap.selka: check ok | debug+leakcheck status"; echo $?)

if [ -z "${SELFTEST_FAST:-}" ]; then   # SELFTEST_FAST=1 skips this slowest part (about six minutes)
  out=$("$LANE_DIR/newly-refused.sh" "$BASE" "$KIT" 2>&1); rc=$?
  echo "$out" | sed 's/^/  | /' | cut -c1-200
  t "newly-refused.sh: the base compiler against itself exits 0" $rc
  t "newly-refused.sh: every project line says newly refused 0, no longer refused 0, warnings +0 -0" \
    $([ "$(grep -c 'newly refused 0, no longer refused 0, warnings +0 -0, fix --check edits by code: none' <<< "$out")" = 4 ]; echo $?)
fi

# The comparison on a synthetic "new" result: one invented error, one invented warning, one fix --check edit under an E_ code.
P=$W/synth; mkdir -p "$P"; cp -a "$KIT/proj-base/." "$P/"
echo "error lib/x.selka:12 E_FAKE" >> "$P/selka-sqlite~lib.diag"; echo "warning lib/z.selka:3 W_FAKE" >> "$P/selka-sqlite~lib.diag"
printf 'selka-sqlite\tselka-sqlite~_root\tE_METHOD_REMOVED\tlib/y.selka\t2\nselka-sqlite\tselka-sqlite~_root\tW_MATCH_ELSE\tlib/w.selka\t1\n' >> "$P/fixcheck.txt"
out=$(python3 -B "$LANE_DIR/kitproj.py" compare "$KIT/proj-base" "$P" "$W/synth.txt"); rc=$?
t "compare finds a newly refused error and an E_ fix --check edit, exits 1" $([ $rc -eq 1 ] && has "$out" "selka-sqlite: newly refused 2, no longer refused 0, warnings +1 -0, fix --check edits by code: E_METHOD_REMOVED 2, W_MATCH_ELSE 1" && has "$out" "NEW selka-sqlite lib lib/x.selka:12 E_FAKE" && has "$out" "NEW selka-sqlite fix --check would edit lib/y.selka (2 edits, E_METHOD_REMOVED)"; echo $?) "$out"

# cost-check refuses to start while a gate runs (a stand-in process whose command line starts like verify_cache.py's).
printf 'import time\ntime.sleep(60)\n' > "$W/verify_cache.py"; python3 "$W/verify_cache.py" & fake=$!
out=$("$LANE_DIR/cost-check.sh" "$BASE" "$BASE" 2>&1); rc=$?; kill "$fake" 2> /dev/null; wait "$fake" 2> /dev/null
t "cost-check.sh refuses to start while a gate runs (status 3)" $([ $rc -eq 3 ] && has "$out" "not starting"; echo $?) "$out"

# The parts of finish.sh that need no gate, in a repository of their own (a union-merged CHANGES.md, as in the lanes).
R=$W/repo; mkdir -p "$R"; cd "$R" || exit 2
g() { git -c user.name=kit -c user.email=kit@example.invalid "$@"; }
git init -q -b main . && printf 'CHANGES.md merge=union\n' > .gitattributes && printf '# Changes\n\n### A\n\nbody a\n' > CHANGES.md && echo one > f.txt
g add -A && g commit -qm base && g checkout -q -b lane
printf '\n### L\n\nbody l\n' >> CHANGES.md && g commit -qam lane && g checkout -q main
printf '\n### M\n\nbody m\n' >> CHANGES.md && echo main > f.txt && g commit -qam main && g checkout -q lane
echo untracked > dirty.txt
out=$("$LANE_DIR/finish.sh" --merge-only 2>&1); rc=$?
t "finish.sh refuses a dirty tree (status 2), merging nothing" $([ $rc -eq 2 ] && has "$out" "refusing: the tree of lane is dirty" && ! grep -q '### M' CHANGES.md; echo $?) "$out"
rm dirty.txt
# --headings only reports: on a file shaped as the union merge leaves it (### M right under body l) it lists that one heading and
# leaves the file as it was.
printf '# Changes\n\n### L\n\nbody l\n### M\n\nbody m\n' > "$W/bad-changes.md"; before=$(cksum < "$W/bad-changes.md")
out=$("$LANE_DIR/finish.sh" --headings "$W/bad-changes.md")
t "finish.sh --headings lists the one heading without a blank line and changes nothing" $([ "$(wc -l <<< "$out")" = 1 ] && has "$out" "bad-changes.md:6: ### M" && [ "$(cksum < "$W/bad-changes.md")" = "$before" ]; echo $?) "$out"
head=$(g rev-parse HEAD); mainhead=$(g rev-parse --short=10 main)
out=$("$LANE_DIR/finish.sh" --merge-only 2>&1); rc=$?
echo "$out" | sed 's/^/  | /' | cut -c1-200
t "finish.sh after a clean merge puts the blank line back, says so in one line and goes on (status 0)" \
  $([ $rc -eq 0 ] && has "$out" "merged main $mainhead cleanly" && has "$out" "CHANGES.md: put back the blank line before 1 ### heading(s) the union merge dropped" && [ "$(wc -l <<< "$out")" = 2 ]; echo $?) "$out"
t "the repair is one commit of CHANGES.md alone, with the mechanical message, one added line, nothing deleted" \
  $([ "$(g log -1 --format=%s)" = "CHANGES.md: the blank line the union merge dropped" ] && [ "$(g show --name-only --format= HEAD)" = CHANGES.md ] && \
    [ "$(g show --numstat --format= HEAD | cut -f1,2 | tr '\t' ' ')" = "1 0" ] && [ "$(g rev-list --count "$head..HEAD")" = 3 ] && [ -z "$(git status --porcelain)" ]; echo $?) "$(g log --format='%h %s' -3)"
t "after the repair CHANGES.md has no heading without a blank line, and ### M sits on line 11 under a blank line 10" \
  $([ -z "$("$LANE_DIR/finish.sh" --headings CHANGES.md)" ] && [ "$(sed -n 10p CHANGES.md)" = "" ] && [ "$(sed -n 11p CHANGES.md)" = "### M" ]; echo $?)
out=$("$LANE_DIR/finish.sh" --merge-only 2>&1); rc=$?; now=$(g rev-parse HEAD)
t "finish.sh run again has nothing to merge or repair: no new commit (status 0)" $([ $rc -eq 0 ] && has "$out" "Already up to date" && [ "$now" = "$(g rev-parse HEAD)" ] && ! has "$out" "put back"; echo $?) "$out"
g checkout -q main && echo mainedit > f.txt && g commit -qam m2 && g checkout -q lane && echo laneedit > f.txt && g commit -qam l2
out=$("$LANE_DIR/finish.sh" --merge-only 2>&1); rc=$?
t "finish.sh stops on a merge conflict and names the file (status 1)" $([ $rc -eq 1 ] && has "$out" "stopped on a conflict" && has "$out" "f.txt"; echo $?) "$out"
g merge --abort > /dev/null 2>&1
g checkout -q main; out=$("$LANE_DIR/finish.sh" 2>&1); rc=$?
t "finish.sh refuses to run on branch main (status 2)" $([ $rc -eq 2 ]; echo $?) "$out"

# The gate path of finish.sh against stand-ins for verify_cache.py, corpus_exact.py, build-slot.sh and the compiler: the rerun of a
# deadline, the verdict line, the exactness line, and a real failure that is not rerun. (The real gate is not run here.)
R2=$W/repo2; mkdir -p "$R2/scripts" "$R2/zig-out/bin"; cd "$R2" || exit 2
git init -q -b main . && cp "$LANE_REPO/.zigversion" . && printf 'zig-out/\n.zig-cache/\n.tmp/\n.selka-cache/\n.stubmode\n' > .gitignore
printf 'import pathlib, sys\ncache = pathlib.Path(".selka-cache"); cache.mkdir(exist_ok=True)\ncount = cache / "count"\nk = int(count.read_text()) + 1 if count.exists() else 1\ncount.write_text(str(k))\nmode = pathlib.Path(".stubmode").read_text().strip()\nif mode == "deadline" and k == 1:\n    print("verification: FAIL; in 80.0 s; 17 reused, 12 executed; log: x")\n    print("  test deadline: t ran 301.0 s (limit 300.0 s); killed")\n    sys.exit(1)\nif mode == "real":\n    print("verification: FAIL; in 80.0 s; 17 reused, 12 executed; log: x")\n    print("  test: src/a.zig::b (failed)")\n    sys.exit(1)\nprint("verification: PASS; in 1.0 s; 51 reused, 0 executed; log: x")\n' > scripts/verify_cache.py
printf '#!/bin/sh\nshift\nexec "$@"\n' > scripts/build-slot.sh; chmod +x scripts/build-slot.sh
printf 'print("builds 3: identical 3, different 0, failed both ways 0, failed one way 0")\n' > scripts/corpus_exact.py
printf '#!/bin/sh\necho "selka commit $(git -C "%s" rev-parse HEAD | cut -c1-12), identity x, debug"\n' "$R2" > zig-out/bin/selka; chmod +x zig-out/bin/selka
git add -A && g commit -qm base && g checkout -q -b lane
export FINISH_LOGS=$W/flogs
echo deadline > .stubmode
out=$("$LANE_DIR/finish.sh" 2>&1); rc=$?
echo "$out" | sed 's/^/  | /' | cut -c1-200
t "finish.sh (stand-ins): a deadline is rerun once, the gate's PASS line, then the exactness line, status 0" \
  $([ $rc -eq 0 ] && has "$out" "verification: PASS; in 1.0 s" && has "$out" "first run: RERUN deadline; rerun once by itself" && has "$out" "corpus_exact: builds 3: identical 3, different 0"; echo $?)
rm -rf .selka-cache; echo real > .stubmode
out=$("$LANE_DIR/finish.sh" 2>&1); rc=$?
t "finish.sh (stand-ins): a failed test is not rerun, corpus_exact is skipped, status 1" \
  $([ $rc -eq 1 ] && has "$out" "gate not green (FAIL" && has "$out" "corpus_exact skipped" && ! has "$out" "rerun once"; echo $?) "$out"
unset FINISH_LOGS

# The classifier on saved gate text: the lines are those real gate logs of 15 November carry, and the three known signatures.
L=$W/logs; mkdir -p "$L"
printf 'verification: PASS; in 361.0 s; 17 reused, 34 executed; log: /x\nexit 0\n' > "$L/pass.log"
printf 'verification: FAIL; in 80.0 s; 17 reused, 12 executed; log: /x\nfailure 1/1: unit\n  test deadline: src/root_test.zig::slow test ran 301.2 s (limit 300.0 s); killed\n' > "$L/deadline.log"
printf 'verification: FAIL; in 80.0 s; 17 reused, 12 executed; log: /x\nfailure 1/1: core\n  error: shared compiler cache: WriteFailed\n' > "$L/writefailed.log"
printf 'verification: FAIL; in 80.0 s; 17 reused, 12 executed; log: /x\nfailure 1/1: language\n  error: process exited with code 134\n' > "$L/f22.log"
mkdir -p "$L/f22.dir"; printf 'General protection exception (no address available)\ncrash-state si_code=0x80 trap=13\n' > "$L/f22.dir/stderr.log"
printf 'verification: FAIL; in 80.0 s; 17 reused, 12 executed; log: /x\nfailure 1/1: unit\n  test: src/root_test.zig::a test (failed)\n  error: x\n' > "$L/real.log"
printf 'verification: FAIL; in 80.0 s; 1 reused, 12 executed; log: /x\n  test: src/a.zig::b (failed)\n  test deadline: other ran 301.0 s (limit 300.0 s); killed\n' > "$L/mixed.log"
printf 'verification: FAIL: inputs changed while awaiting admitted work\nexit=2\n' > "$L/inputs.log"
c() { "$LANE_DIR/finish.sh" --classify "$@"; }
t "classifier: PASS"                       $([ "$(c "$L/pass.log")" = PASS ]; echo $?)
t "classifier: a deadline alone reruns"    $([ "$(c "$L/deadline.log")" = "RERUN deadline" ]; echo $?) "$(c "$L/deadline.log")"
t "classifier: WriteFailed reruns"         $([ "$(c "$L/writefailed.log")" = "RERUN writefailed" ]; echo $?) "$(c "$L/writefailed.log")"
t "classifier: F22 found in the log directory reruns" $([ "$(c "$L/f22.log" "$L/f22.dir")" = "RERUN f22" ]; echo $?) "$(c "$L/f22.log" "$L/f22.dir")"
t "classifier: exit 134 without the signature is a failure" $(c "$L/f22.log" | grep -q '^FAIL'; echo $?) "$(c "$L/f22.log")"
t "classifier: a failed test is a failure" $(c "$L/real.log" | grep -q '^FAIL'; echo $?) "$(c "$L/real.log")"
t "classifier: a failed test beside a deadline is a failure" $(c "$L/mixed.log" | grep -q '^FAIL'; echo $?) "$(c "$L/mixed.log")"
t "classifier: no verdict line" $(c "$L/inputs.log" | grep -q '^FAIL\|^NOVERDICT'; echo $?) "$(c "$L/inputs.log")"
out=$(python3 -B "$LANE_DIR/handback_test.py" 2>&1); rc=$?
t "handback_test.py: every selection rule, verdict rule and the --rest, --bg and --wait paths on scratch repositories" $rc "$(tail -5 <<< "$out")"
cd "$LANE_REPO" || exit 2
[ $fails -eq 0 ] && echo "selftest: all checks passed" || echo "selftest: $fails FAILED"
[ $fails -eq 0 ]
