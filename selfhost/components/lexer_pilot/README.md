# Current-profile lexer pilot

This ordinary Selka library ports the preserved historical lexer closure into
`component-v1`, against host baseline `0d9ababf7eb434d2e02e1b2b45fe5c6593715e7a`.
It adds current keywords/internal aliases, removed-word rejection, `|`, `^`,
and triple-quoted text. Historical sources, both seed pins, production routing
and the shared build graph remain unchanged.

## Library and transport contract

`lexer.lex(source.make(raw)) -> token.Token[] fails diagnostic.Diagnostic` owns
ordinary values. Token kinds are current Zig tag strings. Tokens retain source
order and half-open **byte** start/end spans. EOF and dedent are zero width;
a suite-opening colon becomes an indent with the original colon span. There
are no newline tokens. Source records must come from `source.make`; callers
of `source.locate` must supply `0 <= offset <= len(raw)`. LF determines line
starts; diagnostic line and byte column are one based. Raw bytes are retained
without Unicode decoding, normalization or input repair.

Only the adapter `main.my` accesses files/streams. Invoke `BINARY --request FILE`
with one immutable raw-source file, at most 262,144 bytes. It reads one sentinel
byte beyond that bound. Success prints ASCII `kind start end` rows including
EOF. Source errors print exactly `error code line column start end`, exit 0.
Malformed arguments, missing files, oversize requests or invalid library output
produce stderr and exit 2, without a success response. Tokens/errors are fully
validated before printing. The adapter bounds tokens at 524,545 and kind/code
length at 32; spans are at most six decimal digits, so token output is under
25 MiB. The receiver separately bounds each stream to 32 MiB during execution
and applies a 30 second deadline. This is a provisional process/value protocol,
not an installed component manifest or frozen production ABI.

Dependencies are exactly the declared component profile: records, imports,
`int`, `bool`, `str`, `bytes`, nested record lists, explicit mutable bindings,
list append/index updates, loops, ranges, byte indexing/slicing, comparisons,
integer arithmetic, checked `fails`/`try`/`fail`, and file/stream capabilities.
No enum, dictionary, Unicode-string convenience, foreign call, raw pointer,
shared-library ABI, or new compiler feature is required. String token kinds
replace the historical enum; source tables use bytes and integer lists.

## Reproduce qualification

From the repository root, with disk-backed private TMPDIR and local Zig cache:

```sh
export TMPDIR=/path/to/private/disk/tmp
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache"
export ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache
scripts/build-slot.sh build zig build
scripts/build-slot.sh build python3 selfhost/tests/run_lexer_pilot.py --edit-check
MYL_CORE_LEAKCHECK=1 scripts/build-slot.sh build python3 selfhost/tests/run_lexer_pilot.py --release --edit-check
SEED_COMPILER=$(scripts/build-slot.sh build zig-out/tools/selka-components --root . --zig "$(command -v zig)" --seed-only)
scripts/build-slot.sh build "$SEED_COMPILER" test selfhost/components/lexer_pilot/tests.my --force --no-cache
MYL_CORE_LEAKCHECK=1 scripts/build-slot.sh build "$SEED_COMPILER" test selfhost/components/lexer_pilot/tests.my --release --verify-facts --force --no-cache
scripts/build-slot.sh build zig build fmt-check
```

The coordinator verifies the pinned source/toolchain/executable receipt before
the driver uses its seed. The driver builds the **unmodified** current-profile
closure with `--no-cache`; it does not call `fix` or migrate source. The existing
builder does not know about this third component, so the standalone driver
builds it directly with the verified seed. `--edit-check` also copies the
closure privately, builds it, adds a classifier branch and rebuilds at the same
path. It requires a changed component executable digest and an unchanged host
digest, then compares the full corpus again. Release edits inherit release and
fact-verification flags. Fixture bytes are never adapted; committed SHA-256
values pin them. `.lex` denotes raw lexical evidence, including intentionally
invalid UTF-8 and malformed syntax, outside the generic live `.my` formatter.

## Parity evidence and limits

The baseline historical live harness compares tokens and spans for successful
lexing, but obtains error records through `check` and deliberately skips three
later-phase cases. Its `--compiler` mode adapts an old closure in a temporary
directory; that alone is not seed qualification. On this baseline it reported
31 fixtures, 450 token/error rows, zero mismatches and three skips.

The new corpus has 79 fixtures: all 31 historical inputs plus every current
keyword/operator, removed lexical word, format/triple strings, escaped quotes,
numeric extents, comments/layout/continuations, CRLF/lone CR, UTF-8 and invalid
encoding bytes, BOM/NUL, EOF without newline, malformed literals and indentation,
256/257 indentation depths, and 65,536/65,537-byte decoded-size spellings.
`dump-tokens --diagnostics=json` is the lexical oracle, including errors;
parser/checker failures cannot contaminate this comparison. Invalid escapes,
numeric spellings, formatted-string expressions and decoded literal size are
validated later by the host: the lexer correctly accepts their token extents.
There are **no skipped fixtures**. Error codes, byte spans and line/column are
compared explicitly; diagnostic message prose, migration fixes and capture
withholding are not part of this pilot protocol. Removed-word messages use
`removed spelling`, while host diagnostics describe the migration. Ordinary
unterminated literal/layout messages are retained. The library does not adopt
parser/checker behavior or production routing.

Standalone qualification reports 79 fixtures, 1,714 token/error rows, zero
failures/skips, plus six transport checks; both debug and release/fact/leak modes
pass. Ten pure library tests pass in each mode, with zero cached/failed/skipped.
Component-only edits rebuild and preserve the host digest in both modes.
The first fmt check encountered raw malformed `.my` fixtures; renaming those
files `.lex` retained their exact bytes and avoids adding shared exclusions.
The combined full gate is coordinated by the parent integration worktree;
standalone checks are not represented as that gate. Timing is deferred because
isolated timing admission has not been obtained; no performance claim is made.

For gate integration, add a dedicated standalone pilot driver step depending
on the current installed host and coordinator; declare this driver, the
`lexer_pilot/` module closure and `fixtures/lexer_pilot/` tree in
`build_test_inputs.zig`. Add seed pure debug and release/fact/leak checks and a
release differential invocation with leak checks. The coordinator must remain
the receipt authority; do not substitute the current compiler for the seed.
No production adapter/routing should be added until a separate adoption review.

## Verified host comparison preparation

The coordinator now independently builds and installs `lexer-pilot.json` and its
content-named executable alongside the existing components. Ordinary installation
requires no Python. `MYLANG_LEXER_MODE=reference` (the default) uses the native
lexer; `MYLANG_LEXER_MODE=shadow mylang dump-tokens FILE --diagnostics=json`
executes the independently qualified component, compares the result, and renders
the reference tokens or original diagnostic records. Messages, migration fixes,
and captured-name withholding remain exactly native. Explicit `component` mode
uses validated producer tokens directly on success. Lexical failures use native
diagnostic enrichment after matching the producer error code and span. Unknown
modes are refused; reference remains the default. Frontend cache and publication
boundaries authenticate producer identities before reuse and after computation.
`MYLANG_COMPONENT_DIR` selects the installed manifests. Host launch verifies the
manifest/schema and artifact SHA-256, seals those verified bytes in a Linux
memfd, captures at most 3,148,884 reply bytes and 65,536 stderr bytes, and races
the entire child lifecycle against a 30 second deadline. After execution it
revalidates the deployment before accepting a reply. Success stderr must be empty.
No compiler rebuild, hidden source compilation or fallback occurs during launch.

The packaged executable retains `--request FILE` for the original standalone
corpus and adds `--exchange FILE` for a framed binary operation. The 64-byte
`SLKLEX01` header has little-endian u32 protocol=1 at 8, schema=1 at 12,
kind=0 request / 1 reply at 16, exact payload length at 20, correlation bytes at
24..32, and SHA-256 of immutable source bytes at 32..64. The component echoes
all 40 identity bytes; the host requires exact correlation and snapshot identity.
The request payload is raw source (at most 262,144 bytes). Successful reply
payloads contain u32 status=0, token count, then u32 stable kind ID, start, end
per token. IDs follow the explicit `wire.my`/`lexer_component_protocol.zig`
kind tables, never the host enum's incidental ordinal. Source-error payloads
contain status=1, count=0, error ID, physical byte line, physical byte column,
start, end. Error IDs are `E_TOKEN`, `E_INDENTATION`, `E_BYTE_LITERAL`,
`E_NESTING_LIMIT`, `E_REMOVED_SPELLING` in that order. Physical locations allow
mapped-source callers to retain their native original-source diagnostic mapping.
Unknown IDs, truncated/trailing frames, stale identity, overlapping/out-of-range
spans, zero-width real tokens, misplaced EOF or wrong byte locations are rejected.
Protocol/schema/table changes require separate qualification.

`language.lexer_component.lex(allocator, source, sink, Runtime)` is reusable by
later callers. It returns the native token allocation or native `SourceError`,
with component boundary errors distinguished. `identity` binds operation/schema,
mode and the verified component digest; future persistent caches must include
this producer identity and bind the host compiler digest for reference mode.
It is not yet wired into syntax cache validity or compilation. Absolute
`lexRange` without layout is still required by parser format holes, embed-hole
scanning, incremental declaration/function normalization and interface stub
construction. Project discovery, module-name normalization, partial navigation,
formatting and retained/persistent syntax also need explicit adoption review.
These are concrete remaining requirements; shadowing dump-tokens does not prove
that those consumers or full compilation use the component.

Native tests cover successful sealed execution, exact shadow comparison,
retained migration fixes, identity separation, malformed/truncated/stale frames,
unknown token IDs/spans, artifact/manifest corruption, unsuccessful children,
stdout/stderr overflow and deadline expiry after child output streams close.
The standalone seed corpus continues to operate on unchanged raw fixture bytes.

For isolated measurements after correctness and the gate, stop competing gates
and builds, obtain coordinator timing admission, and run on reserved timing CPUs:

```sh
taskset -c 2,3,10,11 python3 selfhost/components/lexer_pilot/measure_transport.py --compiler zig-out/bin/mylang --component-dir zig-out/libexec/mylang/components --isolated --iterations 20
```

This reports medians for complete CLI reference/shadow exchanges and their
incremental latency for a small source, 64 KiB comments and 64 KiB token-rich
source. It checks output stability while measuring. It does not compile or
claim parser/end-to-end adoption. For the edit loop, separately time a warm
`zig-out/tools/selka-components --root . --zig PATH` under the same isolation,
then a real private lexer algorithm edit/rebuild with the host digest unchanged;
`run_lexer_pilot.py --edit-check --host-shadow` provides correctness evidence,
but its combined wall time is not a component-build-only measurement.

Stage 2 qualification commands (through `scripts/build-slot.sh build`) are
`zig build`, `zig build test-units -Dtest-filter='lexer component'`,
`python3 selfhost/tests/run_lexer_pilot.py --edit-check --host-shadow`, the same
pilot command with `--release` and `MYL_CORE_LEAKCHECK=1`, coordinator
`--root . --zig PATH --uncached`, and the seed pure-test commands above.
Results: five named native boundary tests plus seven unnamed initialization
blocks passed (12 total); 79 immutable fixtures/1,714 token/error rows passed
in each guest mode, with six transport and two host configuration checks;
12 pure tests passed in both debug and release/fact/leak modes. The coordinator
reproduced all three component executables from fresh private caches. Full
combined gate and isolated measurements remain coordinated by the parent.
