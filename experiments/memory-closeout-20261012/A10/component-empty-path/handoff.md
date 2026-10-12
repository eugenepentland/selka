# Empty-PATH component bootstrap gate repair

The full gate supplied the qualified independent compiler pin and source archive,
but its integration fixture invoked the component builder without those arguments.
With PATH deliberately empty, that accidentally selected legacy provisioning and
failed before the actual bootstrap test.

The coordinator-authored build options now pass the selected pin/archive through
Zig LazyPath options. The existing fixture forwards them, preserves the empty PATH
and `--uncached` rebuild, and requires both component manifests to state
`memory_mode=zero-rc-v1` whenever a checked compiler pin was selected. No seed,
compiler selection default, source archive, or component cache lock is changed.

Focused test-cli validation passed: one named bootstrap test and three mandatory
unnamed blocks, zero failures. Native component rebuilding took 11.11 seconds.
The exact source/pin/archive identities are recorded in results.json; full log is
focused.log. The parent must still rerun the complete registered verification gate.

Command (after sourcing the shared development environment and setting
MYLANG_COMPONENT_CACHE to the qualified Support6 compiler cache):

```sh
scripts/build-slot.sh build "$ZIG" build test-cli \
  -Dtest-filter='CLI component bootstrap rebuilds' \
  -Dcomponent-owned-compiler-pin=/home/epentland/ai/canopy/mylang-memory-20261012-A10/experiments/memory-closeout-20261012/A10/packaging-support6-candidate/candidate-pin.json \
  -Dcomponent-seed-source=/home/epentland/ai/canopy/mylang-memory-20261012-A10/.tmp/memory-closeout/A10/owned-pin-support6-5167c588/source.tar \
  -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS"
```

The first unsupported Build.pathFromRoot draft was corrected to the pinned Zig
addOptionPath API before the passing run. Equality remains parked in a separate
evidence-only commit and is not part of this repair.
