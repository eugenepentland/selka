# Direct C imports: how it works

Implementation detail and measurements moved out of `docs/c-ffi.md`. The guide keeps the user-visible rule.

## Linking your code

The compiled object is cached in the build's `foreign-v1` store, with what the C
compiler printed, and reused only while the source and every header its compiler
depfile listed keep their bytes. A dependency file lists only the headers the compiler
opened, so the store also records each header that a quoted `#include` or a
`__has_include` in those files names beside the file that names it, present with its bytes
or absent, and checks them all again: one that appears (a local `stdbool.h` shadowing the
system one, an `opt.h` a `__has_include` tests for) or goes rebuilds the object. A file that changes while it compiles
pins nothing. A build that replays its last identical build rechecks the same files
([native builds](../tooling/native-build.md#the-caches)).

A source that names a header through a macro (`#include HEADER`, as SQLite's amalgamation does), or includes a header
that does, cannot list the names it asks for, so its object is keyed instead by the digest of its preprocessed text
(`zig cc -E` with the compile's own flags), together with everything the key above holds. The text holds every header it
included, the line markers that name each by absolute path, and every macro expanded, `__DATE__` and `__TIME__` included,
so a header that appears and shadows another, a `__has_include` that now finds its file, or a new second is a new key. A
text that still names data it does not hold (`#embed` left as a directive, an `.incbin` in inline assembly) is not
cached, and the object is published only when the text preprocessed after its compile is the text before it. Such a
build preprocesses the source every time and does not replay; for `sqlite3.c` an unchanged build costs about
0.2 to 0.4 CPU-s, against about 4 to 10 CPU-s (debug) or 17 to 41 (`--release`) when it was compiled every time:
the figure depends on the machine and its load (measured: 5.4 and 23 on one, 9.8 and 41 on another), and the first
build on a machine also warms the toolchain's own cache, so allow about 30 s of wall time for it. `--verify-cache` compiles
every served `--link` object again and fails when the bytes differ.

## Project links

**Known limit: `__DATE__` and `__TIME__` in a source the depfile check caches.** A source that names its headers plainly
is served while its files keep their bytes, so a `__TIME__` in it keeps the value of the compile that made the object
(seen on 11 November; nobody has decided whether to change it). With `stamp.c` holding
`int stamp(void) { return __TIME__[7] - 48; }` and a program that prints `stamp(host)`:

```text
selka run main.selka --link stamp.c             # 6: the compile's second
(edit main.selka, a few seconds later) selka run main.selka --link stamp.c   # still 6: the object is served
selka run main.selka --link stamp.c --no-cache  # 1: compiled now
```
