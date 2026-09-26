/* Copied native values and explicit domain conversions share one execution. */
#include "native_text.h"
#include "native_bytes.h"
#include "native_dictionary.h"
#include "native_rc_collections.h"
/* `myl_qbe_heap` returns a pointer. Without this declaration the call is an
   implicit `int` and the heap address is truncated to 32 bits, so every text
   argument or result faulted on a wild pointer; `qbe_bytes.h` includes the same
   header for the same reason. */
#include "qbe_runtime.h"
typedef struct {size_t wire,decode,encode,result,ok,err,error_type;} CoCodec;
typedef struct {const char *name;size_t size,count,stride;unsigned kind;const size_t *children,*offsets;const CoCodec *codec;} CoType;
static const CoType co_types[];
/* The program's own descriptor for each `co_types` entry, so a list the codec
   builds is described to the collector by the same `myl_native_type` the guest
   already uses for its lists. Completed by the generated table below. */
static const myl_native_type *const co_native_types[];
static const MylangWireNode *co_input;
static size_t co_count,co_cursor,co_needed,co_result_type,co_argument_count;
static const size_t *co_parameter_types;
static const unsigned char *co_injected;
static void *co_arguments[QBE_CODEC_ARGUMENTS],*co_return;
static MylangWireNode *co_prepared;
static const char *co_error,*co_domain;
static uint64_t co_calls,co_max_calls;
static int co_rejected;
static void *co_context;
/* The caller's output capacity, compared only by the epilogue. The staging
   path is bounded by the global node cap instead, so a result that does not fit
   still reports its required `node_count` (native_embed.h: OutputTooSmall)
   rather than a bare WireLimit from the middle of the write. */
static size_t co_capacity;
/* Every value the adapter holds across guest code is rooted: reading an argument
   allocates in the managed heap, and the guest call that follows can collect.
   Roots point at static slots, because a root records the address of the value,
   not its bytes. The pool is sized by the argument count plus the nesting bound,
   since a container holds a root at every level while its children are read. */
static const myl_native_type co_pointer_type={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
static void *co_root_values[QBE_CODEC_ROOTS];
static myl_native_root co_root_slots[QBE_CODEC_ROOTS];
static size_t co_root_count;
static int co_bad(const char *code){co_error=code;return 0;}
/* Decode one UTF-8 scalar from `bytes` at `*at`, advancing it past the scalar.
   A guest text's payload is valid UTF-8 by construction, so no truncated or
   overlong sequence can reach this and the length bound only keeps a malformed
   header from reading past the payload. */
static uint32_t co_scalar(const unsigned char *bytes,size_t length,size_t *at){
    unsigned char first=bytes[(*at)++];
    if(first<0x80)return first;
    unsigned width=first>=0xf0?3u:first>=0xe0?2u:1u;
    uint32_t point=first&((1u<<(6-width))-1);
    while(width-- && *at<length)point=(point<<6)|(bytes[(*at)++]&0x3fu);
    return point;
}
static int co_charge(void){if(co_calls==co_max_calls)return co_bad("CodecCallLimit");++co_calls;return 1;}
static int co_method(size_t,void *,const void *,void *);
static int co_write(size_t,const void *,size_t);
static int co_root(void *value){
    if(myl_rc_enabled(myl_qbe_heap(co_context)))return 1;
    if(co_root_count==QBE_CODEC_ROOTS)return 0;
    co_root_values[co_root_count]=value;
    myl_native_root_push(myl_qbe_heap(co_context),&co_root_slots[co_root_count],&co_root_values[co_root_count],&co_pointer_type);
    ++co_root_count;return 1;
}
static int co_root_value(size_t index,void *value){
    if(myl_rc_enabled(myl_qbe_heap(co_context)))return 1;
    if(co_root_count==QBE_CODEC_ROOTS)return co_bad("OutOfMemory");
    myl_native_root_push(myl_qbe_heap(co_context),&co_root_slots[co_root_count],value,co_native_types[index]);
    ++co_root_count;return 1;
}
static void co_unroot_to(size_t mark){
    while(co_root_count>mark){--co_root_count;myl_native_root_pop(myl_qbe_heap(co_context),&co_root_slots[co_root_count]);}
}
/* A value a rooted container now holds is reachable through it, so its own root
   is no longer load-bearing. Releasing it as each element is stored keeps the
   live root count at the nesting depth instead of the element count, which a
   list longer than the root pool would otherwise exhaust. */
static void co_unroot(void){co_unroot_to(0);}
static uint64_t co_word(const void *input,size_t index){
    const CoType *type=&co_types[index];
    while(type->kind==4)type=&co_types[type->children[0]];
    uint64_t bits=0;memcpy(&bits,input,type->size);
    if(*type->name=='i' && type->size<8 && (bits&(UINT64_C(1)<<(type->size*8-1))))bits|=UINT64_MAX<<(type->size*8);
    return bits;
}
/* Codec storage owns complete initialized values. Decoding only writes empty
   slots; failures clear their initialized edges before returning to the parent. */
static void co_drop(size_t index,void *value){
    if(value && myl_rc_enabled(myl_qbe_heap(co_context)))
        myl_rc_native_drop(myl_qbe_heap(co_context),co_native_types[index],value);
}
static void co_abort(void *value){
    if(value && myl_rc_enabled(myl_qbe_heap(co_context)))myl_rc_native_abort(myl_qbe_heap(co_context),value);
}
/* Guest callbacks may leave by longjmp. Keep every temporary host allocation
   in a heap-independent journal so teardown can drop its initialized value
   and free the raw buffer without following a departed C stack frame. */
typedef struct CoTemporary {
    struct CoTemporary *previous;
    size_t type;
    _Alignas(max_align_t) unsigned char value[];
} CoTemporary;
static CoTemporary *co_temporaries;
static void *co_temporary(size_t index,int owned){
    size_t size=co_types[index].size;
    if(size>SIZE_MAX-sizeof(CoTemporary))return NULL;
    CoTemporary *temporary=calloc(1,sizeof *temporary+(size?size:1));
    if(!temporary)return NULL;
    temporary->type=owned?index:SIZE_MAX;
    temporary->previous=co_temporaries;co_temporaries=temporary;
    return temporary->value;
}
static void co_temporary_free(void *value){
    if(!value)return;
    CoTemporary *temporary=(CoTemporary *)((unsigned char *)value - offsetof(CoTemporary,value));
    CoTemporary **link=&co_temporaries;
    while(*link && *link!=temporary)link=&(*link)->previous;
    if(!*link)abort();
    *link=temporary->previous;
    if(temporary->type!=SIZE_MAX)co_drop(temporary->type,value);
    free(temporary);
}
static void co_cleanup(void *ctx){
    co_unroot();
    while(co_temporaries)co_temporary_free(co_temporaries->value);
    co_drop(co_result_type,co_return);
    for(size_t i=co_argument_count;i;i--)
        if(!co_injected || !co_injected[i-1])co_drop(co_parameter_types[i-1],co_arguments[i-1]);
    ((MylQbeContext *)ctx)->adapter_cleanup=NULL;co_context=NULL;
}
static int co_read(size_t,void *,size_t);
static int co_validate_one(void *,size_t,const void *);
/* A dictionary or a set: one key subtree per entry, followed for a dictionary
   (`count` 2) by its value subtree; a set's unit value carries none. The keys
   are hashed and compared by the program's own key descriptor, so any
   hashable key the program can build is carried, and a repeated key is a
   malformed request rather than a silent overwrite. */
static int co_read_dictionary(const CoType *type,const MylangWireNode *node,void *output,size_t depth){
    if(node->bits || node->children>co_count-co_cursor || (type->count!=1 && type->count!=2))return co_bad("InvalidArgument");
    size_t key_index=type->children[0],value_index=type->children[1];
    const CoType *key=&co_types[key_index];
    myl_native_dictionary *dict=myl_native_dictionary_new(myl_qbe_heap(co_context),co_native_types[key_index],co_native_types[value_index],key->kind==5);
    if(!dict)return co_bad("OutOfMemory");
    memcpy(output,&dict,sizeof dict);
    if(!co_root(dict))return co_bad("OutOfMemory");
    void *key_scratch=co_temporary(key_index,1),*value_scratch=co_temporary(value_index,1);
    int ok=key_scratch && value_scratch ? 1 : co_bad("OutOfMemory");
    for(size_t i=0;ok && i<node->children;++i){
        size_t mark=co_root_count;
        ok=co_read(key_index,key_scratch,depth+1) && (type->count==1 || co_read(value_index,value_scratch,depth+1));
        if(ok && myl_native_dictionary_contains(dict,key_scratch))ok=co_bad("InvalidArgument");
        if(ok && !myl_native_dictionary_write(myl_qbe_heap(co_context),dict,key_scratch,value_scratch))ok=co_bad("OutOfMemory");
        co_drop(value_index,value_scratch);co_drop(key_index,key_scratch);
        co_unroot_to(mark);
    }
    co_temporary_free(value_scratch);co_temporary_free(key_scratch);
    return ok;
}
/* A recursive value's box (RECURSIVE-VALUES-3) has no node: the value it
   holds is read from the wire into scratch memory, whose own references are
   rooted as they are read, and only then copied into a fresh box, which takes
   over the root. A box is never written after this, like one the guest built. */
static int co_read_box(size_t index,void *output,size_t depth){
    size_t content_index=co_types[index].children[0];
    const CoType *content=&co_types[content_index];
    size_t mark=co_root_count;
    void *scratch=co_temporary(content_index,1);
    if(!scratch)return co_bad("OutOfMemory");
    if(!co_read(content_index,scratch,depth+1)){co_temporary_free(scratch);return 0;}
    void *box=myl_native_heap_alloc(myl_qbe_heap(co_context),co_native_types[index]->element,1);
    if(box){memcpy(box,scratch,content->size);memset(scratch,0,content->size);} /* Relocate the owned body. */
    co_temporary_free(scratch);
    if(!box)return co_bad("OutOfMemory");
    co_unroot_to(mark);
    if(!co_root(box)){co_abort(box);return co_bad("OutOfMemory");}
    memcpy(output,&box,sizeof box);return 1;
}
static int co_read_inner(size_t,void *,size_t);
static int co_read(size_t index,void *output,size_t depth){
    memset(output,0,co_types[index].size);
    size_t mark=co_root_count;
    int ok=co_read_inner(index,output,depth);
    if(!ok){co_drop(index,output);co_unroot_to(mark);}
    return ok;
}
static int co_read_inner(size_t index,void *output,size_t depth){
    if(depth>=QBE_CODEC_DEPTH)return co_bad("WireLimit");
    if(co_types[index].kind==10)return co_read_box(index,output,depth);
    if(co_cursor>=co_count)return co_bad("InvalidArgument");
    const CoType *type=&co_types[index];const MylangWireNode *node=&co_input[co_cursor++];
    if(!node->type || strcmp(node->type,type->name))return co_bad("InvalidArgument");
    if(type->kind==0){
        if(node->children || !valid_scalar((MylangScalar){node->type,node->bits},type->name))return co_bad("InvalidArgument");
        memcpy(output,&node->bits,type->size);return 1;
    }
    if(type->kind==5){
        /* One node per Unicode scalar, decoded into fresh guest-owned storage.
           The input node count already bounds the request, so the decoded size
           is bounded by it rather than by anything the request claims. The
           scalars are staged on the host and encoded in one pass, because a
           text's payload is UTF-8 and a scalar's width is only known once it has
           been read; a value that is not a Unicode scalar is a malformed
           request, since a text storing one could not be valid UTF-8. */
        if(node->bits || node->children>co_count-co_cursor)return co_bad("InvalidArgument");
        const CoType *element=&co_types[type->children[0]];
        if(element->kind || element->size!=sizeof(uint32_t))return co_bad("InternalError");
        uint32_t *scalars=calloc(node->children?node->children:1,sizeof(uint32_t));
        if(!scalars)return co_bad("OutOfMemory");
        for(size_t i=0;i<node->children;++i){
            const MylangWireNode *child=&co_input[co_cursor++];
            if(!child->type || strcmp(child->type,element->name) || child->children || child->bits>UINT32_MAX){free(scalars);return co_bad("InvalidArgument");}
            scalars[i]=(uint32_t)child->bits;
        }
        myl_native_text *text=myl_native_text_from_scalars(myl_qbe_heap(co_context),scalars,node->children);
        free(scalars);
        if(!text)return co_bad("OutOfMemory");
        if(!co_root(text)){co_abort(text);return co_bad("OutOfMemory");}
        memcpy(output,&text,sizeof text);return 1;
    }
    if(type->kind==6){
        /* One node per element, decoded into fresh guest-owned storage sized by
           the request's own node count, so the length is bounded by the input
           rather than by anything the request claims. */
        if(node->bits || node->children>co_count-co_cursor)return co_bad("InvalidArgument");
        myl_native_list *list=myl_native_list_new(myl_qbe_heap(co_context),co_native_types[type->children[0]],node->children);
        if(!list)return co_bad("OutOfMemory");
        memcpy(output,&list,sizeof list);
        if(!co_root(list))return co_bad("OutOfMemory");
        void *scratch=co_temporary(type->children[0],1);
        if(!scratch)return co_bad("OutOfMemory");
        int ok=1;
        for(size_t i=0;ok && i<node->children;++i){
            size_t mark=co_root_count;
            ok=co_read(type->children[0],scratch,depth+1);
            if(ok && !myl_native_list_append(myl_qbe_heap(co_context),list,scratch))ok=co_bad("OutOfMemory");
            co_drop(type->children[0],scratch);
            co_unroot_to(mark);
        }
        co_temporary_free(scratch);
        return ok;
    }
    if(type->kind==8){
        /* One `u8` node per octet, copied into a fresh guest `bytes`. */
        if(node->bits || node->children>co_count-co_cursor)return co_bad("InvalidArgument");
        const CoType *element=&co_types[type->children[0]];
        unsigned char *raw=calloc(node->children?node->children:1,1);
        if(!raw)return co_bad("OutOfMemory");
        for(size_t i=0;i<node->children;++i){
            const MylangWireNode *child=&co_input[co_cursor++];
            if(!child->type || strcmp(child->type,element->name) || child->children || child->bits>255){free(raw);return co_bad("InvalidArgument");}
            raw[i]=(unsigned char)child->bits;
        }
        myl_native_bytes *bytes=myl_native_bytes_new(myl_qbe_heap(co_context),raw,node->children);
        free(raw);
        if(!bytes)return co_bad("OutOfMemory");
        if(!co_root(bytes)){co_abort(bytes);return co_bad("OutOfMemory");}
        memcpy(output,&bytes,sizeof bytes);return 1;
    }
    if(type->kind==9)return co_read_dictionary(type,node,output,depth);
    if(type->kind==4){
        if(!type->codec || node->bits || node->children!=1)return co_bad("InvalidArgument");
        const CoCodec *codec=type->codec;int ok=0;size_t mark=co_root_count;
        void *wire=co_temporary(codec->wire,1);
        void *result=co_temporary(codec->result,1);
        if(!wire || !result){co_bad("OutOfMemory");goto domain_done;}
        if(!co_read(codec->wire,wire,depth+1))goto domain_done;
        if(!co_root_value(codec->result,result))goto domain_done;
        const char *previous=co_domain;co_domain=type->name;
        if(!co_charge() || !co_method(codec->decode,co_context,wire,result))goto domain_done;
        uint32_t tag;memcpy(&tag,result,4);
        if(tag!=codec->ok && tag!=codec->err){co_bad("InternalError");goto domain_done;}
        const void *payload=(const unsigned char *)result+co_types[codec->result].offsets[tag];
        if(tag==codec->ok){memcpy(output,payload,type->size);memset((void *)payload,0,type->size);co_domain=previous;ok=1;}
        else{co_rejected=1;co_needed=0;if(co_write(codec->error_type,payload,0))co_bad("DomainCodecRejected");}
    domain_done:
        co_unroot_to(mark);
        co_temporary_free(result);co_temporary_free(wire);
        return ok && co_root_value(index,output) && co_validate_one(co_context,index,output);
    }
    if(type->kind==3){
        if(node->bits>=type->count)return co_bad("InvalidArgument");
        uint32_t tag=(uint32_t)node->bits;size_t child=type->children[tag];
        if(node->children!=(child==SIZE_MAX ? 0u : 1u))return co_bad("InvalidArgument");
        memcpy(output,&tag,4);return child==SIZE_MAX || co_read(child,(unsigned char *)output+type->offsets[tag],depth+1);
    }
    if(type->kind==7){
        /* A niche optional has no tag word: `None` is the null reference and
           `Some` is the reference itself, decoded over the same word. */
        if(node->bits>=type->count)return co_bad("InvalidArgument");
        size_t child=type->children[node->bits];
        if(node->children!=(child==SIZE_MAX ? 0u : 1u))return co_bad("InvalidArgument");
        memset(output,0,type->size);return child==SIZE_MAX || co_read(child,output,depth+1);
    }
    if(node->bits || node->children!=type->count)return co_bad("InvalidArgument");
    for(size_t i=0;i<type->count;++i){
        size_t child=type->children[type->kind==2 ? 0:i],offset=type->kind==2 ? i*type->stride:type->offsets[i];
        if(!co_read(child,(unsigned char *)output+offset,depth+1))return 0;
    }
    return co_validate_one(co_context,index,output);
}
/* The entries of a dictionary or a set in insertion order: each key
   subtree, then for a dictionary its value subtree. */
static int co_write_dictionary(const CoType *type,MylangWireNode *node,const void *input,size_t depth){
    const myl_native_dictionary *dict=*(const myl_native_dictionary *const *)input;
    if(!dict)return co_bad("InternalError");
    size_t key_index=type->children[0],value_index=type->children[1];
    size_t length=myl_native_dictionary_length(dict);
    if(length>100000-co_needed)return co_bad("WireLimit");
    node->children=length;
    void *key_scratch=co_temporary(key_index,0);
    void *value_scratch=co_temporary(value_index,0);
    int ok=key_scratch && value_scratch ? 1 : co_bad("OutOfMemory");
    for(size_t i=0;ok && i<length;++i){
        if(!myl_native_dictionary_key_at(dict,i,key_scratch))ok=co_bad("InternalError");
        ok=ok && co_write(key_index,key_scratch,depth+1);
        if(ok && type->count==2)ok=myl_native_dictionary_value_at(dict,i,value_scratch) ? co_write(value_index,value_scratch,depth+1) : co_bad("InternalError");
    }
    co_temporary_free(value_scratch);co_temporary_free(key_scratch);
    return ok;
}
static int co_write(size_t index,const void *input,size_t depth){
    if(depth>=QBE_CODEC_DEPTH || co_needed>=100000)return co_bad("WireLimit");
    if(co_types[index].kind==10){
        /* A box writes the value it holds and no node of its own. */
        const void *box;memcpy(&box,input,sizeof box);
        return box ? co_write(co_types[index].children[0],box,depth+1) : co_bad("InternalError");
    }
    const CoType *type=&co_types[index];MylangWireNode *node=&co_prepared[co_needed++];
    *node=(MylangWireNode){type->name,0,type->count};
    if(type->kind==0){node->bits=co_word(input,index);node->children=0;return 1;}
    if(type->kind==5){
        const myl_native_text *text=*(const myl_native_text *const *)input;
        if(!text)return co_bad("InternalError");
        const CoType *element=&co_types[type->children[0]];
        if(element->kind || element->size!=sizeof(uint32_t))return co_bad("InternalError");
        /* One node per scalar of the guest text, bounded by the staging array
           alone: the caller's capacity is deliberately not consulted here, so a
           result that does not fit is still measured and the epilogue reports
           OutputTooSmall with the required count instead of WireLimit. The
           scalars are decoded from the UTF-8 payload, which is a walk per text
           rather than a per-scalar call into the list machinery. */
        if(text->length>100000-co_needed)return co_bad("WireLimit");
        node->children=text->length;
        const unsigned char *bytes=myl_native_text_storage(text);
        size_t at=0;
        for(size_t i=0;i<text->length;++i){
            uint32_t scalar=(uint32_t)co_scalar(bytes,text->bytes,&at);
            co_prepared[co_needed++]=(MylangWireNode){element->name,scalar,0};
        }
        return 1;
    }
    if(type->kind==6){
        const myl_native_list *list=*(const myl_native_list *const *)input;
        if(!list)return co_bad("InternalError");
        /* Bounded by the staging array alone, exactly as text is: a result that
           does not fit the caller's buffer is still measured so the epilogue
           reports OutputTooSmall with the required count, never WireLimit. */
        if(list->length>100000-co_needed)return co_bad("WireLimit");
        node->children=list->length;
        void *scratch=co_temporary(type->children[0],0);
        if(!scratch)return co_bad("OutOfMemory");
        for(size_t i=0;i<list->length;++i){
            if(!myl_native_list_get(list,i,scratch)){co_temporary_free(scratch);return co_bad("InternalError");}
            if(!co_write(type->children[0],scratch,depth+1)){co_temporary_free(scratch);return 0;}
        }
        co_temporary_free(scratch);
        return 1;
    }
    if(type->kind==8){
        /* Bounded by the staging array alone, exactly as a list is. */
        const myl_native_bytes *bytes=*(const myl_native_bytes *const *)input;
        if(!bytes)return co_bad("InternalError");
        if(bytes->length>100000-co_needed)return co_bad("WireLimit");
        const CoType *element=&co_types[type->children[0]];
        const unsigned char *raw=(const unsigned char *)bytes->storage;
        node->children=bytes->length;
        for(size_t i=0;i<bytes->length;++i)co_prepared[co_needed++]=(MylangWireNode){element->name,raw[i],0};
        return 1;
    }
    if(type->kind==9)return co_write_dictionary(type,node,input,depth);
    if(type->kind==4){
        if(!type->codec)return co_bad("UnsupportedSignature");
        node->children=1;const CoCodec *codec=type->codec;
        void *wire=co_temporary(codec->wire,1);
        if(!wire)return co_bad("OutOfMemory");
        const char *previous=co_domain;co_domain=type->name;
        size_t mark=co_root_count;
        int ok=co_root_value(codec->wire,wire) && co_charge() && co_method(codec->encode,co_context,input,wire) && co_write(codec->wire,wire,depth+1);
        if(ok)co_domain=previous;
        co_unroot_to(mark);co_temporary_free(wire);return ok;
    }
    if(type->kind==3){
        uint32_t tag;memcpy(&tag,input,4);if(tag>=type->count)return co_bad("InternalError");
        size_t child=type->children[tag];node->bits=tag;node->children=child==SIZE_MAX ? 0:1;
        return child==SIZE_MAX || co_write(child,(const unsigned char *)input+type->offsets[tag],depth+1);
    }
    if(type->kind==7){
        const void *reference;memcpy(&reference,input,sizeof reference);
        size_t tag=0;
        while(tag<type->count && (type->children[tag]==SIZE_MAX)!=(reference==NULL))++tag;
        if(tag==type->count)return co_bad("InternalError");
        size_t child=type->children[tag];node->bits=tag;node->children=child==SIZE_MAX ? 0:1;
        return child==SIZE_MAX || co_write(child,input,depth+1);
    }
    for(size_t i=0;i<type->count;++i){
        size_t child=type->children[type->kind==2 ? 0:i],offset=type->kind==2 ? i*type->stride:type->offsets[i];
        if(!co_write(child,(const unsigned char *)input+offset,depth+1))return 0;
    }
    return 1;
}
