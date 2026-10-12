# Isolated C3 aggregate-runtime patch

`core-values-C3.patch` removes the single remaining mode branch in
`src/core/runtime/core_values.c`: the fresh float-render text temporary is always
destroyed with `myl_core_drop_owned` after its bytes have been copied into the
render buffer. The legacy `myl_core_release` alternative disappears. The patch
does not change any comparison, hash, rendering descriptor, native work buffer
allocation or repetition code.

`manifest.json` pins the exact integration commit, source/patch/proposed hashes,
and the unchanged repetition-helper digest. A private copy of the committed
source passes `git apply --check`. Signed nonpositive counts, empty inputs,
independent output storage, source bytes/text kind and the allocation terminator
overflow bound remain unchanged. Native allocation and direct destruction remain
valid operations; scalar/descriptor/work-list counts are not reference counts.

This is a draft only. Active production code remains unchanged. It requires
coordinator C3 activation after C2 qualification, the selected count-free runtime
header/destructor, and the corrected numeric formatter object ABI. A02 may use
it in an isolated combined runtime preview with the separate A04 core-text draft.
Actual rendering, numeric formatting, repetition/overflow, ABI-cache and full
C3 qualification are still required before retirement can be claimed.
