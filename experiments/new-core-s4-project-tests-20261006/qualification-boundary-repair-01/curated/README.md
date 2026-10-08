# S4 qualification tooling repair

Only five qualification Python files changed: the four existing adapters/tests
and new `qualification_provenance.py`. `qualification_support.py` remains exactly
`6f78a8ff7627b38c89aa4b5bd9e461aa1cdac214d78ab53297b3192da873f49f`.
No compiler, native guest, build, gate, fuzz harness or performance comparison was
run. The pure suite runs Python timeout/cleanup fixtures and injects synthetic
`CompletedProcess` results into strict-monitor unit tests. It never executes the
compiler-shaped fixture files. No compiler/src/build files or Git state changed.

## Receipt and CLI contract

All three qualification adapters require `--old-origin RECEIPT` and
`--core-origin RECEIPT`, in addition to the existing source assertions. The source
assertions must match the production source recorded by the genuine receipt, and
the requested executable bytes must match its artifact SHA. Canonical recorded
compiler paths are used for execution, independently of caller-supplied aliases.

Two explicitly reviewed codecs are accepted:

* `reviewed-s3-c-legacy-v1`: the exact S3-C corrected-oracle receipt retained in
  commit `51e641fa3`, source `65036fe792ef540392d0eb00c41c9ec71c7b2c82`, old SHA
  `d36658dbfb78d29213224532a13fd5ad8b7c0e290dbfb87613d9815678305c79`.
  Receipt SHA `c47616a8fa55b01c337ef9890cda337c06b4373f265315ccaf66d6a53a7802ce`
  and the genuine install/full-old-gate/validation bytes are pinned. Its separate
  build/evidence HEAD is unknown (`null`); no Capture fields are invented.
* `reviewed-control-compiler-origin-v1`: the actual E schema 1
  `control-compiler-origin` producer SHA
  `93c8c64a3dbec5bd562e1fbf4fde24aecd35c8c328aa16c1575a3776fa38b035`.
  Complete/qualified/error flags, full identical before/after input fingerprints,
  complete production Git source blobs and consumed repository input blobs,
  successful frozen Capture/process/raw job/result/output receipts, original
  producer/tool bindings, build-slot action, and fresh local/global native-cache
  recipe are checked. This producer builds Debug Core; a future old/RF/other
  producer needs its own review. Historical partial schemas are refused rather
  than retrofitted with fields not captured by their original build.

New manifests use `schema: s4-qualification-v2`. `compiler_origins` records each
receipt/chain hash, production source, actual build source and artifact SHA;
`qualification_head` records the later qualification/evidence HEAD separately.
`core_source_diff` compares production source with active src/build.zig/build.zig.zon.
Package/final scope requires that diff empty. Diagnostic controls declare the
diff. Evidence-only HEAD changes before a run remain legal; any HEAD/source/tool/
harness/receipt drift during the run refuses qualification.

Example receipt arguments for the corrected legacy old oracle are:

```text
--old-source 65036fe792ef540392d0eb00c41c9ec71c7b2c82
--old-origin experiments/new-core-s3-20261006/wave-b/s3-c/resume-context-corrected-oracle.json
--core-source ACTUAL_PRODUCTION_COMMIT
--core-origin ACTUAL_FRESH_BUILD_RECEIPT
```

The source/build receipt is evidence from an actual recorded build, not a label
created from the current HEAD or a rewritten historical receipt. Origin validation
identifies a compiler artifact; it does not by itself qualify compiler behavior.

## Live inputs and scopes

Generated project phases inventory all member bytes and file generations. Each
old/Core command checks its phase before and after execution; every case and the
final aggregate recheck again. Explicit mutations may change only the declared
leaf/provider/case paths; unrelated concurrent edits refuse the phase transition.
Retained snapshot hashes must equal the live phase.

The S4 local fuzz monitor preserves actual compiler argv/source paths and checks
complete input-root membership/bytes, imported modules/API/provider/embedded
files, nearest-config discovery absences and policy inputs across modes. Only
exact fresh invocation output/cache paths are excluded. A new case may advance
the phase only after the previous case has all old/debug/release/verify builds
and native argument outcomes. An unowned enclosing project tree or directory
alias is conservatively refused. The inherited S2/S3 sources stay frozen.

S0/S1 use mkdtemp/rmtree; text uses TemporaryDirectory; RC's explicit keep root
remains live. Scoped hooks register reviewed generator-owned roots, verify and
retain all inputs immediately before intentional cleanup, and record successful
removal. Unproved removal, mutation before cleanup, additions, or incomplete
cleanup fail. Remaining live inputs and external config/policy paths are checked
at worker completion and again at the whole matrix's final aggregate. Content
copies are deduplicated by SHA; cleanup never discards the retained input bytes.

Optional executed must equal passed+failed; dropped/unloaded must be typed integer
zero. Full all-file conformance requires leakcheck, verify, both modes and exactly
1518 comparisons per mode. Each manifest declares component and scope:
diagnostic partial selections/counts, package 50-case matrices, final 200-case
matrices or full conformance. A worker also declares parent origin binding required.
Scope describes that component's coverage, not completion of the whole S4 exit.

## Retained tests

Bootstrap RED00 was a shell redirection into a missing evidence parent; it ran no
tests. Pure run01 retained one fixture-layout failure: synthetic strict-monitor
inputs enclosed its own generated evidence, correctly triggering the live guard.
The fixture was separated from evidence. Run02 passed 21 tests, run03 passed 23,
and run04 passed 24; each receipt names its exact pre/post source bytes. Later
source refinements are qualified only by the final fresh suite receipt.

Final pure run05 passes all 26 tests in 5.291s (5.430s command), with identical
pre/post tool-source hashes. The final curated source handoff and artifact
manifest bind those bytes and all copied raw/text fixtures. No Guardian gate was
invoked in this tooling-only task; independent parent review precedes use.

The original boundary REDs are copied unchanged into curated evidence, including
the wrong a16a/d366 source label, live project edit/addition, source mutation across
fuzz modes, contradictory report counters and missing full-mode flags. Additional
pure alias RED05 demonstrates the historical Tool storing a caller alias while
the manifest stores its canonical binary. No protected artifact was modified.

Python timeout fixtures retain partial raw output and prove descendant cleanup and
concurrent-command isolation. The whole old/fuzz exclusion lock remains the
required external invocation contract. No full package/final compiler gate was
admitted by this tooling task, and Wave B remains held.
