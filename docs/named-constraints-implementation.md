# Named constraints — implementation plan (frozen interfaces)

Status: implementation in progress. This file is a working plan, not a language
spec. The language brief is `docs/named-constraints-proposal.md`.

## V1 scope

- Top-level `constraint NAME[SUBJECT] = REQUIREMENTS`; RHS reuses the `+`
  requirement grammar (builtins `copy/equality/integer/codec/storable`, plus
  `field(...)` / `op(...)`). The RHS may not reference another named constraint;
  the parser rejects a named RHS item with a located diagnostic (self reference
  gets its own message).
- Named bounds apply to function type parameters only, spelled `T: Prices` or
  `T: contracts.Prices`, combinable with builtins and inline requirements.
- Expansion normalizes a named bound into the existing
  `generic_requirements.Parameter` representation (builtin `Set` plus field/op
  AST). Subject occurrences are rewritten by *identity* through scoped aliases,
  including inside composite signatures.
- Reject named bounds on records/unions/domains/const-length parameters, reject
  `Prices[int]` bounds, and reject `x: Prices` value annotations.
- Single-file programs and module projects both work.
- Deferred: public schema/navigation expansion polish, new cache guarantees,
  optimization policy, runtime interface values (all per the brief).

## Frozen AST interface (owner: syntax workstream, `src/ast.zig`)

```text
pub const BoundReference = struct { alias: ?Span = null, name: Span };
pub const Constraint = struct { name: Span, span: Span, subject: TypeParameter };
TypeParameter      += named_requirements: []const BoundReference = &.{}
TypeDeclarations   += constraints: []const Constraint = &.{}
```

- `Constraint.subject` is a `TypeParameter` whose `name` is the subject binder
  and whose `requirements` / `field_requirements` / `operation_requirements`
  are the RHS. Its `subject.named_requirements` must be empty (parser rejects).
- `Constraint.span` covers the whole declaration and is the scope used by
  subject aliases.
- `named_requirements` uses `alias == null` for a bare name.
- Declaration identity for duplicate detection is `(Definition.module, Definition.name)`;
  in single-file mode `module` is null and the name span is already unique.

## Frozen requirements interface (owner: semantics workstream, `src/generic_requirements.zig`)

```text
pub const SubjectAlias = struct { name: source.Span, scope: source.Span, parameter: usize };

pub const Definition = struct {
    module: ?usize = null,    // declaring module when the caller has an index
    name: source.Span,        // declaration name span in the caller's coordinates
    subject: source.Span,     // subject binder spelling
    scope: source.Span,       // whole declaration span
    body: *const ast.TypeParameter,
};

pub const Lookup = struct {
    ctx: *anyopaque,
    find: *const fn (ctx: *anyopaque, reference: ast.BoundReference, sink: *diagnostic.Sink) diagnostic.Error!Definition,
};

Parameter += aliases: []const SubjectAlias = &.{};

pub fn validateBounds(allocator, src, parameters, sink, lookup) Error!void;
pub fn resolveBounds(allocator, src, parameters, sink, lookup) Error![]const Parameter;
```

- The existing `resolve(...)` stays builtin-only and is used for nominal
  declarations. A non-builtin bound there reports `E_GENERIC_REQUIREMENT`
  ("named constraints may only bound function type parameters").
- `resolve(...)` and `resolveBounds(...)` must both count `named_requirements`
  so `T: unknown` still reports `E_GENERIC_REQUIREMENT` at the name token.
- `validateBounds` is the interface-layer mode: it resolves each named bound
  through `Lookup`, enforces duplicate/limit rules, but does not build field/op
  expansions (module-local spans of another module must not cross coordinate
  spaces). `resolveBounds` is the semantic mode used by `sema` and
  `generic_bodies`, where `src` is the merged project source.

## Subject aliasing (critical, do not replace with text rewriting)

A named-bound field/op signature is written in the declaring module's source and
keeps those spans. The only name that must be re-interpreted in the consumer's
scope is the constraint's subject binder. `generic_requirements` therefore
attaches `SubjectAlias` entries to the expanded `Parameter`:

- `alias.name` is the subject binder span, `alias.scope` is the whole constraint
  declaration span, `alias.parameter` is the consumer function's type-parameter
  index that the bound applies to.
- A resolver resolving a span `s` consults aliases first, and accepts an alias
  only when `s` lies inside `alias.scope` and `src.text(s)` equals
  `src.text(alias.name)`. It then returns the `.parameter = alias.parameter`
  identity.
- Because the scope check is positional, an inline requirement or a consumer
  type parameter with the same spelling outside the constraint declaration
  cannot be captured. Composite signatures work unchanged because nested leaves
  are resolved by the same recursive resolvers.
- Aliases must be threaded through every resolver that interprets requirement
  signature spans:
  - `generic_substitution.Binding.aliases` (used by concrete conformance)
  - `generic_bodies.Checker.ty` / `Checker.substituted` (symbolic checking)
  - `symbolic_shapes.Context.sourceType` (symbolic field shapes)
  - `structural_constraints.Context.ty` (passes the parameter's aliases)

## Module/name layer (owner: modules workstream)

- `interfaces.Kind += .constraint`; index constraints in `buildWithCache`
  pass 1 before exports are applied; `render` prints them automatically.
- `checkSignatures`: validate constraint declarations (subject shadowing,
  no named RHS, field/op duplicates, all nested requirement signature types are
  public when exported) and reject `named_requirements` on nominal declarations
  in `checkNominalParameters`.
- An exported generic function must not expose an unexported constraint
  (`E_PRIVATE_INTERFACE`, related at the declaration).
- `module_names.Names.constraintIdentity(span, sink) -> interfaces.Identity`,
  sharing the `Index.resolve(..., .kind = .constraint)` path.
- `project_syntax.build` category list must include `"constraints"`.
- `lexer.declarationHead` word list must include `"constraint"`.
- `declarations.Kind += .constraint`, with `Scan.simple` and the `declared`
  switch updated.
- `frontend_cache.format_version` and `semantic_key` prefix bump to `-v2`.

## Semantic layer (owner: semantics workstream)

- `generic_requirements.resolveBounds` expands builtins, named bundles and
  inline requirements: dedupe resolved constraint identities (even through two
  import aliases), coalesce identical fields/ops, reject conflicting same-name
  fields/ops and `E_GENERIC_LIMIT` after expansion.
- Provide `Lookup` implementations: `interfaces` (index + module) for
  validation, and a shared `src/constraint_lookup.zig` over a merged/local
  `ast.Program` plus optional `Names` for `sema` (specialize) and
  `generic_bodies` (inferCall, checkWithCatalog). Single-file mode without
  `Names` resolves by spelling in `program.types.constraints`.
- Replace the `generic_requirements.resolve` calls in `sema.specialize`
  (`src/sema.zig` ~341) and `generic_bodies` (~716, ~1444) with
  `resolveBounds`; pass aliases where requirement field/op types are resolved.
- `Checker.operationCall`, `Checker.structural`, `Checker.validateStructural`
  and `symbolic_shapes.schema` resolve requirement types with the owning
  parameter's aliases.

## Diagnostics

- unknown/undefined bound name: `E_GENERIC_REQUIREMENT` at the bound span.
- private/imported-private constraint: `E_PRIVATE_SYMBOL` from `Index.resolve`.
- imported constraint that is not exported: `E_PRIVATE_SYMBOL`; same-module
  constraint exposed by an exported generic: `E_PRIVATE_INTERFACE`.
- wrong kind (`Prices` as a value type or `Prices[int]`): `E_SYMBOL_KIND`.
- limits: `E_GENERIC_LIMIT`; conflicting duplicates: `E_GENERIC_REQUIREMENT`.

## File ownership (do not edit another owner's files)

- syntax: `src/ast.zig`, `src/lexer.zig`, `src/parser.zig`, `src/declarations.zig`,
  `src/generic_syntax_test.zig`, `src/declarations_test.zig`.
- modules: `src/interfaces.zig`, `src/module_names.zig`, `src/project_syntax.zig`,
  `src/frontend_cache.zig`, `src/semantic_key.zig`, `src/interfaces_test.zig`.
- semantics: `src/generic_requirements.zig`, `src/structural_declarations.zig`,
  `src/generic_substitution.zig`, `src/structural_constraints.zig`,
  `src/generic_bodies.zig`, `src/symbolic_shapes.zig`, `src/sema.zig`,
  `src/nominal_templates.zig`, `src/constraint_lookup.zig`,
  `src/generic_requirements_test.zig`, `src/structural_constraints_test.zig`.
- tooling/docs/tests: `src/generic_api.zig`, `src/features.json`, `SPEC.md`,
  `docs/generics.md`, `test/fixtures/named_constraints/*`, `src/named_constraints_test.zig`,
  `src/root_test.zig`.

## Verification

```sh
zig build test-units -Dtest-filter='named constraints'
zig build test-units -Dtest-filter='structural'
zig build test-units -Dtest-filter='generic'
zig build
zig build test --summary all
```
