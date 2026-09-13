# Runtime budgets

Instruction and frame limits bound how long a guest runs; byte budgets bound how
much memory it may hold while running. The byte runner exposes them as
`--max-runtime-bytes`, `--max-vm-bytes`, `--max-host-bytes` and
`--memory-report`, and an embedding host reaches the same accounting through
`language.allocation_budget.Memory`. The design record is
[runtime byte budgets and allocator attenuation](../experiments/runtime-memory-budgets.md).

## Nested byte budgets

Budgets count live requested bytes routed through the supplied allocator
interfaces, and they nest: the VM and host budgets are children of the runtime
total and both charge it, so raising a child above its parent grants nothing.
The reported limit of a child is clamped to the total rather than accepted as
written, and an allocation deep inside a helper cannot evade any ancestor limit.
Zero permits no nonempty allocation. A failed acquisition charges nothing, a
release restores live accounting while retaining the peak, and a moving
reallocation may need the old and new capacity at once, so it can fail below its
own final-size limit. Exhaustion is a host `OutOfMemory` with normal cleanup — it
is not a guest-recoverable numeric error, and it suppresses the unpublished
output. Embedders must keep both accounting objects at stable addresses until
every allocation made through the child is freed; the allocator is
single-threaded and is not a capability a guest can be handed.

```console
$ printf 'hello bytes' | mylang-io --project examples/contract-echo \
    --max-runtime-bytes=2048 --max-vm-bytes=16777216 --memory-report
{"version":"runtime-memory-v1","scope":"requested-live-bytes-excluding-source-input-and-allocator-overhead","total":{"limit":2048,"live":0,"peak":1976},"vm":{"limit":2048,"live":0,"peak":1976},"host":{"limit":2048,"live":0,"peak":0},"vm_categories":{"guest_backing":{"limit":2048,"live":0,"peak":0},"bookkeeping_and_snapshots":{"limit":2048,"live":0,"peak":1976}}}
mylang-io: OutOfMemory
$ echo $?
1
```

## Memory accounting categories

`--memory-report` prints one `runtime-memory-v1` JSON line on stderr after
cleanup, so a report is produced whether the guest succeeded or ran out of
budget. It reports the limit, remaining live bytes and high-water bytes for the
runtime total, for the VM and for the host, and then splits the VM into two
categories that share the VM's limit: `guest_backing` counts reserved buffer and
pool storage and retained region chunks, while `bookkeeping_and_snapshots` counts
stacks, references, immutable values and snapshots, registries and region
metadata. Their live bytes add up to the VM total, but their peaks need not occur
at the same moment, so adding the peaks does not give the VM high-water mark.
Host bytes include buffered output and whatever the scoped providers allocate
through the supplied allocator. Everything outside that allocator is excluded —
source compilation, input storage, allocator metadata, kernel memory and provider
work that bypasses it — so this is not a whole-process resident-size cap. The
runner's line carries the categories shown here; it does not currently report a
separate logical slot count.

```console
$ printf 'hello bytes' | mylang-io --project examples/contract-echo \
    --max-runtime-bytes=8388608 --max-vm-bytes=4194304 --max-host-bytes=1048576 --memory-report
hello bytes
{"version":"runtime-memory-v1","scope":"requested-live-bytes-excluding-source-input-and-allocator-overhead","total":{"limit":8388608,"live":0,"peak":2624},"vm":{"limit":4194304,"live":0,"peak":2624},"host":{"limit":1048576,"live":0,"peak":129},"vm_categories":{"guest_backing":{"limit":4194304,"live":0,"peak":0},"bookkeeping_and_snapshots":{"limit":4194304,"live":0,"peak":2624}}}
```
