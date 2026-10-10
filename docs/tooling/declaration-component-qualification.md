# Declaration component qualification

The installed declaration boundary is qualified in `reference`, `shadow` and
`component` modes through `MYLANG_DECLARATION_MODE`. Native body checking stays
in place. Isolated cases keep lexer/parser modes in reference; three additional
workflows select all three frontend components together. Installed execution
uses an empty PATH, an explicit native Zig path, and no Python runtime.

`selfhost/test_declarations.py` verifies the qualified seed through the native
coordinator, discovers nonempty declaration `*tests.my` roots and checks exact
uncached pure-test verdicts in normal and release/fact/leak modes. It then runs
`selfhost/tests/run_declaration_qualification.py` against the installed host and
all five verified component packages. The declaration package is explicitly
protocol/schema 1; existing lexer/parser packages remain protocol 1/schema 2.

The current fifteen fixture entries cover duplicate declarations, import alias
conflicts, public/private domain visibility, private imported declarations (including the standalone test-module exception
and its refusal once imported) and
re-export identities. Whole diagnostic-v1 output, including related locations,
is compared byte for byte. Checks, interface/schema/navigation outputs,
implementation source edits and restoration, build/executable/run behavior and
two actual tests are compared. Repeated outputs must preserve exact ordering.
The selection is 30 workflows and 60 comparisons; the coordinator edit repeats
the workflows for 120 comparisons in the normal lane.

Warm checks publish against the same private component directory before each
mutation. Missing manifests/artifacts, unsupported schemas, corrupted artifacts
and replacements with matching digest but incorrect protocol must fail as host
errors before replay. Thirty warm checks retain stable paths and environment;
four live checks mutate the deployment inside a running check-session. Cache
receipt probes enable caching without fact/leak flags, while ordinary workflows
retain fact/leak qualification. Component mode must demonstrate two cached test
receipts; shadow must rerun both tests.

The installed binary accepts the bounded `SLKDIX01` exchange. Qualification
binds the complete `SLKDCL01` payload through its SHA256 and nonce, validates
an empty successful reply, and requires nineteen malformed requests to reject
with exit 2 and no partial stdout. Production transport limits are independent
of harness limits: requests/replies fit 32MiB, source fits 1MiB, declaration and
dependency symbol counts fit 65,536, imports/dependencies fit 4,096, aggregate
name/key bytes fit 1MiB, and source paths fit 16KiB. Qualification subprocesses
inherit a 2GiB address-space ceiling and bounded output/deadline, preserving any
stricter caller limits; these are external test budgets, not a production memory
policy.

The normal lane also copies the component closure privately and uses the native
coordinator to rebuild a dynamic declaration implementation edit. It requires
changed declaration key and artifact bytes, unchanged other four receipts and
host bytes, and exact workflow parity against the new deployment. No direct seed
build bypass is used. Timing is separate and remains unqualified until an
isolated ReleaseFast baseline/candidate run is explicitly performed.

Eight installed-host checks also deploy pinned-Zig compiled native fixtures that
return the correct protocol magic and correlation bytes but forge declaration
results. Empty/incomplete tables, oversized counts, undefined outcomes and
out-of-source spans must produce host exit 2 in both shadow and component modes.
The fixture is developer-only C, runs without Python, and deliberately passes
manifest digest authentication so result validation is exercised independently.

`measure_declaration_adoption.py` prepares isolated warm/edit/interface evidence.
The frozen prior host runs reference only because it has no declaration boundary;
the candidate runs reference and component with lexer/parser held in reference.
Both use the same fixture project, explicit qualified seed verification and
corrected blocking process wait with deadline watchdog. Shared native objects may
be warm across runs; cache reports are retained. Run this only after correctness
qualification under the approved outer gate and all three FIFO build reservations
on CPUs 2,3,10,11. No timing result is implied by registration of the driver.

Domain fixtures exercise inherited owned-method publication and private-member
refusal. The multi-hop facade fixture uses re-exported type, function and
constraint names and compares complete interface output. Private target failure
precedence and local facade collisions preserve their related locations. Bare
`export NAME` is removed by the parser: its explicit source rejection is marked
as a parser boundary case, while repeated direct-export algorithm compatibility
is exercised through the producer's pure projected-facts tests.
