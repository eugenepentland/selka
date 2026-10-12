#!/bin/bash
set -euo pipefail
# Run under scripts/build-slot.sh build after sourcing dev-env.sh.
probe_root=experiments/lox-eda-zero-rc-20261012/lox-vm
MYL_CORE_LEAKCHECK=1 .tmp/lox_vm_probe_native > "$probe_root/run-vm-probe.stdout" 2> "$probe_root/run-vm-probe.stderr"
printf '3\n1\n2\n11\ntrue\n' > "$probe_root/expected-vm-probe.stdout"
cmp "$probe_root/expected-vm-probe.stdout" "$probe_root/run-vm-probe.stdout"
test ! -s "$probe_root/run-vm-probe.stderr"
