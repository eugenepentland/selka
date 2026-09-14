# Idiom probes

Small programs a Python programmer would write, used to measure the simplification work in
`docs/audits/language-simplicity-2026-09-14.md`. They are the acceptance spine for that work:
each probe states what it does **today** and what the plan **requires**, so every workstream
has a concrete list of probes to flip and one command to prove it.

Run them with:

```sh
python3 tests/idiom_probes.py --compiler zig-out/bin/mylang            # measure
python3 tests/idiom_probes.py --compiler zig-out/bin/mylang --verbose  # one line per probe
zig build test-idioms                                                  # the same, from the gate
```

`zig build test` runs this driver, but it fails only on a **regression** — a probe marked
`must_pass` that stops meeting its target. Once the plan's workstreams have landed, enable
`--require-targets` (or pass it in `build.zig`) so every probe must meet its target.

## The two outcomes

`manifest.json` records, per probe, the `baseline` observed before the work and the `target`
the plan requires. A run classifies each probe as:

| State | Meaning |
| --- | --- |
| `target` | the probe now does what the plan requires — progress |
| `baseline` | unchanged from the recorded starting point |
| `changed` | neither — either real progress with a stale record, or a break; review it |

An expectation matches on exit `status`, on printed `stdout` (from `--print-result`), on a
diagnostic `code` (for example `E_LIST_METHOD`), and optionally on `stderr_contains`.

## Groups

| Group | Audit section | Plan workstream |
| --- | --- | --- |
| `collections` | §2.1 | W3 (methods, slices, augmented assignment) |
| `builtins` | §2.2 | W4 (prelude builtins) |
| `dictionary` | §2.1 | W3 |
| `expressions` | §2.3 | W5a/W5d (`lambda`, `Option`, `None`) |
| `program-edge` | §5.1–§5.3, §5.7 | W1, W5b, W5c |
| `entry-command` | §2.4 | W9 (one `run` command) |
| `removals` | §3, §4 | W2 (delete a spelling, keep a migration error) |

`removals` probes invert the usual direction: their target is a located
`E_REMOVED_SPELLING` error whose message names the canonical replacement, so a deletion is
only finished when the old spelling fails *and* says what to write instead.

## Adding a probe

1. Add the program to this directory as `<name>.my`.
2. Add its entry to `manifest.json` with `baseline`, `target` and `group`.
3. Run the driver. If the probe reports `changed`, either your recorded `baseline` is wrong or
   the behaviour genuinely moved — fix the record only after checking which.

The driver refuses to run when a fixture has no manifest entry or a manifest entry has no
fixture, so the two cannot drift apart.
