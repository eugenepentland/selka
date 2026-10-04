// Fuzz test: the AVX2 separator scanner of string_split.c against the exact scalar scanner on random
// byte strings with long runs of the separator character. Build: zig cc -O2 -fno-strict-aliasing -o fuzz fuzz_string_split.c
#define main ss_main
#include "string_split.c"
#undef main
int main(void) {
    uint64_t rng = 88172645463325252ULL;
    int bad = 0;
    for (int trial = 0; trial < 200000; trial++) {
        rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17;
        size_t n = rng % 400;
        unsigned density = 1 + (rng >> 20) % 7;     /* probability of ':' 1/density-ish */
        unsigned char *d = malloc(n + 64);
        for (size_t i = 0; i < n; i++) {
            rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17;
            d[i] = (rng % density) ? ':' : (unsigned char)('a' + rng % 26);
            if ((rng >> 40) % 11 == 0) d[i] = (unsigned char)(rng >> 48); /* arbitrary bytes */
        }
        const unsigned char sep2[2] = {':', ':'}, sep1[1] = {'|'};
        int64_t c1, c2, a1, a2;
        a1 = scan_scalar(d, n, sep2, 2, &c1);
        a2 = scan_avx2(d, n, sep2, 2, &c2);
        if (a1 != a2 || c1 != c2) { printf("FAIL k=2 n=%zu trial=%d scalar(%lld,%lld) avx(%lld,%lld)\n", n, trial, (long long)a1, (long long)c1, (long long)a2, (long long)c2); if (++bad > 5) return 1; }
        a1 = scan_scalar(d, n, sep1, 1, &c1);
        a2 = scan_avx2(d, n, sep1, 1, &c2);
        if (a1 != a2 || c1 != c2) { printf("FAIL k=1 n=%zu\n", n); if (++bad > 5) return 1; }
        free(d);
    }
    printf(bad ? "FAILED\n" : "fuzz OK\n");
    return bad != 0;
}
