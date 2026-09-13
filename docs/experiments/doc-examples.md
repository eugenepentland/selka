# Executable documentation examples

`tests/docs_examples.py` runs every documentation example through the compiler, so a
documented program cannot drift away from the language it describes. The default
`zig build test` gate depends on it through the `test-docs` step.

```sh
zig build test-docs
python3 tests/docs_examples.py --compiler zig-out/bin/mylang
```

`--compiler PATH` defaults to `zig-out/bin/mylang`. `--filter GLOB` restricts the scan
to matching repository-relative document paths, `--verbose` prints every command,
diagnostic and skip reason, and `--report PATH` writes a `doc-examples-v1` JSON report.

## What is scanned

`README.md`, `SPEC.md` and every `*.md` under `docs/`, recursively, except
`docs/legacy/`. That directory holds pages whose subject was removed from the
language, so its examples are deliberately not executed. A fenced block whose info
string is `mylang` or `my` is an executable example and a complete program by
default. Backtick and tilde fences both work.

A block that declares no `main` is type-checked rather than executed: the runner
appends a neutral entry point, because `check` and `check-project` both require one.
Declarations are checked even when unused, so a declaration-only example is really
checked. A block that declares `module NAME` is written to `NAME.my` and
goes through `check-project` or `run-project`; everything else is written to `main.my`
and goes through `check` or `run`. Sources are written under a per-run temporary root
and never into the repository.

The runner is spelling-agnostic. It writes whatever the fence contains, so legacy
brace syntax, the familiar brace spelling and canonical Python-style source all run.

## Directives

The leading lines of a block may carry directives written as `# doc:` comments, or as
`// doc:` in brace-syntax blocks. Directive lines are stripped before the program is
written out. An unknown directive name fails the run.

| Directive | Meaning |
| --- | --- |
| `# doc: expect <text>` | Run the program; stdout, trimmed, must equal `<text>`. Repeated lines join with newlines. |
| `# doc: expect-error <CODE>` | `check` must fail and its `--diagnostics=json` output must carry that code. |
| `# doc: check` | Type-check only. Also the default when the block declares no `main`. |
| `# doc: project <name>` | Group this block with the other blocks of the same document and name into one project. |
| `# doc: file <name>.my` | Name this block's file inside its project; `main.my` is the entry. |
| `# doc: skip <reason>` | Do not execute. The reason is mandatory and appears in the report. |
| `# doc: not-mylang` | Prose block that only looks like guest source; exempt from the mis-tag lint. |
| `# doc: allow-read <dir>` | Run with `--allow-read=docs/fixtures/<dir>`, granting that fixture directory. |
| `# doc: allow-write <dir>` | Run with `--allow-write=docs/fixtures/<dir>`, adding write authority. |

A block with no directive and a `main` is run and must exit 0.

A run unit is given `--print-result` unless its own source calls `print`, so an
example that prints its output asserts that output and an older example still
asserts the entry point's `int` result.

Capability grants name a directory under `docs/fixtures/`. A fixture directory
holds the files the example reads; an example that writes should write only
names it also removes, because the tree is shared by every run.

Grouped blocks become one project checked or run through `run-project`:

```mylang
# doc: project greeting
# doc: file helper.my
# doc: expect 42
module helper
export answer

def answer() -> int:
    return 42
```

```mylang
# doc: project greeting
# doc: file main.my
module main
import helper

def main() -> int:
    return helper.answer()
```

## The mis-tag lint

A block tagged `text`, `rust`, `python`, `go`, or left untagged, whose content has
`def main`, `fn main` or `module ` at the start of a line, is reported as a mis-tagged
example and fails the run. Otherwise a stale example could hide behind a fence that
never executes. Genuinely non-mylang blocks opt out with `# doc: not-mylang` as the
first line, or with an info string like `text notest` when the block should not carry
a visible directive line.

## Exit status and report

The runner prints per-file counts of blocks run, checked, skipped, mis-tagged and
failed, then a one-line summary. It exits 0 only when nothing failed, nothing is
mis-tagged, and at least one executable block was found; finding no executable block
at all is a failure rather than a pass.

## Current inventory

`README.md` and `SPEC.md` contribute no executable blocks: the README fences are all
shell invocations, and `SPEC.md` has no fenced blocks at all. Across the scanned
documents the gate currently runs 30 examples, type-checks 11 and skips 12. Those
figures are a snapshot; the runner's own summary is the authority.

| Document | Skipped block | Reason |
| --- | --- | --- |
| `docs/audits/language-simplicity-2026-09-12.md` | boilerplate probe | removed feature |
| `docs/byte-io-bulk.md` | bulk declarations | fragment: declarations appended to an existing host `io.my` module |
| `docs/byte-io-bulk.md` | copy loop | needs host capability: the `mylang-io` byte host and its `io.my` module |
| `docs/experiments/effects.md` | contracts | fragment: `Numbers` and the removed slice tier are not declared here |
| `docs/experiments/module-discovery.md` | module header | fragment: header excerpt whose imported modules are not shown |
| `docs/experiments/module-interfaces.md` | export placement | fragment: the imported `shared.units` module is not shown |
| `docs/experiments/plain-json-ergonomics.md` | literal arguments | fragment: statements without their enclosing function or document |
| `docs/experiments/plain-json-ergonomics.md` | document queries | fragment: statements without their enclosing function or document |
| `docs/experiments/source-codecs.md` | codec match | fragment: statements without the `Positive` domain and `Wire` declarations |
| `docs/legacy/experiments/source-json.md` | roundtrip | removed feature |
| `docs/legacy/experiments/source-json.md` | generic codec | fragment: continues the `Encoded` declarations of the block above |
| `docs/familiar-syntax.md` | record and list intro | known-wrong example: `E_SYNTAX` rejects the trailing comma after this struct declaration's last field, though calls and record construction accept one; the rest of the example returns 42 |

Every fragment above is a candidate for a later documentation rewrite: completing one
into a whole program removes its `skip` directive and adds it to the executed set. The
two `removed feature` rows are different in kind: they are blocks in dated records
whose syntax the language no longer has, kept for the history rather than rewritten.
The `docs/familiar-syntax.md` entry is different again, because the example and the
prose around it disagree with the compiler; resolving that needs a language or prose
decision rather than an edit to the block.

`README.md` and `SPEC.md` are the other standing item. Neither carries an executable
example today, so neither is covered by this gate; examples added to them are picked up
automatically.
