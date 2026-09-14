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

## Guest memory ceilings

The byte budgets above bound what the VM's own allocator hands out. A *ceiling*
is coarser and applies to every process that runs guest code: the native test
runner's children, `mylang build --run`, and a program you built and started
yourself. It exists so one runaway guest cannot take the machine into swap.

Two mechanisms enforce it. The soft one is the managed heap's byte budget: an
allocation that would exceed it *after a collection* traps with
`R_MEMORY_BUDGET`, "memory budget exhausted", and exit status 1, exactly like
`R_STEP_LIMIT` bounds instructions. The hard one is the kernel's: before its
first allocation the runtime lowers its own `RLIMIT_AS` to the budget plus 256
MiB of headroom, so a defect in the runtime cannot outgrow the budget the heap
is enforcing. `RLIMIT_AS` was chosen over a pre-`exec` hook because Zig's
`std.process.Child` has none, and because a process that bounds itself is also
bounded when you start it by hand. A tighter ceiling already in force is never
loosened, and no ceiling is installed in a sanitizer build, whose shadow mapping
reserves far more address space than any budget would permit.

The budget travels in `MYLANG_MEMORY_LIMIT`, written as bytes with an optional
`K`, `M` or `G` suffix, so no spawner needs a new argument ABI. Precedence is
`--max-memory=BYTES` on `run`, `build --run` and `test` first, then the
variable, then the built-in default: **512 MiB** for one `mylang test` child and
**4 GiB** for `run` and `build --run`. Malformed text refuses the run rather
than leaving it unbounded; `0` removes the ceiling. A program you built with
`-o` and start yourself is unbounded unless the variable is exported. The
resolved test ceiling is part of a receipt key, so raising or lowering it
re-executes rather than reusing.

The compiler bounds itself too, at 8 GiB unless `MYLANG_HOST_MEMORY_LIMIT` says
otherwise, so a compiler defect fails loudly instead of swapping; the `zig cc`
and QBE children a native build spawns complete under that inherited ceiling.

```console
$ cat grow.my
def grow(values: list[int], rounds: int) -> int:
    for r in range(rounds):
        values.append(r)
    return len(values)


def main() -> int:
    values: list[int] = []
    return grow(values, 100000000)
$ mylang build grow.my --run --max-memory=64M -- --max-steps=4000000000
grow.my:3:9: error[R_MEMORY_BUDGET]: memory budget exhausted
  in grow at grow.my:3:9
  in main at grow.my:9:12
$ echo $?
1
```

A `mylang test` child reports the same trap as an ordinary failure, with the
guest source trace, rather than dying:

```console
$ mylang test suite/main.my --max-memory=32M --max-steps=4000000
failed main::test_runaway: R_MEMORY_BUDGET
  in main::grow at main.my:7:9
  in main::test_runaway at main.my:13:12

0 passed, 0 cached, 1 failed, 0 skipped
```

## Fan-out bounded by memory

A directory run (`mylang test suite/`) starts one child per program. Its worker
count is the machine's core count, further limited by how many per-child
ceilings `MemAvailable` in `/proc/meminfo` can hold — each child is counted as
its ceiling plus the same 256 MiB of headroom. A cold fan-out on a loaded
machine therefore waits rather than oversubscribing, and it is never fewer than
one worker or more workers than there are programs. `--jobs N` overrides it,
`MYLANG_JOBS` overrides the derived default, and zero or non-numeric widths are
rejected.

```console
$ mylang test suite/ --jobs 4 --max-memory=256M
8 passed, 0 cached, 0 failed, 0 skipped across 4 programs
```
