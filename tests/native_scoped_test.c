#define _POSIX_C_SOURCE 200809L
#include "native_scoped.h"
#include <assert.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
static MylangScoped scoped;
static MylangResourceProvider provider;
/* Acquire one `<mode>:<path>` request against the configured provider. */
static MylangResourceResult ask(const char *request) {
    return provider.acquire(provider.context, (const uint8_t *)request, strlen(request), provider.permissions);
}
static void denied(const char *request) {
    MylangResourceResult result = ask(request);
    if (result.status != MYLANG_PROVIDER_DENIED) fprintf(stderr, "not denied: %s status %d\n", request, (int)result.status);
    assert(result.status == MYLANG_PROVIDER_DENIED);
}
/* An existing entry refuses an exclusive create as an ordinary failure. */
static void refused(const char *request) {
    MylangResourceResult result = ask(request);
    if (result.status != MYLANG_PROVIDER_FAILED) fprintf(stderr, "not refused: %s status %d\n", request, (int)result.status);
    assert(result.status == MYLANG_PROVIDER_FAILED);
}
static uint64_t granted(const char *request) {
    MylangResourceResult result = ask(request);
    assert(result.status == MYLANG_PROVIDER_OK);
    return result.handle;
}
static void put(const char *directory, const char *name, const char *contents) {
    char path[512];
    snprintf(path, sizeof path, "%s/%s", directory, name);
    FILE *stream = fopen(path, "w");
    assert(stream);
    fputs(contents, stream);
    fclose(stream);
}
int main(void) {
    (void)mylang_host_charge;
    /* Scratch follows TMPDIR like every other runner, so a quota-bound /tmp
       cannot fail this suite; /tmp is only the POSIX fallback. */
    const char *scratch = getenv("TMPDIR");
    if (!scratch || !*scratch) scratch = "/tmp";
    char root[256];
    int written = snprintf(root, sizeof root, "%s/mylang-scoped-XXXXXX", scratch);
    assert(written > 0 && written < (int)sizeof root);
    (void)written;
    assert(mkdtemp(root));
    put(root, "greeting.txt", "hello\n");
    mylang_scoped_init(&scoped);
    assert(mylang_scoped_grant(&scoped, root, 0));
    provider = mylang_scoped_provider(&scoped, 5);
    /* A read-only grant serves reads, metadata and listings only. */
    uint64_t handle = granted("r:greeting.txt");
    unsigned char frame[64];
    size_t width = 0;
    int eof = 0;
    MylangResourceRead read = provider.read(provider.context, handle, frame, sizeof frame);
    assert(read.status == MYLANG_PROVIDER_OK && read.length == 6 && !memcmp(frame, "hello\n", 6));
    read = provider.read(provider.context, handle, frame, sizeof frame);
    assert(read.status == MYLANG_PROVIDER_OK && read.length == 0 && read.eof);
    assert(provider.complete(provider.context, handle) == MYLANG_PROVIDER_OK);
    assert(provider.complete(provider.context, handle) != MYLANG_PROVIDER_OK);
    /* Every writing mode needs a write grant, and traversal never resolves. */
    denied("w:new.txt");
    denied("c:new.txt");
    denied("k:fresh");
    denied("x:greeting.txt");
    denied("r:../escape");
    denied("r:./greeting.txt");
    denied("r:a//b");
    denied("r:back\\slash");
    denied("q:greeting.txt");
    denied("r:");
    /* Metadata and listings accept the empty path, naming the root itself. */
    handle = granted("m:");
    read = provider.read(provider.context, handle, frame, sizeof frame);
    assert(read.status == MYLANG_PROVIDER_OK && read.length == 10 && frame[0] == 1 && frame[1] == 2);
    provider.release(provider.context, handle);
    handle = granted("l:");
    read = provider.read(provider.context, handle, frame, sizeof frame);
    assert(read.status == MYLANG_PROVIDER_OK && frame[0] == 1);
    assert(frame[1] == 1 && frame[2] == 12 && frame[3] == 0);
    assert(!memcmp(frame + 4, "greeting.txt", 12));
    provider.release(provider.context, handle);
    mylang_scoped_close(&scoped);
    /* A write grant serves the whole writing surface. */
    mylang_scoped_init(&scoped);
    assert(mylang_scoped_grant(&scoped, root, 1));
    provider = mylang_scoped_provider(&scoped, 7);
    handle = granted("c:made.txt");
    MylangResourceWrite wrote = provider.write(provider.context, handle, (const uint8_t *)"one\n", 4);
    assert(wrote.status == MYLANG_PROVIDER_OK && wrote.length == 4);
    assert(provider.complete(provider.context, handle) == MYLANG_PROVIDER_OK);
    refused("c:made.txt");
    handle = granted("a:made.txt");
    wrote = provider.write(provider.context, handle, (const uint8_t *)"two\n", 4);
    assert(wrote.status == MYLANG_PROVIDER_OK && wrote.length == 4);
    assert(provider.complete(provider.context, handle) == MYLANG_PROVIDER_OK);
    handle = granted("r:made.txt");
    read = provider.read(provider.context, handle, frame, sizeof frame);
    assert(read.status == MYLANG_PROVIDER_OK && read.length == 8 && !memcmp(frame, "one\ntwo\n", 8));
    provider.release(provider.context, handle);
    handle = granted("t:made.txt");
    assert(provider.complete(provider.context, handle) == MYLANG_PROVIDER_OK);
    handle = granted("r:made.txt");
    read = provider.read(provider.context, handle, frame, sizeof frame);
    assert(read.status == MYLANG_PROVIDER_OK && !read.length);
    provider.release(provider.context, handle);
    assert(provider.complete(provider.context, granted("k:nested")) == MYLANG_PROVIDER_OK);
    assert(provider.complete(provider.context, granted("x:nested")) == MYLANG_PROVIDER_OK);
    assert(provider.complete(provider.context, granted("x:made.txt")) == MYLANG_PROVIDER_OK);
    /* Only metadata and listings name the root itself; a zero-size read never
       probes EOF, including on an immutable snapshot. */
    denied("r:");
    handle = granted("r:greeting.txt");
    read = provider.read(provider.context, handle, frame, 0);
    assert(read.status == MYLANG_PROVIDER_OK && !read.length && !read.eof);
    (void)eof;
    (void)width;
    mylang_scoped_close(&scoped);
    /* A direct root resolves the whole path at once, including an absolute one. */
    mylang_scoped_init(&scoped);
    assert(mylang_scoped_working_directory(&scoped));
    provider = mylang_scoped_provider(&scoped, 7);
    char absolute[512];
    snprintf(absolute, sizeof absolute, "r:%s/greeting.txt", root);
    handle = granted(absolute);
    read = provider.read(provider.context, handle, frame, sizeof frame);
    assert(read.status == MYLANG_PROVIDER_OK && read.length == 6);
    provider.release(provider.context, handle);
    mylang_scoped_close(&scoped);
    char removal[512];
    snprintf(removal, sizeof removal, "%s/greeting.txt", root);
    assert(!unlink(removal));
    assert(!rmdir(root));
    puts("native scoped provider tests passed");
    return 0;
}
