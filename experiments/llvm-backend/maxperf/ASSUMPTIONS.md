# Additional unchecked-wrapper assumptions

Link the extended arm with `--wrap` for `myl_native_text_at`, `myl_native_text_slice`,
`myl_qbe_int_cast`, `myl_qbe_int_neg`, and `myl_qbe_int_binary` in addition to
the list wrappers. Text indexing requires a dominating proof that the normalized
index or slice endpoint is within the receiver length. It retains scalar-text allocation, the
immortal ASCII cache, arena-depth restoration, and allocation failure.

Integer wrappers require widths from 1 through 64. Casts and checked arithmetic
must already be representable; divisors must be nonzero and not the signed
minimum divided by -1; shifts must be below the width. Floor division and modulo
retain the language's sign adjustment. Saturating operations 23-25 delegate to
the production helper.

Text stores one `myl_native_list` header plus four bytes per Unicode scalar in a
single managed allocation. ASCII UTF-8 input therefore widens from one byte to
four and copies every byte once into that allocation. Identifier substrings and
other text copies allocate another header plus four bytes per selected scalar;
the unchecked index wrapper preserves the shared 128-entry ASCII scalar table,
so repeated one-character ASCII indexing does not add per-access allocations
after table initialization.
