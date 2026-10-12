# Conditional owner transfer

The frontend `<conditional>` local receives an owner from whichever arm runs.
Classifying it as a receiver borrow gave the named arm a source root and the
literal arm no root; their join incorrectly made the result unavailable.
The ownership checker now treats this specific generated local as owning storage.
A source owner moved by either reachable arm remains unavailable afterward.

The focused reconstruction batch passed this test in unoptimized debug and
verified release, including output, leak checking, emitted-LLVM RC audit, and
use-after-conditional-move refusal. The complete batch was **4/7**, not a passing
combined gate: optional-negative test setup, setdefault lowering and nested
list/array reconstruction remained separate work. Full raw output is retained.
Final integrated qualification must rerun this regression.
