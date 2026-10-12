# A02 C3 preparation handoff

Base runtime revision `c749ad5a9d2dfef5d5c4d7b9de2a30f03029999f`. Evidence-only proposed commit is the commit containing this file. Owned production files covered by the unapplied patch: `src/core/runtime/core_rt.c`, `src/core/runtime/core_bytes.c`. No production files changed.

Fresh results: original capacity13/13; owned ABI/copy/mutation/destruction native pass; count-member negative compile pass; legacy symbol audits clean. Exact source and artifact identities in manifest.json/native-results.json/preserved-owned-bodies.json. Seventeen selected function bodies remain byte-identical. Required unit/guest test migration patches are prepared separately and remain unapplied.

Commands: under shared build admission, `python3 -B experiments/memory-closeout-20261012/A02/retirement/integration-c749ad5a9/native-preview.py --source-root /home/epentland/ai/canopy/mylang-memory-20261012 --scratch .tmp/memory-closeout/A02/retirement-c749ad5a9`; then `count-member-check.py` under another admitted build lease. Native assembly follows the pinned driver embed order and hashes every input. Scratch path contains the candidate runtime source and binaries; reports retain hashes and raw output.

Dependencies: A07 ABI/emission confirmed; A09 counter-hook removal coordinated; A05 paired runtime/durable evidence available; A04 text/values and A01 task retirement remain separate owner patches. The preview still uses MYL_ZERO_RC for peer runtime files, explicitly documented in README and machine-readable results. No claims about final default/retirement, installed components, runtime speed, RSS or compiler scaling.

Activation remains blocked on coordinator C2 approval and the coupled changes. This is an intentional prepared rollout artifact, not a completed implementation. Preserve the historical parent/nested-extension preview and all ordinary-mode native controls.
