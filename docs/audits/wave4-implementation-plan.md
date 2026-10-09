# Wave 4 language-surface implementation plan

Research-only plan for the six Wave 4 items in
[`docs/audits/quality-and-maintainability-2026-09-18.md`](quality-and-maintainability-2026-09-18.md)
section 7. Every hook point below was read in the working tree at commit `328502c8`
plus the uncommitted Wave 1–3 work (`src/lint.zig`, `src/lint_config.zig` untracked).
No source file was modified to produce this document.

Conventions used in the hook tables:

- Example fences in this plan are ```` ```text ```` (not ```` ```mylang ````) on purpose:
  `mylang doctest .` walks every `docs/**/*.md` except `docs/legacy/`
  (`src/doctest_command.zig:5-7,267-272`) and only `mylang`/`my` fences execute
  (`:17`), so a `mylang` fence here would fail the gate before the feature exists.
  When each example lands in its real doc section it must be a ```` ```mylang ````
  block.
- "lex/parse" = `src/lexer.zig` → `src/python_layout.zig` → `src/parser.zig` (AST in
  `src/ast.zig`).
- "collect" = top-level declaration discovery that never checks bodies:
  `src/declarations.zig` (parse-only listing), `src/project.zig` (module headers,
  imports, export directives), `src/interfaces.zig` (symbol/export index).
- "check" = `src/sema.zig` (`Checker`), producing `src/typed.zig`.
- "lower/emit" = `src/lower.zig` → `src/bytecode.zig` / `src/bytecode_model.zig` →
  `src/qbe.zig` + `src/qbe_*.zig` + `src/qbe_*.c`.
- "format" = `src/formatter.zig` (a token-stream re-printer, not an AST printer).
- "listing/fingerprint" = `src/main.zig` `list-declarations` /
  `list-interfaces`→`src/interfaces.zig`, and the identity machinery in
  `src/incremental.zig`, `src/cache_key.zig`, `src/semantic_key.zig`,
  `src/schema_graph.zig`, `src/frontend_cache.zig`.

## 0. Cross-cutting constraints that shape every choice

**Guardian caps and the type-size ratchet.** `.guardian/baselines/type-size.txt` is a
`guardian-snapshot v2` ratchet that records only structs *above* the 7-field cap. Read
it before growing anything:

- Structs the ratchet has recorded (the number is the recorded value, not necessarily
  today's count) and that must not grow past their recorded entry:
  `src/ast.zig|FunctionPolicy` (recorded 8; 7 today), `src/typed.zig|Record` (8; 8
  today), plus the other entries in that file such as
  `src/native_test_options.zig|Options` (12) and `src/runtime_values.zig|Value` (9).
- Exactly at 7 today and therefore unable to take one more field without a baseline
  accept: `typed.Function` (policy, type_arguments, signature, scope, id, name,
  declaration — `src/typed.zig:456`), `typed.FunctionPolicy` (`src/typed.zig:467`),
  `ast.FunctionPolicy` (`src/ast.zig:149`), `lint.Facts` (`src/lint.zig:72`),
  `lint.Finding` (`src/lint.zig:60`), `lint.Request` (`src/lint.zig:26`),
  `lint_config.RuleSetting` (`src/lint_config.zig:31`), `project.Module`
  (`src/project.zig:60`).
- Room to grow: `ast.Program` (5 fields — `src/ast.zig:203`), `ast.Function` (4 —
  `src/ast.zig:147`), `ast.Assertion` (3 — `src/ast.zig:127`), `typed.Field` (3 —
  `src/typed.zig:119`), `typed.Assertion` (2 — `src/typed.zig:426`), `typed.Program`
  (6 — `src/typed.zig:506`), `interfaces.Symbol` (6 — `src/interfaces.zig:43`),
  `interfaces.ContractDeclaration` (6 — `src/interfaces.zig:23`), `lint.RuleContext`
  (4 — `src/lint.zig:95`), `project.Export` (2 — `src/project.zig:44`).

**Functions are capped at 6 parameters.** `parser.Parser.function(self, owner)` and
`declarations.zig` helpers are the ones this plan might extend; every proposed
signature below stays at ≤6.

**Formatter shape.** `src/formatter.zig` re-emits the validated token stream. A new
token tag usually round-trips for free (`emitToken` `src/formatter.zig:134` falls
through to `emitReal` `:158`, which copies `bytes[span]`). Two exceptions matter for
Wave 4: blank-line insertion between top-level "starts" (`collectTopStarts`
`src/formatter.zig:439`, `classifyRole` `:476`, `blankBetween` `:484`) and the
`declarationEnd` boundary scan (`src/lexer.zig:142`, `declarationHead`
`src/lexer.zig:458`).

**Where the three listings/fingerprints are produced** (referenced repeatedly below):

| Output | Entry point | Renderer |
| --- | --- | --- |
| `list-declarations` | `compiler.Compilation.listDeclarations` `src/compiler.zig:135` | `declarations.render` `src/declarations.zig:55`; JSON assembled `:89` |
| `list-interfaces` (default) | `main.listInterfaces` `src/main.zig:1538` | `interfaces.Index.render` `src/interfaces.zig:423` |
| `list-interfaces --contracts` | same | `interfaces.Index.renderContracts` `src/interfaces.zig:487` (version `interface-contracts-v2`, `:35`) |
| native schema | `Compilation.emitQbeWithOptions` `src/project_compile.zig:81` | `schema_graph.render` `src/schema_graph.zig:144` |
| project interface fingerprint | `incremental.buildChecked*` | `incremental.declarationInterface` `src/incremental.zig:392`; `normalizedFunctionDeclarationHash` `:499`; project roll-up `:~180–230` |
| cache contract fingerprint | `cache_key.Contract.fingerprintHex` `src/cache_key.zig:35` | flags/effects strings only |
| AST syntax cache key | `frontend_cache.syntaxKey` `src/frontend_cache.zig:233` | source bytes + body start; AST is stored in-process, not re-encoded field-by-field |

**A missing piece the whole wave depends on.** `lint_config.Config.warnings`
(`report|deny`, `src/lint_config.zig:24`, parsed at `:178`) is **never read** by any
consumer: `grep -rn "config.warnings" src` has no hits outside `lint_config.zig`. The
audit says `W_DEPRECATED` is deny-able and docstring findings "block under `strict`";
both need this wire-up. Compiler warnings are plain `diagnostic.Sink` entries with
`severity = .warning` (`src/origins.zig:642`, `src/sema.zig:4667`), so "deny" means the
CLI must promote `W_*` to exit 1, which does not exist yet.

---

## 7.1 Attributes: `@deprecated`, `@test`, `@allow`

### 1. Exact hook points

| Stage | file:line | symbol / what happens |
| --- | --- | --- |
| lex | `src/lexer.zig:359` | `tokenize`; `@` currently falls to the `else` arm at `:442` (`E_TOKEN` "unexpected character in source") |
| lex | `src/lexer.zig:405-443` | punctuation table — no `.at` tag; add `Tag.at` in the enum `src/lexer.zig:7`, `spelling` `:278` |
| lex | `src/lexer.zig:458` | `declarationHead` — used by `lexer.declarationEnd` (`:142`) to find where a declaration ends; an attribute line must count as a head |
| parse | `src/parser.zig:343` | `parse()` top-level loop `:351`; `export` handled `:352`, all other heads below |
| parse | `src/parser.zig:477` | `function(owner)` — the only declaration that receives attributes in v1 |
| parse | `src/parser.zig:93` | `expect` — spacing/`E_SYNTAX` reporting for a malformed clause |
| collect | `src/declarations.zig:208` | `Scan.head` — must skip a leading attribute clause and fold it into the declaration bytes |
| collect | `src/declarations.zig:246` | `Scan.body` (uses `lex.declarationEnd`) |
| collect | `src/project.zig:256` | `Scanner.skipDeclaration` → `lex.declarationEnd` |
| collect | `src/interfaces.zig:953-1012` | `buildWithCache`; exports marked `:995-998`; unit symbols added `:989-994` |
| check | `src/sema.zig:187` | `checkFunction`; returns `typed.Function` `:258` (no attribute field — see caps) |
| check (calls) | `src/sema.zig:2806` | `checkCall`; resolved target at `:2856-2859` — the place to emit `W_DEPRECATED` |
| warn API | `src/diagnostic.zig:74-117` | `Sink` has `fail*` but **no `warn`**; warnings are appended as `.severity = .warning` items (`src/sema.zig:4667`) |
| lower | `src/lower.zig:524` | `lowerFunction` copies policy/signature only; attributes are compile-time only |
| format | `src/formatter.zig:134,158` | token re-print; add `.at` to `isWordLike`/`isOperandEnd` (`:504`,`:511`) only if spacing demands it |
| format | `src/formatter.zig:439-489` | `collectTopStarts` / `classifyRole` / `blankBetween` — must not insert blank lines between an attribute and its declaration |
| list-decls | `src/declarations.zig:47` | `Listed` (kind, name, exported, bytes, comment_start); `declared()` `:280` |
| list-decls | `src/declarations.zig:71-86` | main scan loop; `:89` JSON shape |
| list-ifaces | `src/interfaces.zig:423,445` | `render` / `renderFunctionLine` |
| list-ifaces | `src/interfaces.zig:487,521` | `renderContracts` / `contractDeclaration`; test-shape gate `:498-504`, `testShape` `:518` |
| test discovery | `src/project_compile.zig:179,197` | `testRoots` / `discoveredTest` (name-prefix only today) |
| test schema | `src/native_test_contracts.zig:139` | `testSchema`; `native_test_cases.testName` `src/native_test_cases.zig:44` |
| lint waivers | `src/lint.zig:282,294,273` | `scanWaivers` / `parseWaiver` / `isWaived`; `Waiver` `:265` |
| fingerprint | `src/incremental.zig:950-961` | `baseFunctionSpan` starts at `function.name.start`, so an attribute line is outside the hashed header |
| fingerprint | `src/incremental.zig:499-547` | `normalizedFunctionDeclarationHash` / `normalizedFunctionSpan` |
| fingerprint | `src/incremental.zig:392-426` | `declarationInterface` function branch (AST-only fallback `:347`) |

### 2. Smallest viable implementation

**AST.** Add to `src/ast.zig` (near `Program`, `:203`):

```zig
pub const AttributeKind = enum { deprecated, test, allow };
/// One fixed-vocabulary attribute attached to a declaration.
pub const Attribute = struct {
    kind: AttributeKind,
    span: Span,          // the `@name(...)` clause
    argument: ?Span = null, // deprecated reason, or @allow rule name
    reason: ?Span = null,   // `reason="..."` payload span
};
/// One declaration's attribute list, keyed by the declaration name span.
pub const DeclarationAttributes = struct { declaration: Span, attributes: []const Attribute };
```

Store them in a **program-level table** instead of on `ast.Function`, because
`@allow` must also cover records/unions/domains for 7.2's `L_UNDOCUMENTED_EXPORT`:
`ast.Program` gains `attributes: []const DeclarationAttributes = &.{}` (5→6 fields,
cap-safe). This deliberately avoids `typed.Function` (7 fields, at the cap) and
`ast.FunctionPolicy` (`src/ast.zig:149`, 7 fields, at the cap). `src/ast_copy.zig` is
reflective (`Mapper.value`, `src/ast_copy.zig:13-50`) and copies the new table with no
code change provided every field is `Span`/enum/optional-span/slice.

**Lexer.** Add `at` to `Tag`, spell it in `spelling` (`"@"`), and in `tokenize`'s
punctuation switch (`src/lexer.zig:421`) map `'@' => .at`. Add `.at` to
`declarationHead` (`src/lexer.zig:458-468`) so a preceding declaration's boundary scan
stops at an attribute line.

**Parser.** New private helper `attributes(self) Error![]const ast.Attribute` (≤2
params) called at the top of the `parse()` loop (`src/parser.zig:351`), greedily
consuming `@ident` clauses while `current().tag == .at`:
- name must be one of `deprecated`, `test`, `allow` → else
  `sink.fail("E_UNKNOWN_ATTRIBUTE", at_span, "unknown attribute; expected @deprecated, @test or @allow")`;
- `@deprecated` / `@allow` require `( ... )`; `@allow` takes a quoted rule string and
  an optional `reason=`; `@test` takes nothing;
- duplicates of the same kind on one declaration are `E_DUPLICATE_ATTRIBUTE`.
Record the pending list, and after the declaration head is parsed, key it by the
declaration name span. In v1, attributes before a non-function head fail with
`E_ATTRIBUTE_TARGET` ("attributes attach to a function declaration") — an explicit,
documented limitation; extending to types is mechanical once the lookup table exists.

Per the audit's exact 4.4 spelling, `@allow("function-length", reason="…")` takes a
**quoted rule string** (see conflict 5 below).

**Formatter.** Add `.at` handling so the token prints tight (`@` + name + `(` + args)
and, more importantly, make `collectTopStarts` (`src/formatter.zig:439`) not open a
new blank-line group at an `.at` token: either skip `.at` tokens when appending
`TopStart`s, or add a `Role.attribute` whose `blankBetween` values are 0 with the
following declaration and the normal value against the previous one. Without this, the
`:484` table inserts two blank lines between the attribute and its `def`, breaking
round-trip.

**Collectors.** `declarations.zig`: in the main loop (`:71-86`) consume any leading
`.at` clauses, extend `start`/`comment_start` accordingly, then call `head()`;
`head()` must therefore be entered only at the real declaration token. `project.zig`:
in `header` (`:205-220`) skip attribute clauses the same way before checking
`isWord("export")`; `skipDeclaration` (`:256`) already stops at `.at` once
`declarationHead` knows the token, so the next loop iteration must also consume it.

**Semantics.** `@test` is a discovery fact, not a type fact:
- `src/project_compile.zig:197` `discoveredTest`: return true when the name prefix
  matches **or** the declaration carries `@test`. Look the attribute up by
  `function.declaration` through `self.index.units[original.input].syntax.attributes`
  (the merged `src` gives `originalSpan`).
- `src/interfaces.zig:498` `renderContracts`: include `@test` declarations even
  without `test_`; at `:503` bypass the `testShape` gate when the attribute is present
  (the attribute is an explicit declaration, so the shape default need not apply).
- `src/native_test_contracts.zig:139` `testSchema`: copy a `"test": true` marker into
  the function map, and `src/native_test_cases.zig:44` `testName` accepts it. Keep the
  contracts version at `interface-contracts-v2` and **emit the marker only when
  true**, so existing fixtures that never use `@test` keep byte-identical output.
- `src/lint.zig:343` `isTestName`: fold in the attribute so `L_UNTESTED_EXPORT`'s
  test set matches `mylang test`. Build the flags inside `lint.run` (`:188-192`) where
  `request.compilation` is available; `Facts` (7 fields) must not grow.

`@deprecated` warning: in `checkCall` after the target resolves (`src/sema.zig:2856`)
append a `W_DEPRECATED` warning when (a) the callee's AST declaration has
`@deprecated`, and (b) `input.owner`/module qualification shows a different module
than the defining module. Cross-module identity is available through
`self.catalog.module_names`; when there is no project namespace (single-file), no
cross-module call exists, so nothing fires. Use the call name span as the diagnostic
span and append `.{ .severity = .warning, .code = "W_DEPRECATED", ... }` — do **not**
return `SourceError`.

`@allow` replaces `# lint: allow`: in `lint.run` build the waiver list from the
program-level attributes (`scanWaivers` `src/lint.zig:282` becomes a fallback that
emits `E_REMOVED_SPELLING` for the comment form), mapping each `@allow(rule,
reason=...)` to `Waiver{ .rule, .line = src.locate(decl.span).line, .has_reason = reason != null }`.
Keep `Waiver` (4 fields) as is. A missing `reason=` keeps `L_WAIVER_REASON` blocking.

**Fingerprint.** Extend `baseFunctionSpan` (`src/incremental.zig:950`) to start at the
earliest `@…` span for the function, found through `syntax.attributes`. This makes the
attribute part of both the typed branch (`declarationInterface:414-417`) and the
AST-only/template branch (`:499`), and therefore of the project interface fingerprint
rolled up at `:~180–230` (`INCREMENTAL-INTERFACE-1`).

**New codes:** `E_UNKNOWN_ATTRIBUTE` (parse), `E_DUPLICATE_ATTRIBUTE` (parse),
`E_ATTRIBUTE_TARGET` (parse), `W_DEPRECATED` (check, warning; deny-able once the
`lint.warnings` wire exists).

### 3. Test / doc obligations

- **Tests to extend**
  - `src/formatter_test.zig` — new case next to `TOOL-5` (`:42`): `@test`/`@deprecated`
    before `def` round-trips with exactly one newline, comments preserved.
  - `src/declarations_test.zig` — extend the `DECLARATION-LIST-1` test (`:147`):
    attributes appear in the listing and in the declaration byte range.
  - `src/interfaces_test.zig` — `@test`/`@deprecated` in `renderContracts`, and
    `@deprecated` inclusion in the declaration fingerprint.
  - `src/incremental_test.zig` — adding/removing `@deprecated` changes the interface
    hash; a body edit under the same attribute does not.
  - `src/python_assert_test.zig` is not the home for this; use
    `src/parser.zig`-adjacent tests (`src/python_syntax_test.zig`) for the
    `E_UNKNOWN_ATTRIBUTE` location.
  - `test/integration.zig` — a `mylang lint` run where `@allow` suppresses a finding
    and an attribute-free waiver comment now fails.
- **`// spec: TAG` tests.** One new test per bullet in a file that already carries
  `// spec:` lines; recommended: `src/formatter_test.zig` (`ATTR-1`, round-trip),
  `src/declarations_test.zig` (`ATTR-4`, listing), `src/interfaces_test.zig`
  (`ATTR-2`, `ATTR-3`), `src/native_test_command.zig` test module (`@test` discovery,
  a new `ATTR-TEST-*` case or an extension of the existing native-test test).
- **SPEC bullets (proposed wording, to add under `## Surface syntax` / the Python
  section near `PY-ASSERT-*`):**
  - `- [ATTR-1] A declaration may carry a fixed-vocabulary attribute on the line above it: @deprecated("reason"), @test, or @allow("rule", reason="…"). The parser rejects any other @name with E_UNKNOWN_ATTRIBUTE and a repeated attribute on one declaration with E_DUPLICATE_ATTRIBUTE. Attributes are part of the declaration header and the formatter round-trips them.`
  - `- [ATTR-2] @test makes a zero-parameter bool function a discovered test regardless of its name or export flag; mylang test, the native test schema and the W2 test rules agree on that set, and @test is reported in list-declarations and list-interfaces --contracts.`
  - `- [ATTR-3] A call to a @deprecated declaration from another module reports W_DEPRECATED naming the reason; the attribute participates in the declaration and project interface fingerprints, so removing a declaration deprecated in the baseline is an interface-compatible change once api-diff exists.`
  - `- [ATTR-4] @allow("rule", reason="…") on a declaration suppresses that lint rule for findings on the declaration and replaces the # lint: allow comment, which reports E_REMOVED_SPELLING; a reason is still mandatory (L_WAIVER_REASON).`
- **`src/features.json` slug**
  - `"attributes"`: `{ "kind": "language", "summary": "@deprecated, @test and @allow attach a fixed attribute vocabulary to declarations; @test drives discovery and @deprecated warns across modules.", "doc": "docs/functions.md#attributes" }`.
  - Doc: new `## Attributes` section in `docs/functions.md` with a runnable block:
    ```text
    # doc: not-mylang
    # doc: expect 9
    @deprecated("use square_v2; removed after api_version 3")
    def square(x: int) -> int effects():
        return x * x

    @test
    def square_of_three() -> bool effects():
        return square(3) == 9

    def main() -> int effects():
        return square(3)
    ```

### 4. Difficulty / risk and independence

**Difficulty M–L, risk high.** The lexer and formatter changes are small; the risk is
in the four consumers that must agree on "what is a test" (`project_compile`,
`interfaces.renderContracts`, `native_test_contracts`/`native_test_cases`, `lint`) and
in the contracts-JSON marker, which is hashed into native-test receipts. Cross-module
`W_DEPRECATED` also collides with `typed.Function` gaining no attributes, so every
consumer must go back to the AST by declaration span.

**Not independent.** It edits `src/lexer.zig`, `src/parser.zig`, `src/ast.zig`,
`src/formatter.zig`, `src/interfaces.zig`, `src/declarations.zig`,
`src/project_compile.zig`, `src/incremental.zig`, `src/lint.zig` — i.e. it overlaps
7.2 (lexer/parser/ast/lint/interfaces), 7.4 (declarations/interfaces) and 7.5b
(parser). Serialize it with those.

### 5. Audit-vs-code conflicts

- The guide's gate line says attributes are "part of the interface fingerprint". That
  machinery **exists** (`incremental.declarationInterface`), but the function header
  span starts at the name (`baseFunctionSpan` `src/incremental.zig:950`), so
  attributes are currently outside it — an explicit edit is required, not a free win.
- `api-diff` is **not implemented anywhere in the tree** (`grep -rn "api-diff" src`
  returns nothing; it is a Wave 3 item, audit 6.2). Both `@deprecated`'s "api-diff
  treats removal as compatible" and 7.2/7.3/7.4's api-diff claims are blocked on Wave
  3 and must be deferred or the Wave 3 command built first.
- "deny-able `W_DEPRECATED`" is not wired: `lint_config.Config.warnings` is parsed and
  never consumed (see section 0).
- The guide uses two spellings for `@allow`: 7.1 says `@allow(rule, reason=…)` while
  4.4 says `@allow("function-length", reason="…")`. Plan for the quoted string from
  4.4, which is the section that specifies the replacement and the
  `E_REMOVED_SPELLING` removal.
- `list-declarations` today is parse-only and cannot resolve an imported name; the
  audit expects `list-declarations` to "report attributes", which is fine, but it does
  **not** ask it to resolve `@deprecated` targets — keep it parse-only.

---

## 7.2 Docstrings and `L_UNDOCUMENTED_EXPORT`

### 1. Exact hook points

| Stage | file:line | note |
| --- | --- | --- |
| lex | `src/lexer.zig:375-386` | quote branch; `"""` currently lexes as three separate `.bytes` tokens (`byte_literal.end` `src/byte_literal.zig:7` stops at the first matching quote) |
| lex | `src/byte_literal.zig:7` | `end` breaks on `\n`/`\r`; a multi-line literal needs a new path |
| layout | `src/python_layout.zig:16-63` | one token per logical line assumption; a token spanning newlines is legal here because only `span.start`'s line is read |
| parse | `src/parser.zig:343-455` | top-level loop; a leading string statement currently falls to `function(null)` and dies in `expect(.kw_def)` (`:484`) |
| parse | `src/parser.zig:765-781` | `block()` — where a leading docstring statement must be recognized |
| parse | `src/parser.zig:802-893` | `statement()` — unchanged; the docstring is consumed by `block()` |
| check | `src/sema.zig:187` | `checkFunction`; a discarded string literal must not contribute allocation (see `EFFECT-LITERAL-1`, `SPEC.md:115`) |
| check | `src/sema.zig:4111` | `statementAssert`; unrelated but shows the statement-hook style |
| lint | `src/lint.zig:137-150` | `rules` array; add the new rule here |
| lint | `src/lint.zig:95` | `RuleContext` — carry `syntax`/`index` here, **not** on `Facts` (7 fields) |
| lint | `src/lint.zig:369-395` | `runUntestedExport` is the template for a "walk exports" rule |
| lint | `src/lint.zig:153-161` | `resolveMode` — profile `agent`/`strict` defaults live on `Rule.modes` |
| list-ifaces | `src/interfaces.zig:445-464` | `renderFunctionLine`; append the first docstring line |
| list-ifaces | `src/interfaces.zig:535-548` | `contractFunction`; the contract JSON would carry the summary |
| fingerprint | `src/incremental.zig:950-961` | docstring is declaration text; decide explicitly whether it changes the interface hash |
| doc gate | `src/doc_coverage.zig:13` | `definition_keywords` includes `def/record/...`; a docstring is not an export, so no new coverage obligation |

### 2. Smallest viable implementation

**Lexer.** Add a `docstring` tag (or reuse `.bytes` and detect `"""` by span text) and
a triple-quote scanner. The smallest correct change is a dedicated
`byte_literal.tripleEnd(bytes, start, sink)` that scans for the matching `"""`/`'''`,
allows newlines, and reports `E_BYTE_LITERAL` on an unterminated literal; wire it into
`tokenize` in the quote branch before the single-quote path
(`src/lexer.zig:383`). Keep the decoded value as the literal's text (reuse
`byte_literal.decode` with a span that excludes the extra quotes, or a parallel
`tripleDecode`). Multi-line spans are safe for `python_layout` because it only reads
`lineStart(bytes, token.span.start)`; the next real token starts a new line and the
indent logic runs normally. Confirm one edge case with a test: a docstring whose last
line has trailing content on the same line as the closing quotes.

**AST.** Same pattern as 7.1 — a program-level table keyed by declaration span:
`ast.Program.docstrings: []const DeclarationDoc = &.{}` where
`DeclarationDoc = struct { declaration: Span, text: []const u8, span: Span }` (Program
5→7 fields with the 7.1 `attributes` field, exactly at cap). This covers module-level,
function-level, record/union/domain docstrings without touching
`Record`/`Variants`/`Domain` (`Variants` and `Domain` have room, but a single table is
one code path). A module-level docstring has no declaration key; store it as
`DeclarationDoc{ .declaration = module header span }` or a separate
`Program.module_docstring: ?[]const u8` if the 7-field cap allows (it does not, once
`attributes` lands) — prefer a sentinel declaration span of the module header, matched
by `src.moduleHeader` span.

**Parser.** In `parse()`, if the first token is a `.docstring`/triple `.bytes`, consume
it and record it against the module header span. In `block()` (`src/parser.zig:768`),
before the loop, if the first token after `.indent` is a docstring token, consume it and
attach it to the enclosing declaration. `block(self)` becomes
`block(self, owner: ?Span)` (1→2 params) and its seven call sites
(`src/parser.zig:512,793,814,823,826,837,936`) pass `null` except the `function()` site
at `:512`, which passes `function.name`; that also covers module-level docstrings if
`parse()` routes the header through the same helper.

**Lint.** New rule `undocumented-export` in `src/lint.zig`:
- code `L_UNDOCUMENTED_EXPORT`, modes `.{ .agent = .report, .strict = .block, .safety = .block }`;
- `RuleContext` gains `syntax: ast.Program` and `index: *interfaces.Index` (4→6
  fields, cap-safe); build them in `lint.run` from `request.compilation`;
- for every exported symbol (functions, and `kind == .type` records/unions/domains),
  look up the docstring by `symbol.span`; missing → finding; present but with fewer
  than `min_chars` non-whitespace characters → finding; present but equal
  (case-insensitively, ignoring `_`) to the declaration name or to a `"<name>."`/
  `"<name> doc"` spelling → "restates the name" finding;
- default `min_chars = 12`, matching Guardian's `doc-quality` default
  (`../guardian-zig/src/checks/doc_comments.zig:71-77`, `config.zig:524`), counted over
  non-whitespace characters;
- **config surface problem:** the natural home is
  `lint_config.RuleSetting.min_chars`, but `RuleSetting` is at exactly 7 fields and
  cannot grow (`src/lint_config.zig:31`). Either group `max`/`hard_max`/`recover_pct`
  into a sub-struct (a type-size change that must itself respect the cap) or reuse the
  existing `max` field for the length floor under this one rule name. The cheaper,
  honest option is to add a **new top-level `lint` key** `min_chars` on
  `lint_config.Config` (4 fields, room) rather than grow `RuleSetting`.

**list-interfaces.** `renderFunctionLine` (`src/interfaces.zig:445`) appends
`# <first line>` after the signature; `contractFunction` (`:535`) puts the first line
in a new `ContractDeclaration.docstring` field (6→7, exactly at cap). Because the
contracts JSON is hashed into native-test receipts, emitting an empty string for no
docstring changes every existing receipt; either omit the field when empty (preferred,
keeps fixtures stable) or accept a receipts refresh.

**New codes:** `L_UNDOCUMENTED_EXPORT` (lint; report under `agent`, block under
`strict`). No new `E_*`.

### 3. Test / doc obligations

- **Tests to extend**
  - `src/formatter_test.zig` — a triple-quoted docstring round-trips byte-for-byte
    including its interior newlines and `#` characters (extend the `TOOL-5` test area).
  - `src/python_syntax_test.zig` / `src/python_assert_test.zig` style — a docstring as
    the first statement of a function and of a module is accepted and inert; a
    docstring after a statement stays an ordinary discarded string.
  - `src/stdlib_*_test.zig` fixtures are unaffected but `test/integration.zig` should
    gain a `mylang lint` case for the new rule under `agent` and `strict`.
  - `src/interfaces_test.zig` — `render` prints the first docstring line.
- **`// spec: TAG` tests.** New `DOC-1`/`DOC-2` tests in a new
  `src/docstrings_test.zig` (must be added to `guardian.toml` `orphan_files.roots` /
  `test_reachability.roots` if it is a new file — the cheaper path is to extend
  `src/python_syntax_test.zig`, which is already reachable).
- **SPEC bullets:**
  - `- [DOC-1] A triple- or single-quoted string literal that is the first statement of a module or of a function body is that declaration's docstring; it is inert, contributes no effect, and later standalone strings stay ordinary discarded expressions. list-interfaces and the declaration contract show its first line.`
  - `- [DOC-2] L_UNDOCUMENTED_EXPORT reports an exported function, record, union or domain with no docstring, one shorter than min_chars (12 by default, counted over non-whitespace characters), or one that merely restates the declaration name. It reports under agent and blocks under strict.`
- **`src/features.json` slug** `"docstrings"`:
  `{ "kind": "language", "summary": "A leading string-literal statement is a module/function docstring, surfaced by list-interfaces and checked by L_UNDOCUMENTED_EXPORT.", "doc": "docs/functions.md#docstrings" }`.
  Doc section `## Docstrings` with a runnable example:
  ```text
  # doc: not-mylang
  # doc: expect 14
  def area(width: int, height: int) -> int effects():
      "The rectangle's area in square units."
      return width * height

  def main() -> int effects():
      return area(2, 7)
  ```

### 4. Difficulty / risk and independence

**Difficulty L, risk medium-high.** The lexer/layout interaction for multi-line
literals is the main risk: `python_layout.lower` and `lexer.declarationEnd` both reason
about lines and token spans. Restricting v1 to single-line docstrings would remove most
risk but fails the audit's own `a12` probe, which uses `"""…"""`. Include triple quotes,
but test a multi-line docstring followed by a blank line and a dedent explicitly.

**Not independent.** Shares `src/lexer.zig`, `src/parser.zig`, `src/ast.zig` with 7.1
and 7.5b, and `src/lint.zig`/`src/interfaces.zig` with 7.1/7.4.

### 5. Audit-vs-code conflicts

- The guide calls docstrings "`C-5`" and says C-5 "already provides the syntax"; in
  this tree there is **no docstring syntax at all** (`src/ast.zig` has no docstring
  field, the lexer has no triple-quote path, `SPEC.md` has no doc tag). C-5 is a
  backlog title in `velocity/backlog.json`, not implemented.
- The guide says the rule "reports ... one that merely restates the name". Guardian's
  `doc-comments`/`doc-quality` check does **not** implement a restates-the-name test
  (`../guardian-zig/src/checks/doc_comments.zig:53-91`), so that clause is new
  behavior with no reference implementation and needs its own definition (recommended:
  case-insensitive equality with the name, with `_`→space, or `"<name> …"` where the
  remainder is under 2 words).
- `RuleSetting` cannot hold `min_chars` (7-field cap), so the guide's implicit
  per-rule `min_chars` is not reachable through the existing lint object shape.

---

## 7.3 Standard-library error unions and `?` conversion

### 1. Exact hook points

| Stage | file:line | note |
| --- | --- | --- |
| stdlib | `src/stdlib/json.my:603` | `loads` returns `Result[Json, str]`; every `Result[T, str]` in `src/stdlib/*.my` is a conversion site (`grep -n "Result\[" src/stdlib/*.my`) |
| stdlib | `src/stdlib/path.my`, `strings.my`, `math.my`, `time.my`, `random.my`, `base64.my`, `hex.my`, `pool.my`, `sort.my`, `network.my`, `json.my` | each gains `export Error` + a `message`/category helper |
| embed | `src/standard_library.zig` | the embedded sources; no build step, but the files are compiled into tests |
| check `?` | `src/sema.zig:3236-3257` | `.propagate`; `require(input.error_type, output.error_type)` at `:3242` is where conversion must be allowed |
| check helper | `src/sema.zig:853-864` | `require`; a wrapping check can live beside it or inline at the propagate site |
| typed | `src/typed.zig:240-255` | `resultShape`; the output `error_type` is an aggregate union |
| lower | `src/lower.zig:206-215,415-418` | `.propagate` work item → `try_result` instruction |
| bytecode | `src/bytecode_model.zig:16` | `try_result: struct { input, output, error_target }` |
| bytecode | `src/bytecode.zig:485-498` | `validateOpTryResult`; `:489` hard-rejects `input.error_type != output.error_type` |
| emit | `src/qbe.zig:836-865` | try_result emission; `:846-848` writes `output.error_tag` and copies the payload |
| native ir | `src/native_ir.zig:133-136` | stack effect of `try_result` |
| docs | `docs/standard-library.md:616` | "Do not match on them" paragraph to replace |
| doc gate | `src/doc_coverage_command.zig` + `src/doc_coverage.zig:41` | every new stdlib export must be named and exercised in `docs/standard-library.md` |
| tests | `src/stdlib_json_test.zig:7`, `src/stdlib_path_test.zig`, `src/stdlib_fixture.zig:19` | fixture harness and per-module signature tests |
| options docs | `docs/results-and-options.md` `## Postfix error propagation` (`:45`) | `?` conversion belongs here |

### 2. Smallest viable implementation

**Standard library (per module).** Each embedded module declares and exports one error
union and returns it where it returned `str`:

```text
export Error
# One JSON failure; the payload is the human-readable message.
union Error:
    Malformed(str),
    Rejected(str)
```

Because mylang union cases take a payload *type*, "carrying a `message` payload" is
expressed per case plus one exported helper `def message(error: Error) -> str` that
matches and returns the payload. That keeps existing `Result[T, str]` call sites
migratable one signature at a time and gives `?` a real union to wrap. The exact
category names are the one open design decision (see Open questions).

Only `json` and `path` are required by the audit's examples; migrating every module is
mechanical but large. The plan's smallest viable cut: declare the union and the
`message` helper in **every** module that currently returns `Result[_, str]`, switch
`json.loads`/`json.dumps` and `path.*` first, and leave the rest as a follow-up list
inside the same SPEC bullet.

**`?` conversion (check).** At `src/sema.zig:3240-3243`, when
`input.error_type != output.error_type`, search `output`'s union cases
(`self.catalog.records[output.error_type.recordIndex()].shape.variants.cases`) for a
case whose `payload == input.error_type`. If found, accept; otherwise keep the current
`E_TYPE`. A new helper `fn wrappingCase(self, input: typed.Type, output: typed.Type) ?usize`
(3 params) keeps the propagate site readable. The typed node still stores only
`{ .value, .output }`, so no `typed` shape change.

**`?` conversion (bytecode/emit).** `validateOpTryResult` (`src/bytecode.zig:489`) must
accept the wrapping case; `qbe.zig:846-848` must write the *wrapping* case's tag instead
of requiring identical error types and store the whole input error payload into the
output case payload. Add a mirrored helper in `qbe.zig` (or a new
`src/qbe_results.zig`, which must be added to `guardian.toml` roots if new) that maps
`input.error_type` to the output case tag. `native_ir.zig:133` needs no change.

**Docs/tests.** `docs/standard-library.md` gets an `## Error unions` subsection and the
`:616` paragraph is rewritten. `SPEC.md:26` (`CORE-11`) already describes propagation
"by case name across nominal result types"; the new behavior extends it, so amend that
bullet or add `TRY-CONVERT-1`.

**New codes:** none required; reuse `E_TRY_TYPE`/`E_TYPE` for a non-wrapping mismatch.
Optionally add `E_TRY_CONVERSION` with a better message ("the error type is not a case
payload of the enclosing result's error union").

### 3. Test / doc obligations

- **Tests to extend**
  - `src/propagation_test.zig` (`OPTION-TRY-1` `:103`, `CORE-11` `:145`) — add a
    wrapping union case that propagates and one that rejects.
  - `src/results_test.zig` — native execution of a wrapped `?` trap/return.
  - `src/bytecode.zig` unit tests around `validateOpTryResult`.
  - `src/stdlib_json_test.zig:7`, `src/stdlib_path_test.zig` — the fixture returns the
    new union and `message` prints.
  - `src/qbe_test.zig` / `src/qbe_text_test.zig` — emitted QBE for a wrapped
    propagation, if the emitter changes shape.
- **`// spec: TAG` tests.** `TRY-CONVERT-1` in `src/propagation_test.zig`;
  `STDLIB-ERROR-UNION-1` in `src/stdlib_json_test.zig`.
- **SPEC bullets:**
  - `- [TRY-CONVERT-1] ? propagating a result whose error type is the payload of a case of the enclosing function's error union converts implicitly: the error value is wrapped in that case, the outgoing tag is the case's tag, and a payload type that is not a case of the enclosing union still rejects with a located type error.`
  - `- [STDLIB-ERROR-UNION-1] Every standard module whose operations can fail exports an error union and returns Result[T, Module.Error]; each carries a message payload reachable through an exported message(error) helper, so callers match on category instead of the human text and api-diff sees a new case as a breaking change.`
- **`src/features.json` slugs**
  - `"error-conversion"`: `{ "kind": "language", "summary": "? wraps a result error into the matching case of the enclosing function's error union.", "doc": "docs/results-and-options.md#postfix-error-propagation" }`.
  - `"standard-error-unions"`: `{ "kind": "language", "summary": "Standard modules export an error union with a message payload instead of Result[T, str].", "doc": "docs/standard-library.md#error-unions" }`.
  - Runnable examples in both sections. `?` conversion needs a module project, so use
    the project form (as `docs/modules.md:77` does); this one has a single member:
    ```text
    # doc: not-mylang
    # doc: project app
    # doc: file main.my
    # doc: expect 12
    module app
    import json

    union AppError:
        Json(json.Error)

    def field_count(source: str) -> Result[int, AppError]:
        _ = json.loads(source)?
        return Ok(0)

    def main() -> int:
        match field_count("{}"):
            case Ok(_):
                return 12
            case Err(_):
                return 1
    ```

**Doc-coverage caveat.** The `mylang doc-coverage` gate walks every `export NAME` in
`src/stdlib/*.my` (`doc_coverage.zig:41-56`) and requires each to appear and be
exercised in `docs/standard-library.md`. Adding `export Error` and `export message` to
eleven modules adds 22 documented names; plan the doc edits with the stdlib change.

### 4. Difficulty / risk and independence

**Difficulty L, risk medium.** The compiler-side change is small and localized
(`sema` + `bytecode` validate + `qbe` emit). The size is in the standard library and
its documentation; the risk is in the module-by-module signature migration breaking
`stdio`/examples and in the `docs/standard-library.md` gate.

**Mostly independent.** It does not touch the lexer/parser/formatter. It touches
`sema.zig` (7.5a, 7.5b), `qbe.zig` (7.5a), and `bytecode.zig` (7.5a) — coordinate
those files but the regions differ.

### 5. Audit-vs-code conflicts

- The guide's `?` premise ("`Result[T, str]` everywhere") matches the code, but the
  audit's exact payload claim "carrying a `message` payload" does not match mylang's
  union grammar: `union Case: Type`, not named fields. The plan uses per-case payloads
  plus a `message` helper; this is an interpretation the implementer must confirm.
- `docs/standard-library.md:616` says "Do not match on them" — that sentence must be
  rewritten as part of this feature, and it is the only place that states the current
  contract.
- `api-diff` does not exist (again), so "api-diff sees a new variant as breaking" is
  aspirational until Wave 3 ships.

---

## 7.4 Re-export: `export shared.units.Distance`

### 1. Exact hook points

| Stage | file:line | note |
| --- | --- | --- |
| lex helper | `src/lexer.zig:473` | `qualifiedName` already splits `alias.name` and `a.b.name` — reuse it |
| parse | `src/parser.zig:352-357` | `export` is contextual; currently `_ = try self.declaredName();` then `expect(.semicolon)`, so `export a.b.C` rejects at the dot |
| parse (module) | `src/parser.zig:294-316` | `parseModule` builds `import_aliases`; a re-export target must be a registered alias or full dotted path |
| collect | `src/project.zig:205-220` | `header()` scans `export` directives with a single `expect(.ident)` at `:213`, then `expect(.semicolon)` `:215`; `Export` is `{name, span}` `:44` |
| collect | `src/declarations.zig:193-199` | `Scan.exportStatement` — same single-name assumption |
| collect | `src/declarations.zig:100-113` | `resolveExports` — requires a **local** declaration by name; a re-export has none |
| collect | `src/interfaces.zig:995-998` | `buildWithCache` marks `module.exports` entries by local `names.get(name)` |
| resolve | `src/interfaces.zig:100-132` | `Index.resolve` — where a facade symbol must be followed to its target |
| resolve | `src/interfaces.zig:43` | `Symbol` (name, kind, span, exported, owner, restricted) |
| names | `src/module_names.zig:28-43` | `Names.reference` — returns `target_module::symbol`; following the facade here makes sema resolve the real declaration automatically |
| names | `src/module_names.zig:69-88` | `symbolKind` — must see through a facade |
| list-ifaces | `src/interfaces.zig:423-440` | `render` iterates each module's symbols |
| list-ifaces | `src/interfaces.zig:487-514` | `renderContracts`, `contractDeclaration` `:521` |
| listing | `src/declarations.zig:89-96` | declarations-v1 JSON, `exports` array |
| manifest | `src/project.zig:222-234` | `module graph v1` render (imports only today) |
| import policy | `src/import_policy*.zig` | the facade is what `import_policy` should protect |
| spec | `SPEC.md:49` (`EXPORT-PLACEMENT-1`), `:73` (`DECLARATION-LIST-1`), `:53` (`PROJ-3`) | amend |
| tests | `src/interfaces_test.zig:275`, `src/declarations_test.zig:147`, `src/project_test.zig`, `src/dotted_modules_test.zig`, `src/import_policy_test.zig` | extend |

### 2. Smallest viable implementation

**Data.** `project.Export` (`src/project.zig:44`, 2 fields) gains
`alias: ?[]const u8 = null` and `name` becomes the final member
(`export shared.units.Distance` → `alias = "shared.units"`, `name = "Distance"`); the
existing single-name case keeps `alias = null`. This is 3 fields, cap-safe, and keeps
the module-graph JSON mostly stable. `interfaces.Symbol` (`:43`, 6 fields) gains
`re_export: ?Identity = null` (7, exactly at cap).

**Parse/collect (all three scanners).** `parser.zig:352`, `declarations.zig:193` and
`project.zig:212` all change `expect(.ident)` to a dotted-name read. `project.zig`
already has `Scanner.name()` (`src/project.zig:287`) returning
`{ text, last, span }`, where `last` is the final member — use it directly.
`declarations.zig` has the same shape in `Scan.dotted()` (`src/declarations.zig:163`).
`parser.zig` can re-lex the name span with `lexer.qualifiedName` (`src/lexer.zig:473`).
`resolveExports` (`declarations.zig:100`) must not require a local
declaration for a dotted name; instead the `exports` JSON entry carries `alias`, and
the local declaration list is unchanged. In `project.zig`, a dotted export whose alias
matches no import is `E_UNKNOWN_EXPORT` at the export site (the single-file name case
keeps the existing check).

**Interfaces.** In `buildWithCache`'s export loop (`src/interfaces.zig:995`):
1. if `exported.alias == null`, keep today's local-name lookup and mark `exported`;
2. otherwise, resolve the target with `index.resolve(.{ .from = module_id,
   .alias = exported.alias, .name = exported.name, .kind = <resolved>, ... })`.
   `Index.resolve` needs a kind; the clean route is a new
   `fn resolveExported(module, alias, name) Error!Identity` that probes `.type`,
   `.function`, `.constraint` in order (three `resolve` calls, ignoring
   kind-mismatch diagnostics) and returns the first hit;
3. append a facade `Symbol{ .name = local_name, .kind = target.kind, .span = <export
   directive name span in the facade module>, .exported = true, .re_export = target }`
   to the facade unit and register `local_name` in `unit.names`.
4. `Index.resolve` (`:126-131`), after the existing privacy/kind checks, returns
   `symbol.re_export orelse identity`. This makes `Names.reference`
   (`module_names.zig:37-42`) emit the real module-qualified name, so sema's function
   and type lookups work with no further change, and `symbolKind` (`:85-87`) should
   check `re_export`'s target for kind when the facade symbol's kind is ambiguous.

The privacy invariant is preserved by `Index.resolve`'s existing
`if (target != from and !symbol.exported)` check on the target when the facade symbol
is first built.

**Rendering.** `render`/`renderFunctionLine`/`renderContracts`/`contractDeclaration`
must print the *facade* module and local name while reading the declaration from the
*defining* unit: when `symbol.re_export` is set, call the existing
`contractFunction`/`contractType` with `id.module`/`target symbol` and override the
emitted name. This is the fiddliest part; a small indirection
(`fn declarationSource(symbol) struct { module: usize, symbol: usize, display: []const u8 }`)
keeps the 6-param cap.

**New codes:** `E_UNKNOWN_EXPORT` reused for an unresolved facade target;
`E_REEXPORT_PRIVATE` if the target is not exported in its own module (the existing
`E_PRIVATE_SYMBOL` message may be reused).

### 3. Test / doc obligations

- **Tests to extend**
  - `src/declarations_test.zig:147` — a dotted export directive appears in `exports`
    with its alias.
  - `src/interfaces_test.zig:275` (module grammar) and `:91` (symbols) — the facade
    resolves cross-module and a third module can call/name through it.
  - `src/project_test.zig` — an unresolved facade alias rejects; an unexported target
    rejects.
  - `src/import_policy_test.zig` — direct imports of internals denied while the facade
    works.
  - `test/integration.zig` — a two/three module acceptance program.
- **`// spec: TAG` test.** `REEXPORT-1` in `src/interfaces_test.zig`.
- **SPEC bullets (amend `EXPORT-PLACEMENT-1`, `DECLARATION-LIST-1`, `PROJ-3`):**
  - `- [REEXPORT-1] An export directive may name an imported declaration (`export shared.units.Distance`) as well as a local one. The facade module publishes that declaration under its own local name; a reference through the facade resolves to the defining module's identity with the target's own export privacy enforced, and interfaces, contracts and the project fingerprint report the facade name while the schema uses the defining declaration.`
  - `- [REEXPORT-2] An export directive naming a qualified path whose alias is not imported, or whose target is not exported in its defining module, rejects with the existing located E_UNKNOWN_EXPORT/E_PRIVATE_SYMBOL family. list-declarations reports the facade directive with its alias and leaves local declaration flags unchanged.`
- **`src/features.json` slug** `"re-exports"`:
  `{ "kind": "language", "summary": "An export directive may re-export an imported declaration so a package publishes one facade module.", "doc": "docs/modules.md#re-exports" }`.
  New `## Re-exports` section under `docs/modules.md` (near `## Export placement`
  `:146`) with a runnable multi-file `# doc: project` example (the doc runner already
  supports `# doc: project`/`# doc: file` blocks, `docs/modules.md:77`).

### 4. Difficulty / risk and independence

**Difficulty L, risk medium-high.** Three independent scanners must agree on the
dotted grammar, and the interface index has to synthesize a symbol whose span lives in
one module but whose declaration lives in another. The rendering override is where
mistakes surface as `error.InternalError` (every `findFunction`/`contractType` assumes
the symbol's span is in its own module's syntax).

**Independent** of 7.3 and 7.5, and only lightly overlaps 7.1/7.2 in
`interfaces.zig`/`declarations.zig`/`project.zig`.

### 5. Audit-vs-code conflicts

- The guide says "import_policy denies direct imports of the internals". That only
  works if `import_policy` understands facade symbols; today it checks module-level
  import edges. Verify `src/import_policy*.zig` before promising this in the SPEC
  bullet.
- `api-diff` does not exist; "api-diff tracks the facade" is deferred.
- `EXPORT-PLACEMENT-1` (`SPEC.md:49`) currently promises "explicit `export Name;`
  directives", so both the listing contract and that bullet must be amended, not just
  extended.

---

## 7.5a Assert messages with values (`assert n > 0, f"n was {n}"`)

### 1. Exact hook points

| Stage | file:line | note |
| --- | --- | --- |
| parse | `src/parser.zig:846-857` | `statement()` assert arm; `expect(.bytes)` at `:852` makes the message a literal only |
| parse | `src/parser.zig:1194-1235` | `parseFormat` / `formatHole` — the existing f-string parser to reuse |
| ast | `src/ast.zig:127` | `Assertion { condition, message, literal }` |
| check | `src/sema.zig:4111-4115` | `statementAssert`; currently copies `claim.message` and never checks it |
| check | `src/sema.zig:1752-1762` | `checkFormat` builds a `str` via concatenation; allocation means `noalloc` would reject the message if checked as an expression |
| typed | `src/typed.zig:426` | `Assertion { condition, message }` |
| lower | `src/lower.zig:130-133` | assertion lowering emits a single `.assert_true` |
| bytecode | `src/bytecode_model.zig:69` | `assert_true: []const u8` |
| bytecode | `src/bytecode.zig:555` | `assert_true` pops 1 |
| native ir | `src/native_ir.zig:148` | `assert_true` pops 1 |
| emit | `src/qbe.zig:69` | per-pc message collected into `Unit.messages` |
| emit | `src/qbe.zig:900-903` | `assert_true` emission calls `myl_qbe_fail_assert` |
| runtime | `src/qbe_runtime.c:249-265` | `myl_qbe_fail_assert` reads `frame->function->messages[position]` |
| runtime | `src/qbe_runtime.c:104-109` | `fail_detail` renders the message-only trap line |
| metadata | `src/qbe_build_outputs.zig:27-37` | emits one `const char *` message per pc |
| print path | `src/qbe_io.c:8-57`, `src/native_print.h` | `MylPrint` buffer with `bytes/length`; `myl_qbe_print_begin`, `myl_qbe_text_render` |
| print lower | `src/qbe_io.zig:20-56` | renders typed operands into the sink with the generated per-type renderers |
| tests | `src/python_assert_test.zig:26-60` (`PY-ASSERT-1/2`) | extend |

### 2. Smallest viable implementation

There are two tiers; plan the first and note the second.

**Tier 1 (no new bytecode op or runtime symbol).**
1. **Parser:** in the assert arm, accept a `.format` token by calling
   `self.expression(0)` (which routes through `parseFormat`), or any expression
   producing `str`. Store it in `ast.Assertion.value: ?NodeId = null` (3→4 fields).
   Keep the literal path for `.bytes`.
2. **Check:** `statementAssert` gains `message_value: ?NodeId` on
   `typed.Assertion` (2→3 fields). When present, check it with
   `self.expressionExpected(claim.value.?, str_type)` and store the node. Because the
   message is only evaluated on the failure path, exempt it from the enclosing
   function's allocation ceiling (document this carve-out in the SPEC bullet); the
   naive alternative — checking it as an ordinary expression — makes
   `assert n > 0, f"n was {n}"` reject inside a `noalloc` function, which contradicts
   the audit's intent.
3. **Lower:** for a valued assertion, emit a small control-flow shape using existing
   ops only:
   ```
   <condition>              ; leaves bool
   jump_if_false @fail
   jump @done
   @fail:
     <print op> { sink = .stderr, types = [str], arguments = [message], debug = false }
     pop                    ; print pushes unit
     push_bool false
     assert_true ""         ; existing trap, no static message
   @done:
   ```
   `bc.Print` is constructed directly in `lower.zig` (the struct is
   `src/typed.zig:113`); `qbe_io.zig` already renders any `str` operand to stderr with
   no capability and no effect walk, so no runtime change is needed. The existing
   `drop_debug` policy is bypassed because `debug = false`.
4. **Formatter/listing:** assertions are statements; nothing to change.

**Tier 2 (structured detail).** If the trap's JSON `operation` must carry the rendered
text, add one op `assert_render` (or extend `assert_true` to a struct) plus a runtime
entry `myl_qbe_fail_assert_buffer(ctx, sink)` in `qbe_io.c` that copies
`MylPrint.bytes[0..length]` into a bounded buffer on `MylQbeContext` and calls
`fail_detail`. Adding a bytecode op means updating the exhaustive switches in
`bytecode_model.zig`, `bytecode.zig:521-624`, `native_ir.zig:120-160`,
`disassemble.zig`, `effects.zig:537-608`, `qbe.zig:820-870`, and the collection/domain
lowerers; the buffer must be appended at the *end* of `MylQbeContext` (the
`_Static_assert` offsets at `qbe_runtime.c:25-28` cover only the prefix). Recommend
Tier 1 for this wave and file Tier 2 as a follow-up.

**New codes:** none. `E_TYPE` covers a non-`str` message.

### 3. Test / doc obligations

- **Tests to extend** `src/python_assert_test.zig` (`:26`, `:32`): a failed
  `assert n > 0, f"n was {n}"` traps `R_ASSERT` at the condition's location and writes
  the rendered message to stderr before the trap; a passing assertion evaluates no
  message (prove with a side-effecting helper, or with a `noalloc` function that would
  otherwise reject); a non-`str` message is `E_TYPE`.
- **`// spec: TAG` test.** Extend the `PY-ASSERT-2` test and add `PY-ASSERT-3` in the
  same file (already reachable from `src/root_test.zig:38`).
- **SPEC bullet (amend `PY-ASSERT-2`, `SPEC.md:664`):**
  `- [PY-ASSERT-3] The message after assert may be any str expression, including an f-string; it is evaluated only when the condition is false and rendered to standard error immediately before the R_ASSERT trap, so a passing assertion pays nothing and a failed one names the values it saw. The message expression is exempt from the enclosing effect ceiling because it runs only on the failure path.`
- **`src/features.json` slug** `"assert-messages-with-values"`:
  `{ "kind": "language", "summary": "assert accepts an f-string message and renders it only on failure, before the trap.", "doc": "docs/statements.md#assert-statements" }`.
  Update the existing section (`docs/statements.md:74-98`) and add a runnable example:
  ```text
  # doc: not-mylang
  # doc: expect 42
  def half(value: int) -> int effects():
      assert value % 2 == 0, f"half needs an even value, got {value}"
      return value // 2

  def main() -> int effects():
      return half(84)
  ```

### 4. Difficulty / risk and independence

**Difficulty M, risk medium.** Parser + checker + lower changes are localized
(`parser.zig:846`, `sema.zig:4111`, `lower.zig:130`), and Tier 1 reuses the existing
print machinery. The risks are (a) bytecode stack-height validation for the new
`jump_if_false`/`print`/`pop`/`push_bool`/`assert_true` block, (b) evaluation-order
tests proving the message is not evaluated on success, and (c) the deliberate
effect-ceiling carve-out.

**Mostly independent.** Touches `parser.zig` (shared with 7.1/7.2/7.5b), `sema.zig`
(7.3/7.5b) and `lower.zig` (7.3). No `interfaces`/`declarations` changes.

### 5. Audit-vs-code conflicts

- The guide says "Messages are string literals today (`docs/statements.md:76`)" and
  that a failed invariant "cannot say what it saw". Both are accurate: the parser
  hard-requires `.bytes` (`src/parser.zig:852`) and `PY-ASSERT-2` explicitly documents
  a literal.
- The guide does not mention the effect-ceiling interaction: an f-string message
  allocates, and a `noalloc`/`noio` function currently cannot contain one. The plan's
  carve-out is a design decision the implementer should record in SPEC, not a
  discovered requirement.
- The guide says "render values at runtime before the trap"; it does not require the
  values to appear in the structured trap detail. Tier 1 satisfies the wording; Tier 2
  is needed only if tooling must read the message from JSON.

---

## 7.5b Record field defaults and `replace(cfg, retries=5)`

### 1. Exact hook points

| Stage | file:line | note |
| --- | --- | --- |
| parse (fields) | `src/parser.zig:443-449` | record field loop reads `name: Type` and drops `Parameter.default_value` |
| parse (default) | `src/parser.zig:547-557` | `defaultArgument` — the immutable-scalar-literal rule to reuse; also `E_DEFAULT_ARGUMENT` ordering check at `:540` |
| parse (update) | `src/parser.zig:1033` | `.kw_replace` dispatch: `declaresFunction` → `parseLeaf`, else `parseBuiltin` |
| parse (update) | `src/parser.zig:1382-1396` | `parseBuiltin` — positional 3-arg `replace(list, index, value)` intrinsic |
| ast | `src/ast.zig:136-141` | `FieldInit`, `Parameter.default_value` already exists |
| templates | `src/nominal_templates.zig:29` | `Field` (name, ty, builtin_name); built from `ast.Parameter`/`ast.Variant` at `:263-281` (`fields`) |
| templates | `src/nominal_templates.zig:83-86,118,127,135` | builtin declarations with synthesized fields |
| typed | `src/typed.zig:119` | `Field { name, declaration, ty }` |
| catalog | `src/nominal_catalog.zig:200-209` | `Builder.fields` builds `typed.Field` from `templates.Field` |
| catalog | `src/nominal_catalog.zig:232-234` | table-key `typed.Field` construction |
| construct | `src/record_calls.zig:24-34` | `construct` — maps call arguments to `ast.FieldInit`; where defaults must be inserted |
| construct | `src/record_calls.zig:11-23` | `lower` entry (owner/generic guards) |
| check | `src/sema.zig:1369-1436` | `collectionSyntax` calls `record_calls.lower` at `:1380` before anything else |
| check | `src/sema.zig:823-845` | `fields()` — the missing-field diagnostic at `:838-843` |
| check table | `src/sema.zig:2975-2981` | `checkTableLiteral` also uses `fields(complete=true)` — tables must keep requiring every key |
| check update | `src/sema.zig:2806` | `checkCall`; a `replace` keyword form must be handled before `callDeclaration` `:2856` |
| check update | `src/sema.zig:2222-2255` | `queueExpression` `.call` — queue base + named field values |
| typed update | `src/typed.zig:95` | `update: struct { base, fields }` **already exists** |
| lower update | `src/lower.zig:249-255` | `.update` emission **already exists** |
| bytecode | `src/bytecode_model.zig:31`, `src/bytecode.zig:479-484`, `:551-554` | `update_record` validation/height **already exists** |
| emit | `src/qbe_aggregate.zig` (`update_record`) | already implemented |
| effects | `src/effects.zig:61` (`update` return origin), `:389` (effect walk) | already implemented |
| doc | `docs/records-and-unions.md:12` (`## Records`), `:78` (`## Positional and named constructors`) | extend |
| test | `src/records_test.zig:228` (`CORE-5`), `src/python_calls_test.zig`, `src/nominal_templates_test.zig`, `src/duplicates_test.zig` (`src/duplicates.zig:304` already walks `.update`) | extend |

### 2. Smallest viable implementation

**Record field defaults.**
1. **Parser:** in the record field loop (`src/parser.zig:446`), after `ty = typeName()`,
   accept `= default` via the existing `defaultArgument()` and store it in the already
   existing `ast.Parameter.default_value`. Reject a required field after a defaulted
   one with the existing `E_DEFAULT_ARGUMENT` rule (mirror `:540`), so records and
   functions agree.
2. **Metadata:** add `default_value: ?usize = null` (a backing `ast.NodeId`) to
   `nominal_templates.Field` (`:29`, 3→4 fields) and `typed.Field` (`src/typed.zig:119`,
   3→4), populated in `nominal_templates.fields` (`:279-280`) via
   `if (@hasField(@TypeOf(input), "default_value")) input.default_value else null` so
   variant cases stay null, and copied in `nominal_catalog.Builder.fields`
   (`:205`) and the table-key path (`:233`). Using `usize` avoids importing `ast` into
   `typed.zig` and keeps `ast_copy`'s reflective mapper happy.
3. **Construction:** `record_calls.construct` (`:24-34`) allocates
   `call.arguments.len` fields. Change it to walk declarations in order: take the
   supplied positional/named value when present, otherwise the declaration's
   `default_value` node (same syntax table, so no relocation is required), otherwise
   leave it out so `sema.fields()` still reports `E_INCOMPLETE_CONSTRUCTION`. The
   existing named/positional mapping at `:27-31` is unchanged. A default that is not an
   immutable scalar is already rejected by `defaultArgument`.
4. **Table literals stay strict.** `checkTableLiteral` (`src/sema.zig:2975`) calls
   `fields(complete=true)` with synthesized initializers, so enum-keyed tables keep
   requiring every key; do not route tables through the default path.

**Functional update `replace(cfg, retries=5)`.**
1. **Parser:** in `parseBuiltin` (`src/parser.zig:1382`), when the token is
   `.kw_replace`, peek after the first argument: if the next tokens are `comma` then a
   named-argument head (`ident`/`kw_len`/`kw_replace` followed by `equal`), build an
   ordinary `.call` node (`name = replace token span`, `argument_names` populated) via
   `callArguments` instead of the 3-arg intrinsic node. The positional intrinsic path
   is untouched. Reuse the keyword-argument scanner at `:1486-1513`.
2. **Queue:** in `queueExpression`'s `.call` branch (`src/sema.zig:2222`), detect the
   named-`replace` form before `queueBuiltinCall` and queue the base first, then the
   field values in source order (the base must be checked before the values, matching
   evaluation order).
3. **Check:** in `checkCall` (`src/sema.zig:2806`), before `callDeclaration`, handle the
   named-`replace` form: resolve the base as an aggregate record, call the existing
   `fields(record_type, named, false, span)` helper (`:823`, `complete = false`) to
   map and type-check the named initializers, and emit
   `out.data = .{ .update = .{ .base = base, .fields = checked } }` with `out.ty` the
   record type. No new AST or typed node, no lowering, bytecode, effects, formatter or
   fingerprint change — all of `.update` already exists.
4. **Errors:** a `replace` whose first argument is not an aggregate record is `E_TYPE`
   ("replace(...) needs a record value; the positional form replaces a list index");
   a field name that is not a field stays `E_UNKNOWN_FIELD` from `fields()`; a
   duplicate named field stays `E_DUPLICATE_FIELD`.

**New codes:** none required. Consider `E_RECORD_UPDATE` for the non-record base to
make the diagnostic unambiguous.

### 3. Test / doc obligations

- **Tests to extend**
  - `src/records_test.zig:228` (`CORE-5`) — defaulted fields omitted, positional and
    named construction, a required-after-default rejection.
  - `src/nominal_templates_test.zig` / `src/nominal_catalog`-adjacent tests — a
    generic record with defaults.
  - `src/duplicates_test.zig` — a `replace(cfg, x=1)` program exercises the existing
    duplicate walker, which already handles `.update` (`src/duplicates.zig:304`).
  - `src/propagation_test.zig`-style native execution: an update preserves unmentioned
    fields and does not alias-mutate the base.
  - `src/python_calls_test.zig` — `replace` still parses as the list intrinsic in
    positional form.
- **`// spec: TAG` tests.** `RECORD-DEFAULT-1` and `RECORD-UPDATE-1` in
  `src/records_test.zig` (already reachable, `src/root_test.zig:110`).
- **SPEC bullets:**
  - `- [RECORD-DEFAULT-1] A record field may declare an immutable scalar default after `=`; a constructor call may omit that field and the default is materialized, positional and named construction stay in declaration order, and a required field after a defaulted one rejects like a function parameter. Enum-keyed tables keep requiring every key.`
  - `- [RECORD-UPDATE-1] replace(record, field=value, …) returns a copy of the record with only the named fields changed and every other field preserved; the base evaluates before the values, the result is a fresh record value, and the positional replace(list, index, value) intrinsic is unchanged.`
- **`src/features.json` slugs**
  - `"record-field-defaults"`: `{ "kind": "language", "summary": "Record fields may declare scalar defaults omitted at construction.", "doc": "docs/records-and-unions.md#field-defaults-and-functional-update" }`.
  - `"functional-record-update"`: same anchor section, or split into
    `#functional-record-update`; one new `## Field defaults and functional update`
    section with a runnable block:
    ```text
    # doc: not-mylang
    # doc: expect 7
    record Config:
        retries: int = 3
        verbose: bool = False

    def main() -> int effects():
        base = Config(verbose=True)
        changed = replace(base, retries=5)
        return changed.retries + 2
    ```

### 4. Difficulty / risk and independence

**Difficulty M, risk medium.** The `.update` machinery is complete, so the functional
update is mostly parser disambiguation and one checker branch. The risk is (a) the
`replace` keyword's parser ambiguity (must not change the intrinsic), (b) inserting
defaults into `record_calls.construct` without breaking table literals or the
missing-field diagnostics, and (c) the `typed.Field`/`templates.Field` field addition
touching catalog tests.

**Independent** of 7.1–7.4 except for `parser.zig` (shared with 7.1/7.2/7.5a) and
`sema.zig` (7.3/7.5a). `record_calls.zig`, `nominal_templates.zig`,
`nominal_catalog.zig` are otherwise untouched by the wave.

### 5. Audit-vs-code conflicts

- The guide says "today every module writes a constructor helper to get defaults".
  That is true, but it is worth noting the parser **already has** the
  `Parameter.default_value` slot (`src/ast.zig:141`), so the syntax plumbing is a
  small change, not a new AST concept.
- The guide's `replace(cfg, retries=5)` collides with the existing `replace`
  intrinsic (`PY-RESERVED-1`, `SPEC.md:635`). The plan disambiguates by argument shape
  (named form = record update, positional 3-arg = intrinsic); the implementer must
  confirm this is acceptable rather than introducing a differently-named function.
- The guide groups defaults and functional update as one item, but they are separable
  and can ship independently; only the docs section is shared.

---

## 8. Parallelization

`src/parser.zig` and `src/lexer.zig` are the hard serialization points. Recommended
lanes (one write-owner per file at a time):

| Lane | Features | Exclusive files | Shared files it touches |
| --- | --- | --- | --- |
| 1 | 7.4 re-export | `project.zig`, `module_names.zig` | `interfaces.zig`, `declarations.zig`, `parser.zig` |
| 2 | 7.3 error unions | `src/stdlib/*.my`, `docs/standard-library.md` | `sema.zig`, `bytecode.zig`, `qbe.zig` |
| 3 | 7.5a assert values | `lower.zig` (valued-assert block) | `parser.zig`, `ast.zig`, `sema.zig`, `typed.zig` |
| 4 | 7.5b record defaults/update | `record_calls.zig`, `nominal_templates.zig`, `nominal_catalog.zig` | `parser.zig`, `sema.zig`, `ast.zig`, `typed.zig` |
| 5 | 7.1 attributes then 7.2 docstrings | `lexer.zig`, `formatter.zig` | `parser.zig`, `ast.zig`, `lint.zig`, `interfaces.zig`, `declarations.zig`, `project_compile.zig`, `incremental.zig` |

Files that **must not** be edited concurrently: `src/parser.zig`, `src/sema.zig`,
`src/ast.zig`, `src/interfaces.zig`, `src/lint.zig`. Practical sequencing:

1. Wave 2/3 prerequisites first: wire `lint_config.Config.warnings` and (if the
   deprecation/docstring SPEC bullets depend on it) build `api-diff`, or explicitly
   scope those clauses out.
2. Lane 5a (`@test` + `@allow` + declarations/formatter/lexer) because it unblocks
   7.2's lint rule and 7.4 needs the declarations scanner to handle dotted exports.
3. Lane 1 (7.4) and lane 3 (7.5a) in parallel — disjoint files apart from `parser.zig`.
4. Lane 4 (7.5b) after 3 merges, then lane 5b (7.2 docstrings) after 5a.
5. Lane 2 (7.3) can run throughout; it is the only lane that should own
   `src/stdlib/*.my`.

Tests for every lane: `python3 scripts/focused_test.py units <substring>` while
iterating, then `zig build test`, `zig build test-qbe`, `zig build test-qbe-build`,
`zig build fmt-check`, and `zig-out/bin/mylang doc-coverage .` before finishing.

## 9. Open questions for the implementer

1. `@allow` rule argument: quoted string (audit 4.4) or bare name (audit 7.1)?
2. `@allow` on non-function declarations: v1 restricts attributes to functions
   (`E_ATTRIBUTE_TARGET`); is that acceptable for `L_UNDOCUMENTED_EXPORT` on records?
3. Docstrings: is a single-quoted leading string (not just `"""`) a docstring? The
   plan says yes; Guardian requires the doc text be meaningful, not triple-quoted.
4. Error-union shape: per-case payloads plus a `message` helper, or one
   `Message(str)` case per module? The audit's "match on category" favors the former.
5. Does an exported declaration's docstring participate in the *interface
   fingerprint*? The plan says yes for functions via the declaration header span; say
   so explicitly in SPEC, because a wording-only edit would otherwise silently
   invalidate consumers.
6. Assert values: Tier 1 (stderr before trap, no structured message) or Tier 2 (new
   op + runtime buffer + context field)? Tier 1 is the smallest viable.
7. `W_DEPRECATED` under the default profile: is it emitted by `check`/`build`/`run` as
   today's warnings are, or only under `lint`? The audit's "deny-able" implies the
   existing compiler-warning path plus the missing `warnings` wire.
