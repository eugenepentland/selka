# Plain scalar field replacement

The proof and isolated results are in
`docs/audits/d9-rc-scalar-replace-2026-09-27.md`.

`measure.py` runs the exact five-million-step nbody source on CPU 2, using
immutable before/after Debug compilers and actual QBE / LLVM O3 full LTO native
binaries. It records all three samples, complete output, counters and manifests.
`emission.py` archives the generated `advance` body and counts its nine dead
pending publications. `validate.py` compares GC-stress/RC behavior and located
bounds/arithmetic failures; `guests.py` runs existing aggregate/history tests.

The preserved local binary/compiler paths identify the exact evidence. No
main-branch merge, push or full-corpus acceptance is part of this isolated slice.
