#!/usr/bin/env bash
# The installed unit enters through service_worktree.py, holding the same lease
# as core maintenance through checkout and this complete refreshed run.
# The coordinator owns admission. Never wrap this script in a build/gate slot.
#
# The nightly check (D-NIGHTLY-1, experiments/audit-work-20261111/NIGHTLY.md): the complete request with --integration,
# whose builds use empty compiler and test stores of its own, then the forced fact/leak run and the two-run test step
# (`zig build test-lang-rerun`). Its exit status names the step that failed: 0 passed; 5 the request's own stores logged a
# determinism mismatch; 7 the forced fact/leak run; 8 the two-run test step; any other status is the complete request's own
# (1 a failing test or step, 2 a host or usage error, 6 a test reached the per-user stage store, 75 retry). The full output
# goes to the log file; the one line printed to standard output (the service's journal) says which step failed and why.
set -euo pipefail
selka_nightly_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd -- "$selka_nightly_root"
source "$HOME/.config/selka/dev-env.sh"
selka_nightly_logs=${XDG_STATE_HOME:-"$HOME/.local/state"}/selka/nightly-integration
mkdir -p -- "$selka_nightly_logs"
selka_nightly_stamp=$(date -u +%Y%m%dT%H%M%SZ)
selka_nightly_log=$selka_nightly_logs/$selka_nightly_stamp.log
selka_nightly_status=0
{
    printf 'worktree=%s\ncommit=%s\n' "$selka_nightly_root" "$(git rev-parse HEAD)"
    python3 scripts/verify_cache.py --zig "$ZIG" --integration
} >"$selka_nightly_log" 2>&1 || selka_nightly_status=$?
# The coordinator's last `verification: integration PASS|FAIL` line is the verdict with its reasons; a request that stopped
# before the integration checks (an error of the coordinator itself) leaves its last `verification:` line instead.
selka_nightly_line=$(grep -E '^verification: integration (PASS|FAIL)' -- "$selka_nightly_log" | tail -n 1 || true)
if [[ -z $selka_nightly_line ]]; then
    selka_nightly_line=$(grep -E '^verification: ' -- "$selka_nightly_log" | tail -n 1 || true)
fi
printf 'nightly: exit %d: %s; log: %s\n' "$selka_nightly_status" "${selka_nightly_line:-no verdict line}" "$selka_nightly_log"
exit "$selka_nightly_status"
