#!/usr/bin/env bash
# finish.sh [--no-corpus] [--merge-only] | --classify LOG [LOGDIR] | --headings [FILE] : for the coordinator, run in a lane's
# worktree after the lane hands back. It never merges into main and never pushes.
#   1. refuses when the tree is dirty or the branch is main;
#   2. `git merge main` (stops on a conflict, leaving it for you; after a clean merge it puts back the blank line the union merge
#      dropped before a `###` heading of CHANGES.md, commits that one file as "CHANGES.md: the blank line the union merge
#      dropped", says so in one line, and goes on; it stops only if the repair would be anything but that one-file insertion);
#   3. the complete gate, `verify_cache.py --profile complete --fail-fast`, rerun once by itself when the failure carries only a
#      deadline, `shared compiler cache: WriteFailed` or the F22 signature (RULES.md: "The known machine fault F22");
#   4. `corpus_exact.py` on this tree's Debug compiler (rebuilt first when it is not of HEAD).
#   Output: at most 15 lines (the merge, the gate's verdict line and commit, the exactness line, the log path).
#   --merge-only stops after step 2; --no-corpus skips step 4.
#   --classify LOG [LOGDIR] prints how a gate log reads: PASS, RERUN deadline|writefailed|f22, or FAIL (a heuristic on the
#   log text and, when given, the gate's log directory). --headings [FILE] lists `###` headings without a blank line before and
#   changes nothing.
set -u
. "$(dirname "$0")/lib.sh"

# classify LOG [LOGDIR]: PASS | RERUN <kind> | FAIL <why> | NOVERDICT
classify() {
  local log=$1 dir=${2:-} text kinds="" real
  [ -f "$log" ] || { echo "NOVERDICT no log"; return; }
  text=$log
  grep -aq '^verification: PASS' "$log" && { echo PASS; return; }
  grep -aq '^verification: FAIL' "$log" || { echo "NOVERDICT no verification line"; return; }
  # The signatures are looked for in the gate's own output and, when the directory is named, in its saved step logs.
  hit() { grep -aqE -- "$1" "$text" 2> /dev/null || { [ -n "$dir" ] && [ -d "$dir" ] && grep -raqE -- "$1" "$dir" 2> /dev/null; }; }
  hit 'test deadline: .* ran [0-9.]+ s \(limit [0-9.]+ s\); killed|step deadline: .* ran [0-9.]+ s \(limit' && kinds="$kinds deadline"
  hit 'shared compiler cache: WriteFailed' && kinds="$kinds writefailed"
  hit 'General protection exception|trap=13' && kinds="$kinds f22"
  hit 'Segmentation fault at address' && hit '@memset|memset' && kinds="$kinds f22"
  # A test that reports `(failed)` (an assertion, not a kill or a crash) is a real failure whatever else the log says.
  real=$(grep -aE '^ *test: .*\(failed\)' "$log" | grep -avc 'deadline')
  if [ -n "$kinds" ] && [ "$real" -eq 0 ]; then echo "RERUN$kinds" | sed 's/  */ /g'; return; fi
  [ -n "$kinds" ] && { echo "FAIL a test failed besides the signature ($kinds )" | sed 's/  */ /g'; return; }
  echo "FAIL no known signature"
}

# headings FILE: the `###` headings whose previous line is not blank (the union merge of CHANGES.md drops the blank line).
headings() {
  [ -f "$1" ] || return 0
  awk 'prev != "" && /^###/ && NR > 1 {printf "%s:%d: %s\n", FILENAME, NR, $0} {prev = $0}' "$1"
}

# fix_headings LOGDIR: put the blank line back before every heading that headings() lists and commit CHANGES.md alone, with no
# trailer (a mechanical commit). Succeeds only when that commit holds nothing but CHANGES.md and only added lines, one for each
# heading; otherwise it leaves the tree as the merge made it (the file restored, nothing staged) and fails.
fix_headings() {
  local n tmp=$1/changes.$$ got
  n=$(headings CHANGES.md | wc -l)
  awk 'prev != "" && /^###/ && NR > 1 {print ""} {print; prev = $0}' CHANGES.md > "$tmp" && cat "$tmp" > CHANGES.md; rm -f "$tmp"
  git add CHANGES.md
  got=$(git diff --cached --numstat | cut -f1,2 | tr '\t' ' ')
  if [ "$(git diff --cached --name-only)" = CHANGES.md ] && [ "$got" = "$n 0" ] && [ -z "$(headings CHANGES.md)" ] &&
     git commit -q -m "CHANGES.md: the blank line the union merge dropped" > "$1/commit.$$" 2>&1; then
    rm -f "$1/commit.$$"; return 0
  fi
  [ -s "$1/commit.$$" ] && tail -4 "$1/commit.$$" | sed 's/^/  git commit: /'; rm -f "$1/commit.$$"
  git restore --staged --worktree CHANGES.md; return 1
}

case "${1:-}" in
  -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
  --classify) [ $# -ge 2 ] || die "usage: finish.sh --classify LOG [LOGDIR]"; classify "$2" "${3:-}"; exit 0;;
  --headings) headings "${2:-CHANGES.md}"; exit 0;;
esac
corpus=1; merge_only=0
for a in "$@"; do case "$a" in --no-corpus) corpus=0;; --merge-only) merge_only=1;; *) die "unknown option $a (finish.sh -h)";; esac; done

root=$(git rev-parse --show-toplevel 2> /dev/null) || die "not in a git worktree"
cd "$root" || exit 2
branch=$(git rev-parse --abbrev-ref HEAD)
[ "$branch" != main ] || die "this is branch main: finish.sh runs in a lane's worktree and never merges into main"
if [ -n "$(git status --porcelain)" ]; then
  echo "finish: refusing: the tree of $branch is dirty (commit or remove these first):"; git status --short | head -6; exit 2
fi
t0=$SECONDS
mainhead=$(git rev-parse --short=10 main)
logs=${FINISH_LOGS:-$KIT_ROOT/finish-logs}; mkdir -p "$logs"
mlog=$logs/merge.$$
if ! git merge --no-edit main > "$mlog" 2>&1; then
  echo "finish: merge of main ($mainhead) into $branch stopped on a conflict; resolve it (or git merge --abort):"
  git diff --name-only --diff-filter=U | head -8 | sed 's/^/  /'; rm -f "$mlog"; exit 1
fi
mline=$(grep -aE '^(Merge made|Already up to date|Fast-forward)' "$mlog" | head -1 | cut -c1-100); rm -f "$mlog"
bad=$(headings CHANGES.md)
echo "finish: $branch: merged main $mainhead cleanly ($mline), now at $(git rev-parse --short=10 HEAD)"
if [ -n "$bad" ]; then
  if fix_headings "$logs"; then
    echo "finish: CHANGES.md: put back the blank line before $(wc -l <<< "$bad") ### heading(s) the union merge dropped; committed, now at $(git rev-parse --short=10 HEAD)"
  else
    echo "finish: CHANGES.md has a ### heading that lost its blank line (the union merge) and the repair did not apply; fix, commit, run again:"
    echo "$bad" | head -5 | sed 's/^/  /'; exit 1
  fi
fi
[ $merge_only = 1 ] && exit 0

[ -d "$HOME/.config/selka" ] || die "no ~/.config/selka/dev-env.sh"
gate() {  # gate N: the complete gate with --fail-fast in a subshell that sources the development environment; log to $logs/..-N.log
  ( unset SELKA_COMPONENT_DIR
    # shellcheck disable=SC1090
    . "$HOME/.config/selka/dev-env.sh" || exit 2
    python3 scripts/verify_cache.py --zig "$ZIG" --profile complete --fail-fast ) > "$1" 2>&1
}
log=$logs/$(echo "$branch" | tr '/' '_')-$(date +%H%M%S).log
gate "$log"; verdict=$(classify "$log" "$root/.selka-cache/verification-v3/last-logs")
note=""
case "$verdict" in
  RERUN*) note=" (first run: $verdict; rerun once by itself)"; log2=${log%.log}-rerun.log; gate "$log2"; log=$log2
          verdict=$(classify "$log" "$root/.selka-cache/verification-v3/last-logs");;
esac
vline=$(grep -a '^verification: \(PASS\|FAIL\)' "$log" | head -1 | cut -c1-170)
echo "finish: gate at $(git rev-parse --short=10 HEAD): ${vline:-no verification line}$note"
if [ "$verdict" != PASS ]; then
  echo "finish: gate not green ($verdict); the first lines of its summary:"; sed -n '2,7p' "$log" | cut -c1-170 | sed 's/^/  /'
  echo "finish: log $log; corpus_exact skipped"; exit 1
fi
if [ $corpus = 0 ]; then echo "finish: corpus_exact skipped (--no-corpus); log $log"; exit 0; fi
( . "$HOME/.config/selka/dev-env.sh" || exit 2
  have=$(zig-out/bin/selka --version 2> /dev/null | sed -n 's/^selka commit \([0-9a-f]*\),.*/\1/p')
  if [ -z "$have" ] || [ "${have:0:10}" != "$(git rev-parse --short=10 HEAD)" ]; then
    echo "finish: zig-out/bin/selka is of ${have:-nothing}, not HEAD: building it"; scripts/build-slot.sh build zig build -fno-incremental > "$logs/build.log" 2>&1 || { echo "finish: build failed, see $logs/build.log"; exit 1; }
  fi
  scripts/build-slot.sh build python3 scripts/corpus_exact.py --compiler zig-out/bin/selka 2>&1 | tail -3 | cut -c1-170 | sed 's/^/finish: corpus_exact: /'; exit "${PIPESTATUS[0]}" )
crc=$?; [ $crc -eq 0 ] || echo "finish: corpus_exact ended with status $crc (1 means a difference or a one-way build)"
echo "finish: log $log, $(elapsed "$t0") in all"
