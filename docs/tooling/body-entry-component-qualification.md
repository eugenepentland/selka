# Component entry-source qualification preparation

`selfhost/tests/run_body_entry_qualification.py` is a separate B7 harness. It does
not change the frozen B6 corpus or assert installed schema-7 support. Its strict
manifest preserves 24 native-controlled resource cases: 14 successes, eight exact
source diagnostics with ordered notes/repairs, and two native-valid explicit
profile refusals (`file.write` and text `readline`). The original native receipts
and source hashes remain in `body_entry_candidate/proposal.json`.

The coordinator always builds component guests with its qualified `seed.binary`.
It strips `MYLANG_*` mode controls before that build. A coordinator rebuild proves
seed and recipe qualification; it cannot prove selected body ownership. This
harness verifies the seed receipt, then directly calls the installed compiler with
`MYLANG_BODY_CHECK_MODE=reference|shadow|component` and `--no-cache`. Other six
component boundaries stay reference. No Python runs in generated artifacts.

Every real component entry is mandatory: test-index, cache-plan, lexer-pilot,
parser-pilot (`full_adapter.my`), declaration-index, type-interface and body-check.
Each is checked and built from source in all three modes. A bounded native capture
wrapper forwards the selected body exchange unchanged; 35 fresh authenticated
schema-7 request/reply captures prove these selected source operations executed
that boundary. Missing captures, profile refusals or shadow mismatches fail the
run. Shadow remains the complete typed batch/catalog oracle, rather than textual
typed dumps. Compiler bytes, installed packages and the entire component source
closure are checked for drift before complete publication.

The first component-mode builds form a private authenticated seven-artifact
deployment. The installed compiler then builds all seven source entries again
with that deployment's newly generated body checker selected. This is a second
component generation, not a new compiler generation: native catalog/signature
checking, driver, effects/origins, postpasses and backend remain. Private generation
keys bind host/source/parent-artifact identities and exact flags, with separate
receipts. They are not inserted into the coordinator's qualified seed artifact
store and are not represented as coordinator-qualified receipts. Run the normal
lane and the `--release` lane, which adds `--release --verify-facts` to generated
builds. Both enable guest leak checks; these are not timing artifacts.

The strict action total per lane is 349: 72 fixture checks, 44 fixture builds and 44 runtime
runs; 21 actual entry checks; 28 actual entry builds across the first and second
generations; and 140 entry runtime probes. Every installed or generated artifact
has usage, missing-file, malformed-file and successful authentic-request probes.
A required `requests.json` contains all seven packages, with pinned nonempty
request files and their capture provenance. A successful probe must exit zero,
produce a nonempty reply, and have no stderr; all generated probes compare exactly
with the original installed artifact. Lexer's raw malformed-source response can
legitimately be status zero, so its bytes are compared rather than reclassified.

For each of the six repeated-scope fixtures, `RLIMIT_NOFILE=32` applies only to the
generated program, preserving stricter inherited limits. Each executes 128 scope
exits, covering normal exit, early return, caught checked failure, break, continue
and nested return. Exact runtime output and pre-global-cleanup leak checks must
match. This proves no descriptor accumulation on those routes; it does not prove
runtime reverse close ordering. Existing native typed/IR cleanup observations stay
separate evidence and are not substituted for generated runtime checks.

Example once a coherent schema-7 install and authentic request corpus exist:

```sh
scripts/build-slot.sh gate python3 selfhost/tests/run_body_entry_qualification.py \
  --compiler /qualified/bin/mylang --builder /qualified/tools/selka-components \
  --component-dir /qualified/libexec/mylang/components --zig /pinned/zig \
  --source-root "$PWD" --requests-dir /private/authentic-requests \
  --work-dir /private/new-b7-work --report /private/b7-report.json --release
```

The work directory must be new; failed runs retain raw output, all 35 exchanges,
generated binaries and incomplete JSON. The six adversarial selftests run with
`python3 selfhost/tests/body_entry_qualification_test.py`. They validate strict
selection, exact native contracts, request completeness, captured correlation,
descriptor-limit isolation and full action accounting. They are developer tests,
not installed admission.

Unresolved integration requirements are explicit: the coherent schema-7 host and
producer are not yet qualified; all seven source closures must fit the selected
body profile and two-million-value/wire/allocation bounds; and seven authentic
successful replay requests must be supplied from the existing native qualification
captures. No requirement can be silently omitted. Full-language compiler ownership
and the 1.5x performance goal remain separate work.

Capture completion requires the exact 35 distinct `(entry phase, mode)` pairs, not just a total. Each fresh request/reply is retained in deterministic gzip with original and archive hashes, so later captures cannot overwrite earlier proof. All CLI paths are resolved before private work changes the child cwd; the adversarial tests exercise relative full-gate arguments.

The tracked `selfhost/tests/generate_body_entry_requests.py` prerequisite accepts explicit installed compiler, component directory, pinned Zig, source root, and a new output directory. It captures all seven requests through authenticated native forwarding fixtures, compares reference outcomes, validates framed correlation and schema, and replays each request against the real installed artifact. It seals host, toolchain, component, and source identities before publishing `complete: true`; partial inventories cannot feed the source gate. Cache-plan comparison excludes only the deliberately mode-dependent cache/work object, retaining raw reports and exact executed-test outcomes. This developer prerequisite is not part of installation.

The mandatory `test-selfhost-body-entries` gate generates its seven authenticated runtime inputs from the installed deployment, then runs normal and release/fact/leak source lanes. Each lane requires 349 source operations, 35 distinct fresh source captures, two independently probed artifact generations, and a separate 15-case resource-reply attack inventory. Attacks include sibling-scope file use and wrong open, file-shape, scoped-local, resource/slot, and Stream authority. Final initialized=false flow metadata is not an attack: native match restoration can legitimately produce it. Every hostile verdict is persisted before its exact ComponentProtocol diagnostic is checked. The `test-selfhost-body-entries-self` target checks accounting without installing a compiler. Selected source admission remains pending until this entire gate passes.
