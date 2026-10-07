# CFG provenance correction draft

**Rejected, 2026-10-07:** the parent review correctly identified the marker
proposal below as an IR semantic contract change. It will not be implemented.
The production source remains frozen while an external sidecar is reviewed.

The three reduced consuming helpers in `mut-frame-references-02` fail a bounds
check, assertion or overflow. Old and S3 retain `leaf::origin` plus `app::main` in
release. V d4's CFG cloning relabels all three sites as `app::main` and loses the
caller's source call position. Standalone E retains the old frames and paths.
The immutable compiler digests and exact bytes are retained in the report.

No production patch is implemented from this draft. The proposed carrier uses
existing no-value `.copy` instructions, whose `data` field is unused; `ir.zig`,
all operation operand shapes and the runtime ABI stay unchanged. It records
exact function identity, avoiding ambiguous span-to-function inference for
generic instances sharing one body span.

Proposed fixed convention:

- A marker is `.copy`, `.ty=void`, `.a=none`, `.b=none`, with data bit63 set.
  Remaining bits carry the original callee's function index (31 bits) and the
  original source call span (32 bits). Its ordinary span stays a source span.
- Refuse CFG expansion if a function index does not fit. Markers emit no LLVM
  instruction and carry no value, retain, release or runtime effect.
- Insert inherited caller frame markers and the exact callee marker into each
  cloned block, after leading phis. Preserve inherited markers in the split
  continuation, including when a call inside an already cloned helper is split.
  Existing markers in the callee follow the new outer frame markers.
- Versioning already copies instructions and their data, so frame identities
  travel with cloned blocks. Keep CFG-helper application once; the parameter
  aware second pass copies only single-block, proved-safe leaves.

Emission scans a block's ordered markers before rendering its instructions.
Starting with the real emitted function's debug scope, each marker creates a
location for its source call in the current scope, then the exact specialized
callee subprogram scope. The instruction's original source span gets a
`DILocation` in that innermost scope with the composed `inlinedAt` chain. Trap
and fact sites take their function name from the innermost marker. All constant,
site, path and debug nodes remain unit-local first-use dependencies. Raw global
function indexes are resolved to names and never enter emitted LLVM bytes.

Required regressions before final qualification: all three old/split/whole
reducers in debug/release/verify; same helper called twice with distinct source
call positions; two generic instances sharing the same declaration/body and
primitive trap type; nested consuming helpers; loop versioning/unswitching;
native ownership/leaks; full core and conformance; byte stability and genuine
helper edit ripple; union_find/grid and all46; actual five split applications.
Any unhandled marker transformation must refuse expansion rather than silently
report the caller as the callee. Full source-exact package gates must be rerun.
