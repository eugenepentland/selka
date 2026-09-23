/* Probe-footprint model for the million-key knucleotide passes: 1M distinct
 * keys inserted in order into a table that grows at load 5/8, every insert
 * preceded by a miss probe (the read of `d.get(key, 0)`). Layout A is the
 * dictionary's 8-byte slot (hash<<32 | entry+1); layout B is a 1-byte tag array
 * plus a 4-byte entry-index array and a per-entry 4-byte hash array for growth.
 * Only the index is modelled: the entry list and key texts cost the same in both. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
static uint32_t mix(uint64_t x) { x ^= x >> 33; x *= 0xff51afd7ed558ccdULL; x ^= x >> 33; x *= 0xc4ceb9fe1a85ec53ULL; x ^= x >> 33; return (uint32_t)x; }
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }
static size_t n = 1000000;
static double layout_a(void) {
    size_t cap = 8; uint64_t *slots = calloc(cap, 8);
    double t = now(); size_t probes = 0;
    for (size_t i = 0; i < n; i++) {
        uint32_t h = mix(i * 0x9e3779b97f4a7c15ULL + 1);
        size_t mask = cap - 1, at = h & mask;
        for (uint64_t s; (s = slots[at]); at = (at + 1) & mask) { probes++; if ((uint32_t)(s >> 32) == h) probes += 1000; }
        if ((i + 1) * 8 > cap * 5) {
            size_t ncap = cap * 2; uint64_t *ns = calloc(ncap, 8);
            for (size_t j = 0; j < cap; j++) if (slots[j]) { size_t k = (slots[j] >> 32) & (ncap - 1); while (ns[k]) k = (k + 1) & (ncap - 1); ns[k] = slots[j]; }
            free(slots); slots = ns; cap = ncap; mask = cap - 1;
            at = h & mask; while (slots[at]) at = (at + 1) & mask;
        }
        slots[at] = (uint64_t)h << 32 | (i + 1);
    }
    t = now() - t; free(slots); if (probes == 7) puts("");
    return t;
}
static double layout_b(void) {
    size_t cap = 8; uint8_t *tags = calloc(cap, 1); uint32_t *idx = calloc(cap, 4); uint32_t *hashes = malloc(n * 4);
    double t = now(); size_t probes = 0;
    for (size_t i = 0; i < n; i++) {
        uint32_t h = mix(i * 0x9e3779b97f4a7c15ULL + 1);
        uint8_t tag = (uint8_t)(h >> 25) | 0x80;
        size_t mask = cap - 1, at = h & mask;
        for (uint8_t s; (s = tags[at]); at = (at + 1) & mask) { probes++; if (s == tag && hashes[idx[at]] == h) probes += 1000; }
        hashes[i] = h;
        if ((i + 1) * 8 > cap * 5) {
            size_t ncap = cap * 2; uint8_t *nt = calloc(ncap, 1); uint32_t *ni = calloc(ncap, 4);
            for (size_t j = 0; j < cap; j++) if (tags[j]) { uint32_t e = idx[j]; size_t k = hashes[e] & (ncap - 1); while (nt[k]) k = (k + 1) & (ncap - 1); nt[k] = tags[j]; ni[k] = e; }
            free(tags); free(idx); tags = nt; idx = ni; cap = ncap; mask = cap - 1;
            at = h & mask; while (tags[at]) at = (at + 1) & mask;
        }
        tags[at] = tag; idx[at] = (uint32_t)i;
    }
    t = now() - t; free(tags); free(idx); free(hashes); if (probes == 7) puts("");
    return t;
}
int main(void) {
    double a = 1e9, b = 1e9;
    for (int r = 0; r < 9; r++) { double x = layout_a(), y = layout_b(); if (x < a) a = x; if (y < b) b = y; }
    printf("8-byte slots %.1f ms, tag+index %.1f ms (best of 9, %zu keys)\n", a * 1e3, b * 1e3, n);
    return 0;
}
