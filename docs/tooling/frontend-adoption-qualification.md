# Compiler-wide frontend qualification

`selfhost/tests/run_frontend_qualification.py` takes an installed host, native
coordinator and four verified packages. It verifies the qualified seed receipt
on every invocation. It does not build implicitly. Run after installation,
under build admission with a private disk `TMPDIR` and local Zig cache:

```console
scripts/build-slot.sh build python3 selfhost/tests/run_frontend_qualification.py \
  --compiler zig-out/bin/mylang --builder zig-out/tools/selka-components \
  --component-dir zig-out/libexec/mylang/components --zig /path/to/pinned/zig \
  --component --report /private/scratch/frontend-normal.json
```

Repeat with `--release` for native guest release builds, fact verification and
leak checks. `--component` requires successful component-only operation; it
never substitutes shadow or silently skips unsupported modes. Without that
flag, the declared qualification scope is reference and shadow only. Defaults
are not changed by this developer tool.

The workflows cover check, imported project checking, library checking, build,
native executable behavior, run-project, forced guest tests, formatting and
idempotence, declaration/module listings, full syntax/token dumps, dependency
reports, qualified/dotted context names, lexical navigation fallback and embeds
inside format holes. Unicode, syntax and type errors, non-ASCII bytes in comments,
large comment sources, dense declaration pools and exact transport limits are
included. Fixture `.input` files preserve malformed/noncanonical source bytes;
all eight are materialized as `.my` sources in private scratch. Command status,
stdout and stderr compare byte-for-byte where the command is informational.
Build/run/tests additionally assert observable guest results and nonempty test
counts. Forced tests refuse cached, skipped or unsupported verdicts.

Warm build, run and test commands are primed twice with stable paths and a
populated private application cache. Each frontend package is then independently
made unavailable, given an unsupported schema, corrupted without updating its
digest, or replaced with the other native producer under a matching new digest.
Every command must fail with host status 2 and no result stdout. These checks
guard against hiding package failures behind executable/test replay or retained
syntax. They demonstrate warm state, not a claim that every mode serves a cache
hit: shadow may deliberately disable reuse. Runtime commands use empty `PATH`
and an explicit absolute native Zig; installation/runtime need no Python.
Live `check-session` processes are also warmed twice, then lose a manifest or
receive a digest corruption without restarting. The next check must report JSON
status 2; the session must still accept `quit`. These checks exercise retained
memory separately from fresh-process disk replay.

`--edit-check` explicitly copies the source closure and invokes the real native
coordinator for a private installation. A parser implementation branch is added,
the coordinator rebuilds it, and the driver requires a different recipe key and
artifact digest while all three unrelated package manifests and the host digest
stay unchanged. The complete workflow matrix then runs against that private
installation. No installed manifest or shared source tree is edited.

The present qualified lexer bound is 262,144 source bytes. An exact-bound valid
source must succeed; the same valid source plus one byte must produce a repeatable
bounded host failure in shadow/component modes while reference accepts it.
The report records this narrower acceptance as a default-adoption limitation,
not as language parity. The component profile and schema must be explicitly
requalified before widening that bound.

Nine adversarial harness tests run through
`python3 -m unittest selfhost/tests/frontend_qualification_test.py`. They reject
empty/incomplete/cached forced verdicts, malformed artifact basenames/digests,
inherited oracle/routing controls and stderr differences hidden by equal stdout.

Build registration must track this driver, its unit tests and the complete
fixture directory membership. The explicit coordinator edit additionally reads
`selfhost/component-seed.json` and the entire recursive `selfhost/components/`
closure, including file-link targets. Packages, host, coordinator and pinned Zig
are command inputs. Receipt and deployment checks must execute even when a
previous repository-only test verdict could be reused; mutable external stores
are not qualified by a cached green result.

## Isolated measurement

`selfhost/tests/measure_frontend_adoption.py` requires `--isolated` and a prebuilt
ReleaseFast host. Obtain exclusive timing admission from the root coordinator,
with every build/gate reservation held and the host pinned to reserved timing
CPUs. Never run it alongside correctness gates. Supply the same installed
arguments, `--component`, and `--output /private/scratch/frontend-timing.json`.

It records all raw samples and medians for complete parser `dump-syntax`
commands with the lexer held in reference mode, application builds through an
empty application cache, repeated warm builds and imported-source edit loops.
Every sample checks actual output/status; edited executables must return the
new value. Application cache reports are retained without pretending cold
application state is a cold machine, runtime store or toolchain.

The native coordinator separately builds all four packages into an empty
private artifact store, verifies warm receipts, and rebuilds a parser-only edit.
Its private cache links to the previously verified shared seed store, avoiding
duplicate bootstrap builds. Measurements include coordinator verification,
source snapshot, native compilation and installation; the seed is provisioned,
not measured cold. Package identities and unchanged host bytes are checked.
Process affinity, host/package digests and the cumulative child peak RSS are
recorded. That RSS is a whole-driver high-water, not per-exchange allocation.
