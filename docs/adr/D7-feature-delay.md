# D7: Delay compiler use of a feature by one version

Status: accepted.

## Rule

The compiler does not use a language feature in the same release that first
implements it. The feature first lands in the current compiler, passes the full
corpus, and survives one compatibility release. The following compiler version
may use it.

## Rejected alternative

Reject immediately rewriting the feature's own implementation to depend on the
new syntax or semantics. That creates a bootstrap cycle and can leave stage 0
unable to rebuild the compiler.

## Compatibility consequence

New features carry a release-of-first-use marker in bootstrap planning. Compiler
source keeps the older expressible form for one release, even when application
code can already use the feature.
