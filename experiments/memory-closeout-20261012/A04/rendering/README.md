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

`prototype-02/` passes all five native counted zero-RC modes and the ordinary
release control. Every zero-RC lane records 51 whole-program managed allocations,
3,680 cumulative managed bytes, 640 peak live bytes and zero bytes live at exit;
emitted LLVM, linked symbols and counted runtime events are RC-free. These totals
describe this fixture and compiler, not a reduction or performance comparison.
Ordinary release has 48 allocations, 3,488 bytes and the same managed peak.

Three qualification failures remain explicit. Both debug and release replay
attempts link successfully twice but report `program=linked`, not `replayed`:
the changed host `/etc/ld.so.cache` is outside this compiler's qualified native
tool closure, disabling native artifact reuse. The immutable C0 ordinary control
fails linking because its old driver removes uncached unit objects prematurely.
The coordinator owns host qualification; A08 owns the integrated cache rerun.
No successful C0 comparison is claimed. `prototype-01/` retains the earlier five
missing-object failures before the approved driver repair.
Managed counters omit the renderer's native scratch buffer and are not RSS.
No runtime, allocation or peak-memory saving is claimed before paired evidence.
The integrated compiler must rerun all affected cases and the registered full gate.

The integrated support5 rerun (`support5-01/`) passes all six native lanes: five
checked-ownership modes plus ordinary release. Release and debug both pass their
receipt/replay checks on compiler SHA256
`8b1898be7ad2f95cf53bf709f9d468b3bcfbabcaab2aaa7b5aa48d0163b2a789`, source
`a1f19edf255c8c0886731d8d7cce450d5f657720`. All counted ownership lanes retain
zero RC events, zero managed exit bytes and clean LLVM/symbol audits. The old
prototype replay/native-control failures remain preserved as historical evidence.
Support5 is an interim integrated compiler, not the final C1/default/retired
artifact. Its staged installed components still have the coordinator's reported
historical RC boundary; no package-wide RC retirement is claimed here.
