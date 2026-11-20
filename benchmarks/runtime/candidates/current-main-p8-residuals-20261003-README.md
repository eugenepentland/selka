Sixteen additional current-main1fd1d566 hotspot diagnostics cover sort_int,
sort_records, alloc_retained and mutate_nested at both original sizes on LLVM
and QBE. The frozen89f4f85b harness preserves the original main report's source
hashes, receipt and binaries. These captures supplement the earlier eight
families; neither selection measures common-code CPU coverage.

All 16 completed, with 264–323 samples each, no iteration caps and raw throttle
records in every capture. Instrumented duration missed the four-second target
in every capture. Samples include launcher, fixture setup, kernel, formatting
and teardown. Throttle records require caution about the retained distribution;
they do not alone establish the achieved sampling frequency.

Raw samples point to these named implementations and application work:

| Case | Large LLVM leading symbols | Large QBE leading symbols |
|---|---|---|
| sort_int | myl_native_list_sort, batch_result, fold | sort_i64, batch_result/fold hashed bodies |
| sort_records | batch_result, generated list append, keyed_sort_words | batch_result hashed body, generated list append, keyed_sort_words |
| alloc_retained | batch_result, myl_rc_storage_alloc, drain_fast | batch_result hashed body, myl_rc_storage_alloc, drain_fast |
| mutate_nested | transfer_pointer, registered-edge release, finish_clones | transfer_pointer, finish_clones, registered-edge release |

The original rules left private sort and transfer names unclassified. A separate
source-attribution reprocessing records new rule/classifier hashes and the exact
main native_collections.c, native_rc_transfer.c and native_rc_walk.c source
hashes supporting these named implementations. Original reports are unchanged.
The reclassified large sort_int named primitive sample fractions are about81%
LLVM and65%QBE; nested transfer/clone/release fractions are about79%each. These
are observed, whole-process hotspot fractions with throttle records, not kernel
cost shares, causal allocation costs or CPU coverage.

All 16 raw hardware captures contain active cpu_core counts and inactive
cpu_atom rows. Separate PMU reprocessing retains every row and selects CPU2's
PMU from its explicit sysfs membership, read after capture. Selected counters
are available; they include setup/teardown and do not constitute benchmark
timings. The archive preserves raw perf data, samples, records, counter TSV,
original reports and both reprocessing results.

Final-source captures, changed sorting distributions, empty inputs and distinct
alias shapes still require their own evidence. No sort threshold was changed
on the basis of these profiles. Final unseen-seed/non-power-of-two/larger-set
holdouts use all six arms and preserve the original generators; Unicode/error/
alias shape coverage must cite separately identified semantic fixtures.
