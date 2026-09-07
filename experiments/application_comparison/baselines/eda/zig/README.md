# Independent Zig EDA inspector baseline

This stdlib-only implementation follows `../../../contracts/eda-inspector-v1.md`
and its workflow transport rules. It was constructed independently from those
contracts without reading coordinator oracles, fixtures, or other implementations.
The application reads one JSON request from stdin and writes one JSON response to
stdout. Defined input errors exit zero. Operating-system and allocation failures
can exit nonzero.

Pinned compiler: `/home/epentland/.local/bin/zig`, version
`0.17.0-dev.1683+5ceec001b`.

From this directory:

```sh
/home/epentland/.local/bin/zig test main.zig -O Debug
/home/epentland/.local/bin/zig build-exe main.zig -O Debug -femit-bin=eda-inspector-debug
python3 test_stdin.py ./eda-inspector-debug
/home/epentland/.local/bin/zig build-exe main.zig -O ReleaseSafe -femit-bin=eda-inspector
python3 test_stdin.py ./eda-inspector
printf '{"cases":[]}' | ./eda-inspector
```

Python is only the stdlib-based local test harness, never an application runtime
dependency. No package downloads, libc, native geometry helpers, external files,
subprocess helpers, or network are used by the application.

`main.zig` separates strict transport checks, schema parsing, ordered semantic
validation, geometry/connectivity reports, and deterministic SVG export. JSON
numbers remain lexical strings until globally checked for signed-64-bit integer
range or finite float values; only integer lexical forms satisfy board fields.
Container depth is checked before parsing. All distances become integer
micrometers, with `i128` squared-gap calculations. Output has no arbitrary size
limit; an arena holds the parsed request and generated responses until exit.

Own tests cover decoded duplicate keys, integer bounds, nonfinite floats, invalid
UTF-8, nesting 64/65, exact input-byte limits, phase precedence, repeated references,
zero-clearance touch/overlap, Pythagorean equality, boundaries, half-micrometer
rounding, unit scaling, ordering, exact SVG text, independent cases, and a legal
64-board request producing over 55 MiB of output. These tests provide local
construction evidence, not exhaustive correctness proof or scored evaluation.

Known tradeoff: whole-request arena allocation makes peak memory scale with the
response; permitted dense boards can produce tens of megabytes of JSON. No known
contract gaps remain. Guardian integration is intentionally deferred to the
coordinator's subsequent policy setup.

Guardian integration now lives in `guardian.toml` and `SPEC.md`; implementation
is under `src/` with the original root compile/test entry retained. The main trial
uses the coordinator [trusted adapter](../../../guardian_policy/README.md), which
passes Guardian, Debug tests, ReleaseSafe compilation and isolated conformance.
The standalone commands above remain language-only commands.
