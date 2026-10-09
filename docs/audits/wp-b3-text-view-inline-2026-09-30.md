# WP-B3: preserve native text view inlining

The frozen composed `7f5068a5` QBE text_ops profile showed `long_piece`
executing 190,000 times. Its previously inlined `view` became an out-of-line
74-instruction routine: 103 instructions per control call versus 46+74 in the
candidate, adding exactly 3,230,000 simulated instructions. The view body was
byte-identical. The complete rejected-candidate attribution archive is owned by
the integrator; its SHA256 is
`3fe259245d16de599c5a19da633b65a934c546cd65cfbf785862b4fa93877433`.

This continuation starts from `40bd74a0c52939c5f92d56f3a447269592077bd3` and changes
one declaration in `src/native_text.c`: `view` becomes `static inline
__attribute__((always_inline))`. A byte comparison against the base proves its
body, headers and callers are unchanged. Internal C linkage is preserved, and
the annotation matches this file's existing `cut` helper. Allocation/rooting,
view policy, failure cleanup and checked owner/MAX admission remain identical.
Existing TEXT-VIEW-1 through TEXT-VIEW-5 and RC-VIEWS-1 cover the behavior.

Validation used exclusive local caches/TMPDIR and build-slot admission for every
compiler build, native suite and heavy guest execution:

- Fresh compiler-only install: 12/12 steps; whole-tree Guardian: 88/88 checks.
- Seven optimized C/UBSan families: native text views, text indexing, text
  methods, RC collections, heap, Python primitives and regions. RC collections
  executes 47 cases, including real text-view count-limit and backing-budget
  refusal/rollback. Native view cases exercise slicing, splitting, tails,
  Unicode, receiver lifetime and arena escape; the Python family includes
  4,000 reverse oracles and trim/repr budget/refusal checks.
- QBE, LLVM3 without LTO, LLVM3 full LTO and LLVM3 ThinLTO text_ops binaries:
  all four byte-match the expected output. Every actual executable retains
  `long_piece` and has zero out-of-line `view` definitions or call/jump targets.
  This removes the call boundary observed in the 190,000-call frozen workload;
  no new dynamic call-count or performance claim is made.
- Actual `tests/lang/text_views.my`: all ten exact test identities execute and
  pass under RC and again under GC stress, 20/20 total, zero omitted, cached,
  skipped or failed tests.

Compiler SHA256:
`873eb7fdfbecd7a904403b1e0c66dbc159881267312992db380b8abdc9c3c4b4`.
Modified native_text.c SHA256:
`3cff19ae3ee358d7918f0455f04354d7d3aaf089543f73c53497f6b474524839`.
The installed runtime source consumed by all four guest caches is verified
against that modified source. Raw commands, statuses, source copies, assembly,
symbols, native executables and guest JSON are packaged under
`experiments/wp-b3-layout-20260929/view-inline/` with a verified member manifest.

No timing pool was claimed and no duplicate full corpus or broad gate ran in
this lane. The integrator owns final composed gate and performance acceptance.
This candidate does not change the independent LLVM raytrace zero live range,
RC width/ABI, scope costs or any overflow admission.
