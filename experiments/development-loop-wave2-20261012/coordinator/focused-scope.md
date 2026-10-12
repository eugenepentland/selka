# Preliminary integration checks

These logs describe intermediate working source, not a frozen complete candidate.
Exact final source qualification remains outstanding. Native build used pinned Zig,
private local cache, shared global cache and shared build admission (ticket443,
447s queue). Both roots passed: scalar9 and tooling28, exact complete protocol
sidecars. The stderr `w` and `failed command:` display also occurs in the archived
prior direct native run; pinned Maker prints it for Guardian stderr even on success.
No stderr or test behavior was suppressed. Protocol intervals include dispatch,
scheduling and reporting; body duration remains unknown.

Focused Python suites passed: coordinator78, retained session15, measurement11,
fuzz40, Juice42. Later source changes require targeted rechecks and final gate.
Input coverage passes. No full-gate or performance acceptance follows from this log.
