# Native nominal scalar domains
> Removed on 2026-09-13: this page documents a feature that no longer exists in the language.

Native emission now supports domains backed by built-in integers or bool, including
parameters, returns, locals, copying, mutation, and explicit wrap/unwrap operations
inside their defining domain. This applies to single-file and module programs:

```sh
zig build
python3 scripts/native.py examples/modules/domain_main.my --project --mode ReleaseFast -o zig-out/domain-example
zig-out/domain-example
```

The example returns 12 through the shared Distance factory and accessor.

The native representation carries the domain's backing value in the existing scalar
value slot. It does not allocate the VM's host aggregate wrapper. This is a backend
representation choice: the frontend still resolves nominal identities, checks
parameter/result types, and restricts wrap/unwrap to the defining domain. Private
methods and cross-file boundaries are enforced before emission. Distinct domains
with identical backing types are not interchangeable. Domain equality/arithmetic
has not been added; operations still go through explicit methods/accessors.

Wrap/unwrap emit no value transformation, but their bytecode instruction ticks remain
in native control flow. Step budgets therefore include them just as in the VM. Numeric
operations after unwrapping retain the backing width's checked bounds. No bit
truncation, unchecked cast, or implicit conversion bypasses those checks. Native and
VM host allocation patterns differ; host out-of-memory behavior is not required to
occur at identical points.

Acceptance adds copied/mutable i64 domains, boolean-backed domains, a u64 maximum
value followed by a rejecting i64 cast, and u8 overflow after unwrapping. A cross-file
domain fixture uses a private factory helper, exported methods, and a nominal
parameter/return forwarding function. C O0/O2 with undefined-behavior sanitization
are compared with VM values/traps; module comparisons also check file paths and call
frames. Every instruction budget through completion of the module domain case is
executed in both C modes. Rejection tests preserve private-constructor and nominal
mismatch diagnostics. Allocation-failure sweeps cover native emission and VM domain
execution with cleanup.

At this milestone the suite had 27 single-file native fixtures/206 comparisons and six module
fixtures/114 comparisons per host build mode. Those numbers include the earlier
scalar cases; they are not all new tests. At that point, aggregate signatures and reference/resource operations rejected
before C output.

Subsequent milestones add [enums](native-enums.md), [aggregates and variants](native-aggregates.md),
[borrowing](native-references.md), and [owned buffers](native-buffers.md).
Native external resources, pools, arenas, and other unfinished roadmap work remain pending.
