# Generic free-function producer and schema 11 adoption contract

This is a separate rollout from the qualified schema 10 deployment. The producer
owns concrete call inference, requirement diagnostics, signature substitution,
first-demand registration, executable IDs, recursive reuse, and body checking.
The initial slice covers ordinary free functions with scalar/value arguments,
ordered type binders, and literal or forwarded fixed-array lengths. Nominal
generic applications, callbacks, structural/named/codec requirements and general
constant expressions remain explicit profile boundaries.

Executable IDs start with all nongeneric declarations in raw declaration order.
Concrete instances follow first demand. Their keys retain the resolved raw
declaration ordinal, ordered runtime type IDs, and parallel nullable lengths.
Constant slots use `u64` plus a nonnull length; ordinary type slots have null
lengths. Canonical names use native runtime spellings such as `i64`, rather than
diagnostic spellings such as `int`. Keys reuse their original executable ID on
recursive demand. The limits remain 16 arguments and 4096 instances per
declaration; lengths are unsigned and at most 1048576.

The native boundary must prove the ordinary prefix, declaration spans, unique
keys, canonical names, closed type/requirement roles, and prior executable demand.
An added instance cannot justify itself solely with a recursive call. Complete
body graph, function ranges, parameter metadata, and call typing retain their
existing validation. Resource-scope proof must join to the same raw declaration
span rather than assuming executable IDs equal raw declaration ordinals.

Selected catalog recipes materialize before signature authentication. Adoption
then restores the proved ordinary mapping and instance registry, authenticates
substituted parameter and result types against raw signatures, and checks that
authentication adds no catalog or semantic instance authority. It must not invoke
native body checking. Selected function IDs are adopted unchanged; calls are not
rewritten from raw indices. Native specialization cache fingerprints must not be
fabricated for selected bodies.

Native common-phase symbolic-template checking remains retained. A checked
concrete instance does not prove that an unused generic template is universally
valid. Native signature resolution may observe existing retained catalog facts
and populate lookup caches, but cannot create unselected types, instances, or
change semantic definitions. The adoption implementation must distinguish and
verify these effects explicitly, beyond merely comparing catalog lengths.

Current focused producer tests cover an ordinary declaration after a generic,
explicit and contextual/operand inference, recursive reuse, related diagnostics,
fixed-array element/length inference, and canonical instance names. They are not
installed qualification. The unconnected native identity proof is also not an
active schema change. Activation requires a coherent schema 11 validator and
adoption commit, authentic reference/component/shadow controls, and hostile
duplicate, declaration, signature, demand and argument metadata tests.
