# S1(a), D1 and S1(b) — implementation report

Author: the S1(a)/D1/S1(b) package agent (child of `session-05323371-a28d-40d4-8fe2-f92b9e26c6fd`).
Date: 2026-09-20. Worked directly in `/home/epentland/ai/canopy/mylang` on the shared
dirty tree; nothing was committed, staged, stashed or restored.

## Status

| Package | Status | What landed |
| --- | --- | --- |
| S1(a) — `str.split()` with no argument | **done** | `str.split()` and `bytes.split()` follow Python; probe `a64_split_noargs.my` is accepted and agrees with CPython; `split(separator)` unchanged; docs, feature slugs and doctest examples added |
| D1 — call-site rejections print the signature and the alternative | **done** | one shared signature renderer; `E_ARITY` (collection, dictionary, file, prelude), unknown-method, argument-position `E_TYPE`, `E_CALL_ARGUMENT` (sorted) and `E_OUTPUT_CAPABILITY` all name the callee and carry a structured `alternative` note where one exists; signature coverage over the suite re-measured at 20/26 (was 5/26), the six exceptions being three no-callee rejections and three sites outside this package's files |
| S1(b) — prelude `ord`/`chr` with literal folding | **done** | `ord` folds a one-scalar literal at check time; both runtime forms trap `R_TEXT_SCALAR`; `strings` module unchanged; `a55_chr_ord_hex.my` now rejects on `hex` (out of scope), measured separately |

The tree compiles (`zig build`, Guardian `88 check(s) passed`), `zig build test-units`
is 1252 passed / 0 failed, the new guest suite is 4/4, the port suite is 114/114 and
`docs/text.md` doctests 6/6.

## Files changed

Owned files:

- `src/buffer_operations.zig` — new `Kind` members `split_whitespace`, `text_ord`,
  `text_chr` with their arity/mutation/allocation entries; `methodFor`; `spelling`;
  `SignatureNames`; `signatureText`/`signatureBody` (the one shared renderer).
- `src/sema.zig` — `methodFor` at both method-resolution sites; `unknownMethodMessage`
  names the receiver; `signatureNames`, `MethodRejection`, `ArgumentRejection`,
  `methodArityFailure`, `requireArgument`, `attachAlternative`; file-access and
  file-method arity failures; `sorted(reverse=)` alternative; the `E_OUTPUT_CAPABILITY`
  alternative note; the `split`/`bytes` whitespace-split arm in `checkTextDictionary`;
  `methodAlternative`, `alternativeFor`, `fileAccessSignature`, `fileMethodSignature`.
- `src/diagnostic.zig` — `Role` enum, optional `role` on `Related`, text rendering of
  `alternative` notes (including the duplicate-sentence skip).
- `src/diagnostic_output.zig` — `diagnostic-v1` `Note.role` now carries
  `diagnostic.Role`, so an `alternative` note is published as data.
- `src/prelude_builtins.zig` — `ord`/`chr` in `reserved`, `ordCall`, `chrCall`,
  `ordArgument`, `constantScalar`, `preludeSignature` for the one-argument builtins.
- `src/native_text_methods.c` — `myl_native_text_split_whitespace`,
  `myl_native_text_ord`, `myl_native_text_chr`, `myl_native_fail_text_scalar`.
- `src/qbe_text.zig` — `split_whitespace` through `emitFresh`; `emitScalar` for `ord`
  and `chr`; the `text_scalar` trap name.
- `src/features.json` — slugs `whitespace-split`, `prelude-scalar-builtins`.
- `docs/text.md` — `split(separator)` added to the method list, new sections
  "Splitting on whitespace" and "Unicode scalar values", each with a runnable example.
- `SPEC.md` — appended bullets: `SPLIT-WHITESPACE-1..3`, `PRELUDE-SCALAR-1..3`,
  `DIAGNOSTIC-SITES-1..5`, `DIAGNOSTIC-ROLE-1`, `PY-SPLIT-1..3`, `PY-SCALAR-1`.
- `src/root_test.zig` — one appended `test { _ = @import("prelude_scalar_test.zig"); }`.
- `src/prelude_scalar_test.zig` (new) — 10 tests carrying the `src/` spec tags.
- `tests/lang/python_split_scalar.my` (new) — 4 guest tests carrying the `PY-*` tags.

Files outside that list that this change had to touch, each minimal and reported here:

- `src/collection_lower.zig` — three output-type arms (`.split_whitespace`, `.text_ord`,
  `.text_chr`). The plan named `buffer_operations.zig` as the arity entry point, but the
  `Kind` enum is also switched here; without these arms a rejected receiver reports
  "operation is not supported by this collection".
- `src/bytecode.zig` — two validation arms for the same three kinds, for the same reason
  (`else => error.InternalError` otherwise).
- `src/qbe_bytes.zig` — the `bytes` whitespace-split emitter. The plan's "`qbe_text.zig`
  is the path `splitlines()` uses" is true for `str`; `bytes` methods emit from
  `qbe_bytes.zig`, which is a different file from the one the plan names.
- `src/native_bytes.c` — `myl_native_bytes_split_whitespace` and its local prototype.
- `src/python_core_test.zig` — one expected-message string in the `DIAG-ORACLE-1`
  unknown-list-method test, which pinned the pre-D1 wording. Changed with the lead's
  explicit authorisation; nothing else in the file was touched.
- `experiments/sexpr-port/sexpr/tokenizer.my` and `experiments/sexpr-port/sexpr/parser.my`
  — the `ord("x")` rewrite used for the QBE-neutrality measurement (lead-authorised).
  Thirteen comparisons were rewritten, not all 63; see the S1(b) evidence below.

Two files stayed untouched on purpose and are reported as remaining limits:
`src/parser.zig` (`range`/`enumerate` arity wording, another agent's package) and
`src/call_arguments.zig` (`sort(key=…)` wording).

## Commands and observed output

### Build and gate

- `zig build` — success; last line `guardian: run-all: 88 check(s) passed — diff-scoped
  vs b8f6ec3f1178f12971e7dcb1d2255ab8c055b024, 30 file(s) in scope`.
- `zig build test-units` (whole root, unsharded) — `PASS — 1252 passed`,
  `RESULT {"passed":1252,"failed":0,"skipped":0}`. The step's own exit was non-zero only
  because the unsharded process peaked at 2.16 GB against a 2.15 GB declared bound;
  `zig build test` shards this root.
- `zig build test-cli` — `PASS — 153 passed`,
  `RESULT {"passed":153,"failed":0,"skipped":0}` (same unsharded memory-bound caveat).
- `zig build fmt-check` — exit 0.
- `zig-out/bin/mylang doctest .` — `0 mis-tagged, 0 failed` (327 files, 154 run,
  41 checked).
- After the D1 signature follow-up (the `print`/`sorted` signature notes) the focused
  runs are `units signature` 40 passed, `units print` 57 passed, `units scalar` 52
  passed and `units split` 16 passed, with `zig build` at `88 check(s) passed` and
  `zig build fmt-check` exit 0. The whole-root run quoted above predates that follow-up;
  it was not repeated because package H1 took over `src/sema.zig` and
  `src/diagnostic.zig` at that point, so a full-gate verdict would have measured their
  in-flight edits rather than this package.
- `python3 scripts/focused_test.py units split` — `selected: 16`, `PASS - 16 passed`.
- `python3 scripts/focused_test.py units scalar` — `selected: 52`, `PASS - 52 passed`.
- `python3 scripts/focused_test.py units requireArgument` / `methodArity` /
  `unknown method` — `PASS` each.
- `zig-out/bin/mylang test tests/lang/python_split_scalar.my` — `4 passed, 0 cached,
  0 failed, 0 skipped`.
- `zig-out/bin/mylang test experiments/sexpr-port --jobs 4` — `114 passed, 0 failed…
  across 8 programs` (before and after the classifier rewrite).
- `zig-out/bin/mylang doctest .` — `docs/text.md: 6 run, 0 failed`. The run also reports
  pre-existing failures in other agents' audit reports (`baseline-2026-09-20.md`,
  `lint.md`, `scorer.md`); see "Cross-package findings".

### S1(a) — probe against CPython

`./zig-out/bin/mylang check velocity/suites/idioms/a64_split_noargs.my` exits 0 (no
output); `./zig-out/bin/mylang run velocity/suites/idioms/a64_split_noargs.my` exits 42.
The CPython oracle (`runpy.run_path` then `main()`) returns 42 and exit status 42.

A wider oracle probe (`/tmp/scalar_oracle.my`) checked 10 facts and returned 10 both
under mylang and under CPython: `ord("A")==65`, `ord("m")==109`, `ord("é")==233`,
`ord("😀")==128512`, `chr(65)=="A"`, `chr(233)=="é"`, `chr(128512)=="😀"`,
`ord("z")==122`, `chr(ord("z"))=="z"`, `len("a  b\tc".split())==3`.

Whitespace-split cases verified against CPython (all agree): `"a  b\tc"` → 3 pieces,
`""` and `"   "` → 0, `" a "` → 1, `"a\nb\rc\x0bd\x0cf"` → 5, `"héllo wörld"` → 2,
`"a,b,c".split(",")` → 3, `"a,,b".split(",")` → 3, `b" a\tb "` → 2 with `b"a"` first,
`b""` → 0, `b"x,,y".split(b",")` → 3.

### Idiom-suite before/after (110 probes)

First diagnostic code per probe, `check` under
`./zig-out/bin/mylang-baseline-20260920` (before) and `./zig-out/bin/mylang` (after):

| Probe | Before | After |
| --- | --- | --- |
| `a64_split_noargs.my` | `E_ARITY` | **accepted** |

Every other probe keeps its code. Histogram before → after: `OK` 32 → 33,
`E_ARITY` 7 → 6, all other codes unchanged (25 `E_SYNTAX`, 15 `E_OUTPUT_CAPABILITY`,
5 `E_TYPE`, 5 `E_EXPRESSION`, …).

Full-diagnostic text differs on 15 probes: nine of mine (`a18`, `a28`, `a33`, `a42`,
`a55`, `a62`, `a63`, `a64`, `a79`) and six from D2's parser hints (`a24`, `a36`, `a37`,
`a38`, `a39`, `a71`). `diagnostic-v1` JSON differs on 30 probes: the same nine plus the
fifteen `E_OUTPUT_CAPABILITY` probes (structured note only) plus D2's six. Every code
this package does not own — `E_TYPE`, the un-hinted `E_SYNTAX` probes, `E_TOKEN`,
`E_EXPRESSION`, `E_UNBOUND` and the rest — is byte-identical in text and JSON.

### D1 signature coverage, re-measured to the acceptance wording

The acceptance is "every call-site rejection in `velocity/suites/idioms/` carries the
callee signature", so this measures the diagnostic itself rather than lane C. The exact
command, run against all 110 probes, reading the JSON Lines from **stderr**:

```console
$ python3 - <<'EOF'
import subprocess, glob, json, re
CALL_SITE = {"E_ARITY","E_COLLECTION_METHOD","E_LIST_METHOD","E_CALL_ARGUMENT",
             "E_FILE_ARGUMENT","E_OUTPUT_CAPABILITY"}
SIGNATURE = re.compile(r"[A-Za-z_][A-Za-z0-9_.]*\(([^()]*)\)(\s*->\s*[A-Za-z_][A-Za-z0-9_\[\], ]*)?")
def carried(d):
    texts = [d.get("message","")] + [n.get("message","") for n in d.get("notes") or []]
    for m in (SIGNATURE.finditer(t) for t in texts):
        for hit in m:
            if hit.group(2) or ":" in hit.group(1): return True
    return False
for path in sorted(glob.glob("velocity/suites/idioms/*.my")):
    p = subprocess.run(["./zig-out/bin/mylang","check",path,"--diagnostics=json"],
                       capture_output=True, text=True)
    records = [json.loads(l) for l in (p.stdout+p.stderr).splitlines() if l.strip().startswith("{")]
    if not records: continue
    d = records[0]["diagnostic"]
    if d["code"] in CALL_SITE:
        print(("SIGNED  " if carried(d) else "MISSING "), path.split("/")[-1], d["code"])
EOF
```

Result:

| Binary | Call-site rejections carrying a signature |
| --- | --- |
| `zig-out/bin/mylang-baseline-20260920` | 0 / 27 |
| `zig-out/bin/mylang` (after this follow-up) | **20 / 26** |

The denominator drops by one because `a64_split_noargs.my` is no longer a rejection.
The lead measured 5/26 before this follow-up and 20/26 after it. The six without a
signature are exactly:

- `a18_str_format.my` (`E_COLLECTION_METHOD`), `a79_str_methods.my` (`E_LIST_METHOD`) —
  unknown methods. There is no accepted callee to render, so the receiver type plus the
  accepted method spellings (`unknown method for a str receiver; accepted methods: …`)
  is the correct answer; `str.format` additionally carries the f-string alternative.
  This exception is deliberate and is on the record here.
- `d07_str_index_assign.my` (`E_COLLECTION_METHOD`) — `s[0] = "z"` is an operation the
  language forbids outright (`operation is not supported by this collection`). Nothing
  is callable here, so again there is no signature to render. This is a third
  no-callee case, alongside the two unknown-method probes.
- `a30_range_step.my` and `a44_enumerate_start.my` (`E_ARITY` in `src/parser.zig`), and
  `a26_sort_key.my` (`E_CALL_ARGUMENT` in `src/call_arguments.zig`) — outside this
  package's files; costs assessed below.

What the follow-up changed: `E_OUTPUT_CAPABILITY` now renders the accepted callee
(`stream.print(values..., sep: str, end: str) -> None`) and `E_CALL_ARGUMENT` for
`sorted(..., reverse=True)` renders `sorted(values: list[T], key: callback) -> list[T]`,
both as a new `signature` note through `diagnostic.Sink.failCallSite`; the prelude
`range`, `sorted` and `min`/`max` arity rejections in `prelude_builtins.zig` use the same
note. The primary messages and the `alternative` notes are unchanged. Text gains one
`  signature: …` line on those diagnostics; JSON gains a note with `"role":"signature"`.

### Cost of the three remaining sites (not started, on the lead's instruction)

- `src/parser.zig` `rangeBounds` (a30) — one line: the site already holds `self.sink`,
  `node.span` and `call.name`, so
  `self.sink.failCallSite("E_ARITY", node.span, "range requires end or start, end", null, buffer_operations.range_signature)`
  replaces the existing `fail`. It needs one wording decision: `range` is only an
  iteration source, so the rendering is `range(end: int) -> iterable[int], or
  range(start: int, end: int) -> iterable[int]` (no first-class range type exists).
- `src/parser.zig` `forStatement` (a44) — one line in the same shape, rendering
  `enumerate(values: list[T]) -> (index: int, value: T)`; the "two iteration names" half
  of the message is about the loop binding, not the callee.
- `src/call_arguments.zig` `positional` (a26) — **not** a two-line change. This helper
  runs before the receiver is checked and knows only `call.name`: it serves every
  intrinsic and callback value, and spellings such as `pop`, `copy`, `clear` and `items`
  are shared across receiver families, so a rendering chosen there could contradict the
  one `sema.zig` renders. A correct fix either moves the keyword check to where the
  receiver type is known, or accepts two renderings for one spelling. Recommended:
  schedule after H1 releases `src/sema.zig`, and keep the shared renderer as the only
  source of the text.

Exact new messages for the probes the plan named:

```text
a33: error[E_ARITY]: `round(value: float) -> float` takes 1 argument, but this call passes 2
a42: error[E_ARITY]: `open(fs: Filesystem, path: str, mode: str) -> Result[File, str]` takes 3 arguments, but this call passes 1
     alternative: a free file helper takes the Filesystem capability first: `open(fs, path, mode)` or `read_text(fs, path)`; `fs.open(path, mode)` is the method spelling
a62: error[E_ARITY]: `dict[str, int].get(key: str, default: int) -> int` takes 2 arguments, but this call passes 1
a18: error[E_COLLECTION_METHOD]: unknown method for a str receiver; accepted methods: count, encode, endswith, find, …
     alternative: use an f-string: f"{value}" interpolates where str.format does
a28: error[E_CALL_ARGUMENT]: sorted accepts only the named argument key=callback
     alternative: sorted orders ascending only; write `reversed(sorted(values))` for a descending order
a55: error[E_UNKNOWN_FUNCTION]: no function has this qualified name   (now at line 5, `hex(255)`)
```

A two-argument `split` carries both halves D1 asks for:

```text
parts = "a b".split(",", 2)
        error[E_ARITY]: `str.split(separator: str) -> list[str]` takes 1 argument, but this call passes 2
  alternative: `split()` with no argument splits on runs of ASCII whitespace and drops empty parts; `split(separator)` splits on one exact separator
```

Lane C's structured C3, measured the same way the lead's scorer does (first diagnostic
per probe, `notes[].role == "alternative"` in `diagnostic-v1`): **24/79 = 0.304**,
against 0.114 before the `E_OUTPUT_CAPABILITY` note and 0.000 in the frozen baseline.
Nine of the 24 are the D1 collection/file/sorted/f-string notes, fifteen are the bare
`print` note. The plan's "above 0.5" target is **not** met by D1 alone; the remaining
ground is the 25 `E_SYNTAX` and 6 `E_ARITY` rejections the plan did not scope.

### S1(b) — `ord`/`chr` and the fold

- `ord("A")`, `ord("m")`, `ord("é")`, `ord("😀")`, `chr(65)`, `chr(233)`,
  `chr(128512)`, `ord(chr(1114111))` all agree with CPython (probe above).
- Traps: `ord("ab")`, `ord("")`, `ord(text)` for a two-scalar `text`, `chr(0 - 1)`,
  `chr(55296)` and `chr(1114112)` all exit 1 with
  `error[R_TEXT_SCALAR]: native execution failed` at the call's own location.
- `a55_chr_ord_hex.my` still rejects, now at `h = hex(255)` on line 5
  (`E_UNKNOWN_FUNCTION`), because `hex` was out of scope. `chr`/`ord` behaviour is
  measured by the dedicated probe and the guest and Zig tests instead.

QBE-neutrality, fixture: compiling

```text
def letter(code: int) -> bool:
    return code == ord("m")
```

and the same program with `return code == 109` yields **byte-identical `emit-qbe`
JSON** — same symbol, same IL, same dependency hash — except for the file path in the
two `locations` arrays. This is pinned as a test
(`prelude_scalar_test.test.ord of a one-scalar literal lowers to the same QBE as the
raw code`, tag `PRELUDE-SCALAR-3`), which also asserts the folded QBE contains no
`call $myl_native_text_ord`.

QBE-neutrality, port: the measured count in `experiments/sexpr-port` is 63 equality
comparisons against printable byte codes (29 against ASCII letters), not the plan's 33.
Thirteen of them were rewritten — `tokenizer.my`'s `is_scale_letter`,
`is_unit_required_scale` and `is_unit_letter`, and `parser.my`'s `si_scale` letter
branch. `mylang emit-project-qbe experiments/sexpr-port/main.my` before and after:
**101 functions, 101 byte-identical IL bodies**, no changed dependency hash, only three
functions with different `locations` (the column shift from `107` to `ord("k")`). The
port's suite is 114/114 after the rewrite.

## Design decisions

### W0 decision 1 — note role stays inside `diagnostic-v1`

`diagnostic.Related` gained an optional `role: Role = .related` with the new value
`alternative`; the JSON `Note.role` is now that named type. `diagnostic-v1` is
unchanged as a version. The reasons a v2 was not needed:

- The change is additive and backward compatible: every existing note keeps its slot
  role (`related`, `origin`, `requirement`) because the default is `.related` and the
  renderer falls back to the slot name. A 30-probe before/after JSON sweep over the
  idiom suite shows no change for any untouched code.
- A v2 would have forced every existing consumer to accept two versions for one new
  optional field, and the field is a *classification of an existing note*, not a new
  record shape.

The text renderer prints an `alternative` note as `  alternative: <message>` instead of
the located `note:` line, and skips an alternative whose message repeats the primary
diagnostic message word for word. That second rule exists so the `E_OUTPUT_CAPABILITY`
note can be added for structured consumers without changing that diagnostic's terminal
output at all (verified: none of the 15 bare-`print` probes changed text).

### Call-site signature notes

Call-site signature coverage is carried by a note with the new role `signature`
(`diagnostic.Sink.failCallSite`), not by the primary message, because two of the
affected diagnostics already compose their whole sentence — the primary message and the
`alternative` note must stay byte-identical for `E_OUTPUT_CAPABILITY` and for the
`sorted(reverse=)` rejection. Text renders `  signature: <rendering>` with no source
location (the rendering is about the call, not about another source site) and JSON
publishes `"role":"signature"` with the call's span. Collection arity rejections keep
the signature inside the message they already had, so their text is unchanged.

### W0 decision 2 — `ord`/`chr` trap

`ord` and `chr` follow the plan's default: the runtime form traps. One code,
`R_TEXT_SCALAR`, covers both — `ord` on text that is not exactly one scalar and `chr`
on a code point outside `0..0x10FFFF` or in the surrogate range. `strings.ord` and
`strings.chr` keep their `Result` forms unchanged for callers that would rather handle
the failure, and `docs/text.md` says so. The trap reporter
(`myl_native_fail_text_scalar`) lives in `native_text_methods.c` and calls the existing
`myl_qbe_fail`, so no new trap registry or `qbe_runtime.c` entry was needed.

`ord("x")` folds at check time by reading the already-checked text literal (a one-element
`array` of scalar nodes) in `prelude_builtins.constantScalar`; that keeps the fold in the
prelude rather than duplicating literal decoding in the checker. `chr(<literal>)` is not
folded — it takes the runtime path, which costs one empty-text allocation per call. That
is a limit, not a correctness gap.

### S1(a) shape

`split()` and `split(separator)` are two operations, so the whitespace form is a new
`Kind.split_whitespace` (arity 0) and `methodFor(name, argument_count)` is the one place
that maps the shared spelling to one of them. `Kind.arity()` stays one count per
operation, so every existing consumer of the arity table keeps working. The whitespace
class is the same six ASCII scalars `str.isspace()` classifies with, and
`bytes.split()` uses the same six octets, so a `str` and a `bytes` receiver agree on what
separates; both new runtime helpers are allocated from the receiver's own storage and
root the growing list exactly as `splitlines()` does.

## Remaining limits

1. **`range` and `enumerate` arity messages carry no signature.** `a30_range_step.my`
   and `a44_enumerate_start.my` are rejected in `src/parser.zig` (one line each with
   `diagnostic.Sink.failCallSite`; see the cost assessment above). They were left
   untouched on the lead's instruction after H1 took over `src/sema.zig`.
2. **`sort(key=…)` (`a26`) carries no signature or alternative.** The rejection is
   produced in `src/call_arguments.zig`, before the receiver type is known; the accepted
   spelling is `sorted(xs, key=callback)`. `sorted(..., reverse=True)` (`a28`) does
   carry both, attached from `src/sema.zig`.
3. **Three rejections have no accepted callee at all** (`a18_str_format`,
   `a79_str_methods`, `d07_str_index_assign`): two unknown methods and one forbidden
   operation. They carry the receiver type and its accepted spellings, or the
   immutability rule, instead of a signature — this is the criterion's intended
   exception, recorded in the coverage section above.
4. **`hex` remains unknown** (out of scope), so `a55_chr_ord_hex.my` still rejects; the
   `chr`/`ord` half of that probe is covered by
   `tests/lang/python_split_scalar.my::test_ord_and_chr_answer_one_unicode_scalar`.
5. **A generic receiver still rejects `split()`.** `src/generic_bodies.zig` resolves the
   spelling with `buffer_operations.method` and checks the arity table, so `T.split()`
   in a generic body reports `E_ARITY` even though a concrete `str`/`bytes` receiver is
   accepted. The file is outside this package's ownership.
6. **`chr` of a literal is not folded** (see above); `ord("x")` is.
7. **The doctest gate was red on other packages' reports while this work ran.**
   `mylang doctest .` then failed `docs/audits/agent-usefulness-reports/baseline-2026-09-20.md:244`
   (a `mylang`-tagged illustrative snippet with a typed hole) and reported mis-tagged
   fences in that file, `lint.md` and `scorer.md`; those were fixed by their authors
   while this report was being written, and the final run is `0 mis-tagged, 0 failed`.
   This report uses only `text`/`console`/`json` fences and avoids lines beginning
   `def main` or `module `, so it contributed none either way.
8. **`mylang emit-qbe` rejects a file with a `module` header** ("unexpected token;
   expected def" at `module main`). The frozen baseline binary reproduces this, so it is
   pre-existing, not a regression; the port measurement used `emit-project-qbe`.
9. **The unsharded `test-units` root peaks just above its declared `max_rss`**
   (2.16 GB vs 2.15 GB) and so exits non-zero after reporting 1252 passed. Sharded
   `zig build test` splits the same root across processes.

## Cross-package findings

- **Two duplicate file-scope consts blocked the gate** when the reference package
  landed: `function_kind = "function"` (`reference.zig:385` vs `incremental.zig:21`) and
  `qualified_name_format = "{s}::{s}"` (`reference.zig:383` vs `interfaces.zig:13`).
  Reported to the lead; the reference agent has since resolved them (the tree is green).
- **Parser-hint D2 and this package both write `alternative` notes** through the same
  `diagnostic.Role` mechanism and the same text rendering, so the two packages' notes
  are one shape rather than two. The parser's six `E_SYNTAX` changes are the only other
  probes whose diagnostics moved.
- **`velocity/suites/idioms/manifest.json` still records `binary: commit 237871a6` and
  `measured_on: 2026-09-17`**; the lead is regenerating it, so this report measures probe
  verdicts directly from the two binaries instead of trusting the manifest.

## What a reviewer should check first

1. `zig build` then `./zig-out/bin/mylang run velocity/suites/idioms/a64_split_noargs.my`
   → exit 42.
2. `./zig-out/bin/mylang check velocity/suites/idioms/a62_option_or.my` → the `dict.get`
   signature, and `a28_sorted_reverse.my` → the `reversed(sorted(...))` alternative.
3. `./zig-out/bin/mylang test tests/lang/python_split_scalar.my` → 4 passed.
4. `python3 scripts/focused_test.py units scalar` → 52 passed.
