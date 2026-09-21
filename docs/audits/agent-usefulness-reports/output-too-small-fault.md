# The `QBE-TEXT-4` codec fault — root cause and fix

`invoke_test`'s "an undersized codec result buffer reports OutputTooSmall, not
WireLimit" crashed with `SIGSEGV` on its first call through the loaded codec
entry. It was the only red item in the gate for six rounds. It is fixed, and the
cause was not in the codec at all.

## Root cause

**The test binary was statically linked and the shared object it loaded was not.**

`mylang build --library` produces a shared object linked against the system
glibc. `invoke_test` `dlopen`s that object into the Zig test binary. Zig builds
test binaries statically by default, with no libc of its own:

```console
$ file .zig-cache/o/<hash>/test
ELF 64-bit LSB executable ... statically linked
$ ldd .zig-cache/o/<hash>/test
        not a dynamic executable
$ nm -D --defined-only .zig-cache/o/<hash>/test | wc -l
0
```

Loading a glibc-linked object into that process brings up a second, independent
glibc whose process-global state — TLS, `environ`, the allocator — disagrees with
the runtime it was loaded into. The first call through the loaded entry faults
inside glibc. Nothing in the codec is at fault.

## How it was pinned down

Two earlier readings were wrong and both are worth recording, because each cost
a round:

* It is **not** a capacity bug. Moving the eight-node call ahead of the four-node
  one moves the fault with it, so it lands on whichever call runs first, with a
  buffer that is demonstrably large enough. The test's own name describes
  something that never happens.
* It is **not** inside the codec. File-appending probes at the entry statement, at
  `co_read`, at `co_write` and at the `done:` epilogue that runs on every path
  produced no log file at all.

The decisive step was getting the shared object out of the temporary directory
`mylang invoke` deletes it from — polling `/tmp` while an invoke built — and then
calling it from a **plain C driver** compiled by the same compiler:

```console
$ cc -o codec_driver codec_driver.c -ldl && ./codec_driver tests.so
loaded tests.so, entry at 0x73d2fd5454b0
calling with capacity 8 ...
  rc=0 code=(null) node_count=5 first_type=str children=4
calling with capacity 4 ...
  rc=2 code=OutputTooSmall node_count=5 first_type=sentinel
```

Exactly the contract, in both directions, from a dynamically linked host. That
exonerated the library and pointed at the test process.

The first draft of that driver also crashed, on `fprintf` with `%s`, because it
put `code` at offset 16 where the C struct has it at 24 — the Zig side asserts
`@offsetOf(RunResult, "code") == 24`. A `backtrace()` in the signal handler
showed the fault was inside the driver's own `fprintf`, which is what stopped a
second wrong conclusion from being written down.

## Fix

`src/root_test.zig`'s test module now sets `.link_libc = true`, so the tests link
the way the object they load expects and the boundary between the two is an
ordinary dynamic call. Two leaks the crash had been hiding then surfaced and are
fixed too: the temporary cache path, and the entry path `builtLibrary` hands to
the session's options, which nothing released because production runs on an arena
and never notices.

The unit root went from `1317/1318, 1 crashed` to **1318 passed, 0 failed, 0
skipped**. It is fully green for the first time on this branch.

The dynamic linkage costs real memory — the whole root peaks near 2.2 G where it
used to peak near 1.1 G — so `rss.suite` moved from 2048 MiB to 2560 MiB with the
observed figure recorded beside it.

## What would have found it faster

The fault was reported twice-removed and mis-framed twice. A `dlopen` of the
generated object from a plain C host, which took one round to set up once the
object could be captured, answers "is the library or the caller wrong?" in a
single run. That should be the first step for any future ABI fault, not the last.
