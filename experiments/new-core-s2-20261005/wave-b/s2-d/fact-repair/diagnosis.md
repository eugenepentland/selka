# S2-X dictionary fact failure on frozen 090dabd5

The full strict leak/verify sweep of source `090dabd5a6932a7c3beaec68248f9a35d4c637d7` found one real release fact failure. Debug matched 1224 tests; release matched 1223 with one mismatch; each mode precisely refused 316. The sweep exited 1 after 137.86 seconds, with peak RSS 324992 KiB, after waiting 888 seconds for a build slot. The separate old CLI exit-3 classification issue is a harness failure and is being repaired independently.

The saved release executable was rerun without compilation:

```sh
scripts/build-slot.sh build -- bash -c 'MYL_CORE_LEAKCHECK=1 .mylang-cache/s2-x/sweeps/tests/dictionary_hashing-820aee5859e72ba3-release 7 > experiments/new-core-s2-20261005/wave-b/integration/s2-x-dictionary-fact-repro.txt 2>&1; result=$?; printf "native_exit=%s\n" "$result" >> experiments/new-core-s2-20261005/wave-b/integration/s2-x-dictionary-fact-repro.txt; cat experiments/new-core-s2-20261005/wave-b/integration/s2-x-dictionary-fact-repro.txt; exit 0'
```

It waited 86 seconds for a slot, then returned native exit 1 with this diagnostic:

```text
dictionary_hashing.my:309:19: error[R_CORE_FACT]: native execution failed (range [0, 0]: value 27, other 0)
```

The failing assertion is trap site 816 in the preserved release LLVM at `.mylang-cache/s2-x/sweeps/dictionary_hashing-820aee5859e72ba3-release-c767ec5fe599fe7f.ll`: `%v82 = dict_len(fresh)` is asserted to be at most zero after the loop. Runtime length is 27. This is a false dictionary length fact, rather than a text hash, reference-count, or probe assertion.

The focused source `s2_x_dictionary_fact_repro.my` preserves the original helper and test body and adds a main entry. No language tests were edited. Its read-only command was:

```sh
zig-out/bin/mylang-core dump-ir experiments/new-core-s2-20261005/wave-b/integration/s2_x_dictionary_fact_repro.my --facts > experiments/new-core-s2-20261005/wave-b/integration/s2-x-dictionary-fact-repro-ir.txt 2> experiments/new-core-s2-20261005/wave-b/integration/s2-x-dictionary-fact-repro-ir.err
```

The command exits 0, stderr is empty, and the final facts print `%82=[0,0]`.

`recomputeDict` copies the entire input dictionary fact for `dict_copy`, `dict_insert`, `dict_remove`, and `dict_set_value`, including `settled=false` from unknown call and parameter results. A loop phi skips an unsettled fact-producing back edge. In this case the dictionary update after `bump_text` therefore stays unsettled forever, so the phi retains the empty entry fact. Ownership adds COW branches after facts have been computed; those later branches cannot repair this false original fact.

The minimal proposed repair is a `pendingDict` predicate analogous to the existing `pendingList`: only not-yet-computed dictionary-producing operations and phis count as pending. Copy and update transfer should set `settled = !pendingDict(input)`; a call or parameter input then settles to unknown length and hulls, which correctly weakens the loop phi. Regression coverage should exercise unknown call or parameter inputs through copy, insertion, removal, and replacement feeding loop phis, and rerun this original native test in release verify mode. This diagnosis made no compiler source or index changes.
