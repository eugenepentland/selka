# Native build publication and timing
> Removed on 2026-09-13: this page documents a feature that no longer exists in the language.

The native builder publishes only a successfully linked executable. Compilation
uses a temporary directory beside the destination, then a same-filesystem atomic
rename installs the complete candidate. Source rejection, C errors, linker errors,
and subprocess failures leave the previous executable intact. Temporary products
are removed on ordinary success/failure. The existing destination symlink behavior
is retained: the builder resolves the output path before publication.

If a complete candidate is byte-identical to an existing executable, publication
is skipped and the existing inode and modification time survive. An identical
nonexecutable file is replaced with an executable candidate. Concurrent writers
can each publish complete files; this is not a lock or a multi-build transaction.

Generated guest C uses a stable compilation directory and remapped source paths.
This removes random build-directory paths from otherwise-identical Debug outputs.
Guest language source paths and runtime traces remain the checked program's paths.
Guest C, optional trusted adapters, and linking are separate subprocess stages;
all native stages share the existing 180-second timeout budget. Frontend emission
retains its separate 60-second timeout.

Trusted adapters compile in the caller's working directory with fresh local/global
Zig cache storage. An acceptance regression showed that cached C objects could
ignore a changed assembly `.incbin` input. Fresh adapter cache storage prevents
that stale reuse without pretending that the primary C file or C preprocessor
headers describe every possible adapter input. It costs an adapter compilation
on every build. No trusted-provider dependency cache is claimed.

## Reports

Add `--report` to a normal native build:

```sh
python3 scripts/native.py examples/sum.my -o /path/to/sum --report
```

Successful stdout is one `native-build-v1` JSON object containing the selected
mode/pinned Zig version, resolved output path, `output_changed`, generated C byte
count/SHA-256, `frontend_seconds`, `native_seconds`, and
`driver_reused_compilation: false`. Errors go to stderr and produce no success
report. A report output-stream failure may occur after the executable has already
been published; the report and executable are not an atomic pair.

Timings measure elapsed subprocess stages, not CPU time, independent benchmark
results, or a promised speedup. Toolchain version checking and publication are
outside those two measurements. The generated-C digest identifies emitted bytes;
it is not a complete trusted-provider or toolchain dependency receipt. The driver
always invokes the frontend and C build stages. Zig may reuse its own cache for
guest compilation/linking; unchanged publication is not compilation reuse.

## Acceptance and remaining work

`tests/native_builder.py` checks unchanged Debug/ReleaseFast executable identity,
changed output behavior, executable permission repair, source/C/link errors,
simulated partial linker output, temporary cleanup, JSON reports, caller-relative
adapter assembly files, changed assembly bytes, and unchanged adapter output.
The standard build includes this driver. Existing scalar/module native parity
and explicit clock/random/environment/resource builder fixtures cover the staged
compilation path.

Native object/query reuse with complete invalidation receipts, incremental linking,
native embedding/bindings, and broader compilation-performance work remain open.
This is the publication and measurement foundation for that work.

Validation: focused native-builder acceptance passes, including a failing-before
partial-output simulation and the changed `.incbin` regression. Scalar/module
parity passes all 2,616 comparisons; clock/random and environment acceptance pass
32/38 comparisons and 14/56 allocation failures. Final fixed-I/O resource selection
passes two VM/native traces, 28 allocation failures, and six registry sanitizer
runs. The build gate passes all 88 Guardian checks without baselines. This was
focused validation; no new full-suite result is claimed for this milestone.
