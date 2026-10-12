# Preserve the repeated octet type

The existing native repetition helper allocated `MYL_KIND_STR` for every source.
It now allocates `kind_of(source)`, preserving bytes as bytes and text as text.
A07 reviewed this correction. The data and ownership behavior are unchanged.

`run.py` concatenates the exact runtime fragments listed in `driver.zig` and adds
`probe.c`. For both ordinary and zero-RC headers, the previous constant kind fails
the explicit bytes-kind check; the corrected helper passes bytes-kind, invalid
byte payload, text-kind and Unicode payload checks. `results.json` records source
hashes, commands and all four outcomes. The previous variant is constructed with
the single constant-kind line restored in disposable C input, not by changing the
production checkout.

The first `assert`-based probe did not detect the deliberately incorrect variant
under this toolchain. Its results are retained as `initial-assert-disabled.json`;
they are not qualification. The final probe uses explicit conditional failures,
so both required negative controls now fail and both repaired controls pass.

Full integrated guest repetition qualification must use this corrected runtime.
