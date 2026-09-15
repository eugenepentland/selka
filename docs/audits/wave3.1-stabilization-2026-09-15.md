# Wave 3.1 stabilization — review findings resolved

Date: 2026-09-15
Parent plan: [self-hosting implementation plan](self-hosting-implementation-plan-2026-09-14.md), Wave 3
Predecessor: [Wave 3 completion](wave3-incremental-2026-09-15.md)

A post-completion review found six correctness/reliability gaps in the new
incremental contract: stages reported reuse they had not performed, the project
interface hash missed meaningful changes and included irrelevant ones, declaration
interfaces omitted defaults, specialization keys used placeholders, rejected
checks emitted no explanation, and structurally empty baselines compared as hits.
Wave 3.1 fixes all six and connects ordinary body reuse to declaration
identities/dependencies instead of the positional project-wide digest.

## Findings and fixes

### 1. Stage "hits" did not reflect actual reuse

- `invalidation.zig` now takes an explicit execution mask and reports every
  stage as `hit`, `miss` or `skipped`. A stage the command did not run can never
  be reported as reuse.
- Lowering now depends on each declaration's `interface_sha256` and
  `body_sha256`; emission depends on the emitted fragment table; linking depends
  on the fragment inputs as well as compiler, target and runtime ABI.
- A command that lowers (`run`, `run-project`, `emit-project-qbe`) builds its
  receipt after lowering, so the fragment table holds real inputs. A check-only
  command reports lowering/emission/linking as `skipped`.
- `--report`'s `frontend-cache-v1` `stages` entries carry
  `hits`/`misses`/`skipped`; a stored-verdict replay marks the semantic stages
  skipped rather than fresh.

### 2. Project interface hash was the whole public schema

- `incremental.zig` composes `project_interface_sha256` from the sorted
  `interface_identity`/`interface_sha256` pairs of exported interface items only.
- Exported constants, declared effect ceilings and parameter defaults now
  participate; comments, formatting, source paths, spans, source hashes and
  private declarations do not.

### 3. Declaration interface omitted default arguments

- The function interface encoding appends the normalized declaration header,
  which includes every parameter default, to the checked typed encoding.
- `functionSpan` includes default-value node spans so generic/constant fallback
  paths see defaults too.

### 4. Specialization keys did not capture the concrete provider

- `providerFingerprint` renders each concrete type argument's checked record
  shape (fields, variants, layout flags) instead of the generic template's
  interface.
- `incremental.describe` takes a `Contract { compiler_sha256, target_abi }`;
  `dependency_report.render` supplies the real compiler digest and
  architecture/OS/ABI from the receipt identity. Placeholders are gone.

### 5. Failed checks omitted the requested explanation

- `incremental.describePartial` and `dependency_report.renderPartial` build a
  best-effort receipt from the interface index and source bodies without running
  or publishing a successful verdict.
- `main.zig` emits `invalidation-report-v1` on a type error and does **not**
  advance the baseline, so a failed edit cannot be mistaken for a successful
  verdict.

### 6. Structurally corrupt baselines compared as hits

- `invalidation.explain` validates the receipt version, implementation identity,
  inputs array and incremental module table before comparing. A syntactically
  valid `{}` is `corrupt-baseline`, not seven misses and two hits.
- Skipped stages stay skipped; executed stages all miss.

## Declaration-identity-backed body reuse

The review's recommendation was to connect a real declaration-ID/dependency
cache path before freezing the contract. `semantic_key`/`semantic_cache` now
publish an ordered table of `{ declarationIdentity, interfaceDigest }` plus the
resolved type-catalog digest. Reuse requires:

- the ordered declaration identities and interface digests are unchanged;
- the resolved type catalog is unchanged; and
- the declaration's own full source text (header plus body) is byte-identical.

Relocation uses a single segment mapping the declaration to its new offset,
rather than a whole-project body segmentation. Whitespace or comments outside
declarations therefore reuse every body; editing one body rechecks only that
body; an interface change to any declaration stays conservative and rechecks
every body (an unchanged caller may depend on it). Inferred effects are still
recomputed over the whole call graph after reuse, so a callee that gains an
effect still rejects an unchanged effect-bounded caller.

## Evidence

- `src/invalidation_matrix_test.zig` extends the clean/warm matrix with
  whitespace/comment-outside reuse and keeps the full mutation matrix
  (signatures, effects, constants, record/union shape, imports, generic
  templates, specialization arguments, runtime ABI, compiler identity, damaged
  cache).
- `test/integration.zig` adds a CLI test that a body edit makes `check_body`,
  `lower_function`, `emit_fragment` and `link` miss on `run`, that the executed
  result changes, and that a check-only command reports those stages `skipped`.
- A consolidated probe over all six findings passes (kept as
  `scripts/wave31_findings_probe.py`).

## Gates run

- `zig build test` — full documented gate, exit 0.
- `zig build test-units` — 942 passed, 0 failed.
- `zig build test-cli` — 80 passed, 0 failed.
- `zig build test-qbe` — all native/golden sub-suites passed.
- `zig build test-doc-coverage` — 0 failures.
- Guardian whole-tree gate — 88/88 checks.

## Still deferred

- The full generic/nominal reuse engine (templates, constants, aliases and
  nominal syntax remain conservatively fresh).
- Explicit effect ceilings on exported declarations.
- `runtime-abi-v1` (the cache-contract dimension remains
  `runtime-abi-v0-unfrozen` until Wave 4).
