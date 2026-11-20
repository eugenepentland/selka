#!/usr/bin/env bash
# handback.sh [BASE] [--only NAME[,NAME]] [--with NAME] [--plan] [--rest] [--bg] [--wait [PID]] [--compiler PATH] [--zig PATH] : the
# hand-back checks of BRIEF-REPAIR-COMMON in one command, for the files changed since BASE (default: the merge base with main).
# One line per check (PASS name (Ns) / FAIL name (Ns): why / SKIP name: why / LATER name: why), at most ten lines of detail per
# failure, then `handback: N passed, M failed, K skipped, L later; exit E; log PATH`. Exit 0 all passed, 1 a failure, 2 a host
# problem (no compiler newer than the sources, no Zig), 3 nothing failed but something is still to run.
# --plan names the checks that apply and why, running nothing. --only reruns one check; --with forces one that does not apply;
# --rest runs what the last run left LATER; --only NAME --bg starts a slow check detached and --wait waits for it (270 s at a time).
# Needs the worktree's compiler built (zig-out/bin/selka, newer than the sources) and $ZIG (source ~/.config/selka/dev-env.sh).
# Never builds, never runs the gate, the edit check or a test root. Details: docs/tooling/lane-kit.md ("handback.sh").
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
case "${1:-}" in -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0;; esac
exec python3 -B "$here/handback.py" "$@"
