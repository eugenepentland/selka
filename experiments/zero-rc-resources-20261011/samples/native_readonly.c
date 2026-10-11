#include "native_scopes.c"
int64_t readonly_counts(void) {
    if (opened != 1 || completed || released != 1 || active[1]) abort();
    return (int64_t)(completed * 100 + released * 10 + active[1]);
}
