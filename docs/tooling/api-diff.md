# Classifying interface changes

`mylang api-diff` answers "what did this change do to the published interface?"
without a second checkout. It records a baseline of every declaration's stable
identity and its interface and body fingerprints, then classifies a later
project against that baseline.

## `mylang api-diff`

```console
$ mylang api-diff src/app/main.my --write=api-baseline.txt
$ mylang api-diff src/app/main.my --against=api-baseline.txt
api-diff: additive=1 compatible=1 breaking=1 unchanged=12
  additive: app::parse_v2 (new declaration)
  compatible: app::parse (body changed)
  breaking: app::parse_legacy (removed declaration)
$ mylang api-diff src/app/main.my --against=api-baseline.txt --json
{"version":"api-diff-v1","additive":["app::parse_v2"],"compatible":["app::parse"],"breaking":["app::parse_legacy"],"unchanged":12}
```

Exactly one of the two options is required:

| Option | Meaning |
| --- | --- |
| `--write=FILE` | Record the current declarations as an `api-diff-baseline-v1` snapshot. |
| `--against=FILE` | Classify the current project against a recorded snapshot. |
| `--json` | Emit one `api-diff-v1` JSON object instead of the text summary. |

The four classes are:

| Class | Meaning |
| --- | --- |
| `additive` | A declaration identity that did not exist in the baseline. Safe to publish. |
| `compatible` | The identity and its interface fingerprint are unchanged; only the body fingerprint moved. Callers are unaffected. |
| `breaking` | The identity disappeared, or its interface fingerprint changed. A caller must be updated. |
| `unchanged` | Identical identity and both fingerprints. Counted, not listed. |

The command is a report and never blocks a build. A malformed or unreadable
baseline is a usage failure (exit 2); a source error in the current project
stays exit 1. Removing a declaration that was `@deprecated` in the baseline is
still classified `breaking` here; api-diff does not yet consult the attribute.
