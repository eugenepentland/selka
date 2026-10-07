# Unproved native-environment control

This focused control uses the immutable corrected Core binary
`d6e4220ad8a833f3d56510eb5958637e25f9c367071949db281d64584d3bface`
from the three-file native-cache correction committed at `8cd19b82d`. It is
not a package qualification. The compiler source is unchanged by this control.

`CPATH` points at an owned `unistd.h` overlay, making the tool environment
ineligible for persistent reuse. The overlay redirects the runtime trap exit
to 7, then 8. The second header has the same size and restored modification
time. Both builds use the same command and caller cache directories. The
actual guests exit 7 then 8 as required, proving that the existing random
runtime staging also observes this unproved header change. No further driver
correction is indicated by this control.

The executed script's `ROOT` is the experiments directory; its private native
artifacts remain beneath `experiments/.mylang-cache/s4-m/` and are excluded
from this evidence. Commands, exact inputs, raw output and tool/binary hashes
are retained here. All builds ran through the normal build-slot wrapper.
