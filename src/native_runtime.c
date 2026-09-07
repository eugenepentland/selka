/* Runtime support for generated native C. No bytecode decoder is linked. */
#include <stdint.h>
#include <inttypes.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#if !defined(MYLANG_NATIVE_PROVIDER) && !defined(MYLANG_EMBED)
MylangNativeProviders mylang_native_providers(void) { return (MylangNativeProviders){0}; }
#endif
#ifdef MYLANG_EMBED
#include <setjmp.h>
#include <stdatomic.h>
static jmp_buf entry_escape;
static MylangRunResult *active_result;
static int64_t native_value;
static uint64_t native_bits;
static const char *native_type;
#endif
static MylangNativeProviders providers;
typedef __int128 V;
typedef unsigned __int128 U;
/* Layout preflight guarantees widths in 1..127 and packed totals <=127.
   Unsigned shifts avoid signed overflow; signed scalar restoration is explicit. */
static U variant_mask(unsigned bits) { return (((U)1) << bits) - 1; }
static V variant_make(V payload, unsigned tag_bits, unsigned payload_bits, size_t tag) {
    return (V)((((U)payload & variant_mask(payload_bits)) << tag_bits) | (U)tag);
}
static V variant_payload(V value, unsigned tag_bits, unsigned payload_bits, int is_signed) {
    U payload = ((U)value >> tag_bits) & variant_mask(payload_bits);
    if (is_signed && (payload & ((U)1 << (payload_bits - 1))))
        return -(V)(((U)1 << payload_bits) - payload);
    return (V)payload;
}
typedef struct Region Region;
typedef struct Chunk Chunk;
struct Chunk { Chunk *next; size_t used, capacity; max_align_t alignment; unsigned char bytes[]; };
struct Region { uint64_t identity; Region *parent; size_t users, children, slot; Chunk *chunks; };
static Region regions[256];
static Region *active_regions[256];
static size_t nr;
static uint64_t next_region_identity = 2;
static void clear_region_chunks(Region *region) {
    while (region->chunks) { Chunk *next = region->chunks->next; free(region->chunks); region->chunks = next; }
}
typedef struct { uint64_t generation; size_t next; int live; } PoolEntry;
typedef struct { uint64_t identity; size_t issued, live, free_head; PoolEntry entries[]; } Pool;
static size_t pool_owners, pool_slots;
static uint64_t next_pool_identity = 1;
typedef struct Aggregate Aggregate;
typedef struct { V number; Aggregate *object; } Slot;
struct Aggregate {
    size_t refs, count, tag, capacity;
    int buffer;
    Pool *pool;
    Region *region;
    Aggregate *previous, *next, *pending;
    Aggregate *unwind_next;
    size_t unwind_refs;
    unsigned resource_kind;
    size_t resource_index;
    uint64_t resource_generation;
    Slot fields[];
};
typedef struct { Slot value; size_t shared; int exclusive; } Local;
typedef struct Reference Reference;
struct Reference {
    Local *owner;
    Reference *parent;
    size_t children, start, length;
    int active, mutable, slice;
};
typedef struct {
    Local *locals;
    Reference *references;
    size_t base, target, function, call_site, local_count, reference_count, region_base;
    Reference *return_destination, *return_parent;
    Reference captured;
    int return_mutable, has_capture;
} Frame;
static Aggregate *objects;
static size_t guest_capacity;
static Slot *values;
static size_t nv, cv, nf, cf, site;
static Frame *frames;
static int binding_call;
static uint64_t steps, max_steps = 10000000, max_frames = 1024;
static const char *const *source_paths;
static const char *const *function_names;
static const size_t *source_lines, *source_columns;
static void release_value(Slot value);
static void release_resource(Aggregate *object);
static void release_pending_resource(void);
static void cleanup_resources(void);
#ifdef MYLANG_NATIVE_JSON
static void cleanup_native_json(void);
#endif
/* References not held by an aggregate, operand, or local belong to in-flight
   C temporaries. Registry order records their most recent acquisition, rather
   than only object allocation order. No cleanup bookkeeping allocates. */
static void cleanup(void) {
#ifdef MYLANG_NATIVE_JSON
    cleanup_native_json();
#endif
    release_pending_resource();
    for (Aggregate *object = objects; object; object = object->next)
        object->unwind_refs = object->refs;
    for (Aggregate *object = objects; object; object = object->next)
        for (size_t i = 0; i < object->count; ++i)
            if (object->fields[i].object) --object->fields[i].object->unwind_refs;
    for (size_t i = 0; i < nv; ++i)
        if (values[i].object) --values[i].object->unwind_refs;
    for (size_t f = 0; f < nf; ++f)
        for (size_t i = 0; i < frames[f].local_count; ++i)
            if (frames[f].locals[i].value.object) --frames[f].locals[i].value.object->unwind_refs;
    Aggregate *temporaries = NULL, **tail = &temporaries;
    for (Aggregate *object = objects; object; object = object->next) {
        if (!object->unwind_refs) continue;
        *tail = object; tail = &object->unwind_next;
    }
    *tail = NULL;
    while (temporaries) {
        Aggregate *object = temporaries;
        temporaries = object->unwind_next;
        size_t count = object->unwind_refs;
        while (count--) release_value((Slot){0, object});
    }
    while (nv) release_value(values[--nv]);
    while (nf) {
        Frame *frame = &frames[--nf];
        for (size_t i = frame->local_count; i != 0;)
            release_value(frame->locals[--i].value);
        free(frame->references); free(frame->locals);
    }
    cleanup_resources();
    for (size_t i = 0; i < 256; ++i) clear_region_chunks(&regions[i]);
    free(frames); free(values);
    frames = NULL; values = NULL; cf = 0; cv = 0;
}
static void host_failure(const char *message) {
#ifdef MYLANG_EMBED
    active_result->status = 2; active_result->code = message;
    cleanup(); longjmp(entry_escape, 1);
#else
    fprintf(stderr, "mylang: host failure: %s\n", message);
    cleanup(); exit(2);
#endif
}
static void trap(const char *code) {
#ifdef MYLANG_EMBED
    active_result->status = 1; active_result->code = code;
    active_result->path = source_paths[site];
    active_result->line = source_lines[site]; active_result->column = source_columns[site];
    size_t location = site, shown = 0, visible = nf - (binding_call ? 1 : 0);
    for (size_t i = visible; i && shown < 16; --i, ++shown) {
        Frame f = frames[i - 1];
        active_result->frames[shown] = (MylangRunFrame){function_names[f.function], source_paths[location], source_lines[location], source_columns[location]};
        location = f.call_site;
    }
    active_result->frame_count = shown; active_result->omitted_frames = visible - shown;
    cleanup(); longjmp(entry_escape, 1);
#else
    fprintf(stderr, "%s:%zu:%zu: error[%s]\n", source_paths[site], source_lines[site], source_columns[site], code);
    size_t location = site, shown = 0, visible = nf - (binding_call ? 1 : 0);
    for (size_t i = visible; i && shown < 16; --i, ++shown) {
        Frame f = frames[i - 1];
        fprintf(stderr, "  at %s (%s:%zu:%zu)\n", function_names[f.function], source_paths[location], source_lines[location], source_columns[location]);
        location = f.call_site;
    }
    if (visible > shown) fprintf(stderr, "  ... %zu frames omitted\n", visible - shown);
    cleanup(); exit(1);
#endif
}
static void *grow(void *old, size_t *capacity, size_t needed, size_t size) {
    if (needed <= *capacity) return old;
    if (needed > SIZE_MAX / size) host_failure("OutOfMemory");
    size_t next = *capacity ? *capacity : 8;
    while (next < needed) {
        if (next > SIZE_MAX / 2) { next = needed; break; }
        next *= 2;
    }
    if (next > SIZE_MAX / size) next = needed;
    void *result = realloc(old, next * size);
    if (!result) host_failure("OutOfMemory");
    *capacity = next; return result;
}
static Slot temporary_value(Slot value) {
    Aggregate *object = value.object;
    if (object && object != objects) {
        if (object->previous) object->previous->next = object->next;
        if (object->next) object->next->previous = object->previous;
        object->previous = NULL; object->next = objects;
        if (objects) objects->previous = object;
        objects = object;
    }
    return value;
}
static Slot copy_value(Slot value) {
    if (value.object) {
        if (value.object->refs == SIZE_MAX) host_failure("OutOfMemory");
        ++value.object->refs;
    }
    return temporary_value(value);
}
static void release_value(Slot value) {
    Aggregate *work = NULL;
    if (value.object && --value.object->refs == 0) work = value.object;
    while (work) {
        Aggregate *object = work;
        work = object->pending;
        for (size_t i = 0; i < object->count; ++i) {
            Aggregate *child = object->fields[i].object;
            if (child && --child->refs == 0) { child->pending = work; work = child; }
        }
        if (object->previous) object->previous->next = object->next;
        else objects = object->next;
        if (object->next) object->next->previous = object->previous;
        if (object->resource_kind) release_resource(object);
        if (object->buffer) guest_capacity -= object->capacity;
        if (object->pool) { --pool_owners; pool_slots -= object->capacity; if (!object->region) free(object->pool); }
        if (object->region) --object->region->users; else free(object);
    }
}
static Region *find_region(V authority) {
    for (size_t i = 0; i < 256; ++i)
        if (regions[i].identity && (V)regions[i].identity == authority) return &regions[i];
    return NULL;
}
static Region *allocator_region(V authority) {
    if (authority == 1) return NULL;
    Region *region = find_region(authority);
    if (!region) trap("R_CAPABILITY");
    return region;
}
static void *region_allocate(Region *region, size_t size) {
    const size_t alignment = _Alignof(max_align_t);
    if (size > SIZE_MAX - alignment) host_failure("OutOfMemory");
    size_t aligned = (size + alignment - 1) / alignment * alignment;
    Chunk *chunk = region->chunks;
    if (!chunk || aligned > chunk->capacity - chunk->used) {
        size_t capacity = aligned < 4096 ? 4096 : aligned;
        if (capacity > SIZE_MAX - sizeof(Chunk)) host_failure("OutOfMemory");
        chunk = malloc(sizeof(Chunk) + capacity);
        if (!chunk) host_failure("OutOfMemory");
        *chunk = (Chunk){.next=region->chunks, .capacity=capacity};
        region->chunks = chunk;
    }
    void *memory = chunk->bytes + chunk->used;
    chunk->used += aligned; memset(memory, 0, size); return memory;
}
static Aggregate *new_object_in(size_t count, size_t tag, Region *region) {
    if (count > (SIZE_MAX - sizeof(Aggregate)) / sizeof(Slot)) host_failure("OutOfMemory");
    size_t size = sizeof(Aggregate) + count * sizeof(Slot);
    Aggregate *object = region ? region_allocate(region, size) : calloc(1, size);
    if (!object) host_failure("OutOfMemory");
    object->refs = 1; object->count = count; object->capacity = count; object->tag = tag;
    object->region = region;
    if (region) ++region->users;
    object->next = objects;
    if (objects) objects->previous = object;
    objects = object;
    return object;
}
static Aggregate *new_object(size_t count, size_t tag) { return new_object_in(count, tag, NULL); }
static Slot clone_value(Slot value) {
    if (!value.object || value.object->buffer || value.object->pool || value.object->resource_kind) host_failure("InternalError");
    Aggregate *object = new_object(value.object->count, value.object->tag);
    for (size_t i = 0; i < object->count; ++i) object->fields[i] = copy_value(value.object->fields[i]);
    return (Slot){0, object};
}
static void push_value(Slot value) {
    temporary_value(value);
    if (nv == SIZE_MAX) host_failure("OutOfMemory");
    values = grow(values, &cv, nv + 1, sizeof(Slot));
    values[nv++] = value;
}
static void push(V value) { push_value((Slot){value, NULL}); }
static Slot pop_value(void) {
    if (!nf || nv <= frames[nf - 1].base) host_failure("InternalError");
    return temporary_value(values[--nv]);
}
static V pop(void) {
    Slot value = pop_value();
    if (value.object) host_failure("InternalError");
    return value.number;
}
static void grant_external(int kind) {
    int available;
    switch (kind) {
        case 0: available = providers.clock_now != NULL; break;
        case 1: available = providers.random_u64 != NULL; break;
        case 2: available = providers.environment_get != NULL; break;
        default: host_failure("InternalError"); return;
    }
    if (!available) host_failure("CapabilityUnavailable");
    push(-1 - kind);
}
static int external_read(int kind, Slot *value) {
    V authority = pop();
    if (authority != (kind ? -2 : -1)) trap("R_CAPABILITY");
    MylangProviderStatus status;
    if (kind) {
        if (!providers.random_u64) return MYLANG_PROVIDER_UNAVAILABLE;
        MylangRandomResult result = providers.random_u64(providers.random_context);
        status = result.status;
        if (status == MYLANG_PROVIDER_OK) value->number = (V)result.value;
    } else {
        if (!providers.clock_now) return MYLANG_PROVIDER_UNAVAILABLE;
        MylangClockResult result = providers.clock_now(providers.clock_context);
        status = result.status;
        if (status == MYLANG_PROVIDER_OK) value->number = (V)result.value;
    }
    if (status == MYLANG_PROVIDER_OUT_OF_MEMORY) host_failure("OutOfMemory");
    if (status < MYLANG_PROVIDER_OK || status > MYLANG_PROVIDER_FAILED) host_failure("InvalidProviderResult");
    return (int)status;
}
static void clear_values(size_t base) {
    while (nv > base) release_value(values[--nv]);
}
static Local *local_access(size_t index, int write) {
    Local *local = &frames[nf - 1].locals[index];
    if (local->exclusive || (write && local->shared)) trap("R_BORROW_CONFLICT");
    return local;
}
static void store_local(size_t index, Slot value) {
    Local *local = local_access(index, 1);
    release_value(local->value); local->value = value;
}
static void close_region(Region *region) {
    if (region->children || region->users) trap("R_REGION_IN_USE");
    if (region->parent) --region->parent->children;
    clear_region_chunks(region); *region = (Region){0};
}
static void begin_region(size_t slot) {
    Region *parent = allocator_region(pop());
    if (nr == 256) trap("R_REGION_LIMIT");
    if (next_region_identity == UINT64_MAX) host_failure("IdentityExhausted");
    Region *region = NULL;
    for (size_t i = 0; i < 256; ++i) if (!regions[i].identity) { region = &regions[i]; break; }
    if (!region) trap("R_REGION_LIMIT");
    *region = (Region){.identity=next_region_identity++, .parent=parent, .slot=slot};
    if (parent) ++parent->children;
    active_regions[nr++] = region;
    store_local(slot, (Slot){(V)region->identity, NULL});
}
static void end_region(size_t slot) {
    if (nr <= frames[nf-1].region_base || active_regions[nr-1]->slot != slot) host_failure("InternalError");
    close_region(active_regions[--nr]); store_local(slot, (Slot){0});
}
static int reset_arena(void) {
    Region *region = find_region(pop());
    if (!region) return 3;
    if (region->children) return 2;
    if (region->users) return 1;
    clear_region_chunks(region); return 0;
}
static void load_local(size_t index) { push_value(copy_value(local_access(index, 0)->value)); }
static void move_local(size_t index) {
    Local *local = local_access(index, 1);
    Slot value = local->value; local->value = (Slot){0}; push_value(value);
}
static Slot field_value(Slot value, size_t index) {
    if (!value.object || index >= value.object->count) host_failure("InternalError");
    return copy_value(value.object->fields[index]);
}
static void get_field(size_t index) {
    Slot owner = pop_value(), value = field_value(owner, index);
    release_value(owner); push_value(value);
}
static void take_field(size_t index, size_t field) {
    Slot *local = &local_access(index, 1)->value;
    if (!local->object || field >= local->object->count) host_failure("InternalError");
    if (local->object->refs != 1) {
        Slot unique = clone_value(*local); release_value(*local); *local = unique;
    }
    Slot value = local->object->fields[field];
    local->object->fields[field] = (Slot){0};
    push_value(value);
}
static void make_record(size_t count, const size_t *order) {
    Aggregate *object = new_object(count, 0);
    size_t base = nv - count;
    for (size_t i = 0; i < count; ++i) object->fields[order ? order[i] : i] = values[base + i];
    nv = base; push_value((Slot){0, object});
}
static void update_record(size_t count, const size_t *indices) {
    size_t base = nv - count - 1;
    Slot updated = clone_value(values[base]);
    for (size_t i = 0; i < count; ++i) {
        release_value(updated.object->fields[indices[i]]);
        updated.object->fields[indices[i]] = values[base + 1 + i];
    }
    release_value(values[base]); nv = base; push_value(updated);
}
static size_t array_index(V index, Slot owner) {
    if (!owner.object) host_failure("InternalError");
    if (index < 0 || (U)index >= owner.object->count) trap("R_INDEX_BOUNDS");
    return (size_t)index;
}
static void get_index(void) {
    V index = pop(); Slot owner = pop_value();
    Slot value = field_value(owner, array_index(index, owner));
    release_value(owner); push_value(value);
}
static void replace_index(void) {
    size_t base = nv - 3;
    size_t index = array_index(values[base + 1].number, values[base]);
    Slot updated = clone_value(values[base]);
    release_value(updated.object->fields[index]);
    updated.object->fields[index] = values[base + 2];
    release_value(values[base]); nv = base; push_value(updated);
}
static void array_length(void) {
    Slot value = pop_value();
    if (!value.object) host_failure("InternalError");
    size_t count = value.object->count;
    release_value(value); push((V)count);
}
static Slot boxed_variant(size_t tag, Slot payload, int has_payload) {
    Aggregate *object = new_object(has_payload ? 1 : 0, tag);
    if (has_payload) object->fields[0] = payload;
    return (Slot){0, object};
}
/* Guest capacity policy matches the VM's public default slot budget. Native
   storage layout can differ; capacity failures remain typed language results. */
static Slot environment_lookup(size_t capacity, size_t ok, size_t error, size_t bytes_field, size_t length_field, size_t present_field) {
    Slot name = pop_value(); V authority = pop();
    if (authority != -3) trap("R_CAPABILITY");
    if (!name.object) host_failure("InternalError");
    size_t length = name.object->count;
    if (capacity > SIZE_MAX - length) host_failure("OutOfMemory");
    size_t size = length + capacity;
    Aggregate *scratch = new_object(size / sizeof(Slot) + (size % sizeof(Slot) != 0), 0);
    /* Registered raw bytes have no child slots to traverse during cleanup. */
    scratch->count = 0;
    uint8_t *key = (uint8_t *)scratch->fields, *bytes = key + length;
    for (size_t i = 0; i < length; ++i) key[i] = (uint8_t)name.object->fields[i].number;
    MylangEnvironmentResult result = {MYLANG_PROVIDER_UNAVAILABLE, 0, 0};
    if (providers.environment_get)
        result = providers.environment_get(providers.environment_context, key, length, bytes, capacity);
    if (result.status == MYLANG_PROVIDER_OUT_OF_MEMORY) host_failure("OutOfMemory");
    if (result.status != MYLANG_PROVIDER_OK) {
        int status = result.status == MYLANG_PROVIDER_NO_CAPACITY ? 4 : (int)result.status;
        if (status < 1 || status > 4) host_failure("InvalidProvider");
        release_value(name); release_value((Slot){0, scratch});
        return boxed_variant(error, (Slot){status, NULL}, 1);
    }
    if (result.present != 0 && result.present != 1) host_failure("InvalidProvider");
    if (result.present && result.length > capacity) host_failure("InvalidProvider");
    size_t written = result.present ? result.length : 0;
    memset(bytes + written, 0, capacity - written);
    Aggregate *array = new_object(capacity, 0);
    for (size_t i = 0; i < capacity; ++i) array->fields[i].number = bytes[i];
    Aggregate *entry = new_object(3, 0);
    entry->fields[bytes_field] = (Slot){0, array};
    entry->fields[length_field].number = (V)written;
    entry->fields[present_field].number = result.present;
    release_value(name); release_value((Slot){0, scratch});
    return boxed_variant(ok, (Slot){0, entry}, 1);
}
static size_t guest_capacity_limit(void) { return SIZE_MAX / MYLANG_GUEST_VALUE_BYTES; }
static Aggregate *buffer_owner(Local *owner) {
    Aggregate *buffer = owner->value.object;
    if (!buffer || !buffer->buffer) host_failure("InternalError");
    return buffer;
}
static Slot acquire_buffer(size_t ok, size_t error) {
    V capacity = pop(), authority = pop();
    Region *region = allocator_region(authority);
    if (capacity < 0 || (U)capacity > guest_capacity_limit() - guest_capacity)
        return boxed_variant(error, (Slot){1, NULL}, 1);
    Aggregate *buffer = new_object_in((size_t)capacity, 0, region);
    buffer->count = 0; buffer->buffer = 1;
    guest_capacity += (size_t)capacity;
    return boxed_variant(ok, (Slot){0, buffer}, 1);
}
static size_t buffer_length(Local *owner) { return buffer_owner(owner)->count; }
static size_t buffer_capacity(Local *owner) { return buffer_owner(owner)->capacity; }
static Slot buffer_read(Local *owner) {
    V index = pop(); Aggregate *buffer = buffer_owner(owner);
    if (index < 0 || (U)index >= buffer->count) trap("R_BUFFER_BOUNDS");
    return copy_value(buffer->fields[(size_t)index]);
}
static int buffer_write(Local *owner) {
    Slot value = pop_value(); V index = pop();
    Aggregate *buffer = buffer_owner(owner);
    if (index < 0 || (U)index >= buffer->count) { release_value(value); return 3; }
    release_value(buffer->fields[(size_t)index]); buffer->fields[(size_t)index] = value;
    return 0;
}
static int buffer_append(Local *owner) {
    Slot value = pop_value(); Aggregate *buffer = buffer_owner(owner);
    if (buffer->count == buffer->capacity) { release_value(value); return 2; }
    buffer->fields[buffer->count++] = value;
    return 0;
}
static int buffer_resize(Local *owner) {
    Slot fill = pop_value(); V length = pop(); Aggregate *buffer = buffer_owner(owner);
    if (length < 0 || (U)length > SIZE_MAX) { release_value(fill); return 3; }
    if ((U)length > buffer->capacity) { release_value(fill); return 2; }
    while (buffer->count > (size_t)length) release_value(buffer->fields[--buffer->count]);
    while (buffer->count < (size_t)length) buffer->fields[buffer->count++] = copy_value(fill);
    release_value(fill);
    return 0;
}
static int buffer_reserve(Local *owner) {
    V capacity = pop(), authority = pop();
    Aggregate *old = buffer_owner(owner);
    if (allocator_region(authority) != old->region) trap("R_CAPABILITY");
    if (old->refs != 1) host_failure("InternalError");
    if (capacity < 0 || (U)capacity > guest_capacity_limit()) return 1;
    if ((U)capacity <= old->capacity) return 0;
    size_t increase = (size_t)capacity - old->capacity;
    if (increase > guest_capacity_limit() - guest_capacity) return 1;
    Aggregate *grown = new_object_in((size_t)capacity, 0, old->region);
    grown->count = old->count; grown->buffer = 1;
    memcpy(grown->fields, old->fields, old->count * sizeof(Slot));
    /* Transfer initialized children once. No borrowed view can be active here. */
    old->count = 0; old->buffer = 0;
    release_value((Slot){0, old});
    owner->value = (Slot){0, grown};
    guest_capacity += increase;
    return 0;
}
static Aggregate *pool_owner(Local *owner) {
    Aggregate *object = owner->value.object;
    if (!object || !object->pool) host_failure("InternalError");
    return object;
}
static Slot acquire_pool(size_t ok, size_t error) {
    V capacity = pop(); Region *region = allocator_region(pop());
    if (capacity < 0 || capacity > 4096 || pool_owners >= 64 || (U)capacity > 16384 - pool_slots)
        return boxed_variant(error, (Slot){1, NULL}, 1);
    if (next_pool_identity == UINT64_MAX) return boxed_variant(error, (Slot){2, NULL}, 1);
    Aggregate *object = new_object_in((size_t)capacity, 0, region);
    size_t bytes = sizeof(Pool) + (size_t)capacity * sizeof(PoolEntry);
    Pool *pool = region ? region_allocate(region, bytes) : calloc(1, bytes);
    if (!pool) host_failure("OutOfMemory");
    object->pool = pool; pool->identity = next_pool_identity++; pool->free_head = SIZE_MAX;
    ++pool_owners; pool_slots += (size_t)capacity;
    return boxed_variant(ok, (Slot){0, object}, 1);
}
static int pool_index(Aggregate *owner, Slot handle, size_t *index) {
    Aggregate *id = handle.object;
    if (!id || id->count != 3) host_failure("InternalError");
    if ((V)owner->pool->identity != id->fields[0].number) return 2;
    V selected = id->fields[1].number;
    if (selected < 0 || (U)selected >= owner->pool->issued) return 1;
    *index = (size_t)selected;
    PoolEntry entry = owner->pool->entries[*index];
    return !entry.live || (V)entry.generation != id->fields[2].number ? 1 : 0;
}
static size_t pool_length(Local *owner) { return pool_owner(owner)->pool->live; }
static size_t pool_capacity(Local *owner) { return pool_owner(owner)->capacity; }
static int pool_insert(Local *owner, Slot *result) {
    Slot value = pop_value(); Aggregate *object = pool_owner(owner); Pool *pool = object->pool;
    if (pool->free_head == SIZE_MAX && pool->issued == object->capacity) { release_value(value); return 3; }
    size_t index;
    if (pool->free_head == SIZE_MAX) {
        index = pool->issued++; pool->entries[index].generation = 1;
    } else { index = pool->free_head; pool->free_head = pool->entries[index].next; }
    PoolEntry *entry = &pool->entries[index]; entry->live = 1; entry->next = SIZE_MAX;
    object->fields[index] = value; ++pool->live;
    Aggregate *handle = new_object(3, 0);
    handle->fields[0].number = (V)pool->identity;
    handle->fields[1].number = (V)index;
    handle->fields[2].number = (V)entry->generation;
    *result = (Slot){0, handle}; return 0;
}
static int pool_read(Local *owner, Slot *result) {
    Slot handle = pop_value(); Aggregate *object = pool_owner(owner); size_t index = 0;
    int status = pool_index(object, handle, &index); release_value(handle);
    if (!status) *result = copy_value(object->fields[index]);
    return status;
}
static int pool_replace(Local *owner, Slot *result) {
    Slot value = pop_value(), handle = pop_value(); Aggregate *object = pool_owner(owner); size_t index = 0;
    int status = pool_index(object, handle, &index); release_value(handle);
    if (status) { release_value(value); return status; }
    release_value(object->fields[index]); object->fields[index] = value;
    *result = (Slot){1, NULL}; return 0;
}
static void pool_remove_index(Aggregate *object, size_t index) {
    Pool *pool = object->pool; PoolEntry *entry = &pool->entries[index];
    release_value(object->fields[index]); object->fields[index] = (Slot){0};
    entry->live = 0; --pool->live;
    if (entry->generation != UINT64_MAX) {
        ++entry->generation; entry->next = pool->free_head; pool->free_head = index;
    }
}
static int pool_remove(Local *owner, Slot *result) {
    Slot handle = pop_value(); Aggregate *object = pool_owner(owner); size_t index = 0;
    int status = pool_index(object, handle, &index); release_value(handle);
    if (!status) { pool_remove_index(object, index); *result = (Slot){1, NULL}; }
    return status;
}
static V pool_clear(Local *owner) {
    Aggregate *object = pool_owner(owner);
    for (size_t i = object->pool->issued; i; --i)
        if (object->pool->entries[i-1].live) pool_remove_index(object, i-1);
    return 1;
}
static void compare_handle(int unequal) {
    Slot right = pop_value(), left = pop_value();
    if (!left.object || !right.object || left.object->count != 3 || right.object->count != 3) host_failure("InternalError");
    int equal = 1;
    for (size_t i = 0; i < 3; ++i) if (left.object->fields[i].number != right.object->fields[i].number) equal = 0;
    release_value(left); release_value(right); push(unequal ? !equal : equal);
}
static Reference *active_reference(Reference *reference) {
    if (!reference || !reference->active) trap("R_REFERENCE_LIFETIME");
    return reference;
}
static Reference *usable_reference(Reference *reference) {
    active_reference(reference);
    if (reference->mutable && reference->children) trap("R_BORROW_SUSPENDED");
    return reference;
}
static void child_reference(Reference *destination, Reference *parent, int mutable, int slice, size_t start, size_t length) {
    if (destination->active) trap("R_REFERENCE_LIFETIME");
    usable_reference(parent);
    if (mutable && !parent->mutable) trap("R_REFERENCE_READ_ONLY");
    if (parent->children == SIZE_MAX) host_failure("IdentityExhausted");
    ++parent->children;
    *destination = (Reference){.owner=parent->owner, .parent=parent, .start=start, .length=length,
        .active=1, .mutable=mutable, .slice=slice};
}
static void begin_reference(size_t id, size_t owner, size_t parent_id, int mutable, int slice, int narrow) {
    Frame *frame = &frames[nf-1];
    Reference *destination = &frame->references[id];
    if (destination->active) trap("R_REFERENCE_LIFETIME");
    Reference *parent = parent_id == SIZE_MAX ? NULL : active_reference(&frame->references[parent_id]);
    Local *local = parent ? parent->owner : &frame->locals[owner];
    size_t start = 0, length = 0;
    if (slice) {
        if (parent && parent->slice) { start = parent->start; length = parent->length; }
        else {
            if (!local->value.object) host_failure("InternalError");
            length = local->value.object->count;
        }
        if (narrow) {
            V end = pop(), begin = pop();
            if (begin < 0 || end < begin || (U)end > length) trap("R_SLICE_BOUNDS");
            start += (size_t)begin; length = (size_t)(end - begin);
        }
    }
    if (parent) {
        child_reference(destination, parent, mutable, slice, start, length);
    } else {
        if (local->exclusive || (mutable && local->shared)) trap("R_BORROW_CONFLICT");
        if (mutable) local->exclusive = 1;
        else {
            if (local->shared == SIZE_MAX) host_failure("IdentityExhausted");
            ++local->shared;
        }
        *destination = (Reference){.owner=local, .start=start, .length=length, .active=1, .mutable=mutable, .slice=slice};
    }
}
static void end_reference(size_t id) {
    Reference *reference = active_reference(&frames[nf-1].references[id]);
    if (reference->children) trap("R_REFERENCE_LIFETIME");
    if (reference->parent) --reference->parent->children;
    else if (reference->mutable) reference->owner->exclusive = 0;
    else --reference->owner->shared;
    *reference = (Reference){0};
}
static Local *reference_owner(size_t id, int write) {
    Reference *reference = usable_reference(&frames[nf-1].references[id]);
    if (reference->slice) host_failure("InternalError");
    if (write && !reference->mutable) trap("R_REFERENCE_READ_ONLY");
    return reference->owner;
}
static void read_reference(size_t id) {
    Reference *reference = usable_reference(&frames[nf-1].references[id]);
    push_value(copy_value(reference->owner->value));
}
static void write_reference(size_t id) {
    Slot value = pop_value();
    Reference *reference = usable_reference(&frames[nf-1].references[id]);
    if (!reference->mutable) trap("R_REFERENCE_READ_ONLY");
    release_value(reference->owner->value); reference->owner->value = value;
}
static void length_slice(size_t id) {
    Reference *reference = usable_reference(&frames[nf-1].references[id]);
    push((V)reference->length);
}
static size_t slice_index(Reference *reference, V index) {
    if (index < 0 || (U)index >= reference->length) trap("R_SLICE_BOUNDS");
    return reference->start + (size_t)index;
}
static void read_slice(size_t id) {
    V index = pop();
    Reference *reference = active_reference(&frames[nf-1].references[id]);
    size_t selected = slice_index(reference, index);
    usable_reference(reference);
    push_value(field_value(reference->owner->value, selected));
}
static void write_slice(size_t id) {
    Slot value = pop_value(); V index = pop();
    Reference *reference = active_reference(&frames[nf-1].references[id]);
    size_t selected = slice_index(reference, index);
    usable_reference(reference);
    if (!reference->mutable) trap("R_REFERENCE_READ_ONLY");
    Aggregate *object = reference->owner->value.object;
    if (object && object->buffer) {
        release_value(object->fields[selected]); object->fields[selected] = value;
    } else {
        Slot updated = clone_value(reference->owner->value);
        release_value(updated.object->fields[selected]); updated.object->fields[selected] = value;
        release_value(reference->owner->value); reference->owner->value = updated;
    }
}
static void enter(size_t function, size_t locals, size_t arguments, size_t target, size_t references, const size_t *slots) {
    if (nf >= max_frames) trap("R_FRAME_LIMIT");
    if (arguments > nv || (nf && arguments > nv - frames[nf - 1].base)) host_failure("InternalError");
    if (nf == SIZE_MAX || locals > SIZE_MAX / sizeof(Local) || references > SIZE_MAX / sizeof(Reference)) host_failure("OutOfMemory");
    frames = grow(frames, &cf, nf + 1, sizeof(Frame));
    Local *storage = calloc(locals ? locals : 1, sizeof(Local));
    if (!storage) host_failure("OutOfMemory");
    size_t base = nv - arguments;
    for (size_t i = 0; i < arguments; ++i) storage[slots ? slots[i] : i].value = values[base + i];
    frames[nf++] = (Frame){.locals=storage, .base=base, .target=target, .function=function,
        .call_site=site, .local_count=locals, .reference_count=references, .region_base=nr};
    nv = base;
    if (references) {
        frames[nf-1].references = calloc(references, sizeof(Reference));
        if (!frames[nf-1].references) host_failure("OutOfMemory");
    }
}
static void bind_reference(size_t destination, size_t source, int mutable) {
    Reference *parent = active_reference(&frames[nf-2].references[source]);
    child_reference(&frames[nf-1].references[destination], parent, mutable, parent->slice, parent->start, parent->length);
}
static void prepare_reference_return(size_t destination, size_t parent, int mutable) {
    Frame *frame = &frames[nf-1], *caller = &frames[nf-2];
    frame->return_destination = &caller->references[destination];
    if (frame->return_destination->active) trap("R_REFERENCE_LIFETIME");
    frame->return_parent = usable_reference(&caller->references[parent]);
    frame->return_mutable = mutable;
}
static void capture_reference(size_t id) {
    Frame *frame = &frames[nf-1];
    Reference *reference = usable_reference(&frame->references[id]);
    if (!frame->return_parent || frame->has_capture || reference->owner != frame->return_parent->owner) trap("R_REFERENCE_LIFETIME");
    frame->captured = *reference; frame->has_capture = 1;
}
static Frame leave_frame(void) {
    Frame frame = frames[nf-1];
    for (size_t i = 0; i < frame.reference_count; ++i)
        if (frame.references[i].active) trap("R_REFERENCE_LIFETIME");
    for (size_t i = frame.local_count; i != 0;) {
        Local *local = &frame.locals[--i];
        if (local->exclusive || local->shared) trap("R_BORROW_CONFLICT");
        Slot value = local->value;
        local->value = (Slot){0};
        release_value(value);
    }
    clear_values(frame.base);
    while (nr > frame.region_base) close_region(active_regions[--nr]);
    free(frame.references); free(frame.locals); --nf;
    return frame;
}
static size_t leave(Slot result) {
    Frame frame = leave_frame();
    push_value(result); return frame.target;
}
static size_t leave_reference(void) {
    Frame *current = &frames[nf-1];
    if (!current->has_capture || !current->return_destination || !current->return_parent) trap("R_REFERENCE_LIFETIME");
    Frame frame = leave_frame();
    child_reference(frame.return_destination, frame.return_parent, frame.return_mutable,
        frame.captured.slice, frame.captured.start, frame.captured.length);
    return frame.target;
}
static void tick(size_t location) {
    site = location;
    if (steps == max_steps) trap("R_STEP_LIMIT");
    ++steps;
}
static V checked(V value, V minimum, V maximum) {
    if (value < minimum || value > maximum) trap("R_OVERFLOW");
    return value;
}
static V arithmetic(int operation, V a, V b, V minimum, V maximum) {
    V result = 0;
    int overflow = 0;
    switch (operation) {
        case 0: overflow = __builtin_add_overflow(a, b, &result); break;
        case 1: overflow = __builtin_sub_overflow(a, b, &result); break;
        case 2: overflow = __builtin_mul_overflow(a, b, &result); break;
        case 3: if (!b) trap("R_DIVISION_BY_ZERO"); result = a / b; break;
        case 4: if (!b) trap("R_DIVISION_BY_ZERO"); result = a % b; break;
        default: host_failure("InternalError");
    }
    if (overflow) trap("R_OVERFLOW");
    return checked(result, minimum, maximum);
}
static uint64_t budget(const char *text) {
    uint64_t result = 0;
    if (!*text) host_failure("InvalidBudget");
    for (; *text; ++text) {
        if (*text < '0' || *text > '9' || result > (UINT64_MAX - (unsigned)(*text - '0')) / 10) host_failure("InvalidBudget");
        result = result * 10 + (unsigned)(*text - '0');
    }
    if (!result) host_failure("InvalidBudget");
    return result;
}
static void options(int argc, char **argv) {
    int saw_steps = 0, saw_frames = 0;
    for (int i = 1; i < argc; ++i) {
        if (!strncmp(argv[i], "--max-steps=", 12) && !saw_steps++) max_steps = budget(argv[i] + 12);
        else if (!strncmp(argv[i], "--max-frames=", 13) && !saw_frames++) max_frames = budget(argv[i] + 13);
        else host_failure("InvalidBudget");
    }
}
