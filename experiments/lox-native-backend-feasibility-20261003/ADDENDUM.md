# Producer compatibility correction

This addendum supersedes the original note's paragraph proposing that the new
internal policy flag be passed to every `MYLANG_HOST_COMPILER` producer. The
original README, analysis, raw archive and `files.json` remain unchanged so the
first feasibility receipt is preserved. Lookup caught this issue during
independent read-only review, before any implementation.

A newly added flag can turn a successful older/foreign frontend invocation
into an unknown-option failure. That is a compatibility regression; calling it
an existing failure does not make it one. The narrow default is:

- Actual `MYLANG_HOST_COMPILER` override-produced emissions use original policy
  and retain their existing argv, without the new internal flag. Derive this
  choice before fragment/replay/module/object/no-op policy keys are selected.
  Do not infer compatibility from a producer name, a manifest identity string,
  a matching-looking descriptor, or QBE backend selection alone.
- Apply the same default to explicit foreign `native_test_options.Toolchain.compiler`
  producers. The ordinary CLI's current self-compiler path may select the QBE
  policy after effective backend resolution. A declaration-only/facts-only
  path remains original and receives no emission policy flag.
- Per-module compiles that explicitly spawn the current `/proc/self/exe` are
  different from override-produced whole-program emissions. Audit the actual
  producer path and carry its single effective policy consistently through
  project/standard variants, imported-interface config, selected test session
  and the final native library. If an override exists and this cannot be shown
  consistently, conservatively select original for the whole invocation.
- Standalone `compile-module` and raw public generation APIs keep their
  original default. New-policy selection is permitted only through an
  explicitly supported checked-emission API. No compatibility handshake or
  privileged proof metadata is needed for the initial narrow implementation.

Record this effective producer-plus-backend choice in every emission identity
listed in the original note. The same source, mode, compiler-generation and
QBE tool must not allow an original foreign-producer receipt to answer an
enabled self-producer request, or the reverse. A manifest-file build still
performs no new admission or transformation; its supplied IL remains its input.

Focused tests must include an old/foreign producer stand-in that accepts exactly
the old argv and rejects unknown flags. Both QBE and LLVM requested builds must
continue to succeed or fail as before with that producer, while current-self
QBE enables and LLVM/legacy adapter retains original policy. Verify original
IL/calls and cold/warm cache partition, not only the parent process's status.
No code, compiler, test or performance execution is part of this addendum.
