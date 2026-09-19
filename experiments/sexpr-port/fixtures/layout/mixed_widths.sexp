; layout fixture: mixed widths — small atoms, a medium inline sublist, a long
; quoted string, a deeply nested sublist that is itself forced multi-line, and
; a trailing short atom. Exercises the interaction of the per-child width test
; with recursion into children.
(mixed tiny (medium-child here) "a fairly long quoted string value that pushes width" (deep (nested (structure (that (keeps going))))) short)
