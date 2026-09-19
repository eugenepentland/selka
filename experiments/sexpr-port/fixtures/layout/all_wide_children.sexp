; layout fixture: every child of the outer form is itself wide, so the outer
; estimate exceeds 72 and each child lands on its own indented line even though
; each child on its own still fits.
(all-wide
  (aaaaaaaaaaaa bbbbbbbbbbbb)
  (cccccccccccc dddddddddddd)
  (eeeeeeeeeeee ffffffffffff))
(wide-children (aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa) (bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb) (cccccccccccccccccccccccccccccccccccccccc))
