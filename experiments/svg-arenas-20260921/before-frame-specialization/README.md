# Before frame-bookkeeping specialization

These are valid timings and qualifications of the first chunk-arena implementation, before restricting save/restore to functions that open a scope. The final comparison is in the parent directory.

Early experimental allocator-probe results were withdrawn: linker wrapping missed internal runtime calls and yielded incomplete snapshots. Those statistics are not evidence here. The parent directory uses an instrumented private runtime with exact observation points.
