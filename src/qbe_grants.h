#ifndef MYLANG_QBE_GRANTS_H
#define MYLANG_QBE_GRANTS_H
#include "native_scoped.h"
#include "qbe_runtime.h"
/* The environment variable a native executable reads its runtime options from.
   The program's own arguments are never read for options: every value after
   `argv[0]` reaches `main(args)` unchanged, `--` included. */
#define MYLANG_OPTIONS_VARIABLE "MYLANG_OPTIONS"
/* Authority and runtime controls for a native executable, mirroring
   src/cli_grants.zig: `MYLANG_OPTIONS` holds the options `mylang run` takes
   (`--restrict`, `--allow-*`, `--max-steps=N`, `--max-frames=N`,
   `--timeout=SECONDS`, `--gc-stress`, `--print-result`), separated by
   whitespace, with a double-quoted stretch keeping its whitespace and a
   backslash inside it escaping the next character. Every capability is granted
   by default, the way an ordinary interpreter does; `--restrict` switches the
   program to deny-by-default, and only then do the `--allow-*` flags narrow
   anything. A linked native provider is the program's whole authority instead,
   until `--restrict` decides otherwise. An unknown, malformed or repeated option
   exits 2 before the guest runs. Returns the process exit status. */
int mylang_qbe_run_grants(uint64_t (*entry)(void *), int argc, char **argv, const MylangNativeProviders *base);
/* Grant the `Host` authority a foreign call needs, or fail the context when the
   command line did not grant it. The entry shim calls this for a `Host` entry
   parameter before the guest body runs. */
uint64_t myl_qbe_grant_host_checked(void *context, const char *flag);
#endif
