; layout fixture: this flat form is EXACTLY 72 columns wide (parens included).
; isShortList() rejects only total_width > 72, so 72 is the last width that
; still prints on one line. Zig prints it as a single 72-byte line.
(fits-exactly alpha bravo charlie delta echo foxtrot golf hotel india x)
