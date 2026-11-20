/* SHA-256 (FIPS 180-4) over octets in place, for `bytes.sha256()` and `hashes.sha256` (core_bytes.c wraps it in
   blocks and spans). Two block compressions give the same digest: the x86 SHA extensions (SHA-NI), which the first
   hash selects when the CPU has them (CPUID leaf 7 bit 29, with SSSE3 and SSE4.1 that the instruction sequence
   also uses), and portable C everywhere else. Whole 64-octet blocks are read from the caller's octets; only the one
   or two padded final blocks are built in a 128-octet stack buffer, so no copy of the input is made. */
#if defined(__x86_64__)
#include <cpuid.h>
#include <immintrin.h>
#endif

static const uint32_t core_sha256_k[64] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u, 0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
    0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u, 0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
    0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu, 0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
    0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u, 0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
    0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u, 0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
    0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u, 0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
    0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u, 0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u, 0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u,
};

typedef void (*core_sha256_blocks_fn)(uint32_t state[8], const unsigned char *data, size_t blocks);

static inline uint32_t core_sha256_rotr(uint32_t value, unsigned count) { return (value >> count) | (value << (32u - count)); }

/* The portable compression of `blocks` consecutive 64-octet blocks into `state`. */
static void core_sha256_blocks_portable(uint32_t state[8], const unsigned char *data, size_t blocks) {
    for (; blocks; --blocks, data += 64) {
        uint32_t w[64];
        for (unsigned i = 0; i < 16; ++i) {
            uint32_t word;
            memcpy(&word, data + 4 * i, 4);
            w[i] = __builtin_bswap32(word);
        }
        for (unsigned i = 16; i < 64; ++i) {
            uint32_t s0 = core_sha256_rotr(w[i - 15], 7) ^ core_sha256_rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
            uint32_t s1 = core_sha256_rotr(w[i - 2], 17) ^ core_sha256_rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16] + s0 + w[i - 7] + s1;
        }
        uint32_t a = state[0], b = state[1], c = state[2], d = state[3], e = state[4], f = state[5], g = state[6], h = state[7];
        for (unsigned i = 0; i < 64; ++i) {
            uint32_t upper = core_sha256_rotr(e, 6) ^ core_sha256_rotr(e, 11) ^ core_sha256_rotr(e, 25);
            uint32_t choice = (e & f) ^ (~e & g);
            uint32_t first = h + upper + choice + core_sha256_k[i] + w[i];
            uint32_t lower = core_sha256_rotr(a, 2) ^ core_sha256_rotr(a, 13) ^ core_sha256_rotr(a, 22);
            uint32_t majority = (a & b) ^ (a & c) ^ (b & c);
            h = g;
            g = f;
            f = e;
            e = d + first;
            d = c;
            c = b;
            b = a;
            a = first + lower + majority;
        }
        state[0] += a;
        state[1] += b;
        state[2] += c;
        state[3] += d;
        state[4] += e;
        state[5] += f;
        state[6] += g;
        state[7] += h;
    }
}

#if defined(__x86_64__)
/* Four rounds with the message words `w[i & 3]` (groups 0..3 are loaded and byte-swapped, later ones are the
   schedule of the four words before them); `i` is a literal, so the window lives in registers. */
#define CORE_SHA256_QUAD(i)                                                                                    \
    do {                                                                                                       \
        if ((i) < 4) {                                                                                         \
            w[(i)&3] = _mm_shuffle_epi8(_mm_loadu_si128((const __m128i *)(data + 16 * (i))), order);           \
        } else {                                                                                               \
            __m128i partial = _mm_add_epi32(_mm_sha256msg1_epu32(w[(i)&3], w[((i) + 1) & 3]),                  \
                                            _mm_alignr_epi8(w[((i) + 3) & 3], w[((i) + 2) & 3], 4));           \
            w[(i)&3] = _mm_sha256msg2_epu32(partial, w[((i) + 3) & 3]);                                        \
        }                                                                                                      \
        __m128i sum = _mm_add_epi32(w[(i)&3], _mm_loadu_si128((const __m128i *)(core_sha256_k + 4 * (i))));    \
        cdgh = _mm_sha256rnds2_epu32(cdgh, abef, sum);                                                         \
        abef = _mm_sha256rnds2_epu32(abef, cdgh, _mm_shuffle_epi32(sum, 0x0e));                                \
    } while (0)

/* The SHA-NI compression: the same function as `core_sha256_blocks_portable`, sixteen groups of four rounds. */
static void __attribute__((target("sha,ssse3,sse4.1"))) core_sha256_blocks_shani(uint32_t state[8], const unsigned char *data, size_t blocks) {
    const __m128i order = _mm_set_epi64x(0x0c0d0e0f08090a0bLL, 0x0405060700010203LL);
    /* The instructions hold the state as (A, B, E, F) and (C, D, G, H), each from the high lane down. */
    __m128i low = _mm_shuffle_epi32(_mm_loadu_si128((const __m128i *)&state[0]), 0xb1);  /* B A D C */
    __m128i high = _mm_shuffle_epi32(_mm_loadu_si128((const __m128i *)&state[4]), 0x1b); /* E F G H, reversed */
    __m128i abef = _mm_alignr_epi8(low, high, 8);
    __m128i cdgh = _mm_blend_epi16(high, low, 0xf0);
    for (; blocks; --blocks, data += 64) {
        const __m128i abef_before = abef, cdgh_before = cdgh;
        __m128i w[4];
        CORE_SHA256_QUAD(0);
        CORE_SHA256_QUAD(1);
        CORE_SHA256_QUAD(2);
        CORE_SHA256_QUAD(3);
        CORE_SHA256_QUAD(4);
        CORE_SHA256_QUAD(5);
        CORE_SHA256_QUAD(6);
        CORE_SHA256_QUAD(7);
        CORE_SHA256_QUAD(8);
        CORE_SHA256_QUAD(9);
        CORE_SHA256_QUAD(10);
        CORE_SHA256_QUAD(11);
        CORE_SHA256_QUAD(12);
        CORE_SHA256_QUAD(13);
        CORE_SHA256_QUAD(14);
        CORE_SHA256_QUAD(15);
        abef = _mm_add_epi32(abef, abef_before);
        cdgh = _mm_add_epi32(cdgh, cdgh_before);
    }
    low = _mm_shuffle_epi32(abef, 0x1b);
    high = _mm_shuffle_epi32(cdgh, 0xb1);
    _mm_storeu_si128((__m128i *)&state[0], _mm_blend_epi16(low, high, 0xf0));
    _mm_storeu_si128((__m128i *)&state[4], _mm_alignr_epi8(high, low, 8));
}
#undef CORE_SHA256_QUAD

/* Whether this CPU runs `core_sha256_blocks_shani`: SHA (CPUID.7.0:EBX bit 29), SSSE3 and SSE4.1 (CPUID.1:ECX bits 9, 19). */
static bool core_sha256_cpu_has_shani(void) {
    unsigned eax, ebx, ecx, edx;
    if (!__get_cpuid(1, &eax, &ebx, &ecx, &edx) || !(ecx & (1u << 9)) || !(ecx & (1u << 19))) return false;
    if (__get_cpuid_max(0, NULL) < 7) return false;
    __cpuid_count(7, 0, eax, ebx, ecx, edx);
    return (ebx & (1u << 29)) != 0;
}
#endif

/* The digest of `length` octets at `data` (which may be NULL when `length` is 0) through `blocks`, written to `out`. */
static void core_sha256_with(core_sha256_blocks_fn blocks, const unsigned char *data, uint64_t length, unsigned char out[32]) {
    uint32_t state[8] = {0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au, 0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u};
    uint64_t whole = length / 64;
    if (whole) blocks(state, data, (size_t)whole);
    /* The final one or two blocks: the remaining octets, one 0x80, zeros and the length in bits, big-endian. */
    unsigned char tail[128];
    size_t rest = (size_t)(length % 64);
    size_t padded = rest < 56 ? 64 : 128;
    if (rest) memcpy(tail, data + whole * 64, rest);
    memset(tail + rest, 0, padded - rest);
    tail[rest] = 0x80;
    uint64_t bits = length << 3;
    for (unsigned i = 0; i < 8; ++i) tail[padded - 1 - i] = (unsigned char)(bits >> (8 * i));
    blocks(state, tail, padded / 64);
    for (unsigned i = 0; i < 8; ++i) {
        out[4 * i] = (unsigned char)(state[i] >> 24);
        out[4 * i + 1] = (unsigned char)(state[i] >> 16);
        out[4 * i + 2] = (unsigned char)(state[i] >> 8);
        out[4 * i + 3] = (unsigned char)state[i];
    }
}

/* The portable digest, whatever the CPU. */
static void core_sha256_portable(const unsigned char *data, uint64_t length, unsigned char out[32]) {
    core_sha256_with(core_sha256_blocks_portable, data, length, out);
}

#if defined(__x86_64__)
/* The SHA-NI digest; only valid to call where `core_sha256_cpu_has_shani()` holds. */
static void core_sha256_hardware(const unsigned char *data, uint64_t length, unsigned char out[32]) {
    core_sha256_with(core_sha256_blocks_shani, data, length, out);
}
#endif

/* The compression the first hash chose for this process: 0 not yet chosen, 1 portable, 2 SHA-NI. Racing first
   hashes choose the same value. */
static _Atomic int core_sha256_choice;

/* The digest of `length` octets at `data`, 32 octets written to `out`: SHA-NI where the CPU has it, else portable. */
static void core_sha256(const unsigned char *data, uint64_t length, unsigned char out[32]) {
    int choice = atomic_load_explicit(&core_sha256_choice, memory_order_relaxed);
    if (choice == 0) {
        choice = 1;
#if defined(__x86_64__)
        if (core_sha256_cpu_has_shani()) choice = 2;
#endif
        atomic_store_explicit(&core_sha256_choice, choice, memory_order_relaxed);
    }
#if defined(__x86_64__)
    if (choice == 2) {
        core_sha256_hardware(data, length, out);
        return;
    }
#endif
    core_sha256_portable(data, length, out);
}
