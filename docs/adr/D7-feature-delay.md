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

## Independently seeded components

The first progressive toolchain components have their own qualification stage.
They may use the explicitly enumerated `component-v1` profile after a compiler
that implements it has been pinned and qualified independently. The seed must
build without the component; the component must build using that seed alone.
A source/toolchain pin and executable receipt establish this dependency order.
This is not a claim that a compatibility release has occurred.

The full self-hosted compiler retains the release-delay rule above. Component
profile changes require a new seed qualification before adoption, including
pure tests, protocol and production parity, and a cold rebuild. A component
cannot implement a language feature and simultaneously require that feature to
rebuild its own seed. See [bootstrap source profiles](../bootstrap-v1.md).
