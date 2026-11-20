/* SHA-256 in the runtime (core_sha256.c): the FIPS 180-4 vectors on each compression, the portable and the SHA-NI
 * compressions agreeing on every length around the block boundaries and on unaligned input, and the block and span
 * wrappers `bytes.sha256()` calls agreeing with both. The portable path runs on a machine that has SHA-NI too, which
 * is how it is forced. The digests of the pattern inputs of 0 to 200 octets are printed, one line per length, for the
 * Zig test to compare with `std.crypto.hash.sha2.Sha256`. */
#include "core_rt.c"
myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }
const myl_core_site myl_core_sites[1];
const char myl_core_source_path[] = "sha256-regression";

static bool have_shani;
static uint64_t compared;

static void fail(const char *what, size_t length) {
    fprintf(stderr, "sha256 %s at length %zu\n", what, length);
    exit(1);
}

static void hex(const unsigned char digest[32], char out[65]) {
    static const char digits[] = "0123456789abcdef";
    for (int i = 0; i < 32; ++i) {
        out[2 * i] = digits[digest[i] >> 4];
        out[2 * i + 1] = digits[digest[i] & 15];
    }
    out[64] = 0;
}

/* The digest of `data` through every path this process has; they must agree, and `out` is the portable one. */
static void all_paths(const unsigned char *data, size_t length, unsigned char out[32]) {
    unsigned char other[32];
    core_sha256_portable(data, length, out);
    core_sha256(data, length, other);
    if (memcmp(out, other, 32)) fail("dispatch differs from portable", length);
#if defined(__x86_64__)
    if (have_shani) {
        core_sha256_hardware(data, length, other);
        if (memcmp(out, other, 32)) fail("SHA-NI differs from portable", length);
    }
#endif
    myl_block *span = myl_core_span_bytes_sha256(data, length);
    if (span->len != 32 || memcmp(block_data(span), out, 32)) fail("span form differs", length);
    myl_core_drop_owned(span);
    myl_block *source = str_new((int64_t)length);
    if (length) memcpy(block_data(source), data, length);
    myl_block *whole = myl_core_bytes_sha256(source);
    if (whole->len != 32 || memcmp(block_data(whole), out, 32)) fail("block form differs", length);
    myl_core_drop_owned(whole);
    myl_core_drop_owned(source);
    ++compared;
}

static void vector(const char *name, const unsigned char *data, size_t length, const char *expected) {
    unsigned char digest[32];
    char text[65];
    all_paths(data, length, digest);
    hex(digest, text);
    if (strcmp(text, expected)) {
        fprintf(stderr, "sha256 vector %s: got %s, want %s\n", name, text, expected);
        exit(1);
    }
}

int main(void) {
#if defined(__x86_64__)
    have_shani = core_sha256_cpu_has_shani();
#endif
    vector("empty", (const unsigned char *)"", 0, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    vector("abc", (const unsigned char *)"abc", 3, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    const char *bits448 = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    vector("448 bits", (const unsigned char *)bits448, strlen(bits448), "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
    const char *bits896 = "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu";
    vector("896 bits", (const unsigned char *)bits896, strlen(bits896), "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1");
    unsigned char *million = malloc(1000000);
    memset(million, 'a', 1000000);
    vector("a million a", million, 1000000, "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");
    free(million);

    /* Every length from 0 to 4200, on random octets that start at an odd address: all paths agree. */
    unsigned char *noise = malloc(4200 + 8);
    uint64_t seed = 0x9e3779b97f4a7c15ull;
    for (size_t i = 0; i < 4200 + 8; ++i) {
        seed = seed * 6364136223846793005ull + 1442695040888963407ull;
        noise[i] = (unsigned char)(seed >> 56);
    }
    for (size_t offset = 0; offset < 4; ++offset)
        for (size_t length = 0; length <= 4200; ++length) {
            unsigned char digest[32];
            all_paths(noise + offset, length, digest);
        }
    free(noise);

    /* The pattern inputs of 0 to 200 octets, for the Zig side: `length portable shani`, the last `-` without SHA-NI. */
    printf("shani %d\n", have_shani ? 1 : 0);
    for (size_t length = 0; length <= 200; ++length) {
        unsigned char data[200], portable[32], hardware[32];
        char first[65], second[65];
        for (size_t i = 0; i < length; ++i) data[i] = (unsigned char)((i * 7 + 3) % 256);
        core_sha256_portable(data, length, portable);
        hex(portable, first);
#if defined(__x86_64__)
        if (have_shani) {
            core_sha256_hardware(data, length, hardware);
            hex(hardware, second);
        } else
#endif
        {
            (void)hardware;
            strcpy(second, "-");
        }
        printf("%zu %s %s\n", length, first, second);
    }
    printf("sha256 paths agree: %llu inputs compared\n", (unsigned long long)compared);
    return 0;
}
