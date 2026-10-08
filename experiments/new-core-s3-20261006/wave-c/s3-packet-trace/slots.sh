#!/usr/bin/env bash
# Keep the gate descriptor separate from build-slot.sh's descriptor 9.
set -euo pipefail
kind=$1
shift
exec 17>/run/user/1000/mylang-slots/gate1.lock
flock -x 17
if [[ $kind == exclusive ]]; then
    exec 18>/run/user/1000/mylang-slots/build1.lock
    exec 19>/run/user/1000/mylang-slots/build2.lock
    exec 20>/run/user/1000/mylang-slots/build3.lock
    flock -x 18
    flock -x 19
    flock -x 20
    exec taskset -c 0,1,4-9,12-19 "$@"
fi
exec scripts/build-slot.sh build "$@"
