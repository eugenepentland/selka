# Classifying interface changes

`selka api-diff` answers "what did this change do to the published interface?"
without a second checkout. It records a baseline of every declaration's stable
identity and its interface and body fingerprints, then classifies a later
project against that baseline.

## `selka api-diff`

```console
$ selka api-diff src/app/main.selka --write=api-baseline.txt
$ selka api-diff src/app/main.selka --against=api-baseline.txt
api-diff: additive=1 compatible=1 breaking=1 unchanged=12
  additive: app::parse_v2 (new declaration)
  compatible: app::parse (body changed)
  breaking: app::parse_legacy (removed declaration)
$ selka api-diff src/app/main.selka --against=api-baseline.txt --json
{"version":"api-diff-v1","additive":["app::parse_v2"],"compatible":["app::parse"],"breaking":["app::parse_legacy"],"unchanged":12}
```

Exactly one of the two options is required:

| Option | Meaning |
| --- | --- |
| `--write=FILE` | Record the current declarations as an `api-diff-baseline-v2` snapshot. |
| `--against=FILE` | Classify the current project against a recorded snapshot. |
| `--json` | Emit one `api-diff-v1` JSON object instead of the text summary. |

The four classes are:

| Class | Meaning |
| --- | --- |
| `additive` | A declaration identity that did not exist in the baseline. Safe to publish. |
| `compatible` | Only the body changed, or declared `from` sources narrowed to a nonempty subset while every other interface dimension stayed unchanged. |
| `breaking` | An identity disappeared, every `from` source was removed, a source was added, or another interface dimension changed. |
| `unchanged` | Identical identity and both fingerprints. Counted, not listed. |

Return sources are declared in the signature, for example
`func part(s: str) -> str from s`. Reordering the names changes no contract.
Changing its body from a slice to a copy changes only the implementation while
the signature still declares `from s`. Removing the final source changes the
declaration from a borrowed result to a fresh result and is breaking: a caller
that returns the result under its own `from` can then receive `E_BORROW_MIXED`.
For a declaration with several sources, narrowing to a nonempty subset remains
compatible. Adding `from s` to a fresh-result declaration is breaking. Renaming
a parameter or changing its type is a separate interface change, even if the
source set also narrows.

Snapshots read declarations without checking function bodies, so an unfinished
or invalid body does not prevent comparison. A v2 baseline has seven tab-separated
columns: identity, display name, kind, interface fingerprint, body fingerprint,
non-`from` interface fingerprint, and sorted source positions (`fresh` for none).
Positions are not limited to 64 parameters.
Component provider matching still requires the exact selected declaration;
API-diff's directional compatibility does not relax provider validation.

An explicit v1 baseline predates declared borrow sources. Comparing against one
exits 2 with one message and the command to re-record it, rather than reporting
one breaking change per declaration. No comparison is written to standard output,
including with `--json`, and the baseline is left unchanged. `--diagnostics=json`
renders that same message as one `diagnostic-v1` message record.

Preserve the old baseline in version control or save a copy, then re-record it
from the intended reference revision before comparing later changes:

```console
$ selka api-diff src/app/main.selka --write=api-baseline.txt
```

This explicit command replaces the file with a v2 baseline. Shared release and
context readers still accept their existing legacy baseline inputs.

The command is a report and never blocks a build. To keep the published
interface in version control as readable text instead, see
[interface files](interface-files.md): `selka api` writes one `.api` file per
module and can make a stale one a checking error.

The command is a report and never blocks a build. A malformed, unreadable or
obsolete baseline is a usage failure (exit 2); a source error in the current project
stays exit 1. Removing a declaration that was `@deprecated` in the baseline is
still classified `breaking` here; api-diff does not yet consult the attribute.
