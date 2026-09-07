# Baseline feasibility findings

These are unscored construction observations, not comparative participant results.

## EDA output amplification

The v1 contract permits 64 boards, each containing 128 positive-area-overlapping
components with 32-character IDs and no pins. With canonical compact JSON, the
constructed input is 701,963 bytes (below 1 MiB). The exact expected response is
55,087,501 bytes, mostly the 8,128 pairwise clearance findings per board.

Reproduction: IDs are `c` followed by the decimal component index padded to 31
digits; each component has x=y=0, width=height=1, pins=[]; each board has version=1,
unit=um, width=height=10, clearance=0, nets=[]. Repeat the board 64 times. Compute
the output from the contract, using the same sorted records and exact SVG format.

The coordinator's default combined stdout/stderr limit is currently 2 MiB.
That is suitable for its tiny infrastructure fixtures but insufficient for the
application's full contract. Before baseline acceptance/freeze, supply the same
adequate application-specific output budget to all three language adapters and
exercise this input end to end. Do not remove findings, truncate JSON, reduce the
contract, or classify this as a participant defect to fit a default runner limit.
All three independent baselines now pass this exact complete fixture inside the
isolated runner with the same 128 MiB output, 4 GiB address-space and 180-second
per-command budgets. Construction receipts are `../evidence/eda-{python,zig,my}-output-feasibility.json`.
Reproduce with `python3 -m experiments.application_comparison.preflight_eda --language LANGUAGE`.
These are concurrent construction runs, not controlled speed comparisons. The
budget is not yet a proven upper bound or a frozen study setting. Account for JSON parsing, output retention,
VM allocation and host call/work budgets as well as stdout bytes.

## Guest bridge

The existing schematic host validates UTF-8/XML characters before guest execution
and accepts three documents. It cannot be reused unchanged for this study: all
three applications must own their input validation, including invalid-byte cases.
The new `.my` bridge now passes bounded raw bytes untouched and performs only
basic I/O, including inside command isolation. Its output and host-operation
budgets now pass the complete EDA amplification fixture against the guest baseline.

The first isolated guest run failed with OutOfMemory: the host used the process
arena for runtime temporaries, so per-call frees could not reclaim storage.
Switching runtime/context/registry allocation to `init.gpa` resolved the failure
without changing guest source, request bytes, VM step/call limits or coordinator
limits. Before/after source and request digests match; the executable adapter
identity changes. `../evidence/eda-my-output-arena-failure.json` preserves the failure.
A smaller regression produces 8 MiB of output under a 256 MiB memory limit; the
initial debug host fails with OutOfMemory, while the corrected installed host
passes. `test_byte_io_host.py` exercises that regression on the installed host.

## Shared nesting rule

Construction exposed an unspecified recursion boundary. The contract now limits
JSON containers to depth 64, counting the root object as one and ignoring string
contents. All deeper inputs are invalid-request. Coordinator tests cover 63/64/65
and escaped delimiters; each baseline independently implements this rule. This
clarification happened before any scored cohort and must be included in its frozen
contract identity. Independent contract review is still required before scoring.
