# Frozen-candidate raw I/O bridge (construction version)

`zig-out/bin/mylang-io --project DIRECTORY` loads `DIRECTORY/main.my` and imports
from disk, compiles to bytecode and runs the VM. Build/install the tool once with
`zig build -Doptimize=ReleaseFast` outside participant timing. Ordinary application
source changes do not rebuild Zig or exercise Guardian on the language codebase.

Applications declare an `io.my` module:

```text
module io;
export length;
export byte;
export put;
host fn length() -> i64 effects(host);
host fn byte(index: i64) -> u8 effects(host);
host fn put(value: u8) -> i64 effects(host);
```

`length` gives input byte count. `byte` returns a raw byte; negative or out-of-range
indices fail. `put` appends one byte and returns zero. Main returns zero for success;
nonzero exits or traps fail execution and discard all buffered output. Define
ordinary recoverable input errors by serializing their JSON and returning zero.

The bridge does not parse JSON, validate UTF-8, resolve identifiers, evaluate
geometry, process graphs, or serialize reports. No domain helpers or language-
specific rich input adapters are allowed. Applications own every such operation.
Input is passed untouched up to 2 MiB, permitting tests above the application's
1 MiB contract; larger transport inputs fail the host. Output is capped at 128 MiB,
host calls and cooperative work at 300 million each, VM steps at 2 billion. These
are construction bounds requiring feasibility validation before cohort freeze;
they do not override the coordinator's per-command wall/CPU/memory quotas.

Bridge source: `src/byte_io/{host,runner,tests}.zig`. Guardian covers its production
and test roots, with baselines disabled. `zig build test-byte-io` checks raw invalid
text, source reload, no output on guest failure, exact input bounds, registry bounds
and allocation failures. Pin the installed executable, source and toolchain in
cohort receipts. Neither building this bridge nor testing it is a participant trial.
