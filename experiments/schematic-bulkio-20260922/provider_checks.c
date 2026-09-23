/* Direct checks of the schematic provider's owned-payload callbacks, outside
   any generated program. Built with ASan/UBSan; see README.md. */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "../../src/schematic/native_schematic.c"

static MylangHostPackedCall packed_read(int64_t *file, uint64_t work) {
    static MylangHostPackedValue arguments[1];
    arguments[0] = (MylangHostPackedValue){file, sizeof *file};
    return (MylangHostPackedCall){
        .arguments = arguments,
        .argument_count = 1,
        .output = {NULL, 0},
        .work_remaining = work,
    };
}

static MylangHostPackedCall packed_write(void *payload, size_t size, int64_t *result, uint64_t work) {
    static MylangHostPackedValue arguments[1];
    arguments[0] = (MylangHostPackedValue){payload, size};
    return (MylangHostPackedCall){
        .arguments = arguments,
        .argument_count = 1,
        .output = {result, sizeof *result},
        .work_remaining = work,
    };
}

int main(void) {
    unsigned char document[] = {'(', 'n', 'e', 't', ')'};
    int64_t file = 0, result = -1;

    memset(&state, 0, sizeof state);
    state.bytes[0] = document;
    state.length[0] = sizeof document;
    state.count = 1;

    /* The published payload is the provider's own storage, charged per byte. */
    MylangHostPackedCall read = packed_read(&file, 16);
    assert(read_document_packed(NULL, &read) == NULL);
    assert(read.output.bytes == document && read.output.size == sizeof document);
    assert(read.output_written == sizeof document);
    assert(read.work_remaining == 16 - (1 + sizeof document));

    /* A document the driver never supplied is refused without charging. */
    file = 1;
    read = packed_read(&file, 16);
    assert(strcmp(read_document_packed(NULL, &read), "HostFailure") == 0);
    assert(read.work_remaining == 16 && read.output_written == 0);

    /* Exhausted work refuses before the payload is published. */
    file = 0;
    read = packed_read(&file, 2);
    assert(strcmp(read_document_packed(NULL, &read), "HostWorkLimit") == 0);
    assert(read.exhausted == 1 && !read.output.bytes && read.output_written == 0);

    /* An output span the runtime did not hand over empty is a contract break. */
    read = packed_read(&file, 16);
    read.output = (MylangHostPackedValue){document, sizeof document};
    assert(strcmp(read_document_packed(NULL, &read), "HostFailure") == 0);

    /* A buffered write into /dev/full succeeds; finish reports the failure. */
    unsigned char stdio_buffer[4096];
    state.output = fopen("/dev/full", "wb");
    assert(state.output);
    assert(setvbuf(state.output, (char *)stdio_buffer, _IOFBF, sizeof stdio_buffer) == 0);
    MylangHostPackedCall write = packed_write(document, sizeof document, &result, 16);
    assert(write_bytes_packed(NULL, &write) == NULL);
    assert(write.output_written == 8 && result == 0 && state.written == sizeof document);

    MylangHostNode finish_output = {0};
    MylangHostCall finish_call = {.output = &finish_output, .capacity = 1, .work_remaining = 1};
    assert(strcmp(finish(NULL, &finish_call), "HostFailure") == 0);
    assert(finish_call.output_nodes == 0);
    fclose(state.output);
    state.output = NULL;

    /* Oversized payloads and exhausted work refuse before any octet is sent. */
    state.output = tmpfile();
    assert(state.output);
    state.written = MYLANG_SCHEMATIC_OUTPUT - 2;
    write = packed_write(document, sizeof document, &result, UINT64_MAX);
    assert(strcmp(write_bytes_packed(NULL, &write), "HostWorkLimit") == 0);
    assert(state.written == MYLANG_SCHEMATIC_OUTPUT - 2 && ftell(state.output) == 0);

    state.written = 0;
    write = packed_write(document, sizeof document, &result, 2);
    assert(strcmp(write_bytes_packed(NULL, &write), "HostWorkLimit") == 0);
    assert(write.exhausted == 1 && state.written == 0 && ftell(state.output) == 0);

    /* An empty payload is a charged call that writes nothing. */
    result = -1;
    write = packed_write(NULL, 0, &result, 16);
    assert(write_bytes_packed(NULL, &write) == NULL);
    assert(result == 0 && state.written == 0 && ftell(state.output) == 0);
    assert(write.work_remaining == 15);

    /* The node bridge has no form for a payload, so it always refuses. */
    MylangHostCall node_call = {.output = &finish_output, .capacity = 1, .work_remaining = 1};
    assert(strcmp(payload_only(NULL, &node_call), "HostFailure") == 0);

    fclose(state.output);
    state.output = NULL;
    return 0;
}
