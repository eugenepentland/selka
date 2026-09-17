#ifndef MYLANG_QBE_GRANTS_H
#define MYLANG_QBE_GRANTS_H
#include "native_scoped.h"
#include "qbe_runtime.h"
/* Command-line authority for a native executable, mirroring src/cli_grants.zig:
   every capability is granted by default, the way an ordinary interpreter does.
   `--restrict` switches the program to deny-by-default, and only then do the
   `--allow-*` flags narrow anything. A linked native provider is the program's
   whole authority instead, until `--restrict` decides otherwise. Options this
   module consumes never reach the budget parser. Returns the process exit
   status. */
int mylang_qbe_run_grants(uint64_t (*entry)(void *), int argc, char **argv, const MylangNativeProviders *base);
/* Grant the `Host` authority a foreign call needs, or fail the context when the
   command line did not grant it. The entry shim calls this for a `Host` entry
   parameter before the guest body runs. */
uint64_t myl_qbe_grant_host_checked(void *context, const char *flag);
#endif
