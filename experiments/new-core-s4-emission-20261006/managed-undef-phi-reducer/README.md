# Managed memory phi initialization

F and root reduced the inherited zero-trip managed-record ownership failure on M's captured target. Raw release LLVM compiles/links successfully but exits232 with the bundled target; copying the existing40-byte zero initializer onto the undef incoming edge restores exit0. The default-target raw and zero variants both exit0, exposing why prior native runs did not find it. Exact commands and native streams are retained in each receipt. The original binaries and caches remain at the immutable paths in `source-identities.json`.

The minimal emitter correction initializes managed memory undef, whose existing `undefValue` already specifies null managed pointers. It continues to skip unmanaged undef so no memcpy/memmove reads `ptr poison`. Existing zero-trip list/record Debug/Release coverage is retained; native two-record parallel phi swapping and verified unmanaged-phi emission cover staged copies and the poison exception. No IR or runtime ABI changes.
