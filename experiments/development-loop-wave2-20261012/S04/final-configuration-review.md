# Explicit wave 2 configuration consumer qualification

S04 independently reviewed the current integration build/list/native-producer
consumers and recommends the coordinator explicitly qualify:

`4493db3a525705b6f1222c50796175cdff55b2301d5160e8d02297d43942885e`.

The 212 CONFIG_INPUTS-only file hashes, excluding the declarative list file, are
bound in final-configuration-audit.json. No pin was changed by S04. Current lists
match the freshly exported inventory exactly: 46 groups, 106/106 registered actions,
no unknown actions, 16 verification-cache members. The prior pin remains broad
until the coordinator explicitly records this review.

Reviewed consumers: build.zig addInputManifests/cached cohort registration,
build_verification declared/inputLists/native wrappers/reachable member indexing
and producer writer Run inputs, input_manifest expansion, fixture coverage, and
verify_cache strict complete data parser/action_configuration. All list uses are
file dependency/data contracts; no list-derived commands, flags, tool providers,
mode/ABI policy or arbitrary executable configuration were found. Arbitrary build,
Guardian, Zig/standard library and configuration code stay broad. The list remains
watched even when its bytes are projected from action identity.

Native proxies add fixed command prefixes in reviewed build code and explicit
verdict-affecting Python file inputs. Pure tooling/scalar producers retain their
complete source/embedded closures and selected detached records; omitted source
metadata takes whole-artifact fallback. Code-identity helper, loaded-code format,
measurement/admission and qualification changes remain in common implementation
and watched coordinator closures. Fuzz/Juice adapters inherit those expanded
closures. Canonical code identity migration uses receipt2/action5 and preserves
common root/environment and source/ownership/ABI invalidation fields.

Two discovered wiring defects were corrected before this recommendation:
code_identity_test was declared but not registered, and writer Snapshot's newly
imported code_identity helper lacked a Run file input. Additional Juice helper
imports are now declared in juice_pure/juice/juice_runtime. Other build_admission
imports are covered by verification-cache/fuzz/Juice recipes; parity and debug
benchmark commands are opt-in fresh developer actions outside the required gate.
The pure/native telemetry proxy does not dynamically consume report code for its
verdict; report helpers remain advisory. Required group/member additions are fully
represented by the regenerated inventory.

Regression records read from coordinator logs: fixture source coverage PASS,
coordinator 88 tests PASS, selected caller 3 tests PASS, code-helper authorization
7 tests PASS. Exact raw-log SHA256 values are in final-configuration-audit.json.
Snapshot 77 tests and eventless metadata/deferred tool 4 actor fixtures passed in
S04; the fourth production actor patch is supplied in fourth-actor-root-patch.txt.
Root added it and retains all remaining metadata/watch validation boundaries.

S10's 40 balanced paired planning observations compare the actual loaded functions
on frozen B0 inputs with exact dependency/member/report equality. Only reviewed
v4/v5 action domain and receipt1/2 namespace values normalize; actual keys/domains
remain separate. Observed medians 2.077760→1.869006 seconds, empirical p95
4.875942→4.175622 seconds. These are a planning-slice result, not final frozen
production or whole-loop qualification. Setup30.788 seconds is separate; total
220.761 seconds includes setup/validation. No RSS or full-gate inference follows.

Coordinator should record the explicit pin/source/regression provenance and freeze
the final candidate before S10's complete gate, formatting and live edit matrix.
Any further CONFIG_INPUTS changes require renewed consumer review. Python-only
coordinator source changes still invalidate through watched/actual loaded identity;
they do not authorize automatic pin updates or unsupported narrowed dependencies.
