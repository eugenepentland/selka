/* Explicit filesystem/network ownership. Included after native_runtime.c. */
typedef struct {
    uint64_t handle, generation;
    size_t previous, next, free_next;
    unsigned permissions;
    int live;
} ResourceEntry;
typedef struct {
    ResourceEntry *entries;
    size_t count, capacity, live, tail, free_head;
} ResourceStore;
static ResourceStore resource_stores[2] = {
    {.tail=SIZE_MAX, .free_head=SIZE_MAX}, {.tail=SIZE_MAX, .free_head=SIZE_MAX}
};
static unsigned pending_resource_kind;
static size_t pending_resource_index;
static MylangResourceProvider *resource_provider(unsigned kind) {
    return kind ? &providers.network : &providers.filesystem;
}
static void validate_resource_providers(void) {
    for (unsigned kind = 0; kind < 2; ++kind)
        if (resource_provider(kind)->permissions & ~7u) host_failure("InvalidCapability");
}
static unsigned resource_authority(V authority, unsigned *permissions) {
    if (authority < -31 || authority > -16) host_failure("InvalidCapability");
    unsigned encoded = (unsigned)(-16 - authority);
    *permissions = encoded & 7; return encoded >> 3;
}
static void grant_resource(unsigned kind) {
    MylangResourceProvider *provider = resource_provider(kind);
    if (!provider->acquire || !provider->complete || !provider->release)
        host_failure("CapabilityUnavailable");
    push(-16 - (V)(kind * 8 + provider->permissions));
}
static void restrict_resource(unsigned mask) {
    unsigned permissions;
    unsigned kind = resource_authority(pop(), &permissions);
    push(-16 - (V)(kind * 8 + (permissions & mask)));
}
static int resource_status(MylangProviderStatus status) {
    if (status == MYLANG_PROVIDER_OUT_OF_MEMORY) host_failure("OutOfMemory");
    if (status < MYLANG_PROVIDER_OK || status > MYLANG_PROVIDER_FAILED)
        host_failure("InvalidProvider");
    return (int)status;
}
static void remove_resource(unsigned kind, size_t index) {
    ResourceStore *store = &resource_stores[kind];
    ResourceEntry *entry = &store->entries[index];
    if (entry->previous != SIZE_MAX) store->entries[entry->previous].next = entry->next;
    if (entry->next != SIZE_MAX) store->entries[entry->next].previous = entry->previous;
    else store->tail = entry->previous;
    entry->live = 0; entry->previous = SIZE_MAX; entry->next = SIZE_MAX;
    if (entry->generation != UINT64_MAX) {
        ++entry->generation; entry->free_next = store->free_head; store->free_head = index;
    }
    --store->live;
}
static void release_resource_entry(unsigned kind, size_t index) {
    MylangResourceProvider *provider = resource_provider(kind);
    provider->release(provider->context, resource_stores[kind].entries[index].handle);
    remove_resource(kind, index);
}
static void release_pending_resource(void) {
    if (!pending_resource_kind) return;
    unsigned kind = pending_resource_kind - 1;
    pending_resource_kind = 0;
    release_resource_entry(kind, pending_resource_index);
}
static void release_resource(Aggregate *object) {
    unsigned kind = object->resource_kind - 1;
    ResourceStore *store = &resource_stores[kind];
    if (object->resource_index >= store->count) return;
    ResourceEntry *entry = &store->entries[object->resource_index];
    if (entry->live && entry->generation == object->resource_generation)
        release_resource_entry(kind, object->resource_index);
}
static void cleanup_resources(void) {
    for (unsigned kind = 2; kind != 0;) {
        ResourceStore *store = &resource_stores[--kind];
        while (store->tail != SIZE_MAX) release_resource_entry(kind, store->tail);
        free(store->entries);
        *store = (ResourceStore){.tail=SIZE_MAX, .free_head=SIZE_MAX};
    }
}
static ResourceEntry *resource_owner(Slot value, unsigned *kind) {
    Aggregate *object = value.object;
    if (!object || !object->resource_kind) host_failure("InvalidOwner");
    *kind = object->resource_kind - 1;
    ResourceStore *store = &resource_stores[*kind];
    if (object->resource_index >= store->count) host_failure("InvalidOwner");
    ResourceEntry *entry = &store->entries[object->resource_index];
    if (!entry->live || entry->generation != object->resource_generation) host_failure("InvalidOwner");
    return entry;
}
static Slot acquire_resource(unsigned kind, size_t ok, size_t error) {
    Slot request = pop_value();
    unsigned permissions;
    if (resource_authority(pop(), &permissions) != kind) host_failure("InvalidCapability");
    if (!request.object) host_failure("InternalError");
    size_t length = request.object->count;
    Aggregate *scratch = new_object(length / sizeof(Slot) + (length % sizeof(Slot) != 0), 0);
    scratch->count = 0;
    uint8_t *bytes = (uint8_t *)scratch->fields;
    for (size_t i = 0; i < length; ++i) bytes[i] = (uint8_t)request.object->fields[i].number;
    ResourceStore *store = &resource_stores[kind];
    int status = 4;
    Slot value = {0};
    if (store->live < 1024) {
        if (store->free_head == SIZE_MAX) {
            if (store->count == SIZE_MAX) host_failure("OutOfMemory");
            store->entries = grow(store->entries, &store->capacity, store->count + 1, sizeof(ResourceEntry));
            store->free_head = store->count++;
            store->entries[store->free_head] = (ResourceEntry){.generation=1, .previous=SIZE_MAX, .next=SIZE_MAX, .free_next=SIZE_MAX};
        }
        size_t index = store->free_head;
        MylangResourceProvider *provider = resource_provider(kind);
        MylangResourceResult result = provider->acquire(provider->context, bytes, length, permissions);
        status = resource_status(result.status);
        if (!status) {
            ResourceEntry *entry = &store->entries[index];
            store->free_head = entry->free_next;
            *entry = (ResourceEntry){.handle=result.handle, .generation=entry->generation,
                .permissions=permissions, .live=1, .previous=store->tail, .next=SIZE_MAX, .free_next=SIZE_MAX};
            if (store->tail != SIZE_MAX) store->entries[store->tail].next = index;
            store->tail = index; ++store->live;
            pending_resource_kind = kind + 1; pending_resource_index = index;
            Aggregate *object = new_object(0, 0);
            object->resource_kind = kind + 1; object->resource_index = index;
            object->resource_generation = entry->generation;
            pending_resource_kind = 0;
            value.object = object;
        }
    }
    release_value(request); release_value((Slot){0, scratch});
    return boxed_variant(status ? error : ok, status ? (Slot){status, NULL} : value, 1);
}
static Slot complete_resource(size_t ok, size_t error, size_t resource_field, size_t code_field) {
    Slot value = pop_value(); unsigned kind;
    ResourceEntry *entry = resource_owner(value, &kind);
    MylangResourceProvider *provider = resource_provider(kind);
    int status = (entry->permissions & 4) ? resource_status(provider->complete(provider->context, entry->handle)) : 2;
    if (!status) {
        remove_resource(kind, value.object->resource_index);
        value.object->resource_kind = 0;
        release_value(value);
        return boxed_variant(ok, (Slot){1, NULL}, 1);
    }
    Aggregate *failure = new_object(2, 0);
    failure->fields[resource_field] = value;
    failure->fields[code_field].number = status;
    return boxed_variant(error, (Slot){0, failure}, 1);
}
