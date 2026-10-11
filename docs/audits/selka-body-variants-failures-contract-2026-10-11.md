# Proposed B5 union, pattern and checked-failure boundary

Status: read-only proposal, not an implemented or qualified schema. B4 continues to use protocol 1/schema 4. This wave advances the full language selfhost goal; it does not establish bootstrap completion or the <=1.5x performance target.

## Scope and retained authority

Move ordinary nongeneric enum/union construction, named/default fielded cases, exhaustive statement and expression matches, nested/product patterns, checked `fails` functions, `fail`, `try`, and Result/Option flow into the Selka body checker. Retain the common native catalog and later native postpasses explicitly. No native body fallback or pretyped body worklist.

The full `Catalog.records` prefix already serializes `typed.Record.shape.variants`: ordered case names/declaration spans, optional payload IDs, fielded/boxed flags and full type contracts. Nongeneric variants need no new per-use answer table or nominal map. Join the raw variant declaration name span to the retained schema; join each fielded case's raw fields/default AST IDs through the authoritative case payload schema. Preserve imported/re-exported canonical symbol authority and visibility using existing raw module facts.

Generic user functions/nominals, callbacks/resources, typed holes, invariant/function contracts, and boxed recursive layouts require further body closure. Keep those explicit profile refusals until implemented. Ordinary finite record/list/union recursion requires policy fixed points; do not confuse it with unsupported by-value cycles. Lists cannot store pending Results: native `sema_collections.zig:308` reports `E_LIST_TYPE` for noncopyable, nonstorable or result-bearing elements.

## Proposed schema 5 change

Full typed Batch stays `{nodes,statements,functions,ranges}`. The list-only append delta cannot represent new `Result[success,error]` or `Option[element]` identities created during body checking.

Replace the list-only output delta with bounded ordered tagged catalog recipes: list, result, option. Each carries its next canonical ID, one or two already admitted type arguments and the original intern source span. Require contiguous global append order, no duplicate recipe kind/argument tuple, prior dependency identities, valid exact source sites, and bounded totals. Keep the current 65536 catalog/table limits, 64 MiB wire limit, 256 graph-depth limit and aggregate edge/string budgets unless separate qualification justifies changes.

Project only Result/Option template availability from retained common `templates.store.index.names` authority; the producer makes all new type choices. The host materializes a validated recipe using the existing collection/result/nominal instantiation routines and checks the predicted ID and full generated schema. No generic host lookup process per expression.

Compare recipes against the untouched native oracle, then independently recollect the common catalog and materialize producer recipes for full `typed.Record` equality. Preserve retained prefix authentication and schema-4 refusal. Audit the common generic/entry phase for any catalog append before bodies; freeze the input frontier and preserve first-demand order rather than silently attributing common work to the producer.

## Native semantic seams

- `nominal_catalog.zig:243` Builder.variants and `:444` instantiateLengths: ordered cases, fielded payload schemas, closed type identities.
- `sema_expressions.zig:307` variantType, `:313` queueVariant, `:343` caseInitializers, `:762` construction emission: contextual type resolution, named/default initializer order, payload presence and type diagnostics.
- `sema_statements.zig:129` patternTag, `:174` bindArmPayload, `:211` bindFieldedPayload, `:243` bindOrderedFieldedPayload: lexical slots, payload projections, ownership metadata and declaration errors.
- `frontend_patterns.zig:195` normalize and `sema_statements.zig:353` nestedMatchArms: product/nested pattern normalization, retaining source precedence.
- `sema_statements.zig:420` statementMatch: wildcard expansion, duplicate/exhaustiveness errors, arm flow and pending-state joins. Wildcard arms intentionally share a typed body ID.
- `sema_statements.zig:330` matchExpression: yield checks and a hidden result local lowered through block_value/match.
- `frontend_failures.zig:11` resultType, `:33` checkReturn, `:41` checkFail, `:64` injectOptional: checked return wrapping, implicit error-union injection and nested Option layers.
- `sema_expressions.zig:665` checkPropagation: Result/Option eligibility, enclosing return shape, compatible error injection, pending locals and temporary obligations.
- `sema.zig:568` pendingState, `:581` samePending, `:599` requireHandled; statement branch/loop/assignment checks: consumption, overwrite, scope exit and continuing-path equivalence.

## Native validator and adoption requirements

Admit `.variant` only for a supported retained/materialized case schema: tag in range, exact optional payload presence and payload type. Admit `.propagate` only for compatible input and enclosing function result/optional shapes, success type and permitted error injection. Validate `.match` value type, unique complete closed tags, correctly typed optional payload locals and body IDs inside the owning function range. Borrowed matches must correspond to supported Option narrowing, not arbitrary ownership suppression.

Permit and validate full final `LocalOwnership` transfer availability/spans for result-bearing locals; preserve parameter/binding declarations and type association. Source consumption and branch/loop obligation decisions belong to the producer, not a native semantic validator. Shared wildcard bodies and legitimate orphan intermediates must survive structural admission and exact shadow comparison.

Ordinary checked-failure errors use the existing rich SyntaxDiagnostic representation, including related/fix/origin/requirement records. Typed holes or generic/provider errors carrying unsupported obligation/stack metadata remain profile refusals; never drop those fields. Preserve native diagnostic precedence and recovery order.

## Practical split and qualification

Producer core: variant type/constructor binding, Result/Option recipe interning, engine dispatch and return/propagation lowering. A helper lane can own pattern normalization/exhaustiveness and pending-flow snapshots. Native lane owns recipe DTO/framing/materialization and structural typed admission. Qualification lane covers enum/union payloads/defaults, wildcard/duplicate/incomplete matches, nested fielded patterns, match yields, fails/try/error injection, Result overwrite/unhandled/path/loop/temporary failures and authenticated forged reply cases.

Compiler source examples already requiring this closure include `parser_pilot/syntax_value.my` and `full_model.my` union/value models, helpers declaring `fails syntax_value.Problem`, `body_check/main.my` filesystem Result matches, and `type_interface/resolve.my` result matches. These provide meaningful compiler-source admission targets beyond toy fixtures.
