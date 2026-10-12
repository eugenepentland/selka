# Frozen-candidate telemetry collision and isolated fixture fix

Read-only audit of frozen 9d1b51f310477e4ceccffd8ad41ecf6fc2156e13 observed
unit.member.0.json with producer zig-test-protocol-v1, selected0, tests[],
completefalse and malformedtrue. Report parsing correctly treats this as unknown.
The selected gate's real unit/member0 observation can be overwritten by nested
native-proxy regression subprocesses: inherited-FD and cancellation fixtures
use action unit/member0 and inherited MYLANG_TEST_TELEMETRY_DIR.

The owned test fix introduces isolated_environment() and uses it for EVERY proxy
subprocess. It removes the parent telemetry directory, then permits an explicit
fixture-private directory override. Production proxy behavior is unchanged.
A regression supplies a parent directory containing an authentic sidecar, runs
all three real nested proxy subprocess paths (including descriptor forwarding
and forced cancellation), and asserts the parent sidecar bytes and directory
membership remain unchanged. This would detect a future forgotten env isolation
at any of those call sites; it is not just a helper-shape assertion.

Command: python3 -B -m unittest discover -s scripts -p
verification_native_telemetry_test.py. Exit0; eight tests passed. Raw output:
sidecar-isolation-tests.log. No native build/gate, integration write or upstream
Guardian/runtime change. Normal commit hooks remain enabled. Root will adopt
this fixed commit only after the currently frozen gate and requalify a new source
candidate. The old candidate cannot claim this fixture namespace isolation.
