; sexpr-port fixture: the tokenizer's edge cases that the real EDA files only
; ever exercise inside strings — bare mm/mil dimensions, SI-scaled values,
; percent tolerances, and vendor part numbers that must stay single atoms.
(dimensions (width 2.5mm) (height 10mil) (clearance 0.5mm))
(electrical (res 220k) (cap 100nF) (rail 3.3V) (current 10mA) (tol 5%))
(vendor (model PMA3-24323LN+.stp) (pad P$1) (mpn "74AHCT1G125GF,132.stp"))
(oddities (freq 100kHz) (bad 12.5abc) (part 204928-0301.stp) (bare 3m))
(note "escaped \"quote\" and \\ backslash")
(nested (a (b (c (d)))))
