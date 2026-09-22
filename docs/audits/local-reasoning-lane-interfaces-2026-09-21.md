# Shared interfaces for the local-reasoning items 1–6

Status: coordination note for the implementation of
[the plan](local-reasoning-implementation-plan-2026-09-21.md). This file is not a
specification of behavior — the plan is. It exists so that the four lanes can be
implemented in parallel worktrees and merged mechanically: every name, field and
placement below is frozen, and a lane that needs a different one says so instead
of inventing it.

## How the work is split

`F` (foundation, on `main`) lands first: the parser, AST and formatter accept all
four new spellings, with no checker support. The four lanes then branch from `F`
and must not touch each other's files.

| Lane | Items | Owned files |
| --- | --- | --- |
| `mut` | 1, then 2 | `src/origins.zig`, `src/sema.zig`, `src/effects.zig`, `src/callables.zig`, `src/mutation.zig`, `src/interfaces.zig`, `src/navigation.zig`, `src/api_diff.zig`, `src/context.zig`, `src/lexer.zig`, `src/compiler.zig`, `src/incremental.zig`, `src/native_test_options.zig`, `src/main.zig` |
| `simple` | 5, 6 | `src/sema.zig` (expression checking and call binding only), `src/lower.zig`, `src/call_arguments.zig`, `src/lint.zig` |
| `option` | 3 | `src/sema.zig` (method dispatch only), `src/option_flow.zig`, `src/lint.zig` |
| `tuple` | 4 | `src/record_layouts.zig`, `src/type_catalog.zig`, `src/runtime_values.zig`, `src/sema.zig` (record construction only), `src/qbe*.zig`, `src/native_format.zig` |

Two lanes touching one file is expected (`sema.zig`, `lint.zig`); each lane keeps
to its listed region and the merge resolves the rest. **`SPEC.md`,
`src/features.json`, `src/root_test.zig` and `tests/lang/**` are written by the
integration pass, not by a lane**: a lane appends its bullets and tests in its own
worktree so its gate is honest, and the integration pass moves them into the
shared files. A lane that edits `SPEC.md` at all edits only by appending to the
end of the relevant section.

## Frozen surface: parser and AST

`F` adds exactly these, in `src/ast.zig`:

```zig
// type expressions (ast.TypeExpressions, beside `arrays`)
tuples: []const TupleType = &.{},
pub const TupleType = struct { span: Span, elements: []const Span };

// value expressions (ast.Node.data)
/// A parenthesized or bare tuple value; two to eight elements.
tuple: []const NodeId,
/// `value_if_true if condition else value_if_false`.
conditional: struct { condition: NodeId, then_value: NodeId, else_value: NodeId },
/// The `mut` call-argument marker wrapping its target. No type of its own.
mut_argument: NodeId,

// declarations
pub const Parameter = struct {
    default_value: ?NodeId = null,
    name: Span,
    ty: Span,
    /// Whether the declared type was preceded by `mut`.
    mut: bool = false,
};
pub const FunctionSignature = struct {
    // ... existing fields ...
    /// Zero-based index of the first keyword-only parameter, or null when the
    /// list has no `*`. Equal to the positional parameter count.
    keyword_only_from: ?usize = null,
};
pub const CallbackType = struct { span: Span, parameters: []const Span, return_type: Span, mut_parameters: []const bool = &.{} };
```

Spellings the parser must accept, and the node it builds:

- `name: mut T` — `Parameter.mut = true`. `mut` is matched as an identifier by
  text, exactly as `mutates` is today, so it stays usable as an ordinary name
  everywhere else. No new lexer tag.
- `def f(a: int, *, b: int)` — `keyword_only_from = Some(1)`. `*` is the
  existing `.star` tag. A `*` with no following parameter, or a second `*`, is
  `E_SYNTAX` at the `*` span. `*` in a callback type is `E_SYNTAX`.
- `mut expr` in an argument list — `.mut_argument = inner`. The parser accepts
  the prefix in every argument position; the checker decides whether it is
  allowed there.
- `(a, b)` and `a, b` after `return` and on both sides of a multi-target
  assignment — `.tuple` with the element nodes in source order. One element is
  never a tuple. A parenthesized expression with no comma stays the expression.
- `tuple[int, str]` in a type — `TypeExpressions.tuples`. Arity 2–8 is a checker
  rule, not a parse rule, so the parser accepts any comma count and lets `E_TUPLE_ARITY`
  come from `sema.zig`.
- `a if p else b` — `.conditional`, lowest precedence, right-associative: the
  `else` arm of `a if p else b if q else c` is the nested conditional.

The old hints for these four spellings are removed in the same change
(`HintForm.ternary`, `HintForm.tuple` at `parser.zig:254`, and the
`declaration_hints` rows), because each one now parses.

## Frozen surface: typed model

Each lane adds its own typed fields; these names are fixed so the integration
pass has nothing to reconcile.

```zig
// typed.FunctionSignature
/// Zero-based index of the first keyword-only parameter, or null.
keyword_only_from: ?usize = null,

// typed.Callable
/// Whether each parameter was declared `mut`.
mut_parameters: []const bool = &.{},
/// Zero-based index of the first keyword-only parameter, or null.
keyword_only_from: ?usize = null,
```

`declared_mutates` keeps its name and type (`[]const u16`) in the `mut` lane and
becomes the set of `mut`-declared positions; `FunctionSignature.mutates` stays
the inferred write set. Item 2 then removes the inferred mask from
`interface_sha256` only.

The tuple type is **not** a new `typed.Type` variant: `typed.Type` is
`runtime_values.Type`, a compact enum whose non-builtin members are indices into
the record catalog. A tuple is an anonymous record interned in that catalog with
positional fields, so `tuple[int, str]` is one identity everywhere, exactly as
the plan's "identity across modules" decision requires. The interning function
lives in `src/type_catalog.zig` and is owned by the `tuple` lane:

```zig
/// Intern or look up the anonymous record for a tuple with these element types.
pub fn tupleType(catalog: *Catalog, elements: []const typed.Type) !typed.Type
```

## Frozen surface: diagnostics

Codes are fixed; the message text is the lane's to write (the plan's wording is
the default).

| Code | Severity | Item |
| --- | --- | --- |
| `E_MUTATION_MARKER` | error | 1 |
| `E_REMOVED_SPELLING` | error | 1 (`mutates(...)`, `&`) |
| `E_UNUSED_CAPABILITY` | error | 2 |
| `E_DERIVED_EFFECTS` | error | 2 |
| `W_DERIVED_EFFECTS` | warning | 2 |
| `E_TUPLE_ARITY` | error | 4 |
| `E_TUPLE_INDEX` | error | 4 |
| `E_KEYWORD_ONLY` | error | 5 |
| `L_POSITIONAL_LITERAL` | lint | 5 |
| `L_SENTINEL_INT` | lint | 3 |

`E_SYNTAX` and `E_TYPE` are reused where the plan says so.

## Per-lane done conditions

A lane is done when, in its own worktree:

- `zig build` installs a compiler that passes the probe programs the plan names
  under "Done when" for its items;
- `zig build test-units -Dtest-filter=<new test name>` and
  `zig build test-cli -Dtest-filter=<new test name>` pass;
- `zig build fmt-check` passes;
- `zig-out/bin/mylang doc-coverage .` passes;
- `zig build test-lang` passes (guest tests need Python; see the notes below).

`zig build test` in full is the integration pass's job, not a lane's: it is
sharded and slow, and lanes run the filtered subsets.

## Notes that cost time if rediscovered

- `zig build` (not `test`) installs `zig-out/bin/mylang`; a stale binary is the
  usual cause of "the diagnostic did not change".
- Each worktree needs its own `.zig-cache` (it is per-directory, not shared) and
  `MYLANG_MEMORY_LIMIT`-style ceilings already apply per process.
- `guardian.toml` is diff-scoped against `HEAD`, so a lane sees only its own
  files in scope; the whole-tree checks still read everything.
- The `&` marker path (`lexer.lexWithMarkers`, `src.mutation_markers`,
  `--mutation-markers`) exists today and is retired by the `mut` lane, not by
  `F`.
