# Parser pilot

This independent component parses a bounded syntax slice; production routing is
unchanged. Baseline: `0d9ababf7eb434d2e02e1b2b45fe5c6593715e7a`.

## Declared grammar and profile

The slice accepts zero-parameter `func` declarations returning a simple named
type or `bool`, nonempty indentation blocks containing `const`/contextual `mut`
bindings (optional simple type annotation), and value returns. Expressions are
integer spellings, `True`/`False`, ordinary names, unary minus, grouping,
left-associative `+ - * / %`, and ordinary positional calls, including nested
calls and empty argument lists. `/` produces `python_div`; `%` produces
`floor_rem`, matching current syntax rather than historical arithmetic names.
Expression continuations must remain on one physical line. Implicit newline/end-of-file terminators are supported; explicit semicolons
are refused (the current target grammar rejects them). Lexical acceptance
and token/source correspondence belong to the token producer, not this parser.
The parser is syntax-only: it does not resolve names or enforce lexical scope.

Requirements are component-v1 records, explicit mutable parameters/arguments,
bytes/string indexing and slicing, string concatenation, lists and indexed nested
updates, loops, integer arithmetic (including `//` and `%`), checked failures,
and filesystem/stream adapter capabilities. Decimal rendering is implemented
with arithmetic/string indexing; no `str(int)`, `split`, `find`, dictionary,
foreign interface, callback, `Cell` or historical runtime dependency is needed.
Input uses the already-qualified binary `fs.open`/bounded `read` shape; output
uses a `Stream` parameter. Seed source is never rewritten for qualification.

Unsupported grammar includes parameters, defaults, keyword/type arguments,
visibility, attributes/contracts, module/import syntax, records/unions/enums,
generic/compound types, strings/bytes/formats, lists/dictionaries/sets,
indexing/fields/method calls, boolean/comparison/bitwise operators, assignment,
explicit semicolons, control flow, match, fallible functions, resource/effect syntax and intrinsics.
Unsupported statement/type heads report `P_UNSUPPORTED` with byte spans;
unsupported expression heads report `E_EXPRESSION`, and unsupported declaration
heads report `E_SYNTAX`. These are explicit refusals, not production diagnostic
parity claims for excluded grammar. Pilot diagnostics do not include fixes,
related sites, messages, paths or line/column. Limits intentionally differ from
production: nesting is 128, rather than the current Zig parser's 256.

## Provisional syntax and fixture-token transport

Pure API: `parser.parse(tokens: Token[], source: bytes) -> Node[] fails str`.
Tokens are exact Zig `@tagName` strings and half-open byte spans, including final
zero-width EOF and zero-width dedents. `mut` remains `ident`; its contextual
spelling comes from immutable source bytes. Unknown tags, overlapping/backward
spans, out-of-source spans, zero-width ordinary tokens, nonzero-width dedents,
and embedded/missing/incorrect EOF are `P_TRANSPORT`. Indent/semicolon may be
zero width for producer layout tokens. Tables are bounded to 4,096 tokens.
Validation does not retokenize source or prove token spellings match its bytes.

A request file contains decimal source byte length plus LF, exactly that many
raw source bytes, LF, then `kind start end\n` token rows. It must end with the
EOF row; trailing blank lines/bytes are invalid. ASCII tag digits are accepted
(e.g. `kw_i64`). Request bytes are capped at 262,144, with one read sentinel;
the pure source cap is 1,048,576. Decimal fields have at most seven digits.
Adapter errors exit 2, diagnose on stderr, and emit no success output.

Success emits one postorder `kind start end child_id...` row per node. Node IDs
are zero-based, source-local, and every child precedes its parent; a caller
must validate indices before traversing. The final `program` node is the root.
Names and types are spans into source; calls carry a name child followed by
ordered argument children. Function children are name, return type and body;
binding children are name, optional annotation, value. Function span begins at
its name; block span covers first through last child. These two spans are
normalized by the oracle because current production records differ. Pools
contain at most 4,096 nodes and can retain a name node widened by grouping.
Lists/source obey ordinary snapshot ownership; no pointer crosses a boundary.
Nesting/node exhaustion returns `P_LIMIT`. This is a pilot text contract, not a
frozen production AST ABI or production process adapter.

## What the comparison proves

`oracle.zig` compiles a private unchanged copy of the baseline `src/` closure,
invokes production `lexer.lex` and `Parser.parse`, and projects `ast.Program`.
No suitable production full AST export exists (`src/syntax_table.zig` is absent).
`list-declarations` covers declarations rather than full expression trees.
The oracle refuses unsupported AST variants instead of silently flattening them.
The oracle is developer-only and uses libc file/output transport; it is never
linked into production or the Selka component.

The driver compares reachable node kinds, operators, ordered children and byte
spans, independently of pool allocation order. Immutable source jointly
identifies name/type/integer spellings; decoded literal values, operator spans,
policy/signature metadata, unreachable nodes and every excluded AST variant are
not compared. It explicitly compares the first production parser diagnostic
code/start/end for supported malformed fixtures; other diagnostics and recovery
are not claimed equivalent. Unsupported fixtures only prove pilot refusal.
Lexical failures are outside this corpus; token fixtures must lex successfully.
Baseline `.parse.tokens` files are checked byte-for-byte against production
lexer output on every run, never adapted/regenerated by the test driver.

## Donor audit

`git rev-parse selfhost/integration` and `git show fe94e0d0:selfhost/parser.my`
verify donor `fe94e0d0d347c35bf194bd60acb021c781c84fb3`. Direct imports are
`source`, `token`, `diagnostic`, `lexer`, `strings`, `syntax`, `render`.
`render` additionally imports `sort`; `strings`/`sort` are the old standard
library modules under `src/stdlib/`, not local selfhost modules. Lexer's imports
are source/token/diagnostic. The donor's parser mixes CLI source reading and
rendering with parsing in one module, uses `module`/`export`, `def`, `list[T]`,
`Result`/`Option`, postfix failure extraction, unqualified printing, and
one-element mutable state lists. Its 20-field parser state carries old
shadowing scans for `len`/`replace`, imports/exports and broad declaration/type
pools. Donor comments explicitly omit span/op_span/literal from its old
manifest comparison, so that old differential is not today's span oracle.

Salvaged ideas are precedence climbing, indexed pools, immutable source spans,
and final structural validation. No donor checker/lowerer/backend or runtime
source was copied. Historical host declarations/effect names, implicit printing
and function-scope workarounds are inappropriate for current block scope,
capability streams, explicit mutation and Core/LLVM reference counting.
This implementation rewrites the small algorithm in the current declared
profile. Parsing never checks scope; today's checker remains authoritative.

## Production consumer inventory at the baseline

- `src/compiler.zig:124,129,140`: single-file `Compilation.parse/parseCached`,
  frontend lookup/remember and direct `Parser.parse`; core compilation, check,
  run/build/test and analysis consume this syntax.
- `src/compiler.zig:148,158,163`: `format`/`formatModule` parse then call
  `src/formatter.zig`; formatter also independently consumes lexer tokens/type
  spelling tables, so replacing AST production alone is insufficient.
- `src/declarations.zig:126`: parse/parseModule selection for declaration JSON;
  `Compilation.listDeclarations` routes here at `src/compiler.zig:178`.
- `src/project.zig:206,270,393,432`: load/discover imports by lexing headers and
  finding declaration boundaries/qualified imports; this is a separate syntax
  consumer even though it does not call the parser.
- `src/interfaces.zig:1648,1669,1677,1679`: project/interface module parsing;
  `moduleSyntax` caches and preserves parser recovery/fix diagnostics.
- `src/project_syntax.zig:31` relocates and merges indexed module ASTs;
  `src/project_compile.zig:53` consumes the merged syntax for full checking.
- `src/syntax_cache.zig:56,70` lookup/remember deep-clone successful ASTs;
  `src/frontend_cache.zig:173,203,331` persistent syntax serialization/keying.
  `src/ast_copy.zig`, `src/persist_codec.zig` and the project remapper preserve
  every variant and index/span relation needed by these consumers.

Later integration needs one complete validated Zig syntax decoder/adapter,
all AST metadata and grammar variants, complete production diagnostics/fixes,
module/header discovery parity, source ownership/relocation, formatter token
compatibility, bounded transport/process failure handling and component
identity in syntax/semantic/test-result cache validity. Cache ownership stays
with the integration agent. No production switch is authorized by this pilot.

Additional lexical/syntax consumers a full switch must cover:
`src/parser.zig:2322,2347,2354,2355` format interpolation parsing uses absolute
`lexRange` spans; `src/embed.zig:151,184,198,209,213` discovers embed calls and
lexes holes; `src/incremental.zig:491,494,532,536` normalizes declaration text;
`src/module_interface_build.zig:467,471,555,597` scans interface stub/identifier
ranges; `src/interfaces.zig:228,243,395,407` recovers imports/type identities;
`src/module_names.zig:112,118` qualifies identifiers via a lexical fallback;
`src/navigation_partial.zig:27,36` offers lexical navigation;
`src/main.zig:672,676` renders dump-tokens; `src/navigation.zig:239,254,267`
consumes functions/records/variants from merged ASTs. Current quick paths and
fallbacks must share keyword and removed-spelling behavior.

## Standalone qualification

Build the existing coordinator with admitted `zig build component-builder`,
then run the driver through `scripts/build-slot.sh build`. `--builder PATH`
selects an existing coordinator without rebuilding the host; by default it is
`zig-out/tools/selka-components`. The driver obtains and verifies the qualified
seed via coordinator `--seed-only`, prints its digest, and rejects a different
optional `--seed` path. Use `--release` with `MYL_CORE_LEAKCHECK=1` for release
fact/leak qualification. Run pure `tests.my` with that verified seed using
`test ... --force --no-cache`, then with `--release --verify-facts` and leak
checking. Keep worktree-local Zig cache and disk TMPDIR environment variables.

Integration gate additions (separate owner): declare `parser_pilot` sources,
`run_parser_pilot.py`, and `.parse`/token/manifest fixture inputs; add debug and
release standalone qualification steps plus pure tests to component testing.
The builder currently names only test-index/cache-plan: pilot manifest/build
registration is future work. Timing is deferred: no isolated timing admission
was obtained, and no speedup or asymptotic claim is made.
