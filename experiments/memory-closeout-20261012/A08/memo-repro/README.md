# Memo typed-body hydration blocker

Owner: A08. Common Support7 source `bed11cf3bf3102ffec44487e431a1573fdf02ad5`,
ReleaseFast compiler SHA-256 `540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef`.
`minimal.my` is a nine-line reduction: its unoptimized checked build succeeds cold
and exits 1 with empty stdout/stderr warm. A05 first reported this using
`original.my`, whose source SHA-256 is
`28074a03530fda44404c885eaf79a2484723ea9193a76c0a76ed5445ec4da64e`.

Private copied-cache controls isolate the failure to one ordinary typed body,
`fn\x1fmain\x1f\x1fmain`, retained as file
`3e98a3b76679a86c9899a436393a7e3d01e9c6c3d4d08c835680ced89cb20b4d`.
Keeping only that body reproduces the failure. Other ordinary bodies alone,
all symbolic entries, all specialization entries, only syntax, and only Core/native
stages pass. Core-only reuse observes all nine lowering bodies and nine debug
optimizer artifacts reused. Original A05 caches are unchanged.

The preserved Debug compiler SHA-256
`877364887f12a6e7d1757dd6db7aa4bebecc8889bc7a803e984f069f212ef560`
from source `3cf5bef` (production bytes match Support7) first misses the RF cache
namespace, then reproduces the same empty status 1 on its own warm cache.
Its result is separately labeled, not a common-RF qualification result.

`../memo-probe-{01,02}/results.json` retain every layer/kind/single-entry command
and output. `../memo-reduce-01/results.json` retains five cold/warm source pairs.
The direct nongeneric callable control passes both states. These are admitted
correctness probes; elapsed or cache timing fields are not performance evidence.
The scripts record this machine's frozen artifact and preserved-cache paths and
require unused work/output paths when repeated. Root authorized a separate
A08-memo worktree at `69f797479707dba0fbca18aad5c4fb5d3acbffb7` for the fix.
No cache validation was weakened and no production fix is claimed yet.

A standalone frontend regression subsequently located the exact InternalError at
`module_names.reference`, called by `semantic_type_recipe.callable`: raw syntax
keeps `memo.create[str[]]` in `call.name` while `type_arguments` is empty until
ordinary dispatch splits it. The existing generic-site recipe exclusion missed
that form. A narrow conservative-miss fix is under separate qualification; these
reports retain the failing Support7 artifact unchanged.
