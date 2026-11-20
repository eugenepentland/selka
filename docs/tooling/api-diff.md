# Classifying interface changes

`selka api-diff` answers "what did this change do to the published interface?" without a second checkout: it records a
baseline of every declaration's identity and fingerprints, then classifies a later project against it.

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

Exactly one of `--write` and `--against` is required:

| Option | Meaning |
| --- | --- |
| `--write=FILE` | Record the current declarations as an `api-diff-baseline-v2` snapshot. |
| `--against=FILE` | Classify the current project against a recorded snapshot. |
| `--json` | Emit one `api-diff-v1` JSON object instead of the text summary. |

| Class | Meaning |
| --- | --- |
| `additive` | A declaration identity that did not exist in the baseline. Safe to publish. |
| `compatible` | Only the body changed, or declared `from` sources narrowed to a nonempty subset while every other interface dimension stayed unchanged. |
| `breaking` | An identity disappeared, every `from` source was removed, a source was added, or another interface dimension changed. |
| `unchanged` | Identical identity and both fingerprints. Counted, not listed. |

Return sources are declared in the signature, for example `func part(s: str) -> str from s`. Reordering the names changes
no contract, and a body change only changes the implementation. Removing the final source turns a borrowed result into a
fresh one and is breaking: a caller that returns the result under its own `from` can then
get `E_BORROW_MIXED`. Narrowing several sources to a nonempty subset is compatible. Adding `from s` to a fresh-result
declaration is breaking. Renaming a parameter or changing its type is a separate interface change.

Snapshots read declarations without checking bodies, so an unfinished body does not prevent comparison. Removing a declaration that was `@deprecated` in the baseline is still `breaking`.

## Old baselines

Comparing against a v1 baseline exits 2 with one message and the command to re-record it, and prints no comparison, even
with `--json`; the baseline is left unchanged. `--diagnostics=json` renders the message as one `diagnostic-v1` record.
Keep a copy of the old baseline, then re-record from the intended reference revision, which replaces the file with a v2
baseline:

```console
$ selka api-diff src/app/main.selka --write=api-baseline.txt
```

The command is a report and never blocks a build. A malformed, unreadable or obsolete baseline is a usage failure (exit
2); a source error in the current project stays exit 1. To keep the published interface in version control as readable
text, see [interface files](interface-files.md): `selka api` writes one `.api` file per module and can make a stale one
a checking error.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/api-diff.md).
