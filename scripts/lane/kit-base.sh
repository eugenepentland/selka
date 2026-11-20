#!/usr/bin/env bash
# kit-base.sh REV OUTDIR : build a Debug compiler of REV into OUTDIR (OUTDIR/bin/selka, OUTDIR/libexec), the base compiler
# of a kit. A detached worktree under OUTDIR.build/ with its own ZIG_LOCAL_CACHE_DIR. A commit from before GH-2 (18 November
# 2026) needs `../guardian-zig` (build.zig.zon: .guardian = path "../guardian-zig"), and so does a seed compiler build while
# selfhost/components.zig links the sibling for the seed commit (before GH-3a, 19 November 2026); a scratch worktree does
# not have it beside it, so for such a commit a symlink to the guardian checkout is put there, in the scratch folder, and
# the repository's build files stay as they are. A commit that needs neither gets no symlink. The build goes through build-slot.sh. The worktree
# is removed afterwards. Called by kit.sh prepare; usable alone.
# A commit from before the rename (GH-5, 19 November 2026: its guest sources end in `.my`, not `.selka`) builds with the old
# `~/.config/mylang/dev-env.sh` and installs `bin/mylang`; `bin/selka` is then a link to it, so the kit's scripts name one
# path. A kit made before the rename (`base/bin/mylang` only) gets the same link instead of a rebuild.
set -u
. "$(dirname "$0")/lib.sh"
if [ $# -ne 2 ] || [ "$1" = -h ]; then echo "usage: kit-base.sh REV OUTDIR   (Debug compiler of REV installed to OUTDIR)"; [ "${1:-}" = -h ] && exit 0; exit 2; fi
rev=$(git -C "$LANE_REPO" rev-parse --verify "$1^{commit}") || die "no such revision: $1"
out=$(realpath -m "$2"); build="$out.build"
# Whether REV still needs the sibling guardian checkout: its build imports Guardian, or its seed build links the sibling.
needs_guardian=0
git -C "$LANE_REPO" show "$rev:build.zig.zon" 2>/dev/null | grep -q 'guardian' && needs_guardian=1
git -C "$LANE_REPO" show "$rev:selfhost/components.zig" 2>/dev/null | grep -q 'sibling guardian-zig' && needs_guardian=1
[ "$needs_guardian" = 0 ] || [ -d "$KIT_GUARDIAN" ] || die "no guardian checkout at $KIT_GUARDIAN (KIT_GUARDIAN names it)"
# Whether REV is from after the rename: its guest tests are `.selka` files.
renamed=0
git -C "$LANE_REPO" ls-tree -r --name-only "$rev" tests/lang | grep -q '\.selka$' && renamed=1
# An installation from before the rename: name its compiler `bin/selka` as well.
link_old() { if [ -x "$1/bin/mylang" ] && [ ! -e "$1/bin/selka" ]; then ln -s mylang "$1/bin/selka"; fi; }
link_old "$out"
[ -x "$out/bin/selka" ] && { echo "kit-base: $out/bin/selka exists"; exit 0; }
rm -rf "$build"; mkdir -p "$build" "$(dirname "$out")" || exit 2
tree=$build/selka
git -C "$LANE_REPO" worktree prune
git -C "$LANE_REPO" worktree add -q --detach "$tree" "$rev" || die "worktree add failed"
[ "$needs_guardian" = 0 ] || ln -s "$KIT_GUARDIAN" "$build/guardian-zig"
cleanup() { git -C "$LANE_REPO" worktree remove --force "$tree" 2>/dev/null; rm -rf "$build"; git -C "$LANE_REPO" worktree prune; }
trap cleanup EXIT
t0=$SECONDS
rm -rf "$out.tmp"
(
  cd "$tree" || exit 2
  # shellcheck disable=SC1090
  if [ "$renamed" = 1 ]; then
    . "$HOME/.config/selka/dev-env.sh" || exit 2
    export SELKA_ZIG_CACHE_CAP_GB=12
    unset SELKA_COMPONENT_DIR
  else
    . "$HOME/.config/mylang/dev-env.sh" || exit 2
    export MYLANG_ZIG_CACHE_CAP_GB=12
    unset MYLANG_COMPONENT_DIR
  fi
  scripts/build-slot.sh build zig build --prefix "$out.tmp"
) > "$out.build.log" 2>&1
rc=$?
[ $rc -ne 0 ] || link_old "$out.tmp"
if [ $rc -ne 0 ] || [ ! -x "$out.tmp/bin/selka" ]; then
  echo "kit-base: the build of ${rev:0:10} failed (status $rc); the last lines of $out.build.log:" >&2
  tail -15 "$out.build.log" | cut -c1-200 >&2; exit 1
fi
mv "$out.tmp" "$out"
echo "kit-base: built ${rev:0:10} in $(elapsed "$t0") -> $out ($(du -sh "$out" | cut -f1))"
