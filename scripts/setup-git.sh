#!/bin/sh
# Registers selka's repository merge drivers in this clone's git config.
#
# Run once per clone (any worktree of the clone will do: worktrees share the
# common `.git/config`). Re-running it is harmless; it only sets the same keys.
#
#   sh scripts/setup-git.sh
#
# `.gitattributes` routes `SPEC.md` to the `spec-bullets` driver, but git keeps
# driver commands in local config, never in the repository. Until this script
# has run, git finds no `merge.spec-bullets.driver`, ignores the attribute and
# merges SPEC.md with its ordinary line merge — the old append conflicts return,
# nothing else changes.
#
# The driver command is relative: git runs it from the top of the worktree
# being merged, so each worktree uses its own branch's `scripts/merge_spec.py`.
# A tree that has no copy (an old branch, a bare repository) falls back to
# `git merge-file`, which is exactly git's default text merge.
set -eu

top=$(git rev-parse --show-toplevel)
cd "$top"

git config merge.spec-bullets.name "SPEC.md merge by bullet tag (scripts/merge_spec.py)"
git config merge.spec-bullets.driver \
    'if [ -f scripts/merge_spec.py ]; then python3 scripts/merge_spec.py %O %A %B %P --marker-size %L; else git merge-file --marker-size=%L %A %O %B; fi'

echo "merge.spec-bullets configured in $(git rev-parse --git-common-dir)/config"
