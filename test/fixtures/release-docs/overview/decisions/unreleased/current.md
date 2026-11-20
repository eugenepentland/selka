# Explain the pending operation

Date: 2026-10-19
Changes: catalog::pending
Why: The operation remains a typed hole until its boundary behavior is agreed by callers.
Rejected: returning zero would silently hide the missing behavior.

This decision also points to `catalog::value` for the implemented path.
