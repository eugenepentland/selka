/* Untimed diagnostic: count generic publication calls over unrelated scalar
 * keys and payload-free sets. This is not a runtime benchmark fixture. */
#include "native_rc_internal.h"
#include "native_rc_values.h"
#include "native_dictionary.h"
#include <assert.h>
#include <stdio.h>

static const myl_native_type word={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type unit={.size=0,.alignment=1,.kind=MYL_NATIVE_PLAIN};
static size_t transactions, replacements;
myl_rc_status __real_myl_rc_value_retain_many(myl_native_heap *, myl_rc_slot *, const myl_rc_slot *, size_t);
myl_rc_status __wrap_myl_rc_value_retain_many(myl_native_heap *heap, myl_rc_slot *targets,
                                            const myl_rc_slot *sources, size_t count) {
    transactions++;
    return __real_myl_rc_value_retain_many(heap,targets,sources,count);
}
int __real_myl_rc_native_retain_replace(myl_native_heap *, const myl_native_type *, void *, const void *, unsigned);
int __wrap_myl_rc_native_retain_replace(myl_native_heap *heap, const myl_native_type *type,
                                      void *target, const void *source, unsigned region) {
    replacements++;
    return __real_myl_rc_native_retain_replace(heap,type,target,source,region);
}
int main(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,64u<<20);
    if (!myl_rc_enabled(&heap)) assert(myl_rc_storage_init(&heap)==MYL_RC_OK);
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&word,&word,0);
    myl_native_dictionary *set=myl_native_dictionary_new(&heap,&word,&unit,0);
    assert(dict && set);
    transactions=0;
    for (uint64_t i=0;i<512;i++) {
        uint64_t key=i*0x9e3779b97f4a7c15, value=i+5;
        assert(myl_native_dictionary_write(&heap,dict,&key,&value));
    }
    size_t insertions=transactions;
    transactions=0;
    uint64_t nothing=0;
    for (uint64_t i=0;i<128;i++) assert(myl_native_dictionary_write(&heap,set,&i,&nothing));
    size_t set_insertions=transactions;
    transactions=0; replacements=0;
    for (uint64_t i=0;i<4096;i++) {
        uint64_t key=i%128;
        assert(myl_native_dictionary_write(&heap,set,&key,&nothing));
    }
    size_t duplicates=transactions;
    size_t duplicate_replacements=replacements;
    transactions=0; replacements=0;
    uint64_t checksum=0;
    for (uint64_t i=0;i<4096;i++) {
        uint64_t key=(i%512)*0x9e3779b97f4a7c15, value=0;
        assert(myl_native_dictionary_read(dict,&key,&value));
        value+=1;
        assert(myl_native_dictionary_write(&heap,dict,&key,&value));
        checksum+=value;
    }
    printf("{\"scalar_insert_transactions\":%zu,\"set_insert_transactions\":%zu,"
           "\"set_duplicate_transactions\":%zu,\"get_update_transactions\":%zu,"
           "\"set_duplicate_replacements\":%zu,\"get_update_replacements\":%zu,"
           "\"checksum\":%llu,\"allocations\":%zu,\"bytes\":%zu}\n",
           insertions,set_insertions,duplicates,transactions,duplicate_replacements,replacements,
           (unsigned long long)checksum,
           heap.allocations,heap.bytes);
    myl_rc_owner_release(&heap,set);
    myl_rc_owner_release(&heap,dict);
    assert(!heap.objects_live);
    myl_native_heap_destroy(&heap);
    assert(!heap.bytes);
}
