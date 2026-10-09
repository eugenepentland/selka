# Exact duplicate discovery experiment

Implemented command:

```sh
zig build run -- discover-duplicates examples/duplicates.selka
zig build run -- discover-duplicates examples/duplicates.selka --min-nodes=8 --population=production --timings
```

`exact-v3` runs after complete semantic checking and before lowering. It does
not execute guest code. Findings are advisory and exit 0; source errors still
exit 1 and host/usage failures exit 2. Ordinary `check`, `run`, and
`dump-bytecode` do not run discovery. Binding warnings retain their existing
stderr behavior. Reports go to stdout; optional measurement goes to stderr.

## Comparison contract

The unit is a complete checked function. Canonical serialization retains the
return and parameter types, local types/mutability, declaration-slot identities,
literal values, operators, operand/argument order, lexical blocks, branches,
loops, discard, stores, and resolved calls. It excludes source spans, spelling
of bound names, and advisory counters. Parentheses, literal spelling, and
compound-assignment spelling have already been resolved by semantic checking.
There is no algebraic simplification, reordering, or arithmetic folding.

Direct self-recursion uses a dedicated self marker. This is an explicit
normalization of the function's own binding. All other calls preserve their
resolved function name within the checked source file. Distinct mutually
recursive components are not renamed. Reordering declarations therefore cannot
change comparisons through accidentally different numeric function IDs.

A string hash index stores full canonical bytes and compares those bytes when
hashes collide. A hash alone never establishes equality. Each group lists all
members once, in source order; the implementation does not enumerate every
matching pair. The default threshold is eight visited expression/statement
nodes, including the root block. `--min-nodes=N` accepts a positive integer.
Canonicalization walks with an explicit work stack, including long expressions.

The report provides every member's source location, shows up to twelve lines
of the shared body using the first member's spelling, and describes the
preserved and normalized structure. No helper is silently selected as canonical. The
language has no canonical-helper declaration yet. Exact structure can still
represent independent policies; it neither proves shared intent nor justifies
an automatic merge. Source code is never modified.

## Populations and limits

Each invocation analyzes one complete source file. `--population` labels that
invocation as `production`, `tests`, `generated`, `reference`, or `intentional`.
It defaults to production. Inputs from different invocations are never combined.
Separate mixed populations into review corpora; this flag does not classify
individual functions or infer whether they are independent expectations.

Record support preserves nominal record names, resolved field names, field
initializer order, construction versus update, and the conversion contract.
The compiler still has no nominal scalar wrappers, resources, or declared
external effects; analysis cannot claim to preserve absent metadata. New typed variants must extend serialization and
negative fixtures before discovery supports those language features. Whole-
function matching can miss useful repeated blocks and semantically equivalent
implementations. Changed constants, operators, or resolved external callees keep functions in
separate exact groups. [Opt-in approximate discovery](approximate-discovery.md)
now reports bounded near matches separately, with explicit canonical edits.

## Reviewed evidence

These are deliberate, inspectable examples, not production defect statistics.

| Corpus/case | Observation | Review outcome |
| --- | --- | --- |
| `examples/duplicates.selka`: sum_to / legacy_sum | One exact group of two 20-node functions despite renamed locals/parameter | Useful reuse candidate: source explicitly identifies the second as a legacy copy. No automatic extraction. |
| Same file: inclusive_sum | No match with the exclusive loop because `<=` differs from `<` | Correct separation of changed policy. This also illustrates an eventual approximate-match candidate whose operator difference must be shown. |
| `duplicates_test.zig`: swapped operands, changed constants, operators, bool/i64, external callees | No exact groups | Required distinctions remain visible. |
| Direct recursive factorial copies | Exact group; self bindings normalize | Worth reviewing for reuse, not evidence of a correctness defect. |
| Three independent identical functions, population intentional | One group with three locations and advisory wording | Intentional independence remains permitted; analysis does not make the program invalid. |
| Generated benchmark corpus | 31 repeated arithmetic policies with renamed function/parameter bindings | Scaling input only, not an estimate of useful findings in real code. |

[Approximate discovery](approximate-discovery.md) now explains changed constants,
operators, and callees without relabeling them exact. Further ordinary-program
review and scalable candidate indexing remain future improvements.

## Measurement

```sh
zig build -Doptimize=ReleaseFast
python3 scripts/benchmark_discovery.py --mode ReleaseFast > baseline.json
```

The script records machine, Zig version, declared build mode, input sizes, all
samples, and medians for frontend and discovery separately. Build mode is an
explicit caller assertion; build with the command shown before collecting data.
`frontend_ns` measures lexing/parsing/checking; `discovery_ns` measures canonical
serialization and indexing. Neither includes host build, file I/O, source
copying, report rendering, lowering, or VM execution. Byte and node counts
provide input context. Measurements are observations, not performance gates.


The initial local ReleaseFast samples are checked in as
[discovery-baseline.json](discovery-baseline.json). They cover 100, 1,000,
and 10,000 helpers with five samples each. They demonstrate this generated
workload only; they do not establish scalability for future aggregates,
modules, or approximate analysis.


`exact-v2` adds record/field identities and conversion contracts to canonical
serialization. The checked-in baseline JSON remains historical `exact-v1`
evidence; rerun the benchmark script to measure this version. Primitive
normalization and recursion policy are unchanged.


`exact-v3` adds explicit integer casts and preserves signedness/width identities.
Record IDs remain internal compilation identities; comparison uses resolved
names, so inserting built-in types does not conflate unrelated records.


The array extension advances the comparison version to `exact-v4`. Structural
array type names encode length and resolved element identity. Canonical nodes
retain ordered array construction, indexed reads, replacement arguments, and
length operand evaluation. Array type whitespace, the spelling of a length (`[2]`, `[0x2]`) and bound names
remain normalized. `src/arrays_test.zig` verifies these distinctions; historical
benchmark files retain the version actually measured.


Nominal domains advance the comparison version to `exact-v5`. Canonical function
headers retain the owning domain and private/public visibility. Wrapping and
unwrapping remain explicit nodes, and external calls retain qualified names.
`src/domains_test.zig` checks identical bound-renamed methods in one domain and
distinguishes other owners, access contracts, and qualified callees.


Closed variants and matching advance the version to `exact-v6`. Constructors
retain resolved variant names and payloads. Match statements retain source arm
order, variant-to-body mappings, and payload local slots, while normalizing bound
spelling. `src/variants_test.zig` verifies renamed equivalents and distinguishes
changed constructors and arm bodies. This does not introduce approximate matching.


Complete enum tables advance the version to `exact-v7`. Table type identity
includes the nominal enum key and value type. Named constructor entries retain
key names and written evaluation order through the existing canonical field
encoding. Lookup/replacement retains enum expressions. `src/tables_test.zig`
checks renamed equivalents and distinguishes foreign enums, changed mappings,
reordered initializers, and positional numeric arrays.


Scoped references advance the version to `exact-v8`. Canonical identity retains
owner slots, underlying types, permissions, parent reference IDs, borrow scope,
and read/write operations. Renamed bound reference names normalize away;
reborrowing and changed permissions remain distinct.


Reference parameters advance the version to `exact-v9`. Function identity retains
parameter passing modes, parameter lease identity, and ordered reference arguments
at calls. Bound parameter spelling still normalizes away. Value arguments retain
their evaluation order; changed reference argument order or permissions remain
distinct even when value bodies otherwise match.


Bounded slices advance the version to `exact-v10`. Canonical identity retains
slice/whole-value reference distinctions, element types, explicit range endpoints,
parameter modes, and slice read/write/length operations. Bound names normalize
away; changed ranges and argument evaluation order remain distinct.


Returned references advance the version to `exact-v11`. Canonical function identity
retains the declared originating parameter, result permissions and slice shape,
returned reference identity, and the receiving borrow scope. Origin parameter names
normalize to declaration positions; a different provenance contract remains distinct.


Typed result obligations advance the version to `exact-v12`. Canonical expressions
retain whether their type carries a result obligation; explicit acknowledgement
remains distinct from ordinary discard and exhaustive matching. Bound spelling and
flow-checking counters are not part of structural identity.


Explicit propagation advances the version to `exact-v13`. Canonical expressions
retain the `try` operation and its output result identity, in addition to the input
value's type and structure. Manual matching and propagation remain structurally
distinct; changed nominal output contracts cannot normalize away.


Source buffer acquisition advances discovery to `exact-v14`. Canonical nodes retain
acquisition result types/capacity expressions and move-only type behavior. Renaming
bindings preserves exact identity; changed capacity arithmetic remains distinct.
Source ownership cleanup is derived from checked structure and binding identities.


Buffer operations advance discovery to `exact-v15`. Canonical nodes retain the
operation kind, owner binding identity, result type, and ordered value arguments.
Renamed length-query helpers group together; capacity queries remain distinct.
Buffer slices retain the existing checked reference and provenance identities.


Effect contracts advance discovery to `exact-v16`. Canonical functions retain
inferred effect sets and normalized optional allowed sets; source annotation spans
and list ordering do not participate. Equal bodies with different declared bounds
remain separate. Renamed helpers with reordered but equal allowed sets group.


Explicit allocator authority advances discovery to `exact-v17`. Acquisition retains
its capability expression before capacity, reserve retains its additional capability
operand, and function signatures retain the allocator type. Removing or changing
explicit delegation is therefore a structural difference.
