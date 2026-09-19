; layout fixture: empty lists at top level and nested. `()` is handled before
; the width test and always prints as two bytes.
()
(empty)
(holds ())
(pair () ())
(trio () () ())
(deeply (empty (still (empty (inner ())))))
