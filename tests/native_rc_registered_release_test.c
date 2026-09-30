/* RC-REGISTERED-RELEASE-1: canonical collection descriptors keep the public
 * source admission boundary and the original O/H traversal and drain order. */
#include "native_rc_collections.h"
#include "native_rc_internal.h"
#include <assert.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

typedef struct {
    myl_native_type types[4];
    myl_native_field native_fields[3];
    myl_rc_shape sources[4];
    myl_rc_field source_fields[3];
    myl_rc_shape_entry entries[4];
    myl_rc_field image_fields[3];
} ReleaseGraph;
typedef struct {
    const myl_rc_shape *roots[4];
    const myl_rc_shape_entry *entries[4];
    myl_rc_descriptor descriptors[4];
    myl_rc_binding bindings[4];
    myl_rc_module module;
    myl_rc_image image;
} ReleaseRegistration;
static void start(myl_native_heap *heap) {
    myl_native_heap_init(heap,64u<<20);
    if (!heap->rc) assert(myl_rc_storage_init(heap)==MYL_RC_OK);
}
static void finish(myl_native_heap *heap) {
    assert(!heap->objects_live && !heap->rc->walk.depth && !heap->rc->dead.head);
    myl_native_heap_destroy(heap);
    assert(!heap->bytes);
}
static void prepare(ReleaseGraph *graph, ReleaseRegistration *data, int held) {
    memset(graph,0,sizeof *graph);
    memset(data,0,sizeof *data);
    for (unsigned i=0;i<4;++i) {
        graph->types[i]=(myl_native_type){.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
        graph->sources[i]=(myl_rc_shape){.size=sizeof(void *),.kind=held?MYL_RC_SHAPE_HOLD_POINTER:MYL_RC_SHAPE_POINTER};
        if (i) {
            graph->native_fields[i-1]=(myl_native_field){.type=&graph->types[i-1]};
            graph->types[i].kind=MYL_NATIVE_RECORD;
            graph->types[i].fields=&graph->native_fields[i-1];
            graph->types[i].field_count=1;
            graph->source_fields[i-1]=(myl_rc_field){.shape=&graph->sources[i-1]};
            graph->sources[i].kind=MYL_RC_SHAPE_RECORD;
            graph->sources[i].as.record.fields=&graph->source_fields[i-1];
            graph->sources[i].as.record.count=1;
        }
        graph->entries[i]=(myl_rc_shape_entry){.source=&graph->sources[i],.shape=graph->sources[i],.depth=i+1,.inline_depth=i+1};
        if (i) {
            graph->image_fields[i-1]=(myl_rc_field){.shape=&graph->entries[i-1].shape};
            graph->entries[i].shape.as.record.fields=&graph->image_fields[i-1];
        }
        data->roots[i]=&graph->sources[i];
        data->entries[i]=&graph->entries[i];
        data->descriptors[i]=(myl_rc_descriptor){.type=&graph->types[i],.shape=&graph->sources[i]};
        data->bindings[i].descriptor=(myl_rc_descriptor){.type=&graph->types[i],.shape=&graph->entries[i].shape};
        data->bindings[i].flat=(myl_rc_flat){.count=held?MYL_RC_FLAT_LEAVES+1:1,.size=sizeof(void *)};
        if (!held) {
            data->bindings[i].flat.loanable=1;
            data->bindings[i].flat.arm_offset=MYL_RC_FLAT_ALWAYS;
            data->bindings[i].flat.all=data->bindings[i].flat.always=1;
            for (unsigned tag=0;tag<MYL_RC_FLAT_ARMS;++tag) data->bindings[i].flat.arms[tag]=1;
        }
    }
    data->module=(myl_rc_module){.abi=MYL_RC_ABI_VERSION,.shapes=data->roots,.shape_count=4,
        .descriptors=data->descriptors,.descriptor_count=4};
    data->image=(myl_rc_image){.abi=MYL_RC_IMAGE_ABI_VERSION,.shapes=data->entries,.shape_count=4,
        .bindings=data->bindings,.descriptor_count=4,.depth=4};
}
static void release_alias(myl_native_heap *heap, const myl_rc_shape *shape, void *child, int held) {
    if (held) {
        myl_rc_hold token={0};
        assert(myl_rc_hold_acquire(heap,child,&token)==MYL_RC_OK);
    } else assert(myl_rc_owner_acquire(heap,child)==MYL_RC_OK);
    void *slot=child;
    myl_rc_edges_release(heap,shape,&slot,1);
    assert(!slot && ((myl_rc_object *)child-1)->owners==1 && !((myl_rc_object *)child-1)->holds);
}
static void registered_list(int image, unsigned depth, int held) {
    ReleaseGraph graph;
    ReleaseRegistration data;
    prepare(&graph,&data,held);
    myl_native_heap heap;start(&heap);
    assert((image?myl_rc_module_register_image(&heap,&data.module,&data.image):
        myl_rc_module_register(&heap,&data.module))==MYL_RC_OK);
    const myl_native_type *type=&graph.types[depth-1];
    const myl_rc_binding *binding=myl_rc_binding_find(&heap,type);
    const myl_rc_shape *canonical=binding->descriptor.shape;
    assert(canonical!=&graph.sources[depth-1] && myl_rc_registered_depth(canonical)==depth);
    assert(myl_rc_shape_resolve(&heap,&graph.sources[depth-1])==canonical);
    assert(myl_rc_shape_resolve(&heap,canonical)==canonical);
    assert(!image || canonical==&graph.entries[depth-1].shape);
    void *child=myl_rc_storage_bytes(&heap,8,0);assert(child);
    release_alias(&heap,&graph.sources[depth-1],child,held);
    release_alias(&heap,canonical,child,held);
    myl_rc_registered_edges_release(&heap,canonical,NULL,0);
    myl_native_list *list=myl_native_list_new(&heap,type,2);assert(list);
    assert(myl_rc_list_append(&heap,list,&child) && myl_rc_list_append(&heap,list,&child));
    myl_rc_object *object=(myl_rc_object *)child-1;
    assert(object->owners==(held?1u:3u) && object->holds==(held?2u:0u));
    /* Dynamic registration owns its copied graph after source fields vanish;
     * image graphs remain borrowed and immutable until heap destruction. */
    if (!image) memset(graph.sources,0,sizeof graph.sources);
    assert(myl_rc_list_clear(&heap,list) && !list->length && list->generation==3);
    assert(!((void **)list->storage)[0] && !((void **)list->storage)[1]);
    assert(object->owners==1 && !object->holds && binding->descriptor.shape==canonical);
    myl_rc_owner_release(&heap,child);
    myl_rc_owner_release(&heap,list);
    finish(&heap);
}
typedef struct {
    myl_rc_module module;
    myl_rc_descriptor descriptors[40];
    myl_native_type types[40];
    myl_rc_shape shape;
    myl_native_list *list;
    unsigned callbacks;
} RegisteringRelease;
static void registering_finalize(myl_native_heap *heap, void *payload) {
    RegisteringRelease *data=*(RegisteringRelease **)payload;
    assert(!heap->rc->walk.depth && heap->rc->dead.active && !data->list->length);
    assert(!((void **)data->list->storage)[0] && !((void **)data->list->storage)[1]);
    assert(myl_rc_module_register(heap,&data->module)==MYL_RC_OK);
    ++data->callbacks;
}
static void registered_after_callback(void) {
    RegisteringRelease data={.shape={.size=8,.kind=MYL_RC_SHAPE_POINTER}};
    for (unsigned i=0;i<40;++i) {
        data.types[i]=(myl_native_type){.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER};
        data.descriptors[i]=(myl_rc_descriptor){.type=&data.types[i],.shape=&data.shape};
    }
    data.module=(myl_rc_module){.abi=MYL_RC_ABI_VERSION,.descriptors=data.descriptors,.descriptor_count=40};
    const myl_native_type pointer={.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER};
    const myl_native_type finalized={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_PLAIN};
    const myl_rc_shape none={.size=sizeof(void *),.kind=MYL_RC_SHAPE_NONE};
    const myl_rc_descriptor descriptor={.type=&finalized,.shape=&none,.finalize=registering_finalize};
    myl_native_heap heap;start(&heap);
    assert(myl_rc_descriptor_import(&heap,&descriptor)==MYL_RC_OK);
    data.list=myl_native_list_new(&heap,&pointer,2);assert(data.list);
    const myl_rc_binding *binding=myl_rc_binding_find(&heap,&pointer);
    const myl_rc_shape *canonical=binding->descriptor.shape;
    for (unsigned round=0;round<2;++round) {
        RegisteringRelease **child=myl_native_heap_alloc(&heap,&finalized,1);assert(child);
        *child=&data;
        assert(myl_rc_list_append(&heap,data.list,&child) && myl_rc_list_append(&heap,data.list,&child));
        myl_rc_owner_release(&heap,child);
        assert(myl_rc_list_clear(&heap,data.list) && data.callbacks==round+1);
        assert(myl_rc_binding_find(&heap,&pointer)==binding && binding->descriptor.shape==canonical);
        assert(myl_rc_shape_resolve(&heap,canonical)==canonical && myl_rc_binding_find(&heap,&data.types[39]));
    }
    myl_rc_owner_release(&heap,data.list);
    finish(&heap);
}
static void refusal(unsigned kind) {
    myl_native_heap heap;start(&heap);
    const myl_rc_shape source={.size=sizeof(void *),.kind=MYL_RC_SHAPE_POINTER};
    const myl_rc_shape *canonical=NULL;
    assert(myl_rc_shape_import(&heap,&source,&canonical)==MYL_RC_OK);
    pid_t child=fork();assert(child>=0);
    if (!child) {
        struct rlimit no_core={0,0};assert(!setrlimit(RLIMIT_CORE,&no_core));
        void *slot=NULL;
        if (kind==0) {
            const myl_rc_shape unknown=source;
            myl_rc_edges_release(&heap,&unknown,&slot,1);
        } else if (kind==1) myl_rc_edges_release(NULL,&source,&slot,1);
        else if (kind==2) myl_rc_registered_edges_release(&heap,canonical,NULL,1);
        else if (kind==3) myl_rc_registered_edges_release(&heap,canonical,&slot,SIZE_MAX);
        else if (kind==4) {
            heap.rc->walk.depth=1;
            myl_rc_registered_edges_release(&heap,canonical,&slot,1);
        } else myl_rc_registered_edges_release(&heap,NULL,&slot,1);
        _exit(0);
    }
    int status=0;
    assert(waitpid(child,&status,0)==child && WIFSIGNALED(status) && WTERMSIG(status)==SIGABRT);
    finish(&heap);
}
int myl_rc_registered_release_verify(void) {
    registered_list(0,1,0);
    registered_list(0,2,0);
    registered_list(0,4,1);
    registered_list(1,1,0);
    registered_list(1,2,1);
    registered_list(1,4,1);
    registered_after_callback();
    for (unsigned kind=0;kind<6;++kind) refusal(kind);
    return 13;
}
#ifndef MYL_RC_COLLECTIONS_LIBRARY
int main(void) {
    assert(myl_rc_registered_release_verify()==13);
    puts("native RC registered release: 13 passed");
    return 0;
}
#endif
