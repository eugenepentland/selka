# Source me: per-worktree caches and TMPDIR on disk inside the worktree.
W=/home/epentland/ai/canopy/mylang-worktrees/claude-vk-vp3
export ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache
export ZIG_LOCAL_CACHE_DIR=$W/.zig-cache
export TMPDIR=$W/.tmp/tmp
export MYLANG_CORE_RUNTIME_CACHE=$W/.mylang-cache/core-runtime
export MYLANG_TIMING_CPUS=2,3,6,10,11
mkdir -p "$TMPDIR"
