# Borrowed aggregate rendering

The C0 zero-RC build refused compiler-generated `myl_core_render_shape_*` and
`myl_core_show_*` helpers. Merely adding helper names to the ownership registry
would leave an artificial owning box around a borrowed aggregate. The rendering
lowerer now passes the physical value as a borrowed argument. Emission writes its
canonical memory image to an entry stack slot and synchronously calls the existing
renderer, which copies bytes into independent returned text. The stack image never
owns its managed children. No callback or pointer escapes the render call.

Using `storeOperand` preserves wide records, compact union tags, unit payloads and
boxed recursive layouts. The helper name uses the actual descriptor ID, including
its physical suffix for boxed roots. Whole and split-unit emission intercept every
compiler-generated show call and emit no old box adapter body. Source extern names
keep their ordinary external linkage; source extern managed arguments/results are
already refused by `build.functionIndex` and gain no rendering authority.

A07 audited the complete renderer and authored the exact helper registry and shared
emitter hook. Only decimal u32 source/string/physical IDs are admitted; malformed,
empty, overflowing or extra suffixes refuse. Metadata and call signatures are
checked separately. The shared name parser lives in `build_render.zig` so ownership
and emission agree without an import cycle. The coordinator applied the SPEC
sentence and root-test import. A04 does not own broader FFI or cache policy.

`core-tests-02.json` and `core-tests-02.log` record five focused tests passing with
zero failures. They verify no box allocation in rendering IR, direct render calls
in whole and unit output, exact helper contracts, malformed-name refusal, and
wrong ownership/physical-parameter signatures. `tests/lang/a04_render_borrows.my`
adds three executable guest tests for borrowed wide managed records, float/raw-byte
leaves, units, variants, tuples, recursive boxes, dictionary order and independent
text surviving owner replacement. Its source check and formatter check pass.

Prototype source base `1120bde6a3665b2dc1d14c8f5cd708c1e4035417` is A04's
cherry-pick of approved driver repair `38dc781a897182ffbf1fff0906ec319a007a9154`.
Do not integrate that equivalent dependency twice. The source diff and compiler
SHA256 `3b5ed2e54c75d93a19cd9eccdfbeede371e0b09cedaf2066a7c3e770a205377f`
are recorded in the focused-test receipt. Guardian passed all 88 checks while
committing the driver dependency after correcting the in-progress renderer's
import cycle and complexity/test-structure findings.

Native five-mode counted execution and explicit debug/release replay are pending
in `qualify.py`. The first prototype reproduced the shared missing native-object
bug; `prototype-01/` retains those failures. The driver repair is in the second
prototype. Current host tool approval may prevent C0 native linking and cache
replay; those failures must remain explicit, not count as successful qualification.
Managed counters omit the renderer's native scratch buffer and are not RSS.
No runtime, allocation or peak-memory saving is claimed before paired evidence.
The integrated compiler must rerun all affected cases and the registered full gate.
