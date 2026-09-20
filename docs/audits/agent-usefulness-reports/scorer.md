# Lane C scorer, before-measurement and W0 evidence refresh — 2026-09-20

Status: **delivered**. `velocity/score.py` measures lane C end to end over all 110
probes, the frozen "before" result is recorded in
`velocity/suites/idioms/score-baseline-2026-09-20.json`, and the plan's session-probe
timings are re-measured against the frozen binary. No file under `src/` or `test/` was
touched.

Two things a reader must not misread:

1. **C3 is 0.000 on the frozen baseline**, because `diagnostic-v1` carries no `fix`
   field and no note whose `role` is `alternative` yet (verified over all 80
   rejections). A secondary text reading of the prose that already exists is reported
   beside it as `C3_text_any` = 0.250 and is never merged into `C3`.
2. **There is no "after"/"current" measurement in this report.** `zig-out/bin/mylang`
   currently has the *same sha256* as `zig-out/bin/mylang-baseline-20260920`
   (`2c2ed027…`), because the working tree is red mid-refactor and `zig build` has not
   installed a new binary. A run against it would produce before/before numbers, so
   none is recorded. The scorer writes the measured binary's sha256 into every result
   for exactly this reason.

## Files changed

| File | Change |
| --- | --- |
| `velocity/score.py` | New. The lane C scorer (C1/C2/C3, histogram, per-probe table, `--write-manifest`). |
| `velocity/suites/idioms/score-baseline-2026-09-20.json` | New. The frozen "before" result (`lane-c-score-v1`). |
| `tests/idiom_probes.py` | Added the shared `cpython_oracle()` runner and its self-test; no behaviour change to the recorded-expectation corpus. |
| `velocity/README.md` | New "Lane C scorer" section with usage, limits and the V0 relationship. |
| `docs/audits/agent-usefulness-reports/scorer.md` | This report. |

Not touched, by instruction: `velocity/goal.json`, `velocity/backlog.json`,
`velocity/suites/idioms/manifest.json`, everything under `src/` and `test/`.

## 1. `velocity/score.py`

```
python3 velocity/score.py [--binary PATH] [--json] [--baseline PATH] [--write PATH]
                          [--write-manifest PATH] [--probe GLOB] [--jobs N]
                          [--timeout SECONDS] [--gate] [--self-test]
```

* `--binary` defaults to `zig-out/bin/mylang`; `--jobs` to `min(8, cpus)`; `--timeout`
  to 60 s per command. Exit status 0 = measured, 1 = `--gate` and C2 > 0, 2 = setup
  failure (no binary, no probes, the shared driver missing).
* **Oracle tag comes from the probe.** The first `# oracle: <tag>` line is read from
  each file and validated against `cpython`, `rejected-by-design`, `mylang-only`.
  Nothing about the suite is hardcoded, and an unknown tag is a recorded
  `scorer-error` for that probe rather than a silent skip.
* **CPython oracle** (rule from `manifest.json`): run the probe with `runpy` under a
  non-`__main__` name, call `main()` once, truncate its value to the low byte, compare
  that with mylang's run status and compare stdout byte for byte. It is the shared
  `tests/idiom_probes.cpython_oracle()`.
* **Per-probe sequence**: `check --diagnostics=json` (rejection, code, notes, fix),
  then, only when check passes, `run --diagnostics=json` (status, stdout, trap), then
  the oracle for `cpython` probes.
* **Verdicts** (all recorded, none abort the run): `reject` (compile error),
  `reject-run` (only the run stage reported the error), `trap` (error before any
  output), `trapped-after-output`, `run-timeout`, `check-timeout`, `check-error`,
  `run-error`, `oracle-unavailable`, `agree` (C1), `wrong` (C2), `complete` (accepted,
  no oracle). `reject`, `reject-run` and `trap` are the C3 rejections.
* **C1** = agree / probes tagged `cpython`; **C2** = count of `wrong`; **C3** and its
  secondary text readings are described below.
* Every run re-executes every probe. Nothing is cached; the only reused artefacts are
  mylang's own content-addressed native objects, which do not change verdicts. Runs
  with `--jobs 1` and `--jobs 8` produced byte-identical per-probe verdicts.
* Robustness: each command runs in its own process group under `--timeout` and the
  group is killed on expiry (verified with an infinite-loop probe: recorded as
  `run-timeout`, no stray process). A probe that traps, fails to build, times out or
  has a bad header becomes one row, never an aborted run.
* The scorer hashes the binary before and after the run and warns when it changed
  mid-run. The result JSON carries `binary.path`, `binary.sha256`, `binary.mtime` and
  `binary.compiler_identity` (`compiler_sha256`, `zig_version`, `optimize`,
  `architecture-os-abi` from `schema-project --schema-report`).

### How C3 is detected today, and what changes when the field lands

`names_alternative(diagnostic)` is the metric predicate: it is true when
`diagnostic-v1` carries a non-null `fix`, or a note whose `role` is `alternative`
(an absent `fix` key, an explicit `null` and an empty fix all mean no fix). That is
goal.json's rule verbatim. **Today it matches nothing**: over the 80 rejections there
are 0 `fix` fields and the only note role observed is `related`.

`names_alternative_text(diagnostic)` is the documented fallback, reported separately
as `C3_text_any` and never merged with `C3`. It splits the message and note text on
`;` and `.` and matches a clause when either

* it names an accepted spelling: `use <a|an|the> …`, ``use `x` ``, ``requires `x` ``,
  `instead`, `replace … with`; or
* it contains a repair verb followed by an argument:
  `use|add|write|convert|declare|annotate|prefer|rename|replace`.

A clause containing `no replacement`, `cannot`, `not supported`, `not accepted`,
`must not`, `may not` or `unsupported` never matches, so
`` `&` was removed and has no replacement `` and
`native execution failed (add: left …, width 64)` are correctly excluded.

When D1/D2/S1 land the structured field, **no scorer change is needed**: `C3` starts
counting it immediately because the structured predicate is checked first and is
independent of the fallback. `C3_text_any` will not move much, by construction, because
it measures prose that already exists. The detectors are pinned by
`python3 velocity/score.py --self-test` (14 cases: `fix` absent vs null vs present, note
role `alternative` vs `related`, a note carrying its own fix, each negated clause, and
every text pattern):

```
$ python3 velocity/score.py --self-test
lane C detector self-test: 14 passed
cpython oracle self-test: 5 passed
```

## 2. The recorded before-measurement

```
python3 velocity/score.py --binary zig-out/bin/mylang-baseline-20260920 \
    --write velocity/suites/idioms/score-baseline-2026-09-20.json
```

Observed (110 probes, 8 jobs, 0.6–1.1 s warm, 2026-09-20):

```
lane C scorer - velocity/suites/idioms (*), 110 probes, 0.6s
binary .../zig-out/bin/mylang-baseline-20260920 sha256 2c2ed027cb810836...
compiler compiler_sha256 d5c66296f0d92fa7205e049db2547365acd733a62bf84dfb5cb7ee4c62b445df
         zig 0.17.0-dev.1683+5ceec001b debug x86_64-linux-gnu

C1 first-try fidelity      0.239  (16/67 oracle: cpython probes)
C2 silent wrong answers    0
C3 rejections with a fix   0.000  (0/80 rejected)
     definition: diagnostic-v1 carries a non-null fix or a note whose role is alternative
     C3_text_any (secondary, existing prose, not C3): 0.250 (20/80)
     of which name a replacement spelling:            0.025 (2/80)
     text match kinds: text-repair 18, text-spelling 2
```

Per-code histogram (primary diagnostic per probe, matching the baseline document's
"before" table plus the two runtime traps):

```
 30 OK            5 E_TYPE                1 E_DICT_KEY           1 E_REMOVED_SPELLING
 25 E_SYNTAX      2 E_ASSIGNMENT_TARGET   1 E_EXPLICIT_DISCARD   1 E_SHADOWING
 15 E_OUTPUT_CAP  2 E_CALL_ARGUMENT       1 E_FORMAT_STRING      1 E_TEXT_OPERATOR
  7 E_ARITY       2 E_COLLECTION_METHOD   1 E_LAMBDA_CAPTURE     1 E_UNBOUND
  5 E_EXPRESSION  2 E_TOKEN               1 E_LIST_METHOD        1 E_UNKNOWN_FUNCTION
                                          1 E_MODULE_HEADER      1 E_UNKNOWN_TYPE
                                          1 E_MODULE_NAME        1 R_ASSERT / 1 R_OVERFLOW
```

The full per-probe table (probe, oracle, verdict, code, C1/C2/C3/C3t markers) is
printed by the command and stored under `probes` in the result JSON. The 80 rejections
break down as 78 compile errors and 2 traps before output: `a57_assert_fstring.my`
(`R_ASSERT`, a probe that deliberately asserts a false condition to exercise the
f-string message) and `a60_overflow.my` (`R_OVERFLOW`, which CPython evaluates without
overflow). `a60` is therefore not C1 (it does not run to completion) and not C2 (it
fails loudly), but it is a rejection the C3 denominator counts.

C1 agreements (16): `a08 a09 a12 a20 a25 a29 a31 a43 a52 a59 a72 a74 c04 e01 e05 e06`.
The 14 accepted no-oracle probes are listed in the JSON with verdict `complete`.

The 20 `C3_text_any` matches: 2 `text-spelling` (`a14_lambda_capture`,
`d10_unused_result`), 18 `text-repair` (`a16`, 15 × `E_OUTPUT_CAPABILITY` — a32, a35,
a47, a69, a80, c06, d01, d02, d04, d05, d06, d08, e09, e11, e12 — plus a75 and d03).

## 3. Discrepancies against `goal.json` and `manifest.json`

`goal.json` records baselines measured 2026-09-17 on `commit 237871a6`. The frozen
binary is newer (`sha256 2c2ed027…`, `compiler_sha256 d5c66296…`, built 2026-09-20
15:37), so differences are expected. The manifest's `binary` field
(`commit 237871a6`, `measured_on 2026-09-17`) is the right "before" for those numbers,
not this one.

**C1: 0.239 (16/67) here vs 0.343 (23/67) recorded.** Diffing my per-probe verdicts
against `manifest.json`'s `baseline.agree`:

* 8 probes that agreed on 17 September are now rejected with `E_OUTPUT_CAPABILITY`:
  `a32_join_map`, `a35_div`, `a69_print_end`, `a80_none_return_call`,
  `d04_dict_items_keys`, `d08_int_float_mix`, `e09_walk_dict_sorted`,
  `e11_if_no_else_bind` (all eight are bare-`print` programs; the capability rule
  postdates the manifest).
* 1 probe gained: `a12_docstring` (docstrings are now accepted and agree).

23 − 8 + 1 = 16. This is a policy change, not a scorer bug, and the drop must not be
read as a regression when the manifest is regenerated.

**C2: 0 here vs 1 recorded, and that is not good news.** The recorded silent wrong
answer was `d05_round_half.my` (`round(2.5)` is 3 in mylang, 2 in Python). On the
frozen binary `d05` is rejected with `E_OUTPUT_CAPABILITY` before it runs, so C2 cannot
see it. I confirmed the underlying divergence is still present with a probe that
reaches it without printing: `def main() -> int: return int(round(2.5)) * 10` exits 30
under mylang and 20 under CPython 3.14, stdout empty in both. **Until the suite has a
`round` probe that runs to completion, `C2 = 0` is a blind spot, not a fix.** Any
package touching `round` must run that probe, and the C2 gate must not be reported as
verified on the strength of the current suite.

**C3: 0.000 structured here vs 0.02 recorded.** The recorded number predates both the
frozen binary and any instrument (the baseline document's correction 4 already says no
C3 instrument existed). The structured field does not exist yet, so the honest
structured value is 0.000. The secondary text reading is 0.250; it is dominated by the
15 `E_OUTPUT_CAPABILITY` messages, whose prose says "add `out: Stream` to this function
and pass one from main". Neither number should be compared directly with 0.02: the
plan's figure was an estimate of rejections that name a replacement spelling, and the
closest measurable analogue is `C3_text_spelling` = 0.025 (2/80: `a14` "use a top-level
function or pass the value as an explicit state parameter", `d10` "requires `_ =` or
result handling"). Once D1 lands, `C3` (structured) is the number to put in the ledger
against the 0.02 → 0.95 target.

**Probable cause of the 0.02: it was never a command's output.** Nothing in the
repository derives it, and no integer subset of the 80 rejections rounds to 0.02
except 2/110 probes, which is the `C3_text_spelling` set measured over the whole suite
rather than over rejections. Treat 0.02 as a placeholder baseline and say so when the
manifest is regenerated.

**Suite size: 110, not 111.** `velocity/suites/idioms/` holds 110 `.my` files, every
one with an oracle header (67 cpython, 34 mylang-only, 9 rejected-by-design), the
manifest holds 110, and the baseline document's own rejection table has 110 rows.
That document's heading and correction 4 say 111; the plan section 5 says 110. The
heading is a miscount.

**Accepted/agree counts vs the manifest (informational).** Manifest: 36 accepted
(`mylang_accepts` true) and 23 agreeing. Frozen binary: 32 accepted by `check`, of
which 2 trap, and 16 agree. 11 probes that were accepted on 17 September are now
rejected (the 8 above plus `c06_result_record_err`, `d05_round_half`,
`e12_none_default_param`); 7 probes that were rejected are now accepted (`a06_eq_none`,
`a12_docstring`, `a45_record_default`, `a46_record_eq`, `a57_assert_fstring`,
`a60_overflow`, `c07_if_let_style`).

## 4. `tests/idiom_probes.py` — reconciled, not duplicated

The file runs `tests/fixtures/idioms` (57 probes) against recorded baseline/target
expectations; `velocity/suites/idioms` (110 probes) is a different corpus with oracle
tags, so the two drivers cannot be merged today. I added the shared piece V0 asks for:

* `cpython_oracle(path, timeout)` — the runpy/`main()`/`& 0xFF` runner used by both
  instruments, returning `status`, `stdout`, `stderr`, `ok`, `error`.
* `CPYTHON_DRIVER`, `ORACLE_ERROR_PREFIX`, `TRACEBACK_HEADER` constants.
* `oracle_self_test()` (5 cases: value→status, `None`→0, truncation, missing `main`,
  raising probe), run by `--self-test` after the existing classifier self-test.

`velocity/score.py` imports that module by path (no copy) and also reuses its
`failed_run()` classifier. Verified unchanged behaviour:

```
$ python3 tests/idiom_probes.py --self-test
idiom classifier self-test: 8 passed
cpython oracle self-test: 5 passed
$ python3 tests/idiom_probes.py --compiler zig-out/bin/mylang-baseline-20260920 | tail -3
idiom probes: 57 selected, 50 at target, 7 not yet
```

## 5. W0 evidence refresh

Machine: 20 cores (`12th Gen Intel(R) Core i7-12700H`), 30 GiB RAM (`16 GiB`
available), Linux 7.0.0-31-generic, Python 3.14.4, pinned Zig
`0.17.0-dev.1683+5ceec001b`. The box is shared with three other agents; load average
was 2.8–6.7 during these runs, so the numbers below are conservative.

Identity of the measured compiler:

```
$ sha256sum zig-out/bin/mylang-baseline-20260920
2c2ed027cb810836101474ba91f929f0a710f6b34b9f19842eccd4bc659acd21
$ zig-out/bin/mylang-baseline-20260920 schema-project examples/corpus/packet/main.my --schema-report
{"compiler_sha256":"d5c66296f0d92fa7205e049db2547365acd733a62bf84dfb5cb7ee4c62b445df",
 "zig_version":"0.17.0-dev.1683+5ceec001b","architecture":"x86_64","os":"linux",
 "abi":"gnu","optimize":"debug"}
```

`schema-project --schema-report` is the command that prints `compilerIdentity`: the
`source.implementation` block above (it needs a file with a `module` header and an
entry point, hence the corpus entry rather than a suite probe). The plan quotes
`7d3d52d7…` from its review probe; that is a different build, not this binary.

| Action (plan §2) | Plan | Measured here, frozen binary |
| --- | --- | --- |
| `check` on a 25-line single file | 80 ms | **25 ms** median of 5 (18–70 ms) |
| `run` on it (native build + execution) | 414 ms | **40 ms** warm median (40–240 ms); 250 ms with a fresh `--cache-dir` |
| `mylang test experiments/sexpr-port/tests`, 114 tests / 7 programs | 4.0 s | **4.59 s** cold (`--cache-dir`, 0 cached, 114 passed); 2.48–2.77 s warm reruns (11 cached) |
| Sieve to 5,000,000, built binary | 0.15 s | **0.145 s** median of 5 (0.142–0.147 s); `mylang build` itself 0.24 s |
| Same sieve under CPython 3.14 | 0.50 s | **0.286 s** median of 5 (0.281–0.291 s) |

Method: `time.perf_counter` around `subprocess.run`, 5 runs per command unless stated,
median reported. The plan's session programs are not in the repository, so the 25-line
file and the sieve are reconstructions (below); the test-directory measurement uses the
real `experiments/sexpr-port/tests`. `check` is 3× faster than the plan's figure; `run`
is much faster warm but comparable cold; the test directory and the sieves are in the
same range. The sieve is about 2× faster under mylang than CPython here (the plan
recorded 3.3×), but the loop was never the bottleneck in either measurement.

The 25-line file (`wc -l` = 25; `check` and `run` clean):

```python
# doc: not-mylang
def classify(n: int) -> str:
    if n % 15 == 0:
        return "fizzbuzz"
    if n % 3 == 0:
        return "fizz"
    if n % 5 == 0:
        return "buzz"
    return "n"

def even_total(values: list[int]) -> int:
    running = 0
    for value in values:
        if value % 2 == 0:
            running += value
    return running

def main(out: Stream) -> int effects(managed_allocation, output):
    values: list[int] = []
    for i in range(1, 21):
        values.append(i)
    words: list[str] = []
    for value in values:
        words.append(classify(value))
    out.print(even_total(values), len(words), words[14])
    return 0
```

The sieve (`limit = 5000000`, `list[bool]` flags, `out.print(count)`; prints 348513,
CPython prints 348513):

```python
# doc: not-mylang
def main(out: Stream) -> int effects(managed_allocation, output):
    limit = 5000000
    flags: list[bool] = []
    i = 0
    while i <= limit:
        flags.append(True)
        i += 1
    p = 2
    while p * p <= limit:
        if flags[p]:
            multiple = p * p
            while multiple <= limit:
                flags[multiple] = False
                multiple += p
        p += 1
    count = 0
    k = 2
    while k <= limit:
        if flags[k]:
            count += 1
        k += 1
    out.print(count)
    return 0
```

The CPython comparison used `flags = [True] * (limit + 1)` with the same sieve loop
and `print(sum(1 for k in range(2, limit + 1) if flags[k]))`.

## 6. `--write-manifest` for the lead

Implemented and verified with a full 110-probe write to a temporary path
(`/tmp/manifest-full.json`), never against the suite manifest. Schema matches the
existing file exactly — `version`, `measured_on`,
`binary`, `oracle_rule`, `probes[]` with `name`, `oracle`,
`baseline{mylang_accepts, agree, silent_wrong}`; `version` and `oracle_rule` are copied
from the current `velocity/suites/idioms/manifest.json`, `measured_on` becomes the run
date, and `binary` becomes `sha256:<binary> <path> compiler:<compiler_sha256>`.
`agree` is `null` for `mylang-only` probes and a boolean otherwise (always `false` for
`rejected-by-design`, matching the existing file).

Exact command once D1/D2/S1 have landed and `zig build` is green:

```sh
python3 velocity/score.py --binary zig-out/bin/mylang \
    --write-manifest velocity/suites/idioms/manifest.json
```

Add `--write velocity/suites/idioms/score-D1D2S1.json` (or another name) if you also
want the result JSON, or `--baseline velocity/suites/idioms/score-baseline-2026-09-20.json`
to print the before/after deltas in the same run. With `--probe`, the written manifest
describes only the selected probes and the scorer says so on stderr.

## 7. What I could not do

* **No after/current number.** `zig-out/bin/mylang` and the frozen baseline are
  byte-identical right now (same sha256), so a run against the current binary measures
  before/before. Verified and left unrecorded; rerun once the build is green.
* **C3 structured cannot be non-zero until D1 ships the field.** The 0.250 text reading
  is not evidence about D1 and is not comparable to goal.json's 0.02.
* **C2's recorded value is not reproducible and its gate is currently blind to
  `d05_round_half`** (rejected before it runs). The `round(2.5)` divergence itself is
  still present (exit 30 vs 20 above).
* **The plan's session programs are gone**, so the 25-line file and the sieve are
  documented reconstructions; only the test-directory timing is against the original
  artefact.
* **`score.py` is lane C only.** Lanes B and D and the gate list from V0 are not
  implemented, so it does not write `velocity/current.json` and does not reproduce
  `goal.json` wholesale; `gen_project.py`/`solve.py` (V1/V2) remain absent.
* **No `src/`/`test/` change and no suite-manifest regeneration**, per the brief.
