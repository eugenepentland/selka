# Plain native replacement without ownership staging

`myl_rc_native_retain_replace` now directly copies an already registered native
layout when its cached flat plan contains zero ownership leaves and no deaths
are queued. The existing native-layout admission excludes raw unique resources,
held pointers, variants, all pointer leaves and every custom descriptor hook.
This proof is stronger than a counted shape of NONE, which can also describe
raw resource storage. Registration remains bounded; layouts outside that proof
keep the generic path.

The change is nine lines in that one function. It preserves the self-copy no-op,
validates the destination region, and uses `memmove` for overlap. Unregistered
metadata retains its existing staging/registration/refusal order. No shared cache,
header, ABI, compiler or semantic-history code changes.

## Callback and ownership boundary

The generic path stages the source, then drains queued deaths before publishing
the replacement. A queued finalizer can mutate the original source. The fast
path therefore requires an empty death queue; otherwise the entire original
path runs. A regression queues a finalizer which changes source 7 to 99 and
verifies the replacement still receives the staged 7. The test also verifies
custom-finalizer metadata is excluded by flat admission.

Other controls cover overlap in both directions, self-copy, invalid-region
refusal without modifying the destination, valid arena destinations, a wide
nested plain array under a tight budget, and cold metadata refusal. A held-token
replacement preserves H rather than acquiring O. A raw resource nested inside
a record with counted shape NONE still reaches the unique-copy refusal and
aborts, rather than being copied as plain bytes. Existing variant, pinned,
owner-count refusal and transactional rollback suites remain active.

## Independent reduced measurement

The immutable before compiler is built at real merge `2d41fb4f`, joining drain
cache `da5b735a` with held-loan correctness `32aa30cf`. The candidate changes only
the replacement function. Five interleaved samples per arm run on CPU 3 using
the nbody source with 10,000 steps. This is explicitly a reduced diagnostic,
not the required five-million-step acceptance workload.

| Backend | Before instructions | After instructions | After / before |
| --- | ---: | ---: | ---: |
| QBE | 4,661,037,527 | 3,566,783,100 | 0.765234 |
| LLVM O3/full LTO | 3,714,721,079 | 2,807,217,407 | 0.755701 |

Both outputs are exactly `-169075163` then `-169016441`. Both before/after
counting binaries have two heap allocations and retirements, O 1/3,
H 3,620,039/3,620,039, 20,007 uniqueness checks, and no clones/refusals.

QBE disassembly confirms the same nine `myl_rc_list_set` and nine
`myl_rc_native_copy` sites remain in `advance`, along with 24 list-loan sites.
The source performs 75 Body replacements per step. These gains overlap the
separate compiler proposal to remove those Body helper calls; they must not be
multiplied or added as independent cumulative savings. This runtime change
also applies to dynamic dictionary overwrite paths, whose element type reaches
the same helper. A separate normal-program dictionary regression records that
the generated dictionary helper call remains present.

The remaining 362 held-loan pairs per step are untouched and remain a substantial
source of runtime work. Full unchanged nbody and corpus measurements are deferred
to the joined candidate under the root integration task.

## Validation and evidence

Three new normal-program assertions cover repeated dictionary updates, list
snapshots, and nested plain arrays inside an arena. They pass before and after
on both actual backends, with identical balanced counts: 12 allocations and
retirements, O 3/15, H 806/806, four arena allocations and two clones.
The broader 54-assertion standalone driver passes on both candidate backends
with 1,464 allocations/retirements, O 906/2,370 and H 208/208.

ASan/UBSan pass production collections 35, contract 22, semantic history 35,
loans 9, held views 12 and arenas 10, plus execution/statistics harnesses.
The focused production wrapper passes 12/12 and the Debug build passes
Guardian's 88 checks. No full competing gate was run.

`experiments/d9-rc-plain-replace-20260926` preserves commands, compiler and source
hashes, actual backend manifests, every raw instruction sample, stdout/counter
records, relevant disassembly and validation receipts. The isolated before and
after installations remain in `.tmp-plain` for joined follow-up measurements.
