#!/usr/bin/env bash
# Unblock the four local-reasoning lanes after /tmp filled and the harness's
# bash tool stopped spawning commands.
#
# Run this from a terminal on the machine (not through an agent tool):
#
#     bash /home/epentland/ai/canopy/mylang/scripts/unblock-local-reasoning-lanes.sh
#
# It does three things, in the order that protects work first:
#
#   1. Commits every lane worktree as-is, so no uncommitted lane work can be lost
#      to a later reset. It never resets, cleans or checks out anything.
#   2. Frees /tmp: the private Zig cache the `simple` lane put there, plus other
#      build scratch. /tmp is a 16 GB tmpfs here and build caches do not belong
#      in it.
#   3. Replaces the poisoned shared Zig local cache with one cache per lane under
#      $HOME, so a stale cached compiler can never be served to a lane again.
#
# It is idempotent: running it twice is harmless.

set -uo pipefail

ROOT=/home/epentland/ai/canopy/mylang
LANES=(mut simple option tuple)
STAMP=$(date +%Y%m%d-%H%M%S)

echo "== 1. committing lane work (nothing is reset, cleaned or checked out) =="
for lane in "${LANES[@]}"; do
    worktree="$ROOT/../mylang-$lane"
    if [ ! -d "$worktree/.git" ] && [ ! -f "$worktree/.git" ]; then
        echo "   lane/$lane: no worktree at $worktree, skipping"
        continue
    fi
    rm -f "$worktree/.scratch-write-test"
    (
        cd "$worktree" || exit 2
        if [ -n "$(git status --porcelain)" ]; then
            git add -A
            git commit -q -m "lane $lane: work in progress at the /tmp exhaustion ($STAMP)" \
                && echo "   lane/$lane: committed" \
                || echo "   lane/$lane: COMMIT FAILED — inspect by hand"
        else
            echo "   lane/$lane: already clean at $(git log --oneline -1)"
        fi
    )
done

echo "== 2. freeing /tmp =="
df -h /tmp | tail -1
rm -rf /tmp/zc-simple /tmp/zc-mut /tmp/zc-option /tmp/zc-tuple /tmp/zc-*
rm -rf /tmp/canary.log /tmp/tu.log /tmp/tc.log /tmp/tf.log /tmp/tg.log /tmp/tp.log /tmp/tk.log
rm -f  /tmp/sema.bak /tmp/probe.my /tmp/errprobe.my /tmp/mutprobe.my /tmp/rail.my /tmp/opt.my
rm -rf /tmp/recover /tmp/dsh-scratch /tmp/dsh-spill-* /tmp/local-reasoning-verify-*
rm -rf /tmp/optcache /tmp/mlc-m /tmp/mylang-native-* /tmp/cc*
echo "   after:"
df -h /tmp | tail -1

echo "== 3. per-lane Zig caches under \$HOME =="
rm -rf "$HOME/.cache/mylang/zig-local-cache"          # poisoned, see the lane notes
for lane in "${LANES[@]}"; do
    mkdir -p "$HOME/.cache/mylang/zig-local-cache-$lane"
done
mkdir -p "$HOME/.cache/mylang/native-cache"
echo "   $HOME/.cache/mylang/zig-local-cache-{mut,simple,option,tuple}"
echo "   $HOME/.cache/mylang/native-cache"

echo
echo "== state =="
for lane in "${LANES[@]}"; do
    worktree="$ROOT/../mylang-$lane"
    [ -e "$worktree/.git" ] || continue
    printf 'lane/%-6s %s  uncommitted: %s\n' "$lane" \
        "$(git -C "$worktree" log --oneline -1)" \
        "$(git -C "$worktree" status --porcelain | wc -l)"
done
echo
echo "done. Running any command in an agent should work again."
