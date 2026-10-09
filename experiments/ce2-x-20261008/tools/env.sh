# Source this: CE-X's caches and temporary directory, all inside the worktree.
WT=/home/epentland/ai/canopy/mylang-worktrees/claude-main-ce
export ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache
export ZIG_LOCAL_CACHE_DIR=$WT/.zig-cache
export TMPDIR=$WT/.tmp
