# C: resource operation permission attenuation

Status: filesystem/network capability operation permissions can be narrowed in
source and at the embedding entry boundary. Acquired resources inherit those
permissions; runtime reads, writes, and completion enforce them before callbacks.
Provider scope and quotas remain shared. The slice I/O, partial field move and
explicit arena/pool tracks this page once named were removed on 2026-09-13.

```text
fn delegate(fs: filesystem_cap) -> filesystem_cap effects() {
    return restrict_resource<read>(fs);
}
```

`restrict_resource<read, write, complete>(capability)` accepts any subset of the three
named permissions, including an empty list. Names must be known and distinct. The
operand is evaluated once and must be a filesystem or network capability. The result
keeps the same capability type, provider/store identity, and shared quota ceiling.
Its permission set is the intersection of the incoming permissions and requested
set. Asking for a larger set cannot restore removed permissions. Ordering the named
permissions differently has no semantic effect.

The original capability and already-acquired resources remain unchanged. Helpers
can copy, wrap, and forward a narrowed grant, but cannot recover a broader grant from
it. A caller that retains its original broader grant can still deliberately use it.
No ambient lookup supplies the original authority to a restricted helper.

These are **resource operation** permissions. Restriction does not remove acquisition
or fallback-release authority: an empty operation set can still request a resource
with no read/write/complete rights, subject to provider approval and shared quotas.
It does not derive a different directory/endpoint scope, revoke existing owners,
change allocator capabilities, or create independent quota budgets.

## Acquisition and provider contract

The trusted provider acquisition callback now receives
`acquire(context, request, permissions)`. Providers must honor those permissions
when choosing open modes and interpreting requests. For example, a request that
would create or truncate a file must be denied when excluded by the grant. The
runtime cannot infer those semantics from arbitrary request bytes. The callback
signature change is intentional; all repository providers were migrated.

The store checks capability identity and permission-mask validity before invoking
acquisition, passes the narrowed permissions, and records them with the acquired
host handle. Moving ownership preserves them. Slot reuse initializes the new
resource's permissions from its new grant, so old restrictions neither disappear
on movement nor contaminate later unrelated owners.

Read/write/complete without the corresponding permission return recoverable
`Denied = 2` before their provider callback. The owner remains live. A denied
completion returns the owned resource through the existing completion error result,
allowing permitted operations or explicit fallback. Release is always available and
never implies successful completion. A malicious host callback can violate its
contract; this remains a trusted embedding boundary, not a sandbox against the host.

Embedders can set `vm.Options.resources.filesystem_permissions` and
`network_permissions` to constrain initial grants. Both default to all permissions.
Permission bits are read=1, write=2, complete=4; unknown bits are rejected. Source
restriction intersects with these entry ceilings. Copies and narrower grants share
the store's original live-resource limit; they cannot amplify quota capacity.

## Effects, validation, and acceptance

Restriction performs no provider call or guest backing allocation and adds no effect.
It can appear under `effects()`. Possessing restricted authority does not remove the
actual filesystem/network effects of acquisition, I/O, completion, or cleanup.
Permission denial and provider availability remain runtime result conditions under
the current capability types, rather than separate static resource subtypes.

Bytecode checks capability kinds and masks; the VM checks live store identity and
intersects permissions. Exact discovery is `exact-v23`, retaining permission sets
and operand identity while normalizing list ordering and binding spelling.

339 tests pass in Debug and ReleaseFast (304 core, 35 actual CLI). Acceptance covers
forwarding through wrappers/helpers, attempted re-expansion, embedding ceilings,
provider-visible permissions and rejected acquisition requests, pre-callback operation
denial, ownership-preserving completion failure, unchanged parent rights, shared
quotas, moves/slot reuse, stale/foreign/closed grants, malformed permission sets and
bytecode masks, and effect-free restriction. Allocation-failure sweeps cover
restriction, acquisition, denied operations/completion, cleanup, dumps, and discovery.
CLI tests cover checking, dumps, denied execution without providers, and permission
syntax rejection across commands. Formatting/whitespace checks pass on the pinned Zig.
