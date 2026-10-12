# Current-host native runtime requalification

The host changed `/etc/ld.so.cache` at 2026-10-12 01:37:15 UTC during this run.
Its size changed from 44155 to 44227 bytes; the previous reviewed hash no longer
matches. All five reviewed ELF libraries and the loader remain byte-identical at
the same resolved paths. `/etc/ld.so.preload` is absent.

`qualify.py` records exact inputs, `ldconfig -p`, ELF dynamic dependencies, loader
resolution, and actual debug/release execution with loader diagnostics. Both
probes exercise pthread creation/join, backtrace's dynamic libgcc loading and
floating-point math. They load only the previously reviewed loader/libc/libm/
libgcc/libpthread closure, and print `trace=yes sine=0.479426`. All 14 commands
passed. No RPATH/RUNPATH was added to the unchanged runtime libraries.

The production manifest update changes only the exact loader-cache content hash;
unknown cache bytes, unknown libraries, preload inputs and changed generations
continue to disable reuse. The native fallback lifetime bug is fixed separately
in `632726724`; correct execution must not depend on a cacheable tool identity.

C0 installations and immutable seed history remain unchanged. Their approval
policy cannot accept this new host state, so subsequent C0 native-link failures
and unavailable warm-cache comparisons remain in the evidence. Earlier C0 results
are not relabeled as measurements after this host change. Runtime comparisons of
already frozen guest binaries use the same unchanged runtime library bytes.

The first registered runtime-test attempt stopped before compilation: the
coordinator created then moved an unregistered aggregate-provider draft while
`build-identity` was inventorying source inputs, leaving a stale depfile entry.
This was an input-freeze mistake, separate from the guest native-link bug. The
raw failure is retained in `platform-tests-first.log`; the focused test suite
requires a fresh run on frozen inputs. The draft now lives outside `src/`.
