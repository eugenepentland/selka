# Residual scalar-list profile after the room append slice

The exact measured binaries from `3bc671b7` were sampled on CPU 10. Their SHA256
identities match the actual after-build rows in the [append archive](../d9-rc-plain-append-20260927/README.md).
No compiler or guest source was rebuilt or changed for symbolization. Commands,
outputs, binary hashes and perf report commands are in `identity.json`;
`profile.py` is the executed driver. Compressed perf data, reports and LLVM
annotations are retained.

Every sample stream contains throttle/unthrottle records. These profiles are
qualitative attribution, not timing or quantitative component savings. The
median instruction counts in the append archive remain the performance evidence.
No samples were reported lost, but only 157–762 samples were recorded per run.

QBE append samples attribute about 31% to `myl_rc_descriptor_find`, 26% to
`myl_rc_list_plain_ready`, and 42% to the guest. QBE sieve attributes about 18%,
14%, and 68%, respectively. LLVM inlines the query into `entry_run`; its annotated
append loop still hashes and probes immutable type metadata on each room append.
Any future metadata reuse must preserve a real per-operation dead-queue check,
actual native binding identity, cold-registration refusal and slow-path effects.
No query caching is implemented here.

The sieve LLVM write loop also repeatedly reads a flag8 role and its guard,
branches through H propagation, and touches operand/local scratch. The source's
later `for flag in flags` makes `qbe_rc_holds.mayHold` true for every list[bool]
position in the function, including earlier ordinary list captures. The actual
counted workload has one balanced H pair, so these hot checks do not represent
millions of real acquisitions. `emptyLocal` currently refuses the same type-wide
condition. This points to a bounded exact-local/input role proof, rather than
removing iteration holds or changing runtime uniqueness.

A proposed first boundary is an immediate LOAD_LOCAL→STORE_LOCAL capture of a
plain-element list, a named canonical source whose writers cannot install H,
and an already admitted inert/read-anchor interval. Unknown writers, actual
iteration sources, views/dictionaries, projected captures, callbacks, explicit
copies and alternate entries retain existing handling. The compiler must bypass
H handling only for those exact instructions and continue rejecting unexpected
publication into any omitted journal. This is a design target, not an implemented
or accepted optimization.
