# Superseded compiler timing attempt

All six pairs completed successfully. These raw observations are preserved but
excluded from final paired comparisons: `Popen.wait(timeout=600)` uses polling,
quantizing very short warm-build observations around16/32/64ms. The corrected
harness uses blocking `wait()` plus an independent deadline timer. All six pairs
are repeated, including cold builds, with fresh private caches and unchanged
compiler/source identities. This is measurement correction, not source tuning.
Old work remains under `.tmp/lox-eda-improvements-20261012/compilation/`; the new
run uses `compilation-precise/`. The exact superseded harness is preserved here.
