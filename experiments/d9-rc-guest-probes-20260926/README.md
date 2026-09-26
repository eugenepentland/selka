# Initial RC call and trap probes

`results.json` preserves six source programs, all twelve build/run commands,
compiler and binary hashes, exit codes, exact stderr and parsed physical traffic.
The `sources/` files are the exact inputs. Both backends pass each output or
intentional-trap check, emit exactly one report, retire every counted heap
allocation, and report identical counter dictionaries. QBE guests use Debug;
LLVM guests use `--release` (ReleaseFast, opt 3, full LTO). The compiler is Debug.

These are initial correctness probes, not the 43-program performance/RSS gate.
They cover indirect calls, mixed fresh/borrowed returns over 1,000 replacements,
non-tail recursion, short-circuit call temporaries, and direct/nested assertions.
The nested trap crosses 33 recursive frames and retires all 68 heap allocations.
The ordinary return-through-recursion case actually traverses non-tail calls:
its post-call length assertion prevents tail-recursion conversion.

Permanent semantic regressions are in `tests/lang/rc_call_lifetimes.my`.
`calls-qbe.log` and `calls-llvm.log` record all three passing without cached
verdicts under counted RC. Runtime report parsing and cleanup across success,
trap and process fast exit also have a standalone C driver in the joined tree.

To replay a standalone source with a fresh Debug compiler, use `mylang build
SOURCE -o BINARY --rc-runtime=stats`; add `--release` for the LLVM arm. Run the
binary directly and require exit 1 for the two trap sources, otherwise exit 0.
Parse exactly one stderr line starting `MYLANG_RC_COUNTS ` and require
`heap_allocate == retire`. All artifact files and compiler revisions must be
recorded again for a new run. Current mutation and arena lowering work remains
outside this checkpoint.
