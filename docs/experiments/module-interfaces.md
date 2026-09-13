# Module declarations and interface visibility

Track M now parses every discovered module body and builds declaration identities
as `(module, symbol)` pairs. The `list-interfaces` command validates export lists
and the visibility of types mentioned by exported signatures:

```sh
zig build run -- list-interfaces examples/modules/main.my
```

Header order is `module`, then imports. Explicit exports may precede, follow, or be interspersed with top-level declarations:

```mylang
# doc: skip fragment: the imported `shared.units` module is not shown
module main;
import shared.units;
struct Measurement { distance: units::Distance }
export Measurement;
```

`export Measurement;` can be placed next to its declaration or in a separate list.
Exports are module-level directives; they are not permitted inside functions or types.
Formatting preserves their placement and source order.

Declarations are private to their module unless named in its export list. Exports
name local top-level declarations; they cannot re-export an import alias. Unknown
or repeated exports reject. Types and functions share the module declaration
namespace; duplicate names and collisions with import aliases reject. Pool owners
and their nominal handle types have separate declaration identities and export
choices. Exporting a domain also exposes its ordinary methods. Existing `private`
domain methods remain accessible only from that domain, including within the same
module. Exporting a handle alone does not expose its pool implementation.

Module parsing recognizes `alias::Type`, `alias::function(...)`, and
`alias::Domain.method(...)`; qualifiers are direct import aliases, not dotted module
paths or transitively visible dependencies. Qualified names also work in constructors,
variant patterns, array/table types, and borrowed calls. The ordinary single-file
parser retains its previous grammar. The index resolver distinguishes missing
aliases, missing declarations, wrong declaration kinds, module-private declarations,
and domain-private methods, with related declarations rendered in their own files.
These identities are compilation-local and are not yet persistent incremental IDs.

Exported records, variant payloads, buffer elements, pool elements, domain backing
types, and public function parameters/results cannot expose an unexported type.
Array elements and enum table keys participate in this visibility check. Imported
types must be explicitly exported by their defining module; local types referenced
by public signatures must also be exported. Hidden implementation functions may
retain private types. This is a visibility rule, not opaque type inference or
validation of whether a particular backing type is semantically legal.

`interfaces.build` stores parsed ASTs and the index in the project arena. Its public
resolver supplies checked identity lookup for the coming semantic integration.
`list-interfaces` prints only exported declarations in deterministic module order.
Its report states `declarations/signature visibility checked; bodies not type checked`.
Malformed body syntax rejects, but unresolved calls and other semantic errors in
bodies do not yet reject. It does not execute or prove type validity, finite layout,
exhaustiveness, borrowing, ownership, or effect correctness across modules.

Acceptance covers exported nominal identities and domain methods, explicit private
access rejection through the resolver, signature exposure through aggregate/container
types, alias conflicts, duplicate/missing exports and declarations, qualified AST
spans, real multi-file CLI output and cross-file visibility diagnostics, and every
host allocation failure while loading, indexing, resolving, and rendering a valid
interface graph. Existing single-file compiler/VM fixtures remain the execution
baseline.

[Source maps and AST relocation](module-source-mapping.md) provide combined tables
with original locations and module ownership. [Cross-file checking/execution](module-execution.md)
now integrates the index with the type catalog and function checker. The interface
command remains a narrower inspection tool. [Optional direction policy](import-policy.md)
is now implemented separately; module-aware quality, formatting, native, and
incremental work remain pending.
