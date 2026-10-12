# Repaired fallback replay: canceled, not qualified

Both old/new golden harness artifacts were prepared using the same repaired
Debug compiler `abc4663ecc3356557a8238185005f79486343fe2ecde9258b82a266458781040`
from source `5e6180689b5b837aa60bd5a43f60b0981c58b638`. Its companion prefix was
copied from previously qualified components, with no claim of new seed provisioning.
Exact manifest and compile-only preparation logs are retained here.

The two ordinary build-admitted operational replays overlapped. Each selected
one full corpus test, preserving the intended 222 actual compiler calls. Neither
completed. The coordinator requested cooperative cancellation because the next
candidate would have independently qualified host identity and valid cache use.
SIGTERM reached only the two owned measurement supervisors; each killed its
owned child process group and exited 1. The Python interruption exception is
named TimeoutError but this event was an explicit cancellation, not expiration
of the 1100-second command or 1200-second outer experiment deadline.

C0 had prepared 95 source directories; B0 had prepared 74. Preparation counts
are not completed compiler execution or passed-case counts. No golden runtime
pass, all-222 parity, or comparative timing is claimed. Raw logs/usage and exact
hashes are recorded in golden-fallback-canceled.json. Only the two ephemeral
corpus scratch directories were removed after recording those observations.

A rejected import configuration attempt ran no golden guest code. The helper
now places its original CLI dispatch behind main(), permitting authenticated
reuse by the repaired-golden wrapper; prior scalar result hashes and immutable
records remain unchanged. The next operational/timing comparison must use the
same final cacheable compiler/context for both harnesses and complete all 222
calls. Initial old frozen compiler replay was never attempted; its independently
reproduced native-link blocker remains separate historical evidence.
