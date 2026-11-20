# A fact certificate that is not the translation of its IR

`program.core-ir` and `program.fact-certificate` are one build of a small `tests/lang` program, except that line 13 of the
certificate reads `b %0` where the build wrote `b %2`. The gate action `verify-ir-proof` requires
`lake exe irverify --facts` to report this function as a `translate-mismatch` (it shows the check can fail).
