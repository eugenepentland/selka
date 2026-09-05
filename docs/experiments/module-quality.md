# Module quality reports and interface roots

`report-project-quality` checks all reachable module bodies and reports resolved
calls, binding read/write counts, structural metrics, and two reachability views:

```sh
zig build run -- report-project-quality examples/modules/main.my
```

`reachable-from-main` follows calls from the selected entry main. The separate
`reachable-from-exports` view starts at every explicitly exported function and every
ordinary method of an exported domain in the loaded graph. Private domain methods
are not roots, but may be reached through public methods. The `module-exported` flag
marks actual roots rather than their transitive callees. The existing `private`
field describes domain-private methods; module export visibility is reported
separately. Calls retain qualified identities and their original file locations.

The report includes untaken branches and handles recursive cycles. An exported
function unused by main is a potential interface entry, not proof of an external
caller. Helpers reached only from exported interfaces retain that distinction. The
no-call-path review signal applies only when neither root set reaches a function;
it is advisory and limited to the loaded graph. Nothing is automatically deleted,
made private, or suppressed. Runtime coverage and assertions remain unmeasured.

The same configurable function-line, parameter, nesting, decision, and line-width
thresholds as single-file reports apply. Zero disables an individual signal. Source
metrics use combined-buffer indices while displayed paths/lines refer to original
files. Threshold findings do not change exit status. Invalid imported bodies reject
before any report is emitted.

Module reports use `quality-modules-v1`, distinguishing their explicit interface-root
semantics from the unchanged single-file `quality-v1`. Exact-v28 and near-v1 are
unaffected: export reachability is not a duplicate-equivalence fact. The embedding
`analyzeWithExports` accepts a checked list of function roots, validates bounds,
and tolerates duplicate/empty lists. `project_compile.Compilation.exportRoots`
derives this list from checked declaration identities and the interface index;
callers do not infer roots from naming conventions.

Acceptance covers main-only, export-only, and shared reachability; private helpers
behind exported functions/domains; isolated recursive groups; empty/duplicate/invalid
root lists; qualified cross-file calls; threshold advisories; original source locations;
all allocation failures through compilation/root extraction/analysis/rendering; and
real CLI rejection of invalid dependency bodies without partial reports.

Module formatting, broader corpus/scaling review, project native parity, generics,
compile-time/schema/incremental work, and wider native operations remain pending.
Future generated/schema entry points will require explicit roots when those features
are introduced; this report does not invent them.
