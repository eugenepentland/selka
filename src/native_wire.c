/* Private schemas and bounded preorder host value traversal. */
typedef struct {
    const char *name;
    unsigned kind, bits, is_signed, tag_bits;
    size_t count;
    const size_t *children;
} WireSchema;
static const WireSchema wire_schemas[];
typedef struct {
    const MylangWireNode *input;
    size_t count, cursor;
    MylangWireNode *output;
    size_t capacity, needed, return_type;
} WireCall;
static WireCall *wire_call;
static V wire_scalar(size_t type, uint64_t bits) {
    const WireSchema *schema = &wire_schemas[type];
    V number = (V)bits;
    if (schema->is_signed && (bits >> 63)) number -= (V)((U)1 << 64);
    V lower = schema->is_signed ? -(V)((U)1 << (schema->bits-1)) : 0;
    V upper = (V)(((U)1 << (schema->bits-schema->is_signed))-1);
    if (number < lower || number > upper) host_failure("InvalidArgument");
    return number;
}
static void wire_read(size_t type, unsigned depth) {
    if (depth >= 128) host_failure("WireLimit");
    if (wire_call->cursor == wire_call->count) host_failure("InvalidArgument");
    const WireSchema *schema = &wire_schemas[type];
    const MylangWireNode *node = &wire_call->input[wire_call->cursor++];
    if (!node->type || strcmp(node->type, schema->name)) host_failure("InvalidArgument");
    if (schema->kind == 1) {
        if (node->children) host_failure("InvalidArgument");
        push(wire_scalar(type, node->bits)); return;
    }
    if (schema->kind == 2 || schema->kind == 3) {
        if (node->bits || node->children != schema->count) host_failure("InvalidArgument");
        for (size_t i=0; i<schema->count; ++i)
            wire_read(schema->children[schema->kind == 3 ? 0 : i], depth+1);
        make_record(schema->count, NULL); return;
    }
    if (schema->kind == 4) {
        if (node->bits >= schema->count) host_failure("InvalidArgument");
        size_t child = schema->children[node->bits];
        int present = child != SIZE_MAX;
        if (node->children != (size_t)present) host_failure("InvalidArgument");
        Slot payload = {0};
        if (present) { wire_read(child, depth+1); payload = values[--nv]; }
        if (!schema->bits) push_value(boxed_variant((size_t)node->bits, payload, present));
        else push(present ? variant_make(payload.number, schema->tag_bits, wire_schemas[child].bits, (size_t)node->bits) : (V)node->bits);
        return;
    }
    host_failure("UnsupportedSignature");
}
static void wire_write(size_t type, Slot value, unsigned depth, size_t *cursor, int write) {
    if (depth >= 128 || *cursor >= 100000) host_failure("WireLimit");
    const WireSchema *schema = &wire_schemas[type];
    MylangWireNode node = {schema->name, 0, 0};
    size_t child = SIZE_MAX;
    if (schema->kind == 1) node.bits = (uint64_t)(U)value.number;
    else if (schema->kind == 2 || schema->kind == 3) node.children = schema->count;
    else if (schema->kind == 4) {
        node.bits = schema->bits ? (uint64_t)((U)value.number & variant_mask(schema->tag_bits)) : value.object->tag;
        if (node.bits >= schema->count) host_failure("InternalError");
        child = schema->children[node.bits]; node.children = child != SIZE_MAX;
    } else host_failure("UnsupportedSignature");
    if (write) wire_call->output[*cursor] = node;
    ++*cursor;
    for (size_t i=0; i<node.children; ++i) {
        size_t child_type = child;
        Slot part;
        if (schema->kind == 4 && schema->bits) {
            const WireSchema *payload = &wire_schemas[child];
            part = (Slot){variant_payload(value.number, schema->tag_bits, payload->bits, payload->is_signed), NULL};
        } else {
            if (!value.object || i >= value.object->count) host_failure("InternalError");
            part = value.object->fields[i];
            if (schema->kind != 4) child_type = schema->children[schema->kind == 3 ? 0 : i];
        }
        wire_write(child_type, part, depth+1, cursor, write);
    }
}
static void wire_finish(Slot value) {
    if (!wire_call) return;
    size_t count = 0;
    wire_write(wire_call->return_type, value, 0, &count, 0);
    wire_call->needed = count;
    if (count > wire_call->capacity) host_failure("OutputTooSmall");
    count = 0;
    wire_write(wire_call->return_type, value, 0, &count, 1);
}
