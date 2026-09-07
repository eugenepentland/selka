# Schematic development verification trial

Run the real disk-loaded application through the shared verification tools:

```sh
python3 tests/schematic_verification.py --runner zig-out/bin/schematic-svg \
  --output /tmp/schematic-verification.json
```

The script copies the current `.my` project and three actual DSL fixtures into two
independent temporary agent directories, including a path containing spaces. It
uses the installed runner throughout; its SHA-256 must remain unchanged. No Zig
build or Guardian invocation occurs. The manifest and source/tool identities are
recorded in the JSON evidence. Temporary stores are fresh on every trial.

Two complete, self-contained jobs are declared: rendering with an independent XML
oracle (30 unique component references and 99 pad entries), and fixture integrity.
Both declare their oracle and local Python runtime files/shared-library identities.
The rendering job declares every guest module and fixture. The integrity job has
no guest dependency. This is a trusted local experiment; it does not sandbox the
commands or prove arbitrary dependency declarations complete.

The script asserts cold execution, warm receipt reuse, equivalent-root reuse,
exactly two executions across four concurrent clients requesting eight jobs, and
renderer-only affected selection. A malformed renderer must fail both its first
run and its retry instead of reusing prior success. The first affected edit is a
comment: it intentionally tests source invalidation, not semantic-change precision.
The malformed edit then demonstrates that a different source cannot borrow the
successful rendering receipt.

`verification-baseline.json` records the initial renderer on this machine:

| Scenario | Suite executions | Reused receipts | Coalesced deliveries | Wall time |
| --- | ---: | ---: | ---: | ---: |
| Cold | 2 | 0 | 0 | 3.40 s |
| Warm | 0 | 2 | 0 | 0.19 s |
| Equivalent second root | 0 | 2 | 0 | 0.18 s |
| Four concurrent clients, cold store | 2 total | 6 total | 6 total | 3.50 s slowest client |
| Renderer-only edit | 1 | 0 | 0 | 3.21 s |
| Invalid renderer | 1 failed | 0 | 0 | 0.25 s |
| Invalid renderer retry, full manifest | 1 failed | 1 | 0 | 0.25 s |

Coalesced deliveries are also reported as cached receipt deliveries; those columns
must not be added as distinct jobs. The fixture job is explicitly `not-selected`
in affected mode. The retry requests the full manifest and reuses its valid fixture
receipt while re-executing the failed render.

These timings are observations, not performance thresholds or a general speedup
claim. This trial checks suite-level selection and receipt safety for an actual
application; it does not test Git worktree behavior, combined-merge certificates,
semantic dependency discovery, or visual equivalence with the webpage. The SVG
acceptance suite remains responsible for detailed connectivity and rendering checks.

## Final renderer checkpoint

`verification-final.json` records the formatted final guest project with the same
installed host binary as the baseline. All recorded guest source hashes were
checked against the final files. Other agents were running application acceptance
and visual checks on this machine during collection.

| Scenario | Suite executions | Reused receipts | Coalesced deliveries | Wall time |
| --- | ---: | ---: | ---: | ---: |
| Cold | 2 | 0 | 0 | 2.44 s |
| Warm | 0 | 2 | 0 | 0.21 s |
| Equivalent second root | 0 | 2 | 0 | 0.21 s |
| Four concurrent clients, cold store | 2 total | 6 total | 6 total | 2.75 s slowest client |
| Renderer-only edit | 1 | 0 | 0 | 2.50 s |
| Invalid renderer | 1 failed | 0 | 0 | 0.27 s |
| Invalid renderer retry, full manifest | 1 failed | 1 | 0 | 0.27 s |

The final drawn-topology trial also passes with the unchanged installed binary.
These are opt-in application jobs, not a replacement for production merge gates.

## Independent drawn-topology checks

```sh
python3 tests/schematic_layout.py --runner zig-out/bin/schematic-svg
```

The geometry oracle checks actual SVG segments and pin coordinates, including
chip pin leads: Manhattan routing, connected multi-pad signal nets, connected local
supply branches, in-bounds pads, no different-net coincident pads, and no wire
passing through another net's pad. Routes cannot cross or run beneath the chip
body, and routes meeting its boundary must meet a matching physical pin. Canonical supply aliases are resolved before
comparison; globally labeled power/ground nets need not have one continuous wire.
Crossings away from pads are permitted. Ground and dangling-pin glyphs are marked
separately from actual wire segments.

The trial rewires `C_LF1` from `LMX_CPOUT` to `LMX_VTUNE` in the actual schematic
DSL and requires the endpoint placement and both drawn nets to change. It then
modifies a copied `.my` renderer to emit zero-length routes: the VM still succeeds
and emits the complete pin metadata, but the independent connectivity check must
reject the result. This guards against certifying an SVG from metadata alone.

During this implementation the oracle exposed wrong-net pad touches in the
oscillator, loop filter, and RF output branches. Placement fixes and an obstacle
detour removed those failures; the assertions were retained. These are correctness
findings in generated schematic geometry, independent of the cache reuse results.
