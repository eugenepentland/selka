# SVG host I/O audit arms

These sources build private `gc-lto` audit arms from the frozen audit compiler.
They do not modify the production runtime or schematic provider.

* `control`: regenerated from the unmodified provider.
* `counts`: the same ABI, with per-declaration counters printed only when
  `MYLANG_HOST_COUNTS` is set.  This arm is for untimed call-count collection.
* `unchecked`: removes provider-side argument-node, output-capacity, known-file,
  position, output-capacity, and host-work checks from `io::byte` and `io::put`.
  The generated host runtime still validates types, budgets, results, and reentry.
  It is a specialization ceiling, not a production-safe implementation.
* `memory-output`: keeps the normal host ABI and checks but appends output bytes
  to a fixed 4 MiB memory buffer and performs one `fwrite` at process cleanup.
  This delays output errors until cleanup and does not propagate a cleanup write
  failure into the guest result.  It is an output-library ceiling, not a valid
  replacement for the current synchronous failure contract.
* `metadata-control`: unchanged LTO guest objects relinked with freshly generated
  production-equivalent host metadata and the ordinary provider.
* `typed-host`: the matched metadata control with `io::byte` and `io::put`
  dispatched to typed provider entry points. It retains registry validation at
  startup, host call/work limits, reentry state, byte bounds, output bounds and
  provider I/O failures. It removes per-call node creation, indirect callback
  dispatch, argument arity/capacity validation, output node count/type/range
  validation, and generic provider work-charge propagation for those two calls.
  The metadata wrapper directly charges the same two work units per call.

`build.sh` records compiler, source, and binary SHA-256 hashes in `builds.json`.
`build_typed.py` records the relink and all unchanged guest-object hashes in
`typed-builds.json`.

For a later algorithm/compiler arm, `relink_typed_pair.py` accepts its already
built receipt and its exact emitted manifest. It does not regenerate guest code:

```sh
python3 experiments/svg-gap-audit-20260921/host/relink_typed_pair.py \
  --receipt PATH.qbe-manifest.json --manifest PATH.emit-project-qbe.json \
  --prefix .tmp/svg-gap-audit-20260921/host/combined
```

This produces `combined-metadata-control`, `combined-typed-host`, and
`combined-host-relink.json` with hashes of every retained input and output.
`qualify.py` checks all three frozen cases, exact SVG hashes, status/stdout/stderr,
and GC-stress execution. It also collects untimed declaration counts.
