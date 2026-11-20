#!/bin/sh
# Write DIR/selka.commit: the commit the tree is at and whether it has changes, for `selka --version` (D-FR22-4).
#
# The install step runs this beside the compiler. The file is deliberately NOT part of the compiler: the compiler's
# identity digests the sources under src and the products build.zig embeds, and a commit hash among them would change
# that identity at every commit, including a commit that changes only a guide, and empty every cached result. The file
# is rewritten only when its text changes, so an unchanged tree leaves its modification time alone. Format
# (src/version_line.zig): `commit HASH` and `tree clean` or `tree dirty`; `commit unknown` when git cannot say.
#
# What it costs (FR24): `git status --no-optional-locks` never refreshes the repository's index, and an index whose stat data
# is stale (a fresh worktree, or any checkout until someone runs a plain `git status`) makes git read all 11,000 tracked files
# at every call: 70 to 120 ms at every install. The refresh is done in a private copy of the index instead, kept in WORK, the build's
# cache (`selka.commit.index`, and `selka.commit.index.stamp`, a file made before the copy): the copy is 1.4 MB and belongs to
# the build, not to an installation, so DIR holds `selka.commit` and nothing else. The repository's own index and its lock are
# never touched, and the copy is made again whenever the repository's index is not older than the stamp (a commit, an `add` or a
# checkout replaced it; equal times count as newer). A tree with changes skips the untracked-file walk. Without a copy (no WORK, or
# it cannot be written) the old questions are asked of the repository's own index, as before. The two files that an earlier version
# of this script left in DIR are removed.
#
# usage: sh scripts/write-commit-file.sh DIR [WORK]
set -u
dir=${1:?usage: write-commit-file.sh DIR [WORK]}
work=${2:-}
# The directories are made only when they are missing: a process each is 2 ms of an 18 ms run.
[ -d "$dir" ] || mkdir -p -- "$dir" || exit 1
# The copy used to live beside the commit file.
if [ -e "$dir/selka.commit.index" ] || [ -e "$dir/selka.commit.index.stamp" ]; then
  rm -f -- "$dir/selka.commit.index" "$dir/selka.commit.index.stamp" 2>/dev/null
fi
if [ -n "$work" ] && [ ! -d "$work" ]; then mkdir -p -- "$work" 2>/dev/null || work=; fi
# The hash of HEAD and the path of the index, one per line.
found=$(git rev-parse HEAD --git-path index 2>/dev/null) || found=
hash=${found%%
*}
case $hash in
  '' | *[!0-9a-f]*) text='commit unknown' ;;
  *)
    real=${found#*
}
    private=$work/selka.commit.index
    stamp=$private.stamp
    if [ -z "$work" ]; then
      ready=
    elif [ -f "$real" ] && [ -f "$private" ] && [ -f "$stamp" ] && [ "$stamp" -nt "$real" ]; then
      ready=yes
    elif [ -f "$real" ] && [ ! -d "$private" ] && : >"$stamp.$$" 2>/dev/null && cp -- "$real" "$private.$$" 2>/dev/null &&
      mv -f -- "$private.$$" "$private" 2>/dev/null && mv -f -- "$stamp.$$" "$stamp" 2>/dev/null; then
      ready=yes
    else
      rm -f -- "$private.$$" "$stamp.$$" "$stamp"
      ready=
    fi
    state=
    if [ -n "$ready" ]; then
      # A change `git` can see: a tracked file staged or modified anywhere, or an untracked file under src (it is built in).
      # A plain `git status` on the private copy refreshes its stat data, which is the point of the copy. If git cannot read
      # the copy, the answer comes from the repository's own index below.
      if changed=$(GIT_INDEX_FILE=$private git status --porcelain --untracked-files=no 2>/dev/null); then
        if [ -n "$changed" ]; then
          state=dirty
        elif fresh=$(GIT_INDEX_FILE=$private git ls-files --others --exclude-standard -- src 2>/dev/null); then
          if [ -n "$fresh" ]; then state=dirty; else state=clean; fi
        fi
      fi
    fi
    if [ -z "$state" ]; then
      changed=$(git --no-optional-locks status --porcelain --untracked-files=no 2>/dev/null) || changed=dirty
      fresh=$(git --no-optional-locks ls-files --others --exclude-standard -- src 2>/dev/null) || fresh=dirty
      if [ -n "$changed" ] || [ -n "$fresh" ]; then state=dirty; else state=clean; fi
    fi
    text="commit $hash
tree $state"
    ;;
esac
target=$dir/selka.commit
if [ -f "$target" ] && [ "$(cat -- "$target")" = "$text" ]; then exit 0; fi
printf '%s\n' "$text" >"$target.tmp.$$" && mv -f -- "$target.tmp.$$" "$target"
