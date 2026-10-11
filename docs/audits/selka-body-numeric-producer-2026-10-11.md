# Selka numeric body producer, 11 October 2026

This commit implements the selected B9 numeric closure in ordinary Selka and
packages it as body protocol 1/schema 9. The strict installed admission passed
all 40 fixtures and 366 reference, shadow and component operations in each of
the normal and release qualification lanes, with zero
failures and zero skips. Generated runtime checks use release, fact verification
and leak checks, including both exact runtime overflow traps. Complete canonical
batch/catalog shadow comparison is mandatory; typed dumps supplement it.

This is an intermediate compiler component result. Compiler bootstrap,
whole-language checker/backend coverage, production activation and the 1.5x
compile/test/runtime goal remain outstanding. The integration branch must retain
and requalify B8 collection coverage when adopting schema 9.

## Implementation and authority

Integer literals use eight radix-65536 limbs to reproduce the native u128
magnitude limit with qualified signed-i64 operations. Type suffix/context,
magnitude, width-range and directly negated signed-minimum behavior follow the
native literal implementation. Canonical upper-half u64 payloads use body-only
wire kind 8 containing their signed bit pattern; lower values retain kind 1.
There is no syntax literal representation change.

Float identity comes only from the retained synthetic float domain backed by
u64. Decimal grammar follows native literal diagnostics. The existing numeric
runtime parser supplies correctly rounded binary64 magnitudes; exact powers of
two recover the bits using public language operations. Invalid parsing never
becomes a successful zero. The qualified seed still refuses private float domain
access, and this implementation does not bypass it. Source negative zero retains
the native unary negation lowering over a positive zero literal.

Numeric lowering preserves native hidden-local evaluation order, conversions,
floor/remainder, rounding, comparisons and exact Option identities for numeric
text and byte-range parsing. Retained list and record closure now recognizes all
eight integer widths and the synthetic float leaf. No new structural recipe,
primitive authority, wire budget or decode limit is introduced.

The selected fixtures are the scope of the installed B9 result. Other numeric
surface combinations, including integer `abs` and shadowed text-conversion
repair names, still need broader checker closure work. Structural array/tuple
recipes are a separate continuation owned by integration.

## Reproducible evidence

The isolated branch started at parser `173a154a2`, incorporated frozen ROOT
`653ae191d` native prerequisites and committed B8 native donors, then native B9
`909fbcb46` and probes `b09dcee15`/`668a14274`. The pre-implementation foundation
is `aa7243caf`. No active root/parser/lexer dirty files were copied.

The final body package key is
`4a24d37efe0e9b539b1032234e27469be35013c4b9ea5e35b46073b9763e7031`,
artifact SHA256
`7eb7679601b754350f68ecd1f7d2b6c5281943914e0e7b877e30a1883a00e026`.
The qualified seed remains
`c4f1ea0b6618cb7b146bbb8e035220eb36b99ff078d4a959d8bf0948d0c6d98b`.
The strict runner reauthenticates the seed, compiler and all packages.

[Archived evidence](evidence/selka-body-numeric-20261011/receipt.json) records
full raw admission outputs, package identities and an exact producer source
snapshot. The supplemental runner passed 35 cases/168 comparisons: positive and
negative zero; minimum subnormal; normal/subnormal boundary neighbors; powers of
two neighbors; maximum finite; long decimal ties; underflow and overflow;
malformed decimal/prefixed grammar; and native numeric-method arity diagnostics.
It uses genuine installed producer output and native complete shadow checks.

The following commands use a private host installation and component cache under
`/home/epentland/ai/canopy/.selka-agent-cache/numeric-b9`; the pinned Zig is
`/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig`.

```sh
scripts/build-slot.sh build python3 selfhost/tests/run_body_numeric_admission.py \
  --compiler PRIVATE/install-host/focus/mylang \
  --builder PRIVATE/install-host/tools/selka-components \
  --component-dir PRIVATE/components-arity --source-root ISOLATED_SOURCE \
  --zig PINNED_ZIG --report PRIVATE/numeric-admission-arity.json --release
scripts/build-slot.sh build python3 selfhost/tests/run_body_numeric_boundaries.py \
  --compiler PRIVATE/install-host/focus/mylang \
  --component-dir PRIVATE/components-arity \
  --report PRIVATE/numeric-boundaries-final.json
```

Focused qualified-seed tests passed: integer helper 8 normally and in release
with facts/leaks; float helper 7 in both modes; numeric lowering 2 normally; list
catalog 7 normally. Native numeric codec/validator tests passed 16/16 (9 named,
7 unnamed). Numeric admission Python selftests passed 8/8; component builder
selftests passed 25/25.

The first full producer test gate waited 616 seconds and terminated with status
143 immediately after admission, before reporting tests. Its log is retained;
it is not a passing receipt. The replacement gate admitted immediately, but its
normal seed compiler child terminated with signal 15 before emitting output.
The wrapper retained status -15 and did not run release. Integration confirmed
that no cleanup or termination command targeted these processes. The cause is
still under investigation. Terminal successful pure-suite results and the
numeric package-admission unit will be recorded in a follow-up evidence update.
No complete repository gate is claimed for this branch.

## Integration requirements

Merge the committed producer with the latest B8 producer. Resolve engine changes
locally while keeping the numeric literal helpers, float type authority and
native numeric lowering order. Apply corrected hostile harness donor
`f48e330f0ca4a2004492e306e29f9ee405355118` before rolling prior B8 harnesses from
schema 8 to 9. Re-run the original 34/246 collection corpus, the 27 authentic
hostile refusals and collection extension controls under schema 9. Preserve
schema-8 package refusal. Re-run strict B9 40/366 and supplemental boundaries on
the merged installation. Only then can integration accept the combined stage;
this evidence does not substitute for earlier-stage regressions.
