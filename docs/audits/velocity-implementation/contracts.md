# Development velocity: frozen shared contracts (W0)

Frozen 2026-09-15 at baseline `9ce142e98cb22e684622ed1d5678071d6944206e`.
These are the single definitions for representations shared by two or more
packages. Changing one requires the integrator to update this file, the relevant
cache/validator/runtime versions, and the ledger owners together.

## 1. Effect vocabulary and mutation effect

- `effect_set.Effect` gains exactly one category, `mutation`, appended after
  `output` so existing bits do not move. The backing integer widens from `u3` to
  `u4`; `Mask` stays `u16`.
- `effect_set.all` becomes `0b1_1111_1111` (`0x1ff`). `io` is unchanged.
- Source spelling: `effects(mutation)` names the new category. The parser's
  unknown-effect message and every serialized effect list include it.
- Serialized/interface/cache effect contracts move to `effects-v3`; `frontend_cache`
  and the native object cache contract are versioned together. Old `effects-v2`
  entries must never be admitted. Exact effect-mask equality remains the identity
  relation for interning and schema fingerprints.

## 2. Mutation contract grammar

Function signatures and callable-type signatures accept one optional clause after
the effect ceiling, on the ordinary signature line:

```text
def replace_first(values: list[int], replacement: int) -> None effects(mutation) mutates(values):
def total(values: list[int]) -> int effects():
def apply(f: def(values: list[int]) -> None effects(mutation) mutates(values)) -> None effects():
```

- `mutates(a, b)` names binders in the enclosing signature's parameter list.
  Names normalize to zero-based parameter positions, sorted and duplicate-free.
  An unknown name is a declaration-site error.
- Omitted `mutates` at a declared contract means the empty footprint. `mutates()`
  is the same and is accepted for emphasis.
- `mutates(...)` on a declared contract requires the `mutation` effect bit.
- Callable binder names introduce no keyword arguments and do not participate in
  callable identity. Callable parameters are matched by position.
- Private helper effects and write footprints may be inferred; their inferred
  value is a diagnostic fact, never a published ceiling.

## 3. Mutation metadata (M1/M2)

- `typed.Callable` gains `mutates: []const u16` (parameter positions) and
  `return_origin: typed.ReturnOrigin`.
- `typed.ReturnOrigin` is an extensible tagged bound:
  `fresh`, `params([]const u16)`, `unknown`. `fresh` is only valid with proof;
  an exported declaration with no published bound defaults to `unknown`.
- `unknown` is never treated as `fresh` and never as `params(empty)`.
- Exact callable identity (`callables.equal`, interning, schema fingerprints)
  includes the effect mask, the normalized `mutates` position set and the
  `return_origin` bound. Binder spelling is excluded.
- The `mutation` effect bit permits externally observable managed-state writes
  subject to the footprint. Definitely-fresh local storage may be mutated without
  the bit, but storing an input descendant in fresh storage does not launder it.

## 4. Directional callable assignability (E1)

An implementation `I` satisfies destination contract `D` iff:

1. parameter types and count are exactly equal (invariant);
2. the result type is exactly equal (invariant; shape identity is separate);
3. `I.effects & ~D.effects == 0` (subset);
4. `I.mutates ⊆ D.mutates` as position sets;
5. `I.return_origin` is a subset of `D.return_origin` (`fresh ⊆ params(S) ⊆ unknown`;
   `params(A) ⊆ params(B)` iff `A ⊆ B`).

Exact equality remains the relation for interning and schema identity. Runtime
target validation (`callables.accepts`) uses exactly relation 1–5, not equality.
Calls through a stored callable use the destination contract's ceiling.

## 5. Reuse and work counters (C0/C1)

- New report version string `work-report-v1`. A stage status is
  `hit | miss | skipped`; `skipped` is never counted as reuse.
- Per invocation the report names: `parsed_modules`, `checked_bodies`,
  `instantiated_specializations`, `lowered_functions`, `emitted_fragments`,
  `links`, `executed_tests`, plus `reused` and `bypassed` with reasons.
- `fingerprint_unchanged` is a distinct boolean from `reused`. Existing `hit`
  fields are not silently redefined; new consumers read `work-report-v1` and the
  old shape remains documented as comparison-only.
- `session` counters are cumulative for the process; `request` counters are
  deltas for one invocation. Both are emitted and their deltas reconcile with
  independently counted executions.

## 6. Semantic cache entries (C1/C2)

- In-memory retention uses one shared byte budget across ordinary, symbolic and
  specialization entries. A snapshot over budget keeps a bounded stable prefix
  rather than disabling reuse; relocation remaps only the references a body
  actually carries; oversized entries bypass retention; eviction is deterministic
  and index storage is compacted; clear releases every entry kind.
- Version tag `semantic-cache-v1`. Entries carry checksum, length, compiler
  identity, `effects-v3`, mutation-contract version, runtime ABI and build flags.
- Persistent references are stable qualified identities (defining module +
  declared name + declaration kind), never numeric catalog ordinals, pointers or
  allocator addresses. Decoding remaps them to the fresh catalog; missing or
  ambiguous remapping is a miss.
- Damaged, truncated, oversized or version-incompatible entries are discarded and
  re-derived. Only successful results are persisted; fresh errors never inherit a
  previous pass. Publication is atomic; readers never observe a partial entry.

## 7. Native structured trap detail (D1)

- Appended at the end of `MylQbeContext` and `MylQbeResult` (no context-prefix
  offset moves):

```c
typedef struct {
    uint32_t version;   /* 1 */
    uint32_t present;   /* bitmask; absent fields are zero and omitted downstream */
    int64_t  index;     /* original index, negative preserved */
    uint64_t length;    /* collection/object length at the failure */
    int64_t  left;      /* arithmetic operand where captured */
    int64_t  right;     /* arithmetic operand where captured */
    uint64_t width;     /* element width / integer width where relevant */
    const char *operation; /* static bounded name, e.g. "index", "pop", "div" */
} MylQbeTrapDetail;
```

- The structured detail is the single source for both text and JSON. JSON key
  `"trap_detail"` carries `version`, `operation` and only the present numeric
  fields; text renders the same values. The current text-reparsing JSON path is
  not extended.
- Values are captured at the failing operation; no receiver/index/expression is
  reevaluated and no unrooted guest pointer is retained.
- Native children emit one bounded record `\x1eMYLANG-TRAP ` + JSON + `\n` on
  stderr. Ordinary stdout, diagnostics and exit statuses are unchanged; a host
  that sees no such record behaves exactly as before. Infrastructure failures
  stay distinguishable from guest traps.
- Trap code, primary location, call stack, omitted-frame count, cleanup behavior
  and first-trap stickiness are preserved. The runtime ABI identity is bumped
  together with this addition.

## 8. Formatter canonical style (F1)

Four-space suites; one space around binary/assignment operators and after commas
and annotation colons; no padding inside ordinary delimiters; no trailing
whitespace; one final newline for nonempty source; two blank lines between
top-level declarations and one after the header directive group. Comments,
literal values, directive order and expression evaluation order are preserved.
Long-line wrapping, if added, is one fixed policy with no settings. These bytes
are the `--check` oracle.

## 9. Required import policy in ordinary projects (A1)

- Configuration filename is `mylang.json`. Discovery starts at the entry source
  file's directory (the entry project root) and walks up toward the filesystem
  root; the first `mylang.json` found wins. Shell working directory never
  participates. A path discovered from the entry directory upward is still
  anchored to the entry, not to cwd.
- Minimal versioned shape, strict JSON (unknown fields, duplicate keys and
  unsupported versions reject):

```json
{"version": 1, "import_policy": "policy.json"}
```

- `import_policy` is optional. When present it is a nonempty relative or absolute
  path resolved against the directory containing `mylang.json`; the file must
  exist and parse under the existing `import_policy.Policy` rules. A missing or
  malformed config/policy is a configuration failure (host status 2), never a
  silent skip.
- Once discovered, every ordinary command (`check`, `check-project`, `build`,
  `run`, `run-project`, project variants and native test preparation) enforces the
  policy through one shared frontend step, including unused direct imports, before
  any cached success is returned. Policy and config identity participate in
  verification receipts and caches: a stricter policy invalidates an earlier pass.
  Import-cycle checking stays independent and cannot be disabled.
- Projects with no `mylang.json` keep today's behavior. `check-policy
  --policy=path` remains for explicit inspection. There is no inline suppression
  and no ordinary-command bypass flag.

## 10. Exported effect API fingerprints (E2)

- An exported function requires an explicit declared effect ceiling. The declared
  ceiling (effect mask, plus the normalized mutation footprint and return-origin
  bound once M1/M2 land) is part of the public API fingerprint and invalidates
  consumers when it changes.
- The inferred implementation effect set is a diagnostic and test-cacheability
  fact only. A body edit that stays within the same declared ceiling must not
  change the public API fingerprint or invalidate callers' type checking.
- The public API fingerprint covers the declared effect mask, the normalized
  declared `mutates(...)` positions, and the exported return-origin bound. The
  language currently has no syntax for a narrower declared return-origin, so that
  bound hashes as explicit `unknown`; inferred private `mutates`/`return_origin`
  stay out of the public fingerprint and remain body/diagnostic facts.
- A change from `mutates(a)` to `mutates(b)` must change the function interface
  hash and the project interface hash; `mutates(a, b)` normalizes to sorted,
  duplicate-free positions and `mutates()` equals an omitted clause. Stable
  declaration identity (module/kind/owner/name) is intentionally unchanged.
- Non-exported helpers keep inference. A non-exported `main` keeps its current
  entry behavior. Exported tests follow the same rule as other exports.
- A missing-ceiling diagnostic is reported at the declaration; an optional
  compiler-suggested bound must be derived from the body and described as a bound,
  never emitted as an unconditional `effects(all)`.
- Parameter defaults, keyword parameter names, nominal type identities and generic
  requirements remain part of the public contract.
- Test declaration manifests are versioned `interface-contracts-v2` and carry canonical
  declaration-level type descriptors: builtin aliases normalize, transparent aliases
  expand recursively through arrays/callbacks/nominal applications, and nominal
  identities stay qualified. Test discovery and provider comparison consume those
  descriptors; a manifest from another version is rejected, never compared as text.
