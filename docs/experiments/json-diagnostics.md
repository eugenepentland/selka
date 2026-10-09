# Versioned CLI diagnostics

Use `--diagnostics=json` with a compiler command to receive `diagnostic-v1` JSON
Lines on stderr. Each line is one complete JSON record. Command results remain
on stdout with their existing format, and exit statuses retain their existing
meaning. The default and explicit `--diagnostics=text` use terminal text.

```sh
selka check-project main.selka --diagnostics=json
selka run main.selka --diagnostics=json
selka check-session main.selka --diagnostics=json
```

The option is accepted once, before or after the path. Unknown formats and
repeated options are usage errors. Usage output and emergency failures before
format selection or during diagnostic output may still use text; consumers must
also check process status and handle incomplete output.

Consumers should check `version` and `kind`, and tolerate additional fields.
Incompatible protocol changes require a new version.

## Source and VM records

A source error, warning or VM trap has this shape:

```json
{
  "version": "diagnostic-v1",
  "kind": "diagnostic",
  "diagnostic": {
    "code": "E_RETURN_LIFETIME",
    "severity": "error",
    "message": "returned reference does not borrow from the declared input parameter",
    "location": {
      "path": "helper.selka",
      "start": {"line": 6, "column": 8},
      "end": {"line": 6, "column": 12},
      "bytes": {"start": 117, "end": 121}
    },
    "notes": [],
    "stack": {"frames": [], "omitted": 0}
  }
}
```

The byte offsets in the example illustrate the shape; actual offsets are derived
from the source. `code` retains the compiler's stable diagnostic code; `severity`
is `error` or `warning`. Messages are explanations, not stable identifiers.

Every location uses the original file's coordinates, including imported generic
bodies. Module paths retain loader-relative names beneath the entry directory;
single-file paths retain the spelling passed to the compiler. `bytes` is a zero-based half-open byte range. Lines and columns are
one-based; columns count UTF-8 bytes, not characters or terminal display cells.
Tabs count as one byte. EOF is a valid zero-length range. If a synthetic span
crosses source segments or has no valid original range, `bytes` and `end` are
null; the located start remains available. No invented range crosses files.

Notes are ordered objects with `role`, `message` and `location`. Roles are
`related` for immediate evidence, `origin` for the original binding, and
`requirement` for a signature's required input. Absent notes are omitted from the
array. Module discovery/interface failures use a related note in the other
module's coordinate space. Each stack frame has `function` and `location`;
frames retain VM order from the innermost frame outward, up to 16 entries, with
`omitted` recording older frames that did not fit. These notes and frames explain
current evidence; they are not automatically applicable edits.

All textual fields normally encode as JSON strings with normal JSON escaping.
For invalid UTF-8 bytes in a path or diagnostic message, the serializer emits an
array of unsigned byte values instead. This preserves those bytes without invalid
JSON or replacement characters; consumers must accept either representation for
text borrowed from external input. Version, kind, role and severity values use
the fixed ASCII strings described here.

## Auxiliary output and sessions

Non-source CLI messages use a separate record:

```json
{"version":"diagnostic-v1","kind":"message","message":"cannot load missing.selka: FileNotFound\n"}
```

This includes normal host I/O failures, manifest/value/policy errors, formatting
notices and requested timing reports. Their text is preserved, but this record
does not promise a language error code or source span. Codec rejection payloads
are carried as an auxiliary message; source traps inside codec execution retain
the diagnostic record above. Machine-readable command results, such as typed
values and evaluation requests, keep their existing stdout protocols.

A check session selects the format once at startup. Its `check-session-v1` status
replies stay on stdout. Cold and cached successful checks emit identical warning
records on stderr; source edits and clear operations keep their existing reuse
rules. The bounded successful-verdict cache records the diagnostic format, so a
format change cannot replay stale terminal text as JSON or vice versa. Error
verdicts are not cached. Cache byte limits and allocation-failure preservation
still apply to the retained warning representation.

The format is additive tooling around the same checks and VM. It does not run
programs during `--evaluation-request`, change error handling, or implement native
guest execution.

## Acceptance

`src/diagnostic_output_test.zig` verifies JSON parsing, Unicode/escaped text,
byte columns, EOF and mapped spans, cross-module notes, all provenance roles,
stack omission, invalid UTF-8 byte preservation and allocation failures.
`src/check_cache_test.zig` covers JSON replay, cross-format misses and allocation
failures. `tests/diagnostic_output.py` is part of default interpreter acceptance
and checks the protocol independently through the CLI: source/syntax errors,
warnings, returned-lifetime notes and executed repair, import/interface failures,
VM traps and truncated traces, auxiliary errors, text compatibility, unchanged
request-only evaluation and persistent cold/warm/clear warning replay.

This implements the CLI protocol milestone. Real agent repair success and the
board/constraint application trial remain unmeasured.
