/* Internal generation boundaries cannot be reached by practical source runs. */
#include "native_memory.h"
#include <assert.h>
#include "../src/native_providers.h"
#define MYLANG_GUEST_VALUE_BYTES 48
#include "../src/native_runtime.c"
#include "../src/native_resources.c"

typedef struct { uint64_t next; unsigned live, released; } Context;
static MylangResourceResult acquire(void *opaque, const uint8_t *bytes, size_t length, unsigned permissions) {
    Context *context = opaque;
    (void)bytes; (void)length; (void)permissions;
    ++context->live;
    return (MylangResourceResult){MYLANG_PROVIDER_OK, ++context->next};
}
static void release(void *opaque, uint64_t handle) {
    Context *context = opaque;
    assert(handle && handle <= context->next && context->live);
    --context->live; ++context->released;
}
static Slot owner(unsigned kind) {
    push(-16 - (V)(kind * 8 + 7));
    push_value((Slot){0, new_object(0, 0)});
    Slot result = acquire_resource(kind, 0, 1);
    assert(result.object && result.object->tag == 0);
    Slot value = result.object->fields[0];
    result.object->fields[0] = (Slot){0};
    release_value(result);
    return value;
}
static void generations(unsigned kind, int invalid_lookup) {
    Context context = {0};
    *resource_provider(kind) = (MylangResourceProvider){.context=&context, .permissions=7, .acquire=acquire, .release=release};
    Slot first = owner(kind);
    size_t index = first.object->resource_index;
    Aggregate stale = {.resource_kind=kind + 1, .resource_index=index,
        .resource_generation=first.object->resource_generation};
    release_value(first);
    Slot replacement = owner(kind);
    assert(replacement.object->resource_index == index);
    assert(replacement.object->resource_generation == stale.resource_generation + 1);
    release_resource(&stale);
    assert(context.live == 1 && context.released == 1);
    if (invalid_lookup) {
        unsigned found_kind;
        (void)resource_owner((Slot){0, &stale}, &found_kind);
        abort();
    }

    /* Relocation must preserve the existing owner's index/generation lookup. */
    Slot held[24];
    for (size_t i = 0; i < 24; ++i) held[i] = owner(kind);
    unsigned found_kind;
    assert(resource_owner(replacement, &found_kind)->handle == 2 && found_kind == kind);
    for (size_t i = 24; i != 0;) release_value(held[--i]);

    ResourceStore *store = &resource_stores[kind];
    store->entries[index].generation = UINT64_MAX - 1;
    replacement.object->resource_generation = UINT64_MAX - 1;
    release_value(replacement);
    Slot last = owner(kind);
    assert(last.object->resource_index == index && last.object->resource_generation == UINT64_MAX);
    stale.resource_generation = UINT64_MAX;
    release_value(last);
    Slot next = owner(kind);
    assert(next.object->resource_index != index);
    unsigned before = context.released;
    release_resource(&stale);
    assert(context.released == before && context.live == 1);
    assert(!store->entries[index].live && store->entries[index].generation == UINT64_MAX);
    release_value(next);
    assert(context.live == 0 && context.released == context.next);
}
static void simultaneous_quotas(void) {
    Context contexts[2] = {0};
    Slot held[2][1024];
    for (unsigned kind = 0; kind < 2; ++kind) {
        *resource_provider(kind) = (MylangResourceProvider){.context=&contexts[kind], .permissions=7, .acquire=acquire, .release=release};
        for (size_t i = 0; i < 1024; ++i) held[kind][i] = owner(kind);
    }
    for (unsigned kind = 0; kind < 2; ++kind) {
        assert(contexts[kind].live == 1024);
        push(-16 - (V)(kind * 8 + 7));
        push_value((Slot){0, new_object(0, 0)});
        Slot denied = acquire_resource(kind, 0, 1);
        assert(denied.object->tag == 1 && denied.object->fields[0].number == 4);
        assert(contexts[kind].next == 1024);
        release_value(denied);
    }
    for (size_t i = 1024; i != 0;) {
        --i;
        release_value(held[0][i]); release_value(held[1][i]);
    }
    for (unsigned kind = 0; kind < 2; ++kind) {
        release_value(owner(kind));
        assert(contexts[kind].live == 0 && contexts[kind].released == 1025);
    }
}
int main(int argc, char **argv) {
    enter(0, 0, 0, 0, 0, NULL);
    if (argc == 2) generations(strcmp(argv[1], "stale-1") == 0, 1);
    generations(0, 0);
    generations(1, 0);
    simultaneous_quotas();
    size_t before = test_attempts;
    cleanup();
    assert(test_attempts == before && objects == NULL && test_live == 0);
    return 0;
}
