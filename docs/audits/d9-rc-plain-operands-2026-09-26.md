# RC plain operand cleanup — 2026-09-26

RC generated runtime drop calls for scalar operands whenever a function had an owning frame. Consult the input stack state before emission: an input without counted edges or unique resources has no drop obligation. Owning inputs still retire before their operand position is reused for a plain result.

The new IL test retains a list parameter while running scalar arithmetic and requires exactly one managed input drop. Focused Debug tests: 12/12; uncached `rc_owned_values.my`: 9/9 on each backend; whole-tree Guardian: 88 checks. The combined full gate follows integration.

A one-million-step modular recurrence with a read-only list parameter prints `87970` in all four binaries. Median retired user instructions (three interleaved CPU-2 samples) fall from 370,237,755 to 82,236,775 on QBE (0.2221×) and from 259,233,160 to 24,232,918 on LLVM O3/full LTO (0.09348×). Both compilers are Debug. This is a focused diagnostic, not D9 corpus acceptance. Compiler and binary hashes, all samples, fixture and driver are in `experiments/d9-rc-plain-operands-20260926/`. The before compiler is cf317255; after differs by this change.

The first measurement attempt rejected this machine's hybrid-PMU event spelling (`cpu_core/instructions/u`). The rerun accepts the sole numeric instructions event and ignores the uncounted atom event; it still rejects zero or multiple numeric events.
