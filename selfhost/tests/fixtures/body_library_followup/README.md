# Pure compiler-library follow-up candidate

This isolated 24-case corpus is not part of the frozen B5/B6 installed manifest. Sixteen native generated programs return 7 with release/fact/leak checks; eight source diagnostics pin exact messages, byte spans, related notes and repair edits. Source hashes prevent unchanged counts from hiding fixture replacement.

The examples come from production dependencies: syntax_codec.ascii and codec/checking string iteration; full_adapter and body codec/sequences/suggestions byte iteration; cache_plan.incremental source-first comprehensions; body engine diagnostic str(int) and variant_patterns.fresh_key str/ord/buffer composition. Cases include UTF-8 scalar iteration, empty sources, break/continue, source-rebinding snapshots, negative-to-positive counted range capacity, filtered iterable and nested comprehensions, text/bytes comprehension elements, and signed integer formatting limits. Errors cover immutable/shadowed loop names, non-Bool filters, rendering arity/type, ord arity, a declared managed literal type mismatch and private imported constant access with its related declaration span. The added slice controls cover omitted endpoints, negative/clamped endpoints, reversed empty ranges and nested list snapshot independence. Nested collection iteration and canonical conditional expressions exercise selection-only runtime evaluation. Imported str/bytes literal constants use a separately hash-pinned donor. General scalar constant evaluation and embed initializers remain explicitly outside this admission scope.

Native semantics require exact text/bytes iteration guards/local ordering and internal u64 capacity arithmetic for counted range comprehensions. The absence of source u64 annotations does not excuse those typed rows. Dictionaries, generic callbacks, resource comprehension elements and broader prelude operations remain separate full-language work.

`run_body_library_admission.py --native-controls` deliberately executes only native fixture controls and reports selected admission as pending. It does not pretend unexecuted library checks were skipped or passed.

The actual admission invocation is:

```sh
scripts/build-slot.sh build python3 selfhost/tests/run_body_library_admission.py \
  --compiler /qualified/prefix/bin/mylang \
  --builder /qualified/prefix/tools/selka-components \
  --component-dir /qualified/prefix/libexec/mylang/components \
  --zig /pinned/zig --source-root /coherent/source/root \
  --report "$TMPDIR/body-library-admission.json"
```

It fails closed on seed receipt/package verification, missing source/test selection, profile/source refusals, differing native/selected results, cached/skipped/unsupported test receipts, and missing test identities. It runs reference/shadow/component fixture behavior, nine actual library checks, and six actual test roots at both normal and release/fact/leak settings, all forced and uncached with a 100M step budget. Existing shadow checks compare full typed batches/catalogs, not merely text dumps. Helper test results retain each named verdict and exact host/source/package provenance. Every mode keeps the other six boundaries reference.

Selected admission is pending until the producer/native validator implement the required forms and a coherent installed package qualifies. Nine libraries and six test roots do not cover all seven package entry closures. B7 capabilities, file/resource lifetime, streams, bootstrap second-generation checks, and retained signature/catalog/contracts/effect/backend owners remain separate acceptance work. No timing or <=1.5x claim follows from these controls.

The strict selection requires all24 source controls (16 success/8 diagnostic), plus the hash-pinned imported literal donor. Native-only execution contains40 operations. Full selected admission contains120 fixture operations and63 actual-helper operations (183 total); unchanged nine library/six test-root obligations remain mandatory. Extra/missing sources, donor changes and nonempty profile refusals cannot count as admission.

Native controls were rerun against frozen B5 Debug host e379d007c0a9a5e97f9c1fa9b6c4138958e8359ca3081b098f783e398c20e46e: 24 project checks and16 generated release/fact/leak executions (40 operations), all expected verdicts. Private imported constants exercise retained interface visibility, not a body ownership claim. Native write-through of an iterated nested source traps R_LIST_ITERATION_MUTATION; the nested success control is intentionally readonly, while list-slice snapshots exercise mutation outside iteration. Exploratory legacy conditional and builtin-shadow failures remain in private raw evidence and are not counted as passes.
