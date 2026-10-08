# Source this: CE2-A's caches and temporary directory, all inside the worktree.
WT=/home/epentland/ai/canopy/mylang-worktrees/claude-ce2-effects
export ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache
export ZIG_LOCAL_CACHE_DIR=$WT/.zig-cache
export TMPDIR=$WT/.tmp
export MYLANG_CORE_RUNTIME_CACHE=$WT/.mylang-cache/core-runtime
