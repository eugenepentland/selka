# Canonical RC collection release

Source checkpoint: `c13be022aa4a5260d15b002c377de15c5abb4480`, based on
`5535e5a3f0b67e23d0fc9f92f594d7b3feb12a3f`. Only the trusted
`rc_elements_release` call changes. The public source API retains its heap/depth
admission and registry lookup; the private helper is the byte-exact previous
walker after its lookup and signature are removed. Neither API adds registration
authority, metadata/cache fields, ABI versions, or count changes.

Dynamic descriptor shapes and children are rewritten into retained metadata
batches (`native_rc_shapes.c:512–527`); independent descriptor registration
resolves its shape (`:784`). Images validate correspondence before copying
mutable bindings and borrowing immutable graphs (`:685–716`). Canonical shapes
are inserted as their own identity keys (`:175–176`); batches survive table/frame
growth and are freed only at heap teardown (`native_rc.c:95–103`). The original
finalizer/reacquisition and public fallback in `drain_one` are unchanged.

`receipt.json` records actual counts and compiler/runtime/source digests.
`manifest.json` pins all 106 members of `artifacts.tar.gz`, including original
failed developer commands, compiled native/guest probes, raw outputs, assembly,
source snapshots, and the independent ASLR experiment inputs/results. Installed
compiler binaries remain frozen in the owned worktree at
`.tmp/registered-release/compiler/`; their hashes are recorded separately.

Validation executed:

- New native suite: 13 cases under UBSan. Six dynamic/image O/H cases exercise
  depth 1/2/4, repeated aliases, public source/canonical resolution, copied
  dynamic fields, empty release, and production list clear. One registering
  finalizer grows binding/shape tables; its second release retains the original
  descriptor and canonical shape. Six subprocess cases require SIGABRT for an
  unregistered public source, invalid heap, null nonempty storage, overflowing
  extent, active walk, and null canonical shape.
- Existing native collection 47, contract 25, and image 15 cases pass. Image
  tests also execute six host-allocation and six budget failure points.
- Reachable primary Zig test: one name match plus twelve unconditional unnamed
  import blocks, 13/13. Its assertion executes all 13 new C cases.
- Install/fmt/input coverage: 28/28 steps. Whole-tree Guardian: 88/88.
- Fresh LLVM O3/full-LTO and QBE ReleaseFast `text_ops`: two builds, two exact
  frozen-control output matches. This is functional evidence, not timing.
- Production-mode C O3 assembly retains the original collection guard branches,
  selecting the canonical helper where the original selected the public walker.
  The source proof also verifies exact walker extraction and one call replacement.

Run the native reproduction through `scripts/build-slot.sh build`, with TMPDIR
and Zig caches inside the new worktree:

```sh
python3 experiments/wp-b3-layout-20260929/registered-release/probe/native.py --out .tmp/native-replay
python3 experiments/wp-b3-layout-20260929/registered-release/probe/source.py
```

The preserved ASLR experiment used the exact frozen 5535 ET_EXEC executable,
changing only live breakpoint bytes and restoring them after 100 entries. Six
initial samples found the fixed image key `0x100b618` with zero occupied misses.
Six samples gated at the first text split found a later heap key: five trials had
zero misses and one had one miss for all 100 sampled calls. Every trial completed
with the same output. All twelve predeclared trials, the initial copy-mode error,
and the profiler revisions are retained; none were selected by outcome.

The previously captured low profile has 399,999 public release entries and zero
occupied misses. Its occupied-miss cycle contains ten instructions. One extra
miss for every entry would contribute 3,999,990 instructions, near the root's
3,999,976 high/low difference, but the frequency of that later key across the
whole run was not established. The exact 2–4M variability explanation remains
unproven. The GC `pool_hits` cache is consulted by tracing `mark`, rather than
this RC shape lookup. Root owns all quantitative corpus acceptance; no hardware
timing or performance gain is claimed by this receipt.
