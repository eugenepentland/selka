# Friction: the opt-in compiler log, and harvest

Repair rounds (the velocity loop's A3 signal) come from real sessions. The
compiler can append one JSON line per command, off by default; `harvest.py`
folds that log into repair rounds per diagnostic code and per idiom.

## Enabling it

```sh
SELKA_FRICTION_LOG=velocity/friction/session-$(date +%F).jsonl selka check app/main.selka
selka check app/main.selka --friction-log=velocity/friction/session-$(date +%F).jsonl
```

- `--friction-log=PATH` (once the `src/main.zig` hook lands) outranks
  `SELKA_FRICTION_LOG`; an absent or empty value means **off**, and no file is
  created. Off is the default on every command.
- One record per command, appended. The file is never read by the compiler, and
  a log that cannot be written never changes a command's exit status.
- The destination is used exactly as typed: a relative path stays relative to
  the working directory. Missing parent directories are created.

**Status:** `src/friction_log.zig` is landed and tested; the CLI hook
(`--friction-log` parsing and the call sites in `src/main.zig`) is a separate,
proposed change — see
[`docs/audits/agent-usefulness-reports/friction.md`](../../docs/audits/agent-usefulness-reports/friction.md).
`SELKA_FRICTION_LOG` therefore has no effect until that hook lands.

## Log format (`friction-log-v1`)

One JSON object per line, exactly these seven fields:

```json
{"version":"friction-log-v1","invocation":{"command":"check","path":"probe4.selka"},"compiler":{"compiler_sha256":"c93d…","zig_version":"0.17.0-dev.1683+5ceec001b","architecture":"x86_64","os":"linux","abi":"gnu","optimize":"ReleaseFast"},"snapshot":"b55c…","diagnostics":[{"code":"E_ARITY","severity":"error","start":79,"end":88}],"status":1,"wall_ns":44100000}
```

| Field | Meaning |
| --- | --- |
| `version` | Schema identifier, `friction-log-v1`. |
| `invocation.command` | Command spelling as typed (`check`, `run`, `run-project`, …). |
| `invocation.path` | Source path **exactly as the user typed it**; never resolved, never rewritten. |
| `compiler` | Build identity from the compiler's own receipt: digest of its build inputs, Zig version, architecture, OS, ABI, optimize mode. |
| `snapshot` | Lowercase SHA-256 of the source snapshot the command checked — the same content digest `source_receipt.Input.sha256` and `project.Module.digest` carry. |
| `diagnostics` | One entry per rendered diagnostic: `code`, `severity` (`error`/`warning`), and the byte `start`/`end` of its span. No message text. |
| `status` | Exit status the command returned. |
| `wall_ns` | The command's **monotonic duration** in nanoseconds, never a calendar date. |

### Privacy rules

A record never contains source text, diagnostic message text, environment
values, or any absolute path the user did not pass. The only path in a record is
the source path exactly as typed; the log destination is not recorded. The
sentinel tests in `src/friction_log_test.zig` log a session over a source file
containing `SENTINEL-DO-NOT-LOG-9137` (and a diagnostic message quoting it) and
assert the sentinel never appears in the log.

## Harvesting repair rounds

```sh
python3 velocity/friction/harvest.py LOG                 # tables per code and per idiom
python3 velocity/friction/harvest.py LOG --json          # one machine-readable document
python3 velocity/friction/harvest.py LOG --window 8      # wider look-ahead (default 5)
python3 velocity/friction/harvest.py LOG --top 10        # ten largest rows per table
python3 velocity/friction/harvest.py LOG --classifier velocity/friction/classifier.json
```

A **repair round** is: a failing record for a file, carrying an **error-severity**
code, followed within the next `--window` records **for that same file** by a
record whose status is a passing check. One round per (failing record, code)
pair, so a repair that clears two codes is two rounds. Warnings never seed a
round (they do not block a check), a passing record never seeds one, and a fix
that is never re-checked is not counted — the log holds no evidence for it.
Records for other files never consume a window.

The default window is 5: the 2026-09-20 session shows repairs taking one or two
commands (`edit → check → fix → check`), so five covers a repair that also runs
or tests in between, while a pass five same-file commands later is more likely a
different repair. Long edit/build loops want `--window 8` or more.

Every code the log observed appears in the per-code table, with `rounds: 0` when
no passing check followed it: a code reported often and repaired without a round
is free rather than friction. `records` is how many records carried that code,
so `0 rounds / 7 records` is readable as "cheap".

### Idioms: the classifier's source-text limitation

`classifier.json` maps (diagnostic code + a source regex) to an idiom name.
A friction-log record deliberately carries **no source text**, so only rows that
need no source — a wildcard regex such as `.` — can name a harvested round
(`E_MODULE_NAME → module-header`, `E_RESULT_UNHANDLED → unhandled-result`, and
their neighbours). Everything else cannot be named honestly:

- `harvest.py` carries `CODE_ONLY_IDIOMS`, a small **code-only extension** for
  codes with one meaning (`E_ARITY → call-arity`, `E_MODULE_HEADER →
  module-header`, `E_TYPE → type-mismatch`, `E_LAMBDA_CAPTURE →
  lambda-capture`, `W_UNUSED_BINDING → unused-binding`, …).
- A code that is neither a source-free classifier row nor in that table is
  reported as `unclassified`, **never guessed**. `E_SYNTAX` is the important
  case: its classifier rows distinguish `is None`, docstring,
  module constant, method, set literal, nested comprehension, generator
  argument, exceptions and `del`, and a record with no source cannot choose
  between them.

**Limitation.** Harvested idioms are therefore coarser than solver-transcript
idioms: a union-comma `E_SYNTAX` round is counted under `unclassified` even
though `classifier.json` knows several `E_SYNTAX` idioms. The two honest
extensions are (a) record the matched idiom name at log time (the compiler holds
the source in memory and the name is not secret — this widens the pinned record
shape) or (b) move `CODE_ONLY_IDIOMS` into `classifier.json`, whose owner has not
been asked for that edit yet. Until one of them lands, read the `named by`
column: `unclassified` rows are the improver's first thing to look at.

## The replay fixture

`session-2026-09-20.jsonl` is a hand-built log of the session the M1 acceptance
names: ten commands over `probe4.selka`, `sexpr/ast.selka` and `sexpr/lexer.selka`,
yielding exactly four rounds — `E_ARITY` (`split()`), `E_SYNTAX` (union comma),
`E_MODULE_HEADER` (import without a header) and `E_TYPE` (`ord` in text
concatenation) — and zero for `E_LAMBDA_CAPTURE` and `W_UNUSED_BINDING`.

```sh
python3 velocity/friction/harvest.py velocity/friction/session-2026-09-20.jsonl
python3 tests/test_friction_harvest.py         # replays it and pins the numbers
```

The compiler identity and per-record wall times in the fixture are synthetic
placeholders of the right shape; each `snapshot` is the real SHA-256 of a probe
snippet, and the snippet texts are recorded in
[`docs/audits/agent-usefulness-reports/friction.md`](../../docs/audits/agent-usefulness-reports/friction.md).
