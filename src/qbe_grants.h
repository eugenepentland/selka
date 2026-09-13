#ifndef MYLANG_QBE_GRANTS_H
#define MYLANG_QBE_GRANTS_H
#include "native_scoped.h"
#include "qbe_runtime.h"
/* `--allow-*` command-line authority for a native executable, mirroring
   src/cli_grants.zig: a grant provisions a host provider and every capability
   the entry point requests without one fails before the first guest
   instruction. Options this module consumes never reach the budget parser.
   Returns the process exit status. */
int mylang_qbe_run_grants(uint64_t (*entry)(void *), int argc, char **argv, const MylangNativeProviders *base);
#endif
