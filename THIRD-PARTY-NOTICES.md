# Third-party notices

Selka itself is under the MIT License (`LICENSE`). This file lists what else is in the release download
(`selka-VERSION-x86_64-linux.tar.xz`) and what else the repository carries, with the license of each and where its text is.
The release has one top folder; `PREFIX` below is where `install.sh` puts it (`~/.local` unless you say otherwise), so
`bin/selka` lands at `PREFIX/bin/selka` and `lib/selka/zig/` at `PREFIX/lib/selka/zig/`.

## 1. Zig, bundled in the release (`lib/selka/zig/`)

The release carries the official Zig 0.17.1 distribution for x86-64 Linux, unmodified except that its `doc/` folder and README are
left out: `zig` (its SHA-256 is `58959f01285c05a74276f09327b551d42ed6006bf325a78dc661a024e314987b`) and the whole `lib/` folder.
`lib/` is kept whole on purpose: `selka native show` accepts only the unmodified distribution for cache reuse. The programs you
build are compiled and linked by `zig cc`, so they take from this folder what `zig cc` takes for any C program (headers, start
files, compiler-rt).

- **Zig** (the compiler, its standard library under `lib/std`, and `lib/compiler`, `lib/compiler_rt`, `lib/c`, `lib/zig.h`): the MIT
  License (Expat), Copyright (c) Zig contributors. The text is in **`lib/selka/zig/LICENSE`**, which is Zig's own `LICENSE`.
- **Inside the `zig` executable**, linked statically (read from the binary's own version strings): LLVM, the Clang C compiler and
  the LLD linker, all 22.1.8, under the Apache License v2.0 with LLVM Exceptions (the text is in
  `lib/selka/zig/lib/libcxx/LICENSE.TXT`, and identical in `libcxxabi`, `libunwind` and `libtsan`); and zlib 1.3.1 (the zlib
  license, Copyright (C) 1995-2024 Jean-loup Gailly and Mark Adler; it asks for no notice in a binary). These are the libraries the
  strings name; Zig's own release notes are the authority for the full list.
- **Under `lib/selka/zig/lib/`**, the C libraries and headers Zig ships so `zig cc` can build for any target:

  | Folder | What | License | Where the text is |
  | --- | --- | --- | --- |
  | `libcxx`, `libcxxabi`, `libunwind`, `libtsan` | LLVM's C++ library, C++ ABI library, unwinder and thread sanitizer runtime | Apache-2.0 with LLVM Exceptions | `LICENSE.TXT` in each folder |
  | `include` | Clang's own compiler headers (`immintrin.h` and the rest) | Apache-2.0 with LLVM Exceptions | the header of each file |
  | `libc/musl` | musl libc | MIT, with the other permissive notices it lists | `libc/musl/COPYRIGHT` |
  | `libc/glibc` | GNU C Library sources, stubs and symbol lists | LGPL-2.1+ for most files, other licenses for some | each file's header; the notices that must travel with binaries are in `libc/glibc/LICENSES` |
  | `libc/mingw` | mingw-w64 | Zope Public License 2.1, with public-domain, BSD and LGPL parts | `libc/mingw/COPYING` |
  | `libc/wasi` | wasi-libc | Apache-2.0 with LLVM Exceptions, Apache-2.0 and MIT; dlmalloc CC0, emmalloc MIT, cloudlibc BSD-2-Clause, musl MIT | `libc/wasi/LICENSE`, `LICENSE-APACHE-LLVM`, `LICENSE-APACHE`, `LICENSE-MIT` and the files they name |
  | `libc/freebsd` | FreeBSD libc parts | BSD-style | `libc/freebsd/COPYRIGHT` |
  | `libc/netbsd`, `libc/openbsd` | NetBSD and OpenBSD libc parts | BSD-style | the header of each file (no separate license file ships) |
  | `libc/include` | system headers for each target: glibc, musl, the BSDs, mingw-w64 and the Linux kernel's user-space headers (mostly `GPL-2.0 WITH Linux-syscall-note`) | as each file states | the `SPDX-License-Identifier` or notice at the top of each file |
  | `libc/darwin` | `libSystem.tbd` and `SDKSettings.json`, the stubs Zig uses to link for macOS | no license file ships with them | none |

  None of these licenses forbids redistributing the files unchanged, which is all the bundle does. What a program built with them
  inherits is a question for each license; the Linux headers' `Linux-syscall-note` exception exists for programs that include them.

## 2. Zig's standard library inside the `selka` executable

`selka` and the two helper programs under `libexec/selka/components/` are written in Zig and Selka and built with Zig 0.17.1, so
the parts of Zig's standard library they use (formatting, hashing, `std.crypto` BLAKE3 and SHA-256, the allocator and file code)
are compiled in. That code is the MIT License, Copyright (c) Zig contributors: the same text as `lib/selka/zig/LICENSE`.

## 3. Third-party code in Selka's own sources

Searched: `src/`, `tools/` and `selfhost/` for license headers, copyright lines, and for the places a source says it was copied,
ported, adapted or derived. This is everything found.

| File | What | License | Note |
| --- | --- | --- | --- |
| `tools/test_runner/test_runner.zig`, `tools/test_runner/test_timing.zig` | The test runner the Zig test steps use (repository only, not in the release): copied from `guardian-zig` (`https://github.com/eugenepentland/guardian-zig`, `src/test_runner.zig` and `src/test_timing.zig`, commit `14cedaa8d42eeca33e90af220fe01332afea638d`), the same author's project, with the renames of the Selka rename. The header says it is Zig's stock test runner plus one line of honesty, so it also derives from Zig's `lib/compiler/test_runner.zig` | MIT: `tools/test_runner/LICENSE` (Copyright (c) 2026 Eugene Pentland) for the copy; Zig's MIT License (Copyright (c) Zig contributors) for the Zig-derived part | the header of each file says where it was copied from |
| `src/core/runtime/core_unicode_data.h` | Ranges of code points that are not printable, "static CPython3.14.4 / Unicode16.0.0 printability data": facts derived from the Unicode Character Database (general categories), read out through CPython's `str.isprintable` | the underlying data is under the Unicode License v3 (`https://www.unicode.org/license.txt`); the table of ranges is a derived list of facts, with no code from CPython | no license header in the file; the table is part of the C runtime the compiler embeds, so programs built by Selka carry it |
| `src/core/runtime/core_sha256.c` | SHA-256 (FIPS 180-4): the round constants and the message schedule are the published algorithm; the SHA-NI block uses the `_mm_sha256*` intrinsics, which fix its shape | none claimed; a public standard | no header and no named source; it reads as written for the project |
| `src/core/runtime/core_sort.c` | stable sort by powersort (Munro and Wild's published algorithm) | none claimed | the file says it is a port of the project's own `native_collections.c`; no outside code named |
| `src/core/runtime/core_number_format.zig`, `core_number_parse.zig`, `core_number_text.zig` | exact decimal formatting and parsing that follows the Python format mini-language and CPython's round-half-even rule | none claimed | the files say they are ports of the project's own `src/format_spec.zig` and `src/number_text.zig`; CPython is named only as the behaviour to match (`_Py_dg_dtoa`), no CPython code |

No other file in `src/`, `tools/` or `selfhost/` carries a license header or says it was copied from outside the project.
`proofs/` imports Lean's `Std` library for its build-time checks; none of Lean is copied, and none of `proofs/` is in the release.
Not searched for third-party content: `examples/`, `tests/`, `bench/`, `benchmarks/`, `docs/` (repository only; none is in the
release download).
