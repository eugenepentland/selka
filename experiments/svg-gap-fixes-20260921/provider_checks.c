#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "../../src/schematic/native_schematic.c"

static MylangHostPackedCall packed_write(unsigned char payload[256], int64_t *count,
                                          int64_t *result, uint64_t work) {
    static MylangHostPackedValue arguments[2];
    arguments[0] = (MylangHostPackedValue){payload, 256};
    arguments[1] = (MylangHostPackedValue){count, sizeof *count};
    return (MylangHostPackedCall){
        .arguments = arguments,
        .argument_count = 2,
        .output = {result, sizeof *result},
        .work_remaining = work,
    };
}

int main(void) {
    unsigned char stdio_buffer[4096];
    unsigned char payload[256] = {'O', 'K'};
    int64_t count = 2, result = -1;

    memset(&state, 0, sizeof state);
    state.output = fopen("/dev/full", "wb");
    assert(state.output);
    assert(setvbuf(state.output, (char *)stdio_buffer, _IOFBF, sizeof stdio_buffer) == 0);

    MylangHostPackedCall write = packed_write(payload, &count, &result, 3);
    assert(write_block_packed(NULL, &write) == NULL);
    assert(write.work_remaining == 0 && write.output_written == 8 && result == 0);
    assert(state.written == 2); /* stdio accepted the unpublished buffered bytes. */

    MylangHostNode finish_output = {0};
    MylangHostCall finish_call = {
        .output = &finish_output,
        .capacity = 1,
        .work_remaining = 1,
    };
    assert(strcmp(finish(NULL, &finish_call), "HostFailure") == 0);
    assert(finish_call.output_nodes == 0);
    fclose(state.output);
    state.output = NULL;

    /* Invalid counts and exhausted work fail before bytes become published. */
    state.output = tmpfile();
    assert(state.output);
    state.written = 0;
    count = 257;
    write = packed_write(payload, &count, &result, UINT64_MAX);
    assert(strcmp(write_block_packed(NULL, &write), "HostWorkLimit") == 0);
    assert(state.written == 0 && ftell(state.output) == 0);

    count = 2;
    write = packed_write(payload, &count, &result, 2);
    assert(strcmp(write_block_packed(NULL, &write), "HostWorkLimit") == 0);
    assert(write.work_remaining == 2 && write.exhausted == 1);
    assert(state.written == 0 && ftell(state.output) == 0);

    MylangHostCall limit_call = {
        .output = &finish_output,
        .capacity = 1,
        .work_remaining = 1,
    };
    assert(strcmp(output_limit(NULL, &limit_call), "HostWorkLimit") == 0);
    assert(limit_call.work_remaining == 0 && limit_call.output_nodes == 0);

    fclose(state.output);
    state.output = NULL;
    return 0;
}
