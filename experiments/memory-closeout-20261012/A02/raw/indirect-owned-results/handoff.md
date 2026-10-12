# A02 indirect owned-result handoff

- Base: `78213cabec272c321a24850fc7e5099a319b51b6` after the separate bounded
  aggregate-worklist repair. The coordinator owns integration and final retesting.
- Production edit: only `src/core/own.zig::ownedRecord`, admitting an internal
  `call_indirect` result under the same existing proofs as direct calls.
- Tests: `a02_indirect_owned_test.zig` and formatted source fixture; coordinator
  authored the `root_test.zig` import. Existing CALLBACK-1 contract applies.
- Validation: registered 2/2; five checked modes and two native callback choices;
  two borrowed-return refusals; 21/21 independent matrix runs including all 26
  unchanged `rc_pin_elide` Boolean oracles and ordinary release/debug controls.
- Exact candidate SHA256:
  `37742e49746da007fd9caea88680369945d1b3e2852c71940029370142f1be30`.
  Source/toolchain/commands in `registered.json`; raw counters in `native/`;
  genuine indirect-call IR in `indirect.facts.txt`/`diagnostic.json`.
- Baseline exact fixture refusal preserved in `baseline.json`. No source-checker
  waiver, result-contract relaxation, runtime ABI change or performance claim.
- Separate A05 investigation: sibling scalar interior mutable arguments may need
  refreshed-parent writeback; that issue is outside this managed-result fix.
- Historical runtime retirement drafts remain unapplied. The final integrated
  compiler must requalify changed paths; these hashes must not label later builds.
