#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>

#define PROBE(N) \
    extern uint64_t slot_##N##_default(int64_t count, int64_t seed); \
    extern uint64_t slot_##N##_legacy(int64_t count, int64_t seed);
PROBE(0)
PROBE(1)
PROBE(2)
PROBE(3)
PROBE(4)
PROBE(5)

typedef uint64_t (*probe)(int64_t, int64_t);
static const probe direct[] = {slot_0_default, slot_1_default, slot_2_default,
                              slot_3_default, slot_4_default, slot_5_default};
static const probe legacy[] = {slot_0_legacy, slot_1_legacy, slot_2_legacy,
                              slot_3_legacy, slot_4_legacy, slot_5_legacy};

void poke(int64_t address, int64_t seed) {
    *(uint64_t *)(uintptr_t)(uint64_t)address = (uint64_t)seed + 123;
}

static uint64_t oracle(unsigned form, int64_t count, int64_t seed) {
    uint64_t result = (uint64_t)seed;
    switch (form) {
    case 0:
    case 1:
        for (int64_t index = 0; index < count; ++index) result += (uint64_t)index;
        return result;
    case 2: return result + 123;
    case 3: return result + 99;
    case 4: return result + 1 + (uint64_t)count;
    case 5: return result + (count > 0 ? 3 : 7);
    }
    return 0;
}

int main(void) {
    static const int64_t counts[] = {-3, 0, 1, 2, 7, 16, 129};
    static const int64_t seeds[] = {INT64_MIN, -17, 0, 1, INT64_MAX};
    unsigned checked = 0;
    for (unsigned repeat = 0; repeat < 3; ++repeat) {
        for (unsigned form = 0; form < 6; ++form) {
            for (unsigned c = 0; c < sizeof counts / sizeof counts[0]; ++c) {
                for (unsigned s = 0; s < sizeof seeds / sizeof seeds[0]; ++s) {
                    uint64_t expected = oracle(form, counts[c], seeds[s]);
                    uint64_t before = legacy[form](counts[c], seeds[s]);
                    uint64_t after = direct[form](counts[c], seeds[s]);
                    if (before != expected || after != expected) {
                        fprintf(stderr, "form=%u count=%" PRId64 " seed=%" PRId64
                                " expected=%" PRIu64 " legacy=%" PRIu64 " default=%" PRIu64 "\n",
                                form, counts[c], seeds[s], expected, before, after);
                        return 1;
                    }
                    ++checked;
                }
            }
        }
    }
    printf("%u default/legacy/oracle comparisons; %u native function executions passed\n", checked, 2 * checked);
    return 0;
}
