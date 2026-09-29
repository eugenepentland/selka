/* Generated registration images borrow immutable semantic graphs, while every
 * mutable binding/index/frame and its failure rollback remains heap-private. */
#include "native_rc_alloc.h"
#include "native_rc_internal.h"
#include "native_rc_values.h"
#include <assert.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

_Static_assert(offsetof(myl_native_heap, rc)==5640,"image admission preserves heap.rc ABI");
_Static_assert(offsetof(myl_rc_state, metadata.bytes)==48,"image admission preserves metadata charge ABI");
_Static_assert(offsetof(myl_rc_state, scopes)==248,"image admission preserves scope ABI");
_Static_assert(offsetof(myl_rc_state, spare.entries)==256,"image admission preserves spare node ABI");
_Static_assert(offsetof(myl_rc_state, spare.count)==264,"image admission preserves spare count ABI");
_Static_assert(offsetof(myl_rc_state, dead.head)==200,"image admission preserves pending queue ABI");

static const myl_native_type old_type = {.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER,.rc_id=MYL_RC_ID_FIRST_GENERATED};
static const myl_rc_shape old_shape = {.size=8,.kind=MYL_RC_SHAPE_POINTER};
static const myl_rc_descriptor old_descriptor = {.type=&old_type,.shape=&old_shape};
static const myl_rc_module old_module = {.abi=MYL_RC_ABI_VERSION,.descriptors=&old_descriptor,.descriptor_count=1};
#define IMAGE_COUNT 40
/* Initialized once before each test heap; the graph is immutable until every
 * such heap is destroyed. It deliberately contains dense/colliding/id-free
 * bindings and independent source/registered graphs. */
typedef struct {
    myl_native_type types[IMAGE_COUNT];
    myl_native_field native_fields[3];
    myl_rc_shape sources[IMAGE_COUNT];
    myl_rc_field source_fields[3], image_fields[3];
    myl_rc_shape_entry entries[IMAGE_COUNT];
    const myl_rc_shape_entry *entries_list[IMAGE_COUNT];
    const myl_rc_shape *sources_list[IMAGE_COUNT];
    myl_rc_descriptor descriptors[IMAGE_COUNT];
    myl_rc_binding bindings[IMAGE_COUNT];
    myl_rc_module module;
    myl_rc_image image;
} TestImage;
static void prepare(TestImage *data) {
    memset(data,0,sizeof *data);
    for (unsigned i=0;i<IMAGE_COUNT;++i) {
        data->types[i]=(myl_native_type){.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER,
            .rc_id=i<20 ? MYL_RC_ID_FIRST_GENERATED+i : 0};
        data->sources[i]=(myl_rc_shape){.size=8,.kind=MYL_RC_SHAPE_POINTER};
        data->entries[i]=(myl_rc_shape_entry){.source=&data->sources[i],.shape=data->sources[i],.depth=1,.inline_depth=1};
        data->sources_list[i]=&data->sources[i];
        data->entries_list[i]=&data->entries[i];
        data->descriptors[i]=(myl_rc_descriptor){.type=&data->types[i],.shape=&data->sources[i]};
        data->bindings[i].descriptor=(myl_rc_descriptor){.type=&data->types[i],.shape=&data->entries[i].shape};
        data->bindings[i].flat=(myl_rc_flat){.count=1,.loanable=1,.size=8,.arm_offset=MYL_RC_FLAT_ALWAYS,.all=1,.always=1};
        for (unsigned tag=0;tag<MYL_RC_FLAT_ARMS;++tag) data->bindings[i].flat.arms[tag]=1;
    }
    for (unsigned i=0;i<3;++i) {
        unsigned at=IMAGE_COUNT-3+i;
        data->native_fields[i]=(myl_native_field){.type=&data->types[at-1]};
        data->types[at].kind=MYL_NATIVE_RECORD;
        data->types[at].fields=&data->native_fields[i];
        data->types[at].field_count=1;
        data->source_fields[i]=(myl_rc_field){.shape=&data->sources[at-1]};
        data->image_fields[i]=(myl_rc_field){.shape=&data->entries[at-1].shape};
        data->sources[at].kind=MYL_RC_SHAPE_RECORD;
        data->sources[at].as.record.fields=&data->source_fields[i];
        data->sources[at].as.record.count=1;
        data->entries[at].shape=data->sources[at];
        data->entries[at].shape.as.record.fields=&data->image_fields[i];
        data->entries[at].depth=data->entries[at].inline_depth=i+2;
    }
    data->types[20].rc_id=MYL_RC_ID_FIRST_GENERATED+3;
    data->types[21].rc_id=1u<<30;
    data->module=(myl_rc_module){.abi=MYL_RC_ABI_VERSION,.shapes=data->sources_list,.shape_count=IMAGE_COUNT,
        .descriptors=data->descriptors,.descriptor_count=IMAGE_COUNT};
    data->image=(myl_rc_image){.abi=MYL_RC_IMAGE_ABI_VERSION,.shapes=data->entries_list,.shape_count=IMAGE_COUNT,
        .bindings=data->bindings,.descriptor_count=IMAGE_COUNT,.depth=4};
}
static void start(myl_native_heap *heap) {
    myl_native_heap_init(heap,64u<<20);
    if (!heap->rc) assert(myl_rc_storage_init(heap)==MYL_RC_OK);
    assert(myl_rc_module_register(heap,&old_module)==MYL_RC_OK);
    assert(myl_rc_descriptor_find(heap,&old_type));
}
static void finish(myl_native_heap *heap) {
    assert(!heap->objects_live);
    myl_native_heap_destroy(heap);
    assert(!heap->bytes);
}
// spec-case: RC-STARTUP-IMAGE-1
static void image_operations(void) {
    TestImage data;
    prepare(&data);
    myl_native_heap a,b;
    start(&a);start(&b);
    b.rc->metadata.ids.entries[MYL_RC_ID_FIRST_GENERATED].key=NULL;
    const void *pending=b.rc->metadata.ids.entries[MYL_RC_ID_FIRST_GENERATED].value;
    myl_rc_image original=data.image;
    myl_rc_binding immutable[IMAGE_COUNT];
    memcpy(immutable,data.bindings,sizeof immutable);
    assert(myl_rc_module_register_image(&a,&data.module,&data.image)==MYL_RC_OK);
    assert(myl_rc_module_register_image(&b,&data.module,&data.image)==MYL_RC_OK);
    assert(!b.rc->metadata.ids.entries[MYL_RC_ID_FIRST_GENERATED].key &&
        b.rc->metadata.ids.entries[MYL_RC_ID_FIRST_GENERATED].value==pending);
    assert(myl_rc_descriptor_find(&b,&old_type) && b.rc->metadata.ids.entries[MYL_RC_ID_FIRST_GENERATED].key==&old_type);
    assert(myl_rc_reserved_depth(&a)==4 && myl_rc_reserved_depth(&b)==4);
    size_t stable=a.bytes;
    assert(myl_rc_module_register_image(&a,&data.module,&data.image)==MYL_RC_OK && a.bytes==stable);
    assert(myl_rc_module_register(&a,&data.module)==MYL_RC_OK && a.bytes==stable);
    for (unsigned i=0;i<IMAGE_COUNT;++i) {
        assert(myl_rc_shape_resolve(&a,&data.sources[i])==&data.entries[i].shape);
        assert(myl_rc_shape_resolve(&a,&data.entries[i].shape)==&data.entries[i].shape);
        const myl_rc_binding *left=myl_rc_binding_find(&a,&data.types[i]), *right=myl_rc_binding_find(&b,&data.types[i]);
        assert(left && right && left!=right && left!=&data.bindings[i] && left->flat.count==1);
        if (i && i<20) assert(a.rc->metadata.ids.entries[data.types[i].rc_id].key==&data.types[i]);
    }
    /* A conflicting id preserves the old identity and uses the hash fallback;
     * unsorted/id-free bindings are valid and already have their image plan. */
    assert(a.rc->metadata.ids.entries[MYL_RC_ID_FIRST_GENERATED].key==&old_type);
    assert(myl_rc_map_get(&a.rc->metadata.bindings,&data.types[0])==myl_rc_binding_find(&a,&data.types[0]));
    assert(myl_rc_map_get(&a.rc->metadata.bindings,&data.types[20]));
    void *child=myl_rc_storage_bytes(&a,8,0), *source=child, *copy=NULL;
    assert(child && myl_rc_native_copy(&a,&data.types[39],&copy,&source,0));
    assert(copy==child && ((myl_rc_object *)child-1)->owners==2);
    myl_rc_native_drop(&a,&data.types[39],&copy);
    assert(!copy && ((myl_rc_object *)child-1)->owners==1);
    void **body=myl_native_heap_alloc(&a,&data.types[39],1);assert(body);
    *body=child;
    assert(myl_rc_binding_find(&a,&data.types[39])->alloc_class &&
        !myl_rc_binding_find(&b,&data.types[39])->alloc_class && !data.bindings[39].alloc_class);
    myl_rc_owner_release(&a,body);
    /* Unknown types stay unknown. Temporary imports keep their copied graph
     * and a computed plan after the caller overwrites the source metadata. */
    myl_native_type dynamic={.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER,.rc_id=1u<<30};
    myl_rc_shape temporary={.size=8,.kind=MYL_RC_SHAPE_HOLD_POINTER};
    myl_rc_descriptor imported={.type=&dynamic,.shape=&temporary};
    assert(!myl_rc_binding_find(&a,&dynamic));
    assert(myl_rc_descriptor_import(&a,&imported)==MYL_RC_OK);
    const myl_rc_binding *binding=myl_rc_binding_find(&a,&dynamic);
    assert(binding && binding->descriptor.shape!=&temporary && binding->flat.count>MYL_RC_FLAT_LEAVES);
    memset(&temporary,0,sizeof temporary);
    assert(binding->descriptor.shape->kind==MYL_RC_SHAPE_HOLD_POINTER && binding->descriptor.shape->size==8);
    assert(!memcmp(&original,&data.image,sizeof original) && !memcmp(immutable,data.bindings,sizeof immutable));
    finish(&a);finish(&b);
}
typedef struct { myl_native_resource base; void **slot; unsigned closed; } ImageUnique;
static void image_unique_close(myl_native_resource *base) {
    ImageUnique *resource=(ImageUnique *)base;
    assert(!*resource->slot);++resource->closed;
}
// spec-case: RC-STARTUP-IMAGE-1
static void image_unique_depth(void) {
    myl_native_type types[3]={{.size=8,.alignment=8,.kind=MYL_NATIVE_RESOURCE}};
    myl_native_field native_fields[2]={{.type=&types[0]},{.type=&types[1]}};
    myl_rc_shape sources[3]={{.size=8,.kind=MYL_RC_SHAPE_NONE}};
    myl_rc_field source_fields[2]={{.shape=&sources[0]},{.shape=&sources[1]}};
    myl_rc_shape_entry entries[3]={0};
    myl_rc_field image_fields[2]={{.shape=&entries[0].shape},{.shape=&entries[1].shape}};
    const myl_rc_shape *roots[3]={&sources[0],&sources[1],&sources[2]};
    const myl_rc_shape_entry *image_roots[3]={&entries[0],&entries[1],&entries[2]};
    for (unsigned i=1;i<3;++i) {
        types[i]=(myl_native_type){.size=8,.alignment=8,.kind=MYL_NATIVE_RECORD,.fields=&native_fields[i-1],.field_count=1};
        sources[i]=(myl_rc_shape){.size=8,.kind=MYL_RC_SHAPE_RECORD,.as.record={&source_fields[i-1],1}};
    }
    for (unsigned i=0;i<3;++i) {
        entries[i]=(myl_rc_shape_entry){.source=&sources[i],.shape=sources[i],.inline_depth=i+1};
        entries[i].shape.kind=MYL_RC_SHAPE_NONE;
        if (i) entries[i].shape.as.record.fields=&image_fields[i-1];
    }
    const myl_rc_descriptor descriptor={.type=&types[2],.shape=&sources[2],.finalize=myl_rc_finalize_unique};
    const myl_rc_binding binding={.descriptor={.type=&types[2],.shape=&entries[2].shape,.finalize=myl_rc_finalize_unique},
        .flat={.count=MYL_RC_FLAT_LEAVES+1,.size=8}};
    const myl_rc_module module={.abi=MYL_RC_ABI_VERSION,.shapes=roots,.shape_count=3,.descriptors=&descriptor,.descriptor_count=1};
    const myl_rc_image image={.abi=MYL_RC_IMAGE_ABI_VERSION,.shapes=image_roots,.shape_count=3,
        .bindings=&binding,.descriptor_count=1,.depth=3};
    myl_native_heap heap;start(&heap);
    assert(myl_rc_module_register_image(&heap,&module,&image)==MYL_RC_OK && myl_rc_reserved_depth(&heap)==3);
    assert(!myl_rc_registered_depth(&entries[2].shape) && entries[2].inline_depth==3);
    /* Dynamic parents around a collapsed image shape retain its independent
     * resource traversal depth rather than rebuilding a depth-one NONE leaf. */
    const myl_rc_field outer_field={.shape=&entries[2].shape};
    const myl_rc_shape outer={.size=8,.kind=MYL_RC_SHAPE_RECORD,.as.record={&outer_field,1}};
    const myl_rc_shape *imported=NULL;
    assert(myl_rc_shape_import(&heap,&outer,&imported)==MYL_RC_OK && imported->kind==MYL_RC_SHAPE_NONE);
    assert(myl_rc_reserved_depth(&heap)==4);
    void **body=myl_native_heap_alloc(&heap,&types[2],1);assert(body);
    ImageUnique resource={.base={.drop=image_unique_close},.slot=body};*body=&resource;
    heap.limit=heap.bytes;
    myl_rc_owner_release(&heap,body);
    assert(resource.closed==1);
    finish(&heap);
}
// spec-case: RC-STARTUP-IMAGE-1
static void invalid_image(unsigned fault) {
    pid_t child=fork();assert(child>=0);
    if (!child) {
        struct rlimit none={0,0};assert(!setrlimit(RLIMIT_CORE,&none));
        TestImage data;prepare(&data);
        myl_native_heap heap;start(&heap);
        switch (fault) {
            case 0:data.image.abi++;break;
            case 1:data.image.descriptor_count--;break;
            case 2:data.image.shape_count--;break;
            case 3:data.entries[0].shape.size++;break;
            case 4:data.image.depth--;break;
            case 5:data.entries[39].depth=1;break;
            case 6:data.bindings[0].flat.count=18;break;
            case 7:data.bindings[0].flat.offsets[0]=8;break;
            case 8:data.bindings[0].flat.arms[0]=3;break;
            case 9:data.image_fields[2].shape=&data.entries[39].shape;break;
            case 10:data.bindings[0].descriptor.type=&old_type;break;
            case 11:data.descriptors[1].type=data.bindings[1].descriptor.type=&data.types[0];break;
            default:assert(0);
        }
        (void)myl_rc_module_register_image(&heap,&data.module,&data.image);
        _exit(0);
    }
    int status=0;pid_t finished;
    do {finished=waitpid(child,&status,0);} while (finished<0 && errno==EINTR);
    assert(finished==child && WIFSIGNALED(status) && WTERMSIG(status)==SIGABRT);
}
static void filled_start(myl_native_heap *heap,myl_rc_module modules[16]) {
    static const myl_rc_shape *const roots[]={&old_shape};
    start(heap);
    size_t index=0;
    while (heap->rc->metadata.modules.count<16) {
        assert(index<16);
        modules[index]=(myl_rc_module){.abi=MYL_RC_ABI_VERSION,.shapes=roots,.shape_count=1};
        assert(myl_rc_module_register(heap,&modules[index++])==MYL_RC_OK);
    }
}
static void unchanged(myl_native_heap *heap,const myl_rc_state *before,size_t bytes) {
    assert(heap->bytes==bytes && heap->rc->metadata.bytes==before->metadata.bytes &&
        heap->rc->metadata.batches==before->metadata.batches);
    assert(!memcmp(&heap->rc->metadata.modules,&before->metadata.modules,sizeof before->metadata.modules));
    assert(!memcmp(&heap->rc->metadata.shapes,&before->metadata.shapes,sizeof before->metadata.shapes));
    assert(!memcmp(&heap->rc->metadata.bindings,&before->metadata.bindings,sizeof before->metadata.bindings));
    assert(!memcmp(&heap->rc->metadata.ids,&before->metadata.ids,sizeof before->metadata.ids));
    assert(!memcmp(&heap->rc->walk,&before->walk,sizeof before->walk));
    assert(myl_rc_descriptor_find(heap,&old_type) && myl_rc_shape_resolve(heap,&old_shape));
}
// spec-case: RC-STARTUP-IMAGE-1
static void budget_rollback(void) {
    TestImage data;prepare(&data);
    myl_native_heap heap;
    myl_rc_module modules[16];filled_start(&heap,modules);
    void *child=myl_rc_storage_bytes(&heap,8,0);assert(child);
    myl_rc_state before=*heap.rc;size_t bytes=heap.bytes;
    heap.limit=bytes;
    assert(myl_rc_module_register_image(&heap,&data.module,&data.image)==MYL_RC_ALLOCATION_REFUSED);
    unchanged(&heap,&before,bytes);
    assert(!myl_rc_binding_find(&heap,&data.types[0]) && !myl_rc_shape_resolve(&heap,&data.sources[0]));
    heap.limit=64u<<20;heap.exhausted=0;
    assert(myl_rc_module_register_image(&heap,&data.module,&data.image)==MYL_RC_OK);
    myl_rc_owner_release(&heap,child);finish(&heap);
}
#ifdef MYL_RC_IMAGE_FAIL_TEST
/* Fault the actual host calloc calls in the image transaction only. The unit
 * root also executes all ordinary image, budget and invalid-metadata cases. */
void *__real_calloc(size_t,size_t);
static size_t allocation_count,fail_at,allocated[16];
static int armed;
void *__wrap_calloc(size_t count,size_t bytes) {
    if (armed) {
        assert(allocation_count<16);
        allocated[allocation_count++]=count*bytes;
        if (allocation_count==fail_at) return NULL;
    }
    return __real_calloc(count,bytes);
}
// spec-case: RC-STARTUP-IMAGE-1
static void all_allocation_failures(void) {
    TestImage data;prepare(&data);
    size_t total=0,trace[16]={0};
    for (size_t fault=1;fault<=16;++fault) {
        myl_native_heap heap;myl_rc_module modules[16];filled_start(&heap,modules);
        void *child=myl_rc_storage_bytes(&heap,8,0);assert(child);
        myl_rc_state before=*heap.rc;size_t bytes=heap.bytes;
        allocation_count=0;fail_at=fault;armed=1;
        myl_rc_status status=myl_rc_module_register_image(&heap,&data.module,&data.image);
        armed=0;
        if (status==MYL_RC_OK) {
            total=allocation_count;assert(total+1==fault && total==6);
            memcpy(trace,allocated,total*sizeof *trace);
            myl_rc_owner_release(&heap,child);finish(&heap);break;
        }
        assert(status==MYL_RC_ALLOCATION_REFUSED && allocation_count==fault);
        unchanged(&heap,&before,bytes);
        assert(!myl_rc_binding_find(&heap,&data.types[0]) && !myl_rc_shape_resolve(&heap,&data.sources[0]));
        myl_rc_owner_release(&heap,child);finish(&heap);
    }
    assert(total==6);
    size_t cumulative=0;
    for (size_t stage=0;stage<total;++stage) {
        cumulative+=trace[stage];
        myl_native_heap heap;myl_rc_module modules[16];filled_start(&heap,modules);
        void *child=myl_rc_storage_bytes(&heap,8,0);assert(child);
        myl_rc_state before=*heap.rc;size_t bytes=heap.bytes;
        heap.limit=bytes+cumulative-1;
        allocation_count=0;fail_at=0;armed=1;
        assert(myl_rc_module_register_image(&heap,&data.module,&data.image)==MYL_RC_ALLOCATION_REFUSED);
        armed=0;
        assert(heap.exhausted && allocation_count==stage);
        unchanged(&heap,&before,bytes);
        myl_rc_owner_release(&heap,child);finish(&heap);
    }
    puts("native RC image: all6 host allocation and6 budget admission failures preserve old state");
}
#endif
int myl_rc_image_verify(void) {
    image_operations();image_unique_depth();budget_rollback();
    for (unsigned fault=0;fault<12;++fault) invalid_image(fault);
    return 15;
}
#ifndef MYL_RC_CONTRACT_LIBRARY
int main(void) {
    assert(myl_rc_image_verify()==15);
#ifdef MYL_RC_IMAGE_FAIL_TEST
    all_allocation_failures();
#endif
    puts("native RC image: 15 contract cases passed");return 0;
}
#endif
